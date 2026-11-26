import Foundation

// An agent's turn output, as `workspace-core`'s `steps.rs` serialises it. A coordinator's words
// reach the human two ways: while its turn runs, as `narration` steps; when the turn ends, as its
// reply, a message it sends itself under the id `output:<run id>`.

/// One run's steps that changed after `after`: `runID` names the run, or nil for the session's
/// latest. Pass the page's `revision` back as `after` to fetch only newer changes.
public struct StepsCommand: HostCommand {
    public typealias Reply = StepPage
    public static let type = "steps"
    public let sessionID: String
    public let runID: String?
    public let after: UInt64

    public init(sessionID: String, runID: String? = nil, after: UInt64 = 0) {
        self.sessionID = sessionID
        self.runID = runID
        self.after = after
    }

    private enum CodingKeys: String, CodingKey { case sessionID = "sessionId", runID = "runId", after }
}

/// A session's steps for one run.
public struct StepPage: Decodable, Sendable {
    /// Nil when the session has never run.
    public let runID: String?
    public let running: Bool
    /// The highest revision included.
    public let revision: UInt64
    public let steps: [Step]

    private enum CodingKeys: String, CodingKey { case runID = "runId", running, revision, steps }

    public init(runID: String?, running: Bool, revision: UInt64, steps: [Step]) {
        self.runID = runID
        self.running = running
        self.revision = revision
        self.steps = steps
    }

    /// What the agent has said so far in this run, in order.
    public var narration: [Step] {
        steps.filter { $0.kind == .narration }.sorted { $0.seq < $1.seq }
    }
}

public struct Step: Decodable, Identifiable, Sendable {
    public struct Kind: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let narration = Self(rawValue: "narration")
        public static let thinking = Self(rawValue: "thinking")
        public static let command = Self(rawValue: "command")
        public static let fileEdit = Self(rawValue: "file_edit")
        public static let read = Self(rawValue: "read")
        public static let search = Self(rawValue: "search")
        public static let plan = Self(rawValue: "plan")
        public static let tool = Self(rawValue: "tool")
    }

    public struct State: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let running = Self(rawValue: "running")
        public static let succeeded = Self(rawValue: "succeeded")
        public static let failed = Self(rawValue: "failed")
        public static let interrupted = Self(rawValue: "interrupted")
    }

    /// The provider's id, unique within the run.
    public let id: String
    public let runID: String
    public let kind: Kind
    public let state: State
    /// One line, bounded by the host.
    public let title: String
    /// The whole text of a narration step, as Markdown.
    public let detail: String?
    /// Order of first appearance within the run.
    public let seq: UInt32
    public let revision: UInt64

    private enum CodingKeys: String, CodingKey { case id, runID = "runId", kind, state, title, detail, seq, revision }

    init(id: String, runID: String, kind: Kind, state: State, title: String, detail: String?, seq: UInt32, revision: UInt64) {
        self.id = id
        self.runID = runID
        self.kind = kind
        self.state = state
        self.title = title
        self.detail = detail
        self.seq = seq
        self.revision = revision
    }

    /// What the step says: its detail, or its title when it has none.
    public var text: String { detail ?? title }
}

extension Message {
    /// Who a message in a session's conversation is from, as the desktop tells them apart.
    public enum Kind: Equatable, Sendable {
        /// The human's own message, Inbox answers included.
        case human
        /// The session's reply at the end of a turn: for a coordinator, its own words.
        case reply
        /// Another agent's message, such as a child's report.
        case agent
        /// Wiffletree's notices, timer fires and compaction lines.
        case notice
    }

    /// The id prefix of a session's reply at the end of a turn; the rest is the run's id.
    static let replyPrefix = "output:"

    /// Id prefixes of the messages the host writes with no sender, which are not the human's.
    static let noticePrefixes = [
        "pr:", "keeper:", "verification:", "worktree-kept:", "migration:", "publish:", "merge:", "retarget:",
        "repository:", "processes:", "project-brief:", "child-project:", "child-question:", "child-heard:",
        "evaluation:", "assistant:", "reclaim:",
    ]

    public var kind: Kind {
        if id.hasPrefix(Self.replyPrefix) { return .reply }
        guard let sender else {
            return Self.noticePrefixes.contains { id.hasPrefix($0) } ? .notice : .human
        }
        return sender == recipient ? .notice : .agent
    }

    /// The run a reply ends, for a reply.
    public var runID: String? {
        id.hasPrefix(Self.replyPrefix) ? String(id.dropFirst(Self.replyPrefix.count)) : nil
    }
}
