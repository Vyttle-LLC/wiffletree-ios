import Foundation

// The parts of the host's workspace the first screens show, as `workspace-core` serialises them.
// Only the fields read here are modelled; the host's other fields are ignored. Enumerations the
// host may grow are open string values, so a newer host never breaks decoding. Ids are named
// Swift's way, `projectID`; their keys name them as `HostJSON` converts `project_id`.

/// A string value from a set the host may extend, such as a ticket's state.
public protocol OpenValue: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible where RawValue == String {
    init(rawValue: String)
}

extension OpenValue {
    public var description: String { rawValue }
}

/// What `snapshot` answers: the live workspace.
public struct Snapshot: Decodable, Sendable {
    public let projects: [Project]
    public let spaces: [Space]
    public let sessions: [Session]
    /// What each session is assigned to and runs on.
    public let runtimes: [SessionRuntime]
    /// The Inbox: questions and approvals waiting for the human.
    public let attention: [Attention]
    public let tickets: [Ticket]
    public let repositories: [Repository]
    /// By coordinator, how many tickets it owns, open or not; most settled ones are only in the
    /// archive. An older host leaves it out.
    public let ticketsOwned: [String: Int]

    private enum CodingKeys: String, CodingKey { case projects, spaces, sessions, runtimes, attention, tickets, repositories, ticketsOwned }

    public init(
        projects: [Project], spaces: [Space] = [], sessions: [Session], runtimes: [SessionRuntime] = [],
        attention: [Attention], tickets: [Ticket], repositories: [Repository] = [], ticketsOwned: [String: Int] = [:]
    ) {
        self.projects = projects
        self.spaces = spaces
        self.sessions = sessions
        self.runtimes = runtimes
        self.attention = attention
        self.tickets = tickets
        self.repositories = repositories
        self.ticketsOwned = ticketsOwned
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decode([Project].self, forKey: .projects)
        spaces = try container.decodeIfPresent([Space].self, forKey: .spaces) ?? []
        sessions = try container.decode([Session].self, forKey: .sessions)
        runtimes = try container.decodeIfPresent([SessionRuntime].self, forKey: .runtimes) ?? []
        attention = try container.decode([Attention].self, forKey: .attention)
        tickets = try container.decodeIfPresent([Ticket].self, forKey: .tickets) ?? []
        repositories = try container.decodeIfPresent([Repository].self, forKey: .repositories) ?? []
        ticketsOwned = try container.decodeIfPresent([String: Int].self, forKey: .ticketsOwned) ?? [:]
    }

    /// The projects still open. Archiving a project's coordinator closes the project, and the
    /// snapshot leaves an archived coordinator out, so a project is open while it has an
    /// unarchived one, whoever its parent is: an Assistant's `start_work` project's coordinator
    /// has the Assistant, which no snapshot lists, as its parent.
    public var openProjects: [Project] {
        let open = Set(sessions.filter { $0.role == .projectOrchestrator && !$0.archived }.map(\.projectID))
        return projects.filter { open.contains($0.id) }
    }

    /// This snapshot without the closed projects, their sessions and their Inbox items. The host
    /// still reports a closed project's open items and its open tickets' archived agents.
    public func withoutClosedProjects() -> Snapshot {
        let open = openProjects
        let openIDs = Set(open.map(\.id))
        return Snapshot(
            projects: open, spaces: spaces,
            sessions: sessions.filter { openIDs.contains($0.projectID) }, runtimes: runtimes,
            attention: attention.filter { openIDs.contains($0.projectID) }, tickets: tickets, repositories: repositories,
            ticketsOwned: ticketsOwned
        )
    }

    /// Whether only the human may merge into the ticket's pull request's base, on GitHub. A ticket
    /// whose repository is not listed counts as protected, so the phone never offers its merge.
    public func mergesIntoProtectedBranch(_ ticket: Ticket) -> Bool {
        guard let base = ticket.pullRequest?.base ?? ticket.merging?.base else { return false }
        guard let repository = repositories.first(where: { $0.id == ticket.repositoryID }) else { return true }
        return repository.protects(base)
    }
}

/// A Space: a group of projects that share a brain, as the desktop sidebar groups them.
public struct Space: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
}

/// What a session is assigned to and runs on.
public struct SessionRuntime: Decodable, Sendable {
    public struct Profile: Decodable, Sendable {
        public let provider: String
        /// Such as `opus`.
        public let model: String
    }

    public let sessionID: String
    /// The ticket a ticket agent works on.
    public let ticketID: String?
    public let profile: Profile?

    private enum CodingKeys: String, CodingKey { case sessionID = "sessionId", ticketID = "ticketId", profile }
}

public struct Project: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// The Space it belongs to; empty from an older host.
    public let space: String
    /// The project this one is filed under.
    public let parentID: String?

    private enum CodingKeys: String, CodingKey { case id, name, space, parentID = "parentId" }

    init(id: String, name: String, space: String = "", parentID: String? = nil) {
        self.id = id
        self.name = name
        self.space = space
        self.parentID = parentID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        space = try container.decodeIfPresent(String.self, forKey: .space) ?? ""
        parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
    }
}

/// An agent: a coordinator, an implementer, a verifier.
public struct Session: Decodable, Identifiable, Sendable {
    public struct Role: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let projectOrchestrator = Self(rawValue: "project_orchestrator")
        public static let implementer = Self(rawValue: "implementer")
        public static let tester = Self(rawValue: "tester")
        public static let reviewer = Self(rawValue: "reviewer")
    }

    public struct Status: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let ready = Self(rawValue: "ready")
        public static let working = Self(rawValue: "working")
        public static let blocked = Self(rawValue: "blocked")
        public static let done = Self(rawValue: "done")
        public static let paused = Self(rawValue: "paused")
        public static let disconnected = Self(rawValue: "disconnected")
    }

    public let id: String
    public let projectID: String
    public let parentID: String?
    public let name: String
    public let role: Role
    public let provider: String
    public internal(set) var status: Status
    /// An archived session appears only while its open ticket does.
    public let archived: Bool

    private enum CodingKeys: String, CodingKey {
        case id, projectID = "projectId", parentID = "parentId", name, role, provider, status, archived
    }

    init(id: String, projectID: String, parentID: String?, name: String, role: Role, provider: String, status: Status, archived: Bool = false) {
        self.id = id
        self.projectID = projectID
        self.parentID = parentID
        self.name = name
        self.role = role
        self.provider = provider
        self.status = status
        self.archived = archived
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        projectID = try container.decode(String.self, forKey: .projectID)
        parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
        name = try container.decode(String.self, forKey: .name)
        role = try container.decode(Role.self, forKey: .role)
        provider = try container.decode(String.self, forKey: .provider)
        status = try container.decode(Status.self, forKey: .status)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }
}

/// A message in a conversation; one with no sender is the human's.
public struct Message: Decodable, Identifiable, Sendable {
    public let id: String
    /// Orders a session's messages; `messages` pages by it.
    public let sequence: Int64
    public let projectID: String
    public let sender: String?
    public let recipient: String
    /// Markdown.
    public let body: String
    public let receipt: String
    /// Milliseconds since the epoch.
    public let createdAt: Int64
    /// Only the human's messages carry attachments.
    public let attachments: [Attachment]

    init(
        id: String, sequence: Int64, projectID: String, sender: String?, recipient: String, body: String,
        receipt: String, createdAt: Int64, attachments: [Attachment] = []
    ) {
        self.id = id
        self.sequence = sequence
        self.projectID = projectID
        self.sender = sender
        self.recipient = recipient
        self.body = body
        self.receipt = receipt
        self.createdAt = createdAt
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id, sequence, projectID = "projectId", sender, recipient, body, receipt, createdAt, attachments
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sequence = try container.decode(Int64.self, forKey: .sequence)
        projectID = try container.decode(String.self, forKey: .projectID)
        sender = try container.decodeIfPresent(String.self, forKey: .sender)
        recipient = try container.decode(String.self, forKey: .recipient)
        body = try container.decode(String.self, forKey: .body)
        receipt = try container.decode(String.self, forKey: .receipt)
        createdAt = try container.decode(Int64.self, forKey: .createdAt)
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
    }
}

/// A file on a sent message: the host's read-only copy, which `ReadFileCommand` fetches.
public struct Attachment: Decodable, Equatable, Sendable {
    /// The copy's path on the host.
    public let path: String
    public let size: UInt64
    /// The image format, such as `jpeg`, when the file is an image the host recognised.
    public let image: String?

    public init(path: String, size: UInt64, image: String?) {
        self.path = path
        self.size = size
        self.image = image
    }

    public var name: String { (path as NSString).lastPathComponent }
}

/// An Inbox item: an agent's question, or an approval such as publishing a pull request.
/// Answer it with `ResolveAttention`; an approval takes the answer `approved`.
public struct Attention: Decodable, Identifiable, Sendable {
    public let id: String
    public let projectID: String
    public let sessionID: String
    /// What the item is about; approvals carry prefixes such as `publish:`.
    public let operationID: String
    public let prompt: String
    /// Suggested answers; free text is always allowed.
    public let options: [String]
    public internal(set) var answer: String?

    private enum CodingKeys: String, CodingKey {
        case id, projectID = "projectId", sessionID = "sessionId", operationID = "operationId", prompt, options, answer
    }

    init(id: String, projectID: String, sessionID: String, operationID: String, prompt: String, options: [String] = [], answer: String? = nil) {
        self.id = id
        self.projectID = projectID
        self.sessionID = sessionID
        self.operationID = operationID
        self.prompt = prompt
        self.options = options
        self.answer = answer
    }

    /// What an approval asks for, named by its operation id's prefix as the host writes it, such
    /// as `publish:`.
    public enum Approval: String, CaseIterable, Sendable {
        case permission, publish, merge, retarget, repository
    }

    /// The approval this item is, or nil for a question.
    public var approval: Approval? {
        Approval.allCases.first { operationID.hasPrefix("\($0.rawValue):") }
    }

    /// An approval is approved or denied, never dismissed.
    public var isApproval: Bool { approval != nil }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        projectID = try container.decode(String.self, forKey: .projectID)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        operationID = try container.decode(String.self, forKey: .operationID)
        prompt = try container.decode(String.self, forKey: .prompt)
        options = try container.decodeIfPresent([String].self, forKey: .options) ?? []
        answer = try container.decodeIfPresent(String.self, forKey: .answer)
    }
}

public struct Ticket: Decodable, Identifiable, Sendable {
    public struct State: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let planned = Self(rawValue: "planned")
        public static let assigned = Self(rawValue: "assigned")
        public static let readyForTesting = Self(rawValue: "ready_for_testing")
        public static let verifying = Self(rawValue: "verifying")
        public static let passed = Self(rawValue: "passed")
        public static let failed = Self(rawValue: "failed")
        public static let blocked = Self(rawValue: "blocked")
        public static let completed = Self(rawValue: "completed")
        public static let accepted = Self(rawValue: "accepted")
        public static let closed = Self(rawValue: "closed")
    }

    public let id: String
    /// The project coordinator that owns the ticket.
    public let coordinatorID: String
    public let repositoryID: String?
    public let title: String
    public let brief: String
    public let branch: String
    public internal(set) var state: State
    /// The latest review cycle.
    public let verification: Verification?
    /// Earlier review cycles, oldest first.
    public let previousCycles: [Verification]
    /// Every finding verifiers recorded, across all cycles.
    public let ledger: [LedgerEntry]
    public internal(set) var pullRequest: PullRequest?
    /// The publish the coordinator asked for, while its step runs or waits for the human.
    public internal(set) var publishing: PublishRequest?
    /// The merge the coordinator asked for, while the host carries it out.
    public internal(set) var merging: MergeRequest?

    private enum CodingKeys: String, CodingKey {
        case id, coordinatorID = "coordinatorId", repositoryID = "repositoryId", title, brief, branch, state, verification,
             previousCycles, ledger, pullRequest, publishing, merging
    }

    init(
        id: String, coordinatorID: String, repositoryID: String? = nil, title: String, brief: String, branch: String, state: State,
        verification: Verification? = nil, previousCycles: [Verification] = [], ledger: [LedgerEntry] = [],
        pullRequest: PullRequest? = nil, publishing: PublishRequest? = nil, merging: MergeRequest? = nil
    ) {
        self.id = id
        self.coordinatorID = coordinatorID
        self.repositoryID = repositoryID
        self.title = title
        self.brief = brief
        self.branch = branch
        self.state = state
        self.verification = verification
        self.previousCycles = previousCycles
        self.ledger = ledger
        self.pullRequest = pullRequest
        self.publishing = publishing
        self.merging = merging
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        coordinatorID = try container.decode(String.self, forKey: .coordinatorID)
        repositoryID = try container.decodeIfPresent(String.self, forKey: .repositoryID)
        title = try container.decode(String.self, forKey: .title)
        brief = try container.decode(String.self, forKey: .brief)
        branch = try container.decode(String.self, forKey: .branch)
        state = try container.decode(State.self, forKey: .state)
        verification = try container.decodeIfPresent(Verification.self, forKey: .verification)
        previousCycles = try container.decodeIfPresent([Verification].self, forKey: .previousCycles) ?? []
        ledger = try container.decodeIfPresent([LedgerEntry].self, forKey: .ledger) ?? []
        pullRequest = try container.decodeIfPresent(PullRequest.self, forKey: .pullRequest)
        publishing = try container.decodeIfPresent(PublishRequest.self, forKey: .publishing)
        merging = try container.decodeIfPresent(MergeRequest.self, forKey: .merging)
    }
}

/// A review cycle: rounds of verifiers checking one ticket until they pass or it runs out of
/// rounds.
public struct Verification: Decodable, Sendable {
    public struct Outcome: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let running = Self(rawValue: "running")
        public static let passed = Self(rawValue: "passed")
        public static let blocked = Self(rawValue: "blocked")
    }

    public let cycle: Int
    /// Such as "Full"; a cycle from before levels has none.
    public let level: CycleLevel?
    public let maxRounds: Int
    public let outcome: Outcome
    public let rounds: [VerificationRound]
}

public struct CycleLevel: Decodable, Sendable {
    public struct Kind: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let fullReview = Self(rawValue: "full_review")
        public static let recheck = Self(rawValue: "recheck")
    }

    public let name: String
    public let kind: Kind
}

public struct VerificationRound: Decodable, Sendable {
    public let round: Int
    /// The commit every verifier of the round checks.
    public let commit: String
    public let verifiers: [VerifierRun]
}

/// One verifier's part in a round.
public struct VerifierRun: Decodable, Sendable {
    public struct Result: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let pending = Self(rawValue: "pending")
        public static let passed = Self(rawValue: "passed")
        public static let failed = Self(rawValue: "failed")
        public static let blocked = Self(rawValue: "blocked")
    }

    public let sessionID: String
    public let role: Session.Role
    /// Tells verifiers apart on a ticket, such as "Correctness".
    public let focus: String
    public let result: Result

    private enum CodingKeys: String, CodingKey { case sessionID = "sessionId", role, focus, result }
}

/// A verifier's finding on a ticket, with where it stands.
public struct LedgerEntry: Decodable, Sendable {
    public struct Status: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let open = Self(rawValue: "open")
        public static let fixed = Self(rawValue: "fixed")
        public static let untriaged = Self(rawValue: "untriaged")
        public static let noted = Self(rawValue: "noted")
        public static let fixNow = Self(rawValue: "fix_now")
        public static let followUp = Self(rawValue: "follow_up")
        public static let wontFix = Self(rawValue: "wont_fix")
    }

    public struct Severity: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let blocking = Self(rawValue: "blocking")
        public static let nonBlocking = Self(rawValue: "non_blocking")
        public static let preExisting = Self(rawValue: "pre_existing")
    }

    /// `F1`, `F2`, … within the ticket.
    public let id: String
    public let severity: Severity
    /// `path:line`.
    public let location: String
    public let summary: String
    /// The verifier focus, cycle and round that last reported it.
    public let focus: String
    public let cycle: Int
    public let round: Int
    public let status: Status
}

/// A ticket branch's GitHub pull request, as the host last read it.
public struct PullRequest: Decodable, Sendable {
    public struct State: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let open = Self(rawValue: "open")
        public static let closed = Self(rawValue: "closed")
        public static let merged = Self(rawValue: "merged")
    }

    public struct Checks: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let none = Self(rawValue: "none")
        public static let pending = Self(rawValue: "pending")
        public static let success = Self(rawValue: "success")
        public static let failure = Self(rawValue: "failure")
    }

    public let number: Int
    public let url: String
    public internal(set) var state: State
    public let draft: Bool
    /// The branch it merges into.
    public let base: String
    /// GitHub's merge state, such as `clean`, `behind` or `dirty`.
    public let mergeState: String
    public let checks: Checks
}

/// A coordinator's `publish_ticket`, while its step runs or waits for the human.
public struct PublishRequest: Decodable, Sendable {
    /// The Inbox item the step waits on.
    public let waiting: String?
}

/// A coordinator's `merge_ticket`, while the host carries it out.
public struct MergeRequest: Decodable, Sendable {
    public struct Stage: Decodable, Sendable {
        public struct Kind: OpenValue {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }
            public static let waitingForHuman = Self(rawValue: "waiting_for_human")
        }

        public let kind: Kind
        /// The Inbox item that asks the human, while the stage waits for them.
        public let item: String?
    }

    public let number: Int
    /// The branch it merges into.
    public let base: String
    public let stage: Stage
}
/// What `usage` answers, in part: the period's tokens and their estimated cost.
public struct UsageReport: Decodable, Sendable {
    public let startDate: String
    public let endDate: String
    public let totals: TokenTotals
    /// What the priced requests would cost at list price, in US dollars.
    public let cost: Cost?
    /// Every model used, most expensive first.
    public let models: [ModelUsage]?
    /// Each coordinator's tokens, its team's included.
    public let coordinators: [CoordinatorUsage]
}

public struct CoordinatorUsage: Decodable, Sendable {
    public let id: String
    /// The coordinator's project, by name.
    public let project: String
    public let own: TokenTotals
    public let workers: TokenTotals
}

public struct TokenTotals: Decodable, Sendable {
    /// Every input token, those read from and written to the cache included.
    public let input: UInt64
    public let output: UInt64
    public let cacheRead: UInt64
    public let cacheWrite: UInt64
    public let requests: UInt64

    /// Input and output, as the host totals them.
    public var total: UInt64 { input + output }
}

public struct Cost: Decodable, Sendable {
    public let input: Double
    public let cacheRead: Double
    public let cacheWrite: Double
    public let output: Double

    public var total: Double { input + cacheRead + cacheWrite + output }
}

public struct ModelUsage: Decodable, Sendable {
    public let provider: String
    public let model: String
    public let counts: TokenTotals
    public let cost: Cost?
}

/// A provider's quota windows, as `quotas` answers them.
public struct QuotaReading: Decodable, Sendable {
    public let provider: String
    public let account: String?
    /// Milliseconds since the epoch.
    public let observedAt: Int64
    public let windows: [QuotaWindow]
    public let error: String?
}

public struct QuotaWindow: Decodable, Sendable {
    public let key: String
    /// Such as "5 hours" or "Weekly".
    public let label: String
    /// Nil when the provider has not reported it: unavailable, never zero.
    public let usedPercent: Double?
    /// When the provider last reported this window, in milliseconds since the epoch.
    public let observedAt: Int64
    /// The window's length, such as 300 for five hours.
    public let durationMinutes: UInt64?
    /// Milliseconds since the epoch.
    public let resetsAt: Int64?

    private enum CodingKeys: String, CodingKey { case key, label, usedPercent, observedAt, durationMinutes = "durationMins", resetsAt }
}

/// `upload_attachment`'s reply: how many bytes of the upload the host holds, where the next
/// piece starts.
public struct Uploaded: Decodable, Equatable, Sendable {
    public let uploadID: String
    public let stored: Int

    public init(uploadID: String, stored: Int) {
        self.uploadID = uploadID
        self.stored = stored
    }

    private enum CodingKeys: String, CodingKey { case uploadID = "uploadId", stored }
}

/// `read_file`'s reply.
public struct FileContents: Decodable, Sendable {
    /// The path once the host resolved it.
    public let path: String
    /// The file's bytes, base64.
    public let data: String

    public init(path: String, data: String) {
        self.path = path
        self.data = data
    }

    public var bytes: Data? { Data(base64Encoded: data) }
}
