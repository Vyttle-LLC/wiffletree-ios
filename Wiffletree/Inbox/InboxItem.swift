import Foundation
import WiffletreeKit

/// An Inbox item as its card shows it: what kind it is, where it comes from and what it asks.
struct InboxItem: Identifiable {
    enum Kind: Equatable {
        case question
        case publish
        /// `pullRequestURL` opens the pull request on GitHub, where only the human merges into
        /// a protected base (design call 7).
        case merge(isProtected: Bool, pullRequestURL: URL?)
        /// A permission, a retarget or a repository request: approved or denied, like a publish.
        case approval(String)
    }

    let attention: Attention
    let kind: Kind
    let projectName: String
    /// Who asks: "Coordinator" for a project's coordinator, else the agent's name.
    let asker: String

    var id: String { attention.id }

    /// The prompt's first paragraph, the question itself.
    var title: String { paragraphs.first ?? attention.prompt }

    /// The rest of the prompt, the context.
    var detail: String? {
        let rest = paragraphs.dropFirst().joined(separator: "\n\n")
        return rest.isEmpty ? nil : rest
    }

    var isQuestion: Bool { kind == .question }

    /// Only a question can be dismissed; the others are approved or denied (design call 8). A
    /// UI evaluator run's Start card is answered too: dismissed, its run would wait forever.
    var canDismiss: Bool { isQuestion && !attention.operationID.hasPrefix("evaluation:start:") }

    /// What the card's header says the item is, such as "Publish".
    var kindTitle: String {
        switch kind {
        case .question: asker
        case .publish: "Publish"
        case .merge: "Merge"
        case .approval(let title): title
        }
    }

    var systemImage: String {
        switch kind {
        case .question: "questionmark.bubble"
        case .publish: "arrow.triangle.pull"
        case .merge: "arrow.triangle.merge"
        case .approval: "checkmark.shield"
        }
    }

    /// The approve button's word: "Merge" for a merge, else "Approve".
    var approveTitle: String {
        if case .merge = kind { "Merge" } else { "Approve" }
    }

    private var paragraphs: [String] {
        attention.prompt.components(separatedBy: "\n\n").filter { !$0.isEmpty }
    }

    init(_ attention: Attention, in snapshot: Snapshot) {
        self.attention = attention
        kind = Self.kind(of: attention, in: snapshot)
        projectName = snapshot.projects.first { $0.id == attention.projectID }?.name ?? "Project"
        let session = snapshot.sessions.first { $0.id == attention.sessionID }
        asker = session.map { $0.role == .projectOrchestrator ? "Coordinator" : $0.name } ?? "Agent"
    }

    private static func kind(of attention: Attention, in snapshot: Snapshot) -> Kind {
        switch attention.approval {
        case .publish:
            return .publish
        case .merge:
            // The host asks only about unprotected bases; the ticket says whether that still holds.
            let ticket = snapshot.tickets.first { $0.merging?.stage.item == attention.id }
            return .merge(
                isProtected: ticket.map(snapshot.mergesIntoProtectedBranch) ?? false,
                pullRequestURL: ticket?.pullRequest.flatMap { URL(string: $0.url) }
            )
        case .permission: return .approval("Permission")
        case .retarget: return .approval("Retarget")
        case .repository: return .approval("Repository")
        case nil: return .question
        }
    }
}
