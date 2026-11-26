import Foundation
import WiffletreeDesignSystem
import WiffletreeKit

/// A project as Home and its conversation show it: its coordinator, tickets and open Inbox items,
/// and where its work stands in words.
struct ProjectOverview: Identifiable {
    let project: Project
    /// The project's coordinator; nil only while a snapshot is incomplete.
    let coordinator: Session?
    let tickets: [Ticket]
    /// Its Inbox items not yet answered: what its badge counts.
    let openItems: [Attention]

    var id: String { project.id }

    init(_ project: Project, in snapshot: Snapshot) {
        self.project = project
        let coordinator = snapshot.sessions.first { $0.projectID == project.id && $0.role == .projectOrchestrator && !$0.archived }
        self.coordinator = coordinator
        tickets = snapshot.tickets.filter { $0.coordinatorID == coordinator?.id && $0.state != .closed }
        openItems = snapshot.attention.filter { $0.projectID == project.id && $0.answer == nil }
    }

    var accepted: Int { tickets.count { $0.state == .accepted } }
    var inProgress: Int { tickets.count { Self.inProgress.contains($0.state) } }

    private static let implementing: Set<Ticket.State> = [.assigned, .failed, .blocked]
    private static let verifying: Set<Ticket.State> = [.readyForTesting, .verifying, .passed, .completed]
    private static let inProgress = implementing.union(verifying)

    /// The project's stage, as the desktop's progress names it.
    var phase: String {
        let states = Set(tickets.map(\.state))
        if tickets.isEmpty { return "No tickets yet" }
        if accepted == tickets.count { return "Ready to close" }
        if !states.isDisjoint(with: Self.implementing) { return "Implementing" }
        if !states.isDisjoint(with: Self.verifying) { return "Verifying" }
        return "Planning"
    }

    /// Home's line under the name, such as "Implementing · 1 of 3 tickets accepted".
    var summary: String {
        if openItems.contains(where: { !$0.isApproval }) { return "\(phase) · coordinator asked a question" }
        if tickets.isEmpty { return phase }
        if accepted == tickets.count { return "\(phase) · every ticket accepted" }
        return "\(phase) · \(accepted) of \(tickets.count) tickets accepted"
    }

    /// The ticket moving now, as the pinned card's last line names it: under review first, then
    /// being implemented.
    var activeTicket: Ticket? {
        tickets.first { $0.state == .verifying } ?? tickets.first { Self.implementing.contains($0.state) }
    }
}

extension Snapshot {
    /// Home's projects grouped by Space in the order of `spaces`; projects in no known Space come
    /// last, under no heading.
    var projectGroups: [(space: Space?, projects: [ProjectOverview])] {
        let overviews = projects.map { ProjectOverview($0, in: self) }
        var groups: [(space: Space?, projects: [ProjectOverview])] = spaces.compactMap { space in
            let members = overviews.filter { $0.project.space == space.id }
            return members.isEmpty ? nil : (space, members)
        }
        let known = Set(spaces.map(\.id))
        let loose = overviews.filter { !known.contains($0.project.space) }
        if !loose.isEmpty { groups.append((nil, loose)) }
        return groups
    }

    func overview(of projectID: String) -> ProjectOverview? {
        projects.first { $0.id == projectID }.map { ProjectOverview($0, in: self) }
    }

    /// Agents taking a turn now.
    var workingAgents: [Session] {
        sessions.filter { $0.status == .working && !$0.archived }
    }

    func runtime(of sessionID: String) -> SessionRuntime? {
        runtimes.first { $0.sessionID == sessionID }
    }

    func ticket(_ id: String?) -> Ticket? {
        tickets.first { $0.id == id }
    }

    /// Whether the ticket's merge is approved in the Inbox: its merge request waits there for the
    /// human, and it merges into a branch that is not protected (design call 7). Every other pull
    /// request is merged on GitHub.
    func mergeWaitsInInbox(_ ticket: Ticket) -> Bool {
        guard let stage = ticket.merging?.stage, stage.kind == .waitingForHuman,
              attention.contains(where: { $0.id == stage.item && $0.answer == nil && $0.operationID.hasPrefix("merge:") })
        else { return false }
        return !mergesIntoProtectedBranch(ticket)
    }

    /// The "Need you" card's sentence, such as "Station map asks “Which map tiles?”, and a
    /// publish and a merge wait for your approval."
    var needsYouSummary: String {
        let open = attention.filter { $0.answer == nil }
        let questions = open.filter { !$0.isApproval }
        let approvals = open.filter(\.isApproval)
        var parts: [String] = []
        if let question = questions.first, questions.count == 1 {
            let asker = projects.first { $0.id == question.projectID }?.name ?? "A coordinator"
            parts.append("\(asker) asks “\(question.prompt.firstLine)”")
        } else if !questions.isEmpty {
            parts.append("\(questions.count) questions wait for your answer")
        }
        if !approvals.isEmpty {
            let kinds = approvals.map(\.approvalKind).formatted(.list(type: .and))
            parts.append("\(kinds) \(approvals.count == 1 ? "waits" : "wait") for your approval")
        }
        guard let first = parts.first else { return "" }
        let sentence = parts.count == 1 ? first : "\(first), and \(parts[1].lowercasedFirst)"
        return sentence.uppercasedFirst + "."
    }
}

extension Attention {
    /// What an approval asks to do, such as "a publish".
    fileprivate var approvalKind: String {
        let kinds = ["publish:": "a publish", "merge:": "a merge", "permission:": "a permission", "retarget:": "a retarget"]
        return kinds.first { operationID.hasPrefix($0.key) }?.value ?? "a request"
    }
}

extension Ticket {
    /// The ticket's state in words with its tone, such as "Verifying · round 2".
    var stateLabel: (text: String, tone: Tone) {
        switch state {
        case .planned: ("Planned", .subtle)
        case .assigned: ("Assigned", .cyan)
        case .readyForTesting: ("Ready for testing", .cyan)
        case .verifying: (verification?.rounds.last.map { "Verifying · round \($0.round)" } ?? "Verifying", .yellow)
        case .passed: ("Passed", .green)
        case .failed: ("Failed", .red)
        case .blocked: ("Blocked", .red)
        case .completed: ("Completed", .green)
        case .accepted: ("Accepted", .green)
        case .closed: ("Closed", .subtle)
        default: (state.rawValue.replacing("_", with: " ").uppercasedFirst, .subtle)
        }
    }

    /// The short chip of the pinned ticket list, such as "Verifying · 2".
    var shortStateLabel: (text: String, tone: Tone) {
        guard state == .verifying, let round = verification?.rounds.last?.round else { return stateLabel }
        return ("Verifying · \(round)", .yellow)
    }

    /// The pinned card's line for the ticket moving now, such as "Add the alert: verifying · round 2".
    var progressLine: String {
        let words = state == .assigned ? "implementing" : stateLabel.text.lowercasedFirst
        return "\(title): \(words)"
    }
}

extension Session {
    /// The agent's state in words, with its glyph and tone.
    var statusLabel: (text: String, systemImage: String, tone: Tone) {
        if archived { return ("Archived", "archivebox", .subtle) }
        return switch status {
        case .working: ("Working", "circle.dotted.circle", .cyan)
        case .blocked: ("Needs you", "exclamationmark.circle", .yellow)
        case .ready: ("Idle", "circle", .subtle)
        case .done: ("Done", "checkmark.circle", .green)
        case .paused: ("Paused", "pause.circle", .subtle)
        case .disconnected: ("Disconnected", "bolt.horizontal.circle", .red)
        default: (status.rawValue.uppercasedFirst, "circle", .subtle)
        }
    }

    /// How the Agents list names the agent: a coordinator by its role, others by their name.
    var displayName: String {
        role == .projectOrchestrator ? "Coordinator" : name
    }
}

extension SessionRuntime.Profile {
    /// Such as "Claude Opus" or "Codex": the provider, with the model when it is a short alias.
    var displayName: String {
        let provider = provider.uppercasedFirst
        let isAlias = !model.isEmpty && model.allSatisfy(\.isLetter)
        return isAlias ? "\(provider) \(model.uppercasedFirst)" : provider
    }
}

extension String {
    var firstLine: String {
        split(separator: "\n", maxSplits: 1).first.map(String.init) ?? self
    }

    var uppercasedFirst: String { prefix(1).uppercased() + dropFirst() }
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
