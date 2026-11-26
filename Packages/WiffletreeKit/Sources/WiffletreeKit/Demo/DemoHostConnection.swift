import Foundation
import Synchronization

/// The host built into the app, so App Review and new users can explore it without a Mac: the
/// seed's workspace in memory, with no network. It answers the first screens' commands as a host
/// does, coordinators reply to messages after a short pause, and every change arrives as an
/// event. Anything else is refused as not available in the demo.
public final class DemoHostConnection: HostConnection {
    public struct Options: Sendable {
        /// How long an agent takes to reply.
        public var replyDelay: Duration = .seconds(2)
        /// The time the seed counts back from and new messages carry.
        public var now: @Sendable () -> Date = { Date() }
        /// Waits out `replyDelay`.
        public var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

        public init() {}
    }

    public static let name = "Demo Mac"
    /// Where the demo says it is: nowhere on the network.
    public static let address = HostAddress(host: "demo.invalid")
    public static let notAvailable = ConnectionError.commandFailed("Not available in the demo.")

    public let events: AsyncStream<HostEvent>
    public let states: AsyncStream<ConnectionState>
    public var isDemo: Bool { true }
    private let stateSink: AsyncStream<ConnectionState>.Continuation
    private let options: Options
    /// New for each demo, as a host's is for each start, so an old cursor resyncs.
    private let epoch = UUID().uuidString
    private let shared: Mutex<Shared>

    private struct Shared {
        var workspace: DemoWorkspace
        /// Every event so far; the demo's are few, so it keeps them all.
        var log: [HostEvent] = []
        var subscribers: [UUID: AsyncStream<HostEvent>.Continuation]
        /// Replies still on their way, cancelled by `close()`.
        var replies: [UUID: Task<Void, Never>] = [:]
        var cannedRepliesSent = 0
        var isClosed = false
    }

    public init(options: Options = Options()) {
        self.options = options
        let (events, eventSink) = AsyncStream<HostEvent>.makeStream()
        self.events = events
        (states, stateSink) = AsyncStream.makeStream()
        shared = Mutex(Shared(workspace: DemoSeed.workspace(at: options.now()), subscribers: [UUID(): eventSink]))
        stateSink.yield(.connecting)
        stateSink.yield(.connected(address: Self.address, level: .control))
    }

    /// Another subscription, as `subscribe` gives one: the events after `cursor` when this demo
    /// still holds them, or `resync` first for a cursor of another demo; then live events. With
    /// no cursor, only live events.
    public func events(after cursor: Cursor?) -> AsyncStream<HostEvent> {
        let (stream, continuation) = AsyncStream<HostEvent>.makeStream()
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.shared.withLock { _ = $0.subscribers.removeValue(forKey: id) }
        }
        let subscribed = shared.withLock { shared in
            guard !shared.isClosed else { return false }
            if let cursor {
                if cursor.epoch == epoch, cursor.seq <= UInt64(shared.log.count) {
                    for event in shared.log.dropFirst(Int(cursor.seq)) { continuation.yield(event) }
                } else {
                    continuation.yield(HostEvent(cursor: latestCursor(shared), kind: .resync))
                }
            }
            shared.subscribers[id] = continuation
            return true
        }
        // Outside the lock, which finishing takes again to unsubscribe.
        if !subscribed { continuation.finish() }
        return stream
    }

    public func request<Command: HostCommand>(_ command: Command) async throws -> Command.Reply {
        // Each case answers with its command's reply type.
        try answer(command) as! Command.Reply
    }

    public func close() {
        let ended = shared.withLock { shared -> (subscribers: [AsyncStream<HostEvent>.Continuation], replies: [Task<Void, Never>])? in
            guard !shared.isClosed else { return nil }
            shared.isClosed = true
            defer { shared.subscribers = [:]; shared.replies = [:] }
            return (Array(shared.subscribers.values), Array(shared.replies.values))
        }
        guard let ended else { return }
        ended.replies.forEach { $0.cancel() }
        ended.subscribers.forEach { $0.finish() }
        stateSink.yield(.closed)
        stateSink.finish()
    }

    private func answer(_ command: some HostCommand) throws(ConnectionError) -> any Sendable {
        try shared.withLock { shared throws(ConnectionError) -> any Sendable in
            guard !shared.isClosed else { throw .closed }
            let workspace = shared.workspace
            switch command {
            case is PingCommand:
                return NoReply()
            case is SnapshotCommand:
                return Snapshot(projects: workspace.projects, sessions: workspace.sessions, attention: workspace.attention, tickets: workspace.tickets)
            case let command as MessagesCommand:
                return try messages(command, in: workspace)
            case let command as SendCommand:
                return try send(command, in: &shared)
            case let command as ResolveAttentionCommand:
                return try resolve(command.id, answer: command.answer, in: &shared)
            case let command as DismissAttentionCommand:
                return try dismiss(command.id, in: &shared)
            case is UsageCommand:
                return workspace.usage
            case is QuotasCommand:
                return workspace.quotas
            default:
                throw Self.notAvailable
            }
        }
    }

    // MARK: - Commands

    private func messages(_ command: MessagesCommand, in workspace: DemoWorkspace) throws(ConnectionError) -> [Message] {
        _ = try session(command.sessionID, in: workspace)
        let before = command.before ?? .max
        return Array(workspace.messages.filter { $0.recipient == command.sessionID && $0.sequence < before }.suffix(command.limit))
    }

    private func send(_ command: SendCommand, in shared: inout Shared) throws(ConnectionError) -> Message {
        if let sent = shared.workspace.messages.first(where: { $0.id == command.id }) { return sent }
        let recipient = try session(command.recipient, in: shared.workspace)
        let message = append(id: command.id, from: nil, to: recipient, body: command.body, in: &shared)
        setStatus(.working, of: recipient.id, in: &shared)
        emit([.state], in: &shared)
        let reply = Self.cannedReplies[shared.cannedRepliesSent % Self.cannedReplies.count]
        shared.cannedRepliesSent += 1
        scheduleReply(from: recipient.id, body: reply, in: &shared)
        return message
    }

    /// Answers an Inbox item once, as the host does: an approval takes `approved`, and anything
    /// else denies it. Approving a publish opens its pull request; approving a merge merges it.
    private func resolve(_ id: String, answer: String, in shared: inout Shared) throws(ConnectionError) -> Attention {
        let index = try openAttention(id, in: shared.workspace)
        shared.workspace.attention[index].answer = answer
        let attention = shared.workspace.attention[index]
        let approved = answer == "approved"
        let reply: String
        switch attention.id {
        case DemoID.publishApproval where approved:
            updateTicket(DemoID.thresholdsTicket, in: &shared) { ticket in
                ticket.pullRequest = PullRequest(
                    number: 214, url: "https://github.com/Vyttle-LLC/tidepool/pull/214", state: .open, draft: false,
                    base: "main", mergeState: "clean", checks: .pending
                )
            }
            reply = "Published: **#214** is open on Vyttle-LLC/tidepool, and its checks are running. It merges into `main`, so you merge it on GitHub."
        case DemoID.mergeApproval where approved:
            updateTicket(DemoID.syncRetryTicket, in: &shared) { $0.pullRequest?.state = .merged }
            reply = "Merged **#212** into `feature/sync-retry`. Flaky sync test now waits only on **Log who holds the sync lock**."
        case DemoID.publishApproval, DemoID.mergeApproval:
            reply = "Understood, I've left it as it is. It stays accepted on its branch."
        default:
            reply = "Thanks: **\(answer)** it is. I've passed it to the implementer."
        }
        setStatus(.working, of: attention.sessionID, in: &shared)
        emit([.state, .attention(count: openCount(shared.workspace))], in: &shared)
        scheduleReply(from: attention.sessionID, body: reply, in: &shared)
        return attention
    }

    /// Clears a question without waking its asker. Approvals can only be approved or denied.
    private func dismiss(_ id: String, in shared: inout Shared) throws(ConnectionError) -> Attention {
        let index = try openAttention(id, in: shared.workspace)
        guard !Self.isApproval(shared.workspace.attention[index]) else {
            throw .commandFailed("Approve or deny a permission request")
        }
        shared.workspace.attention[index].answer = "Dismissed by the human"
        emit([.state, .attention(count: openCount(shared.workspace))], in: &shared)
        return shared.workspace.attention[index]
    }

    // MARK: - Workspace

    private func session(_ id: String, in workspace: DemoWorkspace) throws(ConnectionError) -> Session {
        guard let session = workspace.sessions.first(where: { $0.id == id }) else {
            throw .commandFailed("No agent \(id) on this host")
        }
        return session
    }

    private func openAttention(_ id: String, in workspace: DemoWorkspace) throws(ConnectionError) -> Int {
        guard let index = workspace.attention.firstIndex(where: { $0.id == id }) else {
            throw .commandFailed("No Inbox item \(id) on this host")
        }
        guard workspace.attention[index].answer == nil else {
            throw .commandFailed("Request already resolved; stale answer rejected")
        }
        return index
    }

    private func openCount(_ workspace: DemoWorkspace) -> Int {
        workspace.attention.count { $0.answer == nil }
    }

    private static func isApproval(_ attention: Attention) -> Bool {
        ["permission:", "publish:", "merge:", "retarget:", "repository:"].contains { attention.operationID.hasPrefix($0) }
    }

    @discardableResult
    private func append(id: String, from sender: String?, to recipient: Session, body: String, in shared: inout Shared) -> Message {
        let message = Message(
            id: id,
            sequence: (shared.workspace.messages.last?.sequence ?? 0) + 1,
            projectID: recipient.projectID,
            sender: sender,
            recipient: recipient.id,
            body: body,
            receipt: "completed",
            createdAt: Int64(options.now().timeIntervalSince1970 * 1000)
        )
        shared.workspace.messages.append(message)
        return message
    }

    private func setStatus(_ status: Session.Status, of id: String, in shared: inout Shared) {
        guard let index = shared.workspace.sessions.firstIndex(where: { $0.id == id }) else { return }
        shared.workspace.sessions[index].status = status
    }

    private func updateTicket(_ id: String, in shared: inout Shared, _ change: (inout Ticket) -> Void) {
        guard let index = shared.workspace.tickets.firstIndex(where: { $0.id == id }) else { return }
        change(&shared.workspace.tickets[index])
    }

    // MARK: - Replies and events

    /// After `replyDelay`, the agent's reply lands in its conversation. Like the seed's, it is a
    /// message the agent sends itself, since the client reads no turn output yet.
    private func scheduleReply(from sessionID: String, body: String, in shared: inout Shared) {
        let id = UUID()
        shared.replies[id] = Task { [weak self, options] in
            try? await options.sleep(options.replyDelay)
            guard !Task.isCancelled else { return }
            self?.deliverReply(id, from: sessionID, body: body)
        }
    }

    private func deliverReply(_ id: UUID, from sessionID: String, body: String) {
        shared.withLock { shared in
            guard !shared.isClosed, shared.replies.removeValue(forKey: id) != nil,
                  let sender = shared.workspace.sessions.first(where: { $0.id == sessionID }) else { return }
            append(id: "demo-reply-\(id.uuidString)", from: sender.id, to: sender, body: body, in: &shared)
            let stillAsking = shared.workspace.attention.contains { $0.sessionID == sessionID && $0.answer == nil }
            setStatus(stillAsking ? .blocked : .ready, of: sessionID, in: &shared)
            emit([.state, .steps(sessions: [sessionID])], in: &shared)
        }
    }

    private func emit(_ kinds: [HostEvent.Kind], in shared: inout Shared) {
        for kind in kinds {
            let event = HostEvent(cursor: Cursor(epoch: epoch, seq: UInt64(shared.log.count + 1)), kind: kind)
            shared.log.append(event)
            for subscriber in shared.subscribers.values { subscriber.yield(event) }
        }
    }

    private func latestCursor(_ shared: Shared) -> Cursor {
        Cursor(epoch: epoch, seq: UInt64(shared.log.count))
    }

    /// What an agent says to a message, in turn.
    private static let cannedReplies = [
        "Got it. On your Mac I'd plan this as a ticket, hand it to an agent and report back here. In the demo the conversation is simulated, so nothing changes.",
        "Noted. Try the **Inbox** to see a decision land: answering a question or approving a publish updates the tickets here.",
        "Thanks. Everything in the demo is sample data that stays on this iPhone. Pair your Mac to work with your own projects.",
    ]
}
