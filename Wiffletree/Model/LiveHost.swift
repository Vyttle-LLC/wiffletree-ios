import Foundation
import Observation
import WiffletreeKit

/// One host as the screens see it: its live connection, the connection's state and the latest
/// snapshot, kept current from the host's events on the main actor.
@MainActor
@Observable
final class LiveHost: Identifiable {
    let id: HostID
    /// The paired host as last stored; nil for the demo.
    private(set) var paired: PairedHost?
    private(set) var connection: any HostConnection
    private(set) var state = ConnectionState.connecting
    /// The workspace as the host last described it; nil until the first snapshot arrives.
    private(set) var snapshot: Snapshot?
    /// When this iPhone last had a connection to the host.
    private(set) var lastSeen: Date?
    /// Why the last try failed, until a try connects.
    private(set) var lastFailure: ConnectionError?

    @ObservationIgnored private let connect: () throws -> any HostConnection
    @ObservationIgnored private let reload: () -> PairedHost?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let onSeen: (Date) -> Void
    @ObservationIgnored private let onStopped: (ConnectionError) -> Void
    @ObservationIgnored private var watchers: [Task<Void, Never>] = []
    @ObservationIgnored private var refresher: Task<Void, Never>?
    @ObservationIgnored private var wantsSnapshot = false
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<HostEvent>.Continuation] = [:]

    /// - Parameters:
    ///   - connect: Opens a connection, again for each `restart()`.
    ///   - reload: The stored host, which a connection updates with where the host answered.
    ///   - onSeen: Told each time the connection opens or drops, to remember when it was last up.
    ///   - onStopped: Told when the connection stops for good, such as when the host no longer
    ///     knows this iPhone.
    init(
        id: HostID,
        paired: PairedHost?,
        lastSeen: Date?,
        connect: @escaping () throws -> any HostConnection,
        reload: @escaping () -> PairedHost? = { nil },
        now: @escaping () -> Date = Date.init,
        onSeen: @escaping (Date) -> Void = { _ in },
        onStopped: @escaping (ConnectionError) -> Void = { _ in }
    ) {
        self.id = id
        self.paired = paired
        self.lastSeen = lastSeen
        self.connect = connect
        self.reload = reload
        self.now = now
        self.onSeen = onSeen
        self.onStopped = onStopped
        connection = Self.open(connect)
        watch()
    }

    var name: String { paired?.name ?? DemoHostConnection.name }
    var isDemo: Bool { id == .demo }

    var status: HostStatus {
        HostStatus(state: state, isDemo: isDemo, lastSeen: lastSeen, lastFailure: lastFailure, now: now())
    }

    var isConnected: Bool {
        if case .connected = state { true } else { false }
    }

    /// What the host lets this iPhone do: as the live connection says, else as last stored.
    var level: AccessLevel {
        if case .connected(_, let level) = state { level } else { paired?.level ?? .control }
    }

    /// Open Inbox items: what the host's badges count.
    var openAttentionCount: Int {
        snapshot?.attention.count { $0.answer == nil } ?? 0
    }

    /// The host's events from now on, for screens that fetch more than the snapshot, such as a
    /// conversation's steps. The stream ends when the connection does.
    func events() -> AsyncStream<HostEvent> {
        let (stream, continuation) = AsyncStream<HostEvent>.makeStream()
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    /// Drops the connection and opens a new one: "Try again", or the demo started over.
    func restart() {
        stop()
        state = .connecting
        lastFailure = nil
        snapshot = nil
        connection = Self.open(connect)
        watch()
    }

    /// Ends the connection for good.
    func stop() {
        watchers.forEach { $0.cancel() }
        watchers = []
        refresher?.cancel()
        refresher = nil
        subscribers.values.forEach { $0.finish() }
        subscribers = [:]
        connection.close()
    }

    // MARK: - Applying the connection's states and events

    private func watch() {
        let connection = connection
        watchers = [
            Task { [weak self] in
                for await state in connection.states { self?.apply(state) }
            },
            Task { [weak self] in
                for await event in connection.events { self?.apply(event) }
            },
        ]
    }

    private func apply(_ state: ConnectionState) {
        let wasConnected = isConnected
        self.state = state
        switch state {
        case .connected:
            lastFailure = nil
            if let stored = reload() { paired = stored }
            seen()
            refreshSnapshot()
        case .failed(let error):
            lastFailure = error
            if wasConnected { seen() }
            onStopped(error)
        case .waiting(_, let error):
            lastFailure = error
            if wasConnected { seen() }
        case .closed:
            if wasConnected { seen() }
        case .connecting:
            break
        }
    }

    private func apply(_ event: HostEvent) {
        switch event.kind {
        case .state, .resync, .attention: refreshSnapshot()
        case .steps, .progress, .usage, .unknown: break
        }
        subscribers.values.forEach { $0.yield(event) }
    }

    private func seen() {
        guard !isDemo else { return }
        let date = now()
        lastSeen = date
        onSeen(date)
    }

    /// Fetches the snapshot, once more after the current fetch when another change arrives
    /// meanwhile, so the newest always lands last.
    private func refreshSnapshot() {
        wantsSnapshot = true
        guard refresher == nil else { return }
        let connection = connection
        refresher = Task { [weak self] in
            while let self, self.wantsSnapshot, !Task.isCancelled {
                self.wantsSnapshot = false
                guard let snapshot = try? await connection.request(SnapshotCommand()), !Task.isCancelled else { break }
                self.snapshot = snapshot.withoutClosedProjects()
            }
            // A cancelled fetch's slot may already hold the next connection's.
            if !Task.isCancelled { self?.refresher = nil }
        }
    }

    private static func open(_ connect: () throws -> any HostConnection) -> any HostConnection {
        do {
            return try connect()
        } catch {
            return UnopenedConnection(error: .commandFailed("Couldn't open a connection: \(error.localizedDescription)"))
        }
    }
}

/// A connection that could not open, such as when the device key is unreadable: it fails at
/// once with the reason.
private final class UnopenedConnection: HostConnection {
    let events: AsyncStream<HostEvent>
    let states: AsyncStream<ConnectionState>
    private let error: ConnectionError

    init(error: ConnectionError) {
        self.error = error
        events = AsyncStream { $0.finish() }
        states = AsyncStream { continuation in
            continuation.yield(.failed(error))
            continuation.finish()
        }
    }

    func request<Command: HostCommand>(_ command: Command) async throws -> Command.Reply {
        throw error
    }

    func close() {}
}
