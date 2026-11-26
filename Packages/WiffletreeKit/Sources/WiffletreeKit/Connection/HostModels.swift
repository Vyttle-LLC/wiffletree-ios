import Foundation

// The parts of the host's workspace the first screens show, as `workspace-core` serialises them.
// Only the fields read here are modelled; the host's other fields are ignored. Enumerations the
// host may grow are open string values, so a newer host never breaks decoding.

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
    public let sessions: [Session]
    /// The Inbox: questions and approvals waiting for the human.
    public let attention: [Attention]
    public let tickets: [Ticket]

    private enum CodingKeys: String, CodingKey { case projects, sessions, attention, tickets }

    public init(projects: [Project], sessions: [Session], attention: [Attention], tickets: [Ticket]) {
        self.projects = projects
        self.sessions = sessions
        self.attention = attention
        self.tickets = tickets
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decode([Project].self, forKey: .projects)
        sessions = try container.decode([Session].self, forKey: .sessions)
        attention = try container.decode([Attention].self, forKey: .attention)
        tickets = try container.decodeIfPresent([Ticket].self, forKey: .tickets) ?? []
    }
}

public struct Project: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// The project this one is filed under.
    public let parentId: String?
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
    public let projectId: String
    public let parentId: String?
    public let name: String
    public let role: Role
    public let provider: String
    public let status: Status
}

/// A message in a conversation; one with no sender is the human's.
public struct Message: Decodable, Identifiable, Sendable {
    public let id: String
    /// Orders a session's messages; `messages` pages by it.
    public let sequence: Int64
    public let projectId: String
    public let sender: String?
    public let recipient: String
    /// Markdown.
    public let body: String
    public let receipt: String
    /// Milliseconds since the epoch.
    public let createdAt: Int64
}

/// An Inbox item: an agent's question, or an approval such as publishing a pull request.
/// Answer it with `ResolveAttention`; an approval takes the answer `approved`.
public struct Attention: Decodable, Identifiable, Sendable {
    public let id: String
    public let projectId: String
    public let sessionId: String
    /// What the item is about; approvals carry prefixes such as `publish:`.
    public let operationId: String
    public let prompt: String
    /// Suggested answers; free text is always allowed.
    public let options: [String]
    public let answer: String?

    private enum CodingKeys: String, CodingKey { case id, projectId, sessionId, operationId, prompt, options, answer }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        projectId = try container.decode(String.self, forKey: .projectId)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        operationId = try container.decode(String.self, forKey: .operationId)
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
    public let coordinatorId: String
    public let title: String
    public let brief: String
    public let branch: String
    public let state: State
    public let pullRequest: PullRequest?
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
    public let state: State
    public let draft: Bool
    /// The branch it merges into.
    public let base: String
    /// GitHub's merge state, such as `clean`, `behind` or `dirty`.
    public let mergeState: String
    public let checks: Checks
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
}

public struct TokenTotals: Decodable, Sendable {
    public let input: UInt64
    public let output: UInt64
    public let cacheRead: UInt64
    public let cacheWrite: UInt64
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
    public let usedPercent: Double?
    /// Milliseconds since the epoch.
    public let resetsAt: Int64?
}
