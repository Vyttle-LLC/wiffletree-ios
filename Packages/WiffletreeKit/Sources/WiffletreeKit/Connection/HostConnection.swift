import Foundation
import Synchronization

/// A live connection to one host, as the app's screens use it. `RemoteHostConnection` reaches a
/// paired host over the network; a demo host can implement it in memory.
public protocol HostConnection: Sendable {
    /// The host's events, across reconnects, each once and in order. After a gap the host could
    /// not replay, a `resync` comes first: take a fresh snapshot.
    var events: AsyncStream<HostEvent> { get }
    /// The connection's state each time it changes, starting with `connecting`.
    var states: AsyncStream<ConnectionState> { get }
    /// Sends a command once connected and returns the host's reply. While the host cannot be
    /// reached it throws `notConnected` rather than waiting for the next try, and while a try is
    /// in progress it waits only briefly for it.
    func request<Command: HostCommand>(_ command: Command) async throws -> Command.Reply
    /// The app is back in the foreground: try again now if waiting, else check the connection
    /// survived the time the app was suspended.
    func reconnectNow()
    /// Ends the connection and both streams for good.
    func close()
    /// Whether this is the built-in demo host, which the app marks as such.
    var isDemo: Bool { get }
}

extension HostConnection {
    public var isDemo: Bool { false }
    public func reconnectNow() {}
}

public enum ConnectionState: Equatable, Sendable {
    case connecting
    /// `capabilities` names the optional commands the host offers, such as `uploads`.
    case connected(address: HostAddress, level: AccessLevel, capabilities: Set<String> = [])
    /// The last try failed or the connection dropped; another try follows after a pause.
    case waiting(attempt: Int, error: ConnectionError)
    /// Stopped for good: the host's key changed, it no longer knows this device, or it is too
    /// old or new to talk to. The human must pair again or update.
    case failed(ConnectionError)
    case closed
}

/// How long to wait before each try after a failure: doubling from `first` up to `longest`.
public struct Backoff: Sendable {
    public var first: Duration
    public var longest: Duration

    public init(first: Duration = .milliseconds(500), longest: Duration = .seconds(30)) {
        self.first = first
        self.longest = longest
    }

    /// The pause before try number `attempt + 1`, counting the first failure as attempt 1.
    public func delay(after attempt: Int) -> Duration {
        min(first * (1 << min(attempt - 1, 16)), longest)
    }
}

/// A paired host over the network: address racing, the challenge, `Hello`, the event
/// subscription, and reconnecting with the last cursor after a drop.
public final class RemoteHostConnection: HostConnection {
    public struct Options: Sendable {
        public var backoff = Backoff()
        /// How often a `ping` checks the host is still there, which a dead Wi-Fi link would
        /// otherwise hide.
        public var heartbeat: Duration = .seconds(10)
        /// How long a `ping` may wait before the connection counts as dropped.
        public var pingLimit: Duration = .seconds(10)
        /// How long a request made during a try waits for it to connect before it fails with
        /// `notConnected`, so a tap is never held for the whole handshake.
        public var connectingLimit: Duration = .seconds(8)
        /// How far each address's try starts after the one before it.
        public var headStart: Duration = .milliseconds(250)

        public init() {}
    }

    public let events: AsyncStream<HostEvent>
    public let states: AsyncStream<ConnectionState>
    private let eventSink: AsyncStream<HostEvent>.Continuation
    private let stateSink: AsyncStream<ConnectionState>.Continuation
    private let deviceKey: DeviceKey
    private let store: any PairedHostStore
    private let race: AddressRace
    private let appVersion: String
    private let options: Options
    private let shared: Mutex<Shared>

    private struct Shared {
        var host: PairedHost
        var state = ConnectionState.connecting
        var session: HostSession?
        var cursor: Cursor?
        /// Requests waiting for the try in progress.
        var waiters: [UUID: CheckedContinuation<HostSession, any Error>] = [:]
        var runner: Task<Void, Never>?
        /// The pause before the next try, which `reconnectNow` cuts short.
        var pause: Task<Void, Never>?
        /// `reconnectNow` came with no session and no pause yet: skip the next pause.
        var retryNow = false
    }

    /// Starts connecting at once. Call `close()` when done; until then the connection keeps
    /// trying.
    public init(
        host: PairedHost,
        deviceKey: DeviceKey,
        store: any PairedHostStore,
        appVersion: String,
        dialer: any ChannelDialer = NetworkDialer(),
        options: Options = Options()
    ) {
        (events, eventSink) = AsyncStream.makeStream()
        (states, stateSink) = AsyncStream.makeStream()
        self.deviceKey = deviceKey
        self.store = store
        self.appVersion = appVersion
        self.options = options
        race = AddressRace(dialer: dialer, headStart: options.headStart)
        shared = Mutex(Shared(host: host))
        stateSink.yield(.connecting)
        let runner = Task { [weak self] in
            guard let self else { return }
            await run()
        }
        shared.withLock { $0.runner = runner }
    }

    /// The host as last connected: its addresses newest first, and its level.
    public var host: PairedHost {
        shared.withLock { $0.host }
    }

    public func request<Command: HostCommand>(_ command: Command) async throws -> Command.Reply {
        try await currentSession().request(command)
    }

    public func reconnectNow() {
        let (session, pause) = shared.withLock { shared in
            if shared.session == nil && shared.pause == nil { shared.retryNow = true }
            return (shared.session, shared.pause)
        }
        pause?.cancel()
        guard let session else { return }
        Task { [pingLimit = options.pingLimit] in
            _ = try? await session.request(PingCommand(), within: pingLimit)
        }
    }

    public func close() {
        let (runner, session) = shared.withLock { ($0.runner, $0.session) }
        runner?.cancel()
        Task { await session?.close() }
        settle(.closed, waitersGet: .failure(.closed))
        eventSink.finish()
        stateSink.finish()
    }

    private func run() async {
        var attempt = 0
        while !Task.isCancelled {
            let error: ConnectionError
            do {
                let session = try await connect()
                attempt = 0
                let heartbeat = Task { await keepAlive(session) }
                error = await session.ended()
                heartbeat.cancel()
                shared.withLock { $0.session = nil }
            } catch let failure {
                error = failure
            }
            if Task.isCancelled { return }
            if error.isFinal {
                settle(.failed(error), waitersGet: .failure(error))
                eventSink.finish()
                stateSink.finish()
                return
            }
            attempt += 1
            settle(.waiting(attempt: attempt, error: error), waitersGet: .failure(.notConnected))
            await pause(for: options.backoff.delay(after: attempt))
            if Task.isCancelled { return }
            settle(.connecting, waitersGet: nil)
        }
    }

    /// Waits `delay` before the next try, or less when `reconnectNow` or `close` cuts it short.
    private func pause(for delay: Duration) async {
        let pause = Task<Void, Never> { try? await Task.sleep(for: delay) }
        shared.withLock { shared in
            if shared.retryNow { pause.cancel() }
            shared.retryNow = false
            shared.pause = pause
        }
        await withTaskCancellationHandler {
            await pause.value
        } onCancel: {
            pause.cancel()
        }
        shared.withLock { $0.pause = nil }
    }

    /// Races the host's addresses, answers the challenge, says `Hello` and subscribes after the
    /// last cursor, then remembers the address that answered and the level the host gave.
    private func connect() async throws(ConnectionError) -> HostSession {
        let host = self.host
        let (address, channel) = try await race.open(host.addresses, path: ChannelPath.v1, hostKey: host.publicKey)
        let session = try await HostSession.open(channel, host: host, deviceKey: deviceKey, appVersion: appVersion) { [weak self] event in
            self?.receive(event)
        }
        if session.welcome.capabilities.contains("events") {
            let after = shared.withLock { $0.cursor }
            do throws(ConnectionError) {
                let subscribed = try await session.request(SubscribeCommand(after: after), within: handshakeStepLimit)
                shared.withLock { $0.cursor = $0.cursor ?? subscribed.cursor }
            } catch {
                await session.close()
                throw error
            }
        }
        var updated = host
        updated.addresses = host.addresses.answered(at: address)
        updated.level = session.level
        if updated != host { try? store.save(updated) }
        let connected = ConnectionState.connected(address: address, level: session.level, capabilities: Set(session.welcome.capabilities))
        let waiters = shared.withLock { shared -> [CheckedContinuation<HostSession, any Error>]? in
            guard shared.state != .closed else { return nil }
            shared.host = updated
            shared.session = session
            shared.state = connected
            shared.retryNow = false
            defer { shared.waiters = [:] }
            return Array(shared.waiters.values)
        }
        guard let waiters else {
            await session.close()
            throw .closed
        }
        stateSink.yield(connected)
        for waiter in waiters { waiter.resume(returning: session) }
        return session
    }

    private func receive(_ event: HostEvent) {
        shared.withLock { $0.cursor = event.cursor }
        eventSink.yield(event)
    }

    /// Pings the host every `heartbeat`, closing the connection when a ping goes unanswered so
    /// the run loop reconnects.
    private func keepAlive(_ session: HostSession) async {
        while (try? await Task.sleep(for: options.heartbeat)) != nil {
            _ = try? await session.request(PingCommand(), within: options.pingLimit)
        }
    }

    /// The session to send on: the live one, the one being opened if it opens within
    /// `connectingLimit`, or the reason there is none.
    private func currentSession() async throws -> HostSession {
        let waiter = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let ready: Result<HostSession, ConnectionError>? = shared.withLock { shared in
                if let session = shared.session { return .success(session) }
                switch shared.state {
                case .failed(let error): return .failure(error)
                case .waiting: return .failure(.notConnected)
                case .closed: return .failure(.closed)
                case .connecting, .connected:
                    shared.waiters[waiter] = continuation
                    return nil
                }
            }
            if let ready { return continuation.resume(with: ready.mapError { $0 }) }
            Task { [weak self, limit = options.connectingLimit] in
                try? await Task.sleep(for: limit)
                self?.giveUp(on: waiter)
            }
        }
    }

    /// Fails a request still waiting for the try in progress.
    private func giveUp(on waiter: UUID) {
        shared.withLock { $0.waiters.removeValue(forKey: waiter) }?.resume(throwing: ConnectionError.notConnected)
    }

    /// Moves to `state`, telling waiting requests why when `waitersGet` says so.
    private func settle(_ state: ConnectionState, waitersGet result: Result<HostSession, ConnectionError>?) {
        let waiters = shared.withLock { shared -> [CheckedContinuation<HostSession, any Error>]? in
            guard shared.state != .closed else { return nil }
            shared.state = state
            guard result != nil else { return [] }
            defer { shared.waiters = [:] }
            return Array(shared.waiters.values)
        }
        guard let waiters else { return }
        stateSink.yield(state)
        if let result {
            for waiter in waiters { waiter.resume(with: result.mapError { $0 }) }
        }
    }
}
