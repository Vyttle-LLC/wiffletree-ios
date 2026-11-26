import Foundation
import Synchronization

/// The host built into the app, so App Review and new users can explore it without a Mac: the
/// seed's workspace in memory, with no network. It answers the first screens' commands as a host
/// does, keeps uploaded photos in memory, coordinators reply to messages after a short pause, and
/// every change arrives as an event. Anything else is refused as not available in the demo.
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
    /// The optional commands the demo answers.
    public static let capabilities: Set<String> = ["events", "files", "uploads"]

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
        /// Each session's latest run, as `steps` answers it.
        var runs: [String: StepPage] = [:]
        /// Counts step changes across sessions, as a host's per-session revisions grow.
        var stepRevision: UInt64 = 0
        var cannedRepliesSent = 0
        /// Uploads by id, until a message names them.
        var uploads: [String: (name: String, data: Data)] = [:]
        /// Sent messages' attachments by path, as `read_file` serves them.
        var files: [String: Data] = [:]
        var isClosed = false
    }

    public init(options: Options = Options()) {
        self.options = options
        let (events, eventSink) = AsyncStream<HostEvent>.makeStream()
        self.events = events
        (states, stateSink) = AsyncStream.makeStream()
        shared = Mutex(Shared(workspace: DemoSeed.workspace(at: options.now()), subscribers: [UUID(): eventSink]))
        stateSink.yield(.connecting)
        stateSink.yield(.connected(address: Self.address, level: .control, capabilities: Self.capabilities))
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
                return Snapshot(
                    projects: workspace.projects, spaces: workspace.spaces, sessions: workspace.sessions,
                    runtimes: workspace.runtimes, attention: workspace.attention, tickets: workspace.tickets,
                    repositories: workspace.repositories
                )
            case let command as MessagesCommand:
                return try messages(command, in: workspace)
            case let command as StepsCommand:
                return try steps(command, in: shared)
            case let command as SendCommand:
                return try send(command, in: &shared)
            case let command as ResolveAttentionCommand:
                return try resolve(command.id, answer: command.answer, in: &shared)
            case let command as DismissAttentionCommand:
                return try dismiss(command.id, in: &shared)
            case let command as UploadAttachmentCommand:
                return try upload(command, in: &shared)
            case let command as ReadFileCommand:
                return try readFile(command, in: shared)
            case let command as UsageCommand:
                return usage(command, in: workspace)
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
        // The host's limit is unsigned, so it refuses a negative one.
        guard command.limit >= 0 else { throw .commandFailed("The limit can't be negative.") }
        let before = command.before ?? .max
        return Array(workspace.messages.filter { $0.recipient == command.sessionID && $0.sequence < before }.suffix(command.limit))
    }

    /// The session's latest run with only the steps changed after `after`; a session that never
    /// ran has an empty page, as on the host.
    private func steps(_ command: StepsCommand, in shared: Shared) throws(ConnectionError) -> StepPage {
        _ = try session(command.sessionID, in: shared.workspace)
        guard let run = shared.runs[command.sessionID], command.runID == nil || command.runID == run.runID else {
            return StepPage(runID: command.runID, running: false, revision: command.after, steps: [])
        }
        return StepPage(runID: run.runID, running: run.running, revision: run.revision, steps: run.steps.filter { $0.revision > command.after })
    }

    private func send(_ command: SendCommand, in shared: inout Shared) throws(ConnectionError) -> Message {
        if let sent = shared.workspace.messages.first(where: { $0.id == command.id }) { return sent }
        let recipient = try session(command.recipient, in: shared.workspace)
        let attachments = try attach(command.uploads, to: command.id, in: &shared)
        let message = append(id: command.id, from: nil, to: recipient, body: command.body, attachments: attachments, in: &shared)
        setStatus(.working, of: recipient.id, in: &shared)
        let run = startRun(of: recipient.id, in: &shared)
        emit([.state, .steps(sessions: [recipient.id])], in: &shared)
        let reply = Self.cannedReplies[shared.cannedRepliesSent % Self.cannedReplies.count]
        shared.cannedRepliesSent += 1
        scheduleReply(from: recipient.id, run: run, body: reply, in: &shared)
        return message
    }

    /// Keeps a piece where the upload ends, as the host does, and answers how much it holds.
    private func upload(_ command: UploadAttachmentCommand, in shared: inout Shared) throws(ConnectionError) -> Uploaded {
        guard let piece = Data(base64Encoded: command.bytes) else { throw .commandFailed("The piece is not base64") }
        guard piece.count <= Upload.pieceLimit else { throw .commandFailed("A piece is at most 128 KiB") }
        var upload = shared.uploads[command.uploadID] ?? (command.name, Data())
        guard shared.uploads[command.uploadID] != nil || command.offset == 0 else {
            throw .commandFailed("No upload has that id; start it at offset 0")
        }
        guard upload.name == command.name else { throw .commandFailed("That upload has another file name") }
        if command.offset == upload.data.count {
            guard upload.data.count + piece.count <= Upload.sizeLimit else { throw .commandFailed("\(command.name) is over 50 MB") }
            upload.data.append(piece)
        }
        shared.uploads[command.uploadID] = upload
        return Uploaded(uploadID: command.uploadID, stored: upload.data.count)
    }

    /// Moves the named uploads into the message's attachments.
    private func attach(_ ids: [String], to messageID: String, in shared: inout Shared) throws(ConnectionError) -> [Attachment] {
        var attachments: [Attachment] = []
        for id in ids {
            guard let upload = shared.uploads[id] else { throw .commandFailed("No upload has that id") }
            let path = "demo/attachments/\(messageID)/\(upload.name)"
            let isJPEG = upload.data.starts(with: [0xFF, 0xD8, 0xFF])
            attachments.append(Attachment(path: path, size: UInt64(upload.data.count), image: isJPEG ? "jpeg" : nil))
        }
        for (id, attachment) in zip(ids, attachments) {
            shared.files[attachment.path] = shared.uploads.removeValue(forKey: id)?.data
        }
        return attachments
    }

    private func readFile(_ command: ReadFileCommand, in shared: Shared) throws(ConnectionError) -> FileContents {
        guard let data = shared.files[command.path] else { throw Self.notAvailable }
        guard data.count <= command.maxBytes else { throw .commandFailed("The file is larger than \(command.maxBytes) bytes") }
        return FileContents(path: command.path, data: data.base64EncodedString())
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
            updateTicket(DemoID.syncRetryTicket, in: &shared) { ticket in
                ticket.pullRequest?.state = .merged
                ticket.merging = nil
            }
            reply = "Merged **#212** into `feature/sync-retry`. Flaky sync test now waits only on **Log who holds the sync lock**."
        case DemoID.mergeApproval:
            updateTicket(DemoID.syncRetryTicket, in: &shared) { $0.merging = nil }
            reply = "Understood, I've left it as it is. It stays accepted on its branch."
        case DemoID.publishApproval:
            reply = "Understood, I've left it as it is. It stays accepted on its branch."
        default:
            reply = "Thanks: **\(answer)** it is. I've passed it to the implementer."
        }
        setStatus(.working, of: attention.sessionID, in: &shared)
        let run = startRun(of: attention.sessionID, in: &shared)
        emit([.state, .attention(count: openCount(shared.workspace)), .steps(sessions: [attention.sessionID])], in: &shared)
        scheduleReply(from: attention.sessionID, run: run, body: reply, in: &shared)
        return attention
    }

    /// Clears a question without waking its asker. Approvals can only be approved or denied.
    private func dismiss(_ id: String, in shared: inout Shared) throws(ConnectionError) -> Attention {
        let index = try openAttention(id, in: shared.workspace)
        guard !shared.workspace.attention[index].isApproval else {
            throw .commandFailed("Approve or deny a permission request")
        }
        shared.workspace.attention[index].answer = "Dismissed by the human"
        emit([.state, .attention(count: openCount(shared.workspace))], in: &shared)
        return shared.workspace.attention[index]
    }

    /// The demo's one week of tokens, for the project and provider asked about. Whatever the
    /// `days`, it reports that week, and its dates say so.
    private func usage(_ command: UsageCommand, in workspace: DemoWorkspace) -> UsageReport {
        let spent = workspace.usage.filter { spent in
            (command.projectID.map { $0 == spent.projectID } ?? true) && (command.provider.map { $0 == spent.usage.provider } ?? true)
        }
        let models = Dictionary(grouping: spent.map(\.usage), by: \.model).values.map { usages in
            ModelUsage(provider: usages[0].provider, model: usages[0].model, counts: .sum(usages.map(\.counts)), cost: .sum(usages.compactMap(\.cost)))
        }
        let coordinators = workspace.projects.compactMap { project -> CoordinatorUsage? in
            let counts = spent.filter { $0.projectID == project.id }.map(\.usage.counts)
            guard !counts.isEmpty,
                  let coordinator = workspace.sessions.first(where: { $0.projectID == project.id && $0.role == .projectOrchestrator })
            else { return nil }
            return CoordinatorUsage(id: coordinator.id, project: project.name, own: .sum([]), workers: .sum(counts))
        }
        let timeZone = TimeZone(identifier: command.timezone) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = options.now()
        let day = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day()
        return UsageReport(
            startDate: (calendar.date(byAdding: .day, value: -6, to: now) ?? now).formatted(day),
            endDate: now.formatted(day),
            totals: .sum(spent.map(\.usage.counts)),
            cost: .sum(spent.compactMap(\.usage.cost)),
            models: models.sorted { ($0.cost?.total ?? 0) > ($1.cost?.total ?? 0) },
            coordinators: coordinators
        )
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

    @discardableResult
    private func append(
        id: String, from sender: String?, to recipient: Session, body: String, attachments: [Attachment] = [], in shared: inout Shared
    ) -> Message {
        let message = Message(
            id: id,
            sequence: (shared.workspace.messages.last?.sequence ?? 0) + 1,
            projectID: recipient.projectID,
            sender: sender,
            recipient: recipient.id,
            body: body,
            receipt: "completed",
            createdAt: Int64(options.now().timeIntervalSince1970 * 1000),
            attachments: attachments
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

    /// Starts the agent's turn, as the host does when a message wakes it: a running run whose
    /// first narration step says what it is doing. Returns the run's id.
    private func startRun(of sessionID: String, in shared: inout Shared) -> String {
        let runID = "demo-run-\(UUID().uuidString)"
        let step = nextStep(id: "say", runID: runID, state: .running, text: "Reading the project's tickets…", in: &shared)
        shared.runs[sessionID] = StepPage(runID: runID, running: true, revision: step.revision, steps: [step])
        return runID
    }

    private func nextStep(id: String, runID: String, state: Step.State, text: String, in shared: inout Shared) -> Step {
        shared.stepRevision += 1
        return Step(id: id, runID: runID, kind: .narration, state: state, title: text, detail: text, seq: 0, revision: shared.stepRevision)
    }

    /// After `replyDelay`, the agent's turn ends with its reply, as the host ends one: the run's
    /// narration is its final words, and the reply is a message the agent sends itself under
    /// `output:<run>`.
    private func scheduleReply(from sessionID: String, run runID: String, body: String, in shared: inout Shared) {
        let id = UUID()
        shared.replies[id] = Task { [weak self, options] in
            try? await options.sleep(options.replyDelay)
            guard !Task.isCancelled else { return }
            self?.deliverReply(id, from: sessionID, run: runID, body: body)
        }
    }

    private func deliverReply(_ id: UUID, from sessionID: String, run runID: String, body: String) {
        shared.withLock { shared in
            guard !shared.isClosed, shared.replies.removeValue(forKey: id) != nil,
                  let sender = shared.workspace.sessions.first(where: { $0.id == sessionID }) else { return }
            let step = nextStep(id: "say", runID: runID, state: .succeeded, text: body, in: &shared)
            shared.runs[sessionID] = StepPage(runID: runID, running: false, revision: step.revision, steps: [step])
            append(id: Message.replyPrefix + runID, from: sender.id, to: sender, body: body, in: &shared)
            // A coordinator waiting only on an approval is not blocked; only a question blocks it.
            let stillAsking = shared.workspace.attention.contains {
                $0.sessionID == sessionID && $0.answer == nil && !$0.isApproval
            }
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

private extension TokenTotals {
    static func sum(_ all: [TokenTotals]) -> TokenTotals {
        TokenTotals(
            input: all.reduce(0) { $0 + $1.input },
            output: all.reduce(0) { $0 + $1.output },
            cacheRead: all.reduce(0) { $0 + $1.cacheRead },
            cacheWrite: all.reduce(0) { $0 + $1.cacheWrite },
            requests: all.reduce(0) { $0 + $1.requests }
        )
    }
}

private extension Cost {
    static func sum(_ all: [Cost]) -> Cost {
        Cost(
            input: all.reduce(0) { $0 + $1.input },
            cacheRead: all.reduce(0) { $0 + $1.cacheRead },
            cacheWrite: all.reduce(0) { $0 + $1.cacheWrite },
            output: all.reduce(0) { $0 + $1.output }
        )
    }
}
