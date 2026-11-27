import Foundation

// The desktop's tickets panel, pinned above a coordinator's conversation: which tickets it lists,
// and their status and pull request in its words and colours. Mirrors `ticket_table.rs` and
// `ticket_state_color` in the host's `workspace-desktop`.

extension Ticket {
    /// The colour a ticket's status word takes, by the desktop's roles.
    public enum StatusRole: Sendable {
        case subtle, focus, green, red
    }

    /// Accepted and closed tickets take no further agents or state changes.
    public var isOpen: Bool { state != .accepted && state != .closed }

    /// The ticket's own state in words, with the round while a review runs, such as
    /// "Verifying · round 2".
    public var statusWord: String {
        let words = state.rawValue.replacing("_", with: " ")
        let word = words.prefix(1).uppercased() + words.dropFirst()
        guard let cycle = verification, cycle.outcome == .running, !cycle.rounds.isEmpty else { return word }
        return "\(word) · round \(cycle.rounds.count)"
    }

    public var statusRole: StatusRole {
        switch state {
        case .accepted, .passed: .green
        case .blocked, .failed: .red
        case .assigned, .readyForTesting, .completed: .focus
        default: .subtle
        }
    }

    /// "#184 merged", "#12 draft", or "Not published" before the ticket has a pull request.
    public var pullRequestLabel: String {
        guard let pullRequest else { return "Not published" }
        let state = switch pullRequest.state {
        case .open where pullRequest.draft: "draft"
        default: pullRequest.state.rawValue
        }
        return "#\(pullRequest.number) \(state)"
    }

    /// The Inbox item an approval of this ticket waits on: its publish's, or its merge's.
    var waitingItems: [String] {
        [publishing?.waiting, merging?.stage.item].compactMap(\.self)
    }
}

/// A coordinator's tickets as its panel lists them: in progress, and done. Planned tickets with
/// no open pull request are neither, as their work has not started.
public struct TicketTable: Sendable {
    public let inProgress: [Ticket]
    /// The done tickets the snapshot holds; most settled ones are only in the archive.
    public let done: [Ticket]
    /// How many tickets are done, from how many the coordinator owns, so it counts those only in
    /// the archive too.
    public let doneCount: Int
    /// The tickets with an approval waiting on the human in the Inbox.
    public let needingYou: Set<String>

    public init(tickets: [Ticket], owned: Int?, openItems: Set<String>) {
        var inProgress: [Ticket] = []
        var done: [Ticket] = []
        var open = 0
        for ticket in tickets {
            guard ticket.isOpen else {
                done.append(ticket)
                continue
            }
            open += 1
            if ticket.state != .planned || ticket.pullRequest?.state == .open { inProgress.append(ticket) }
        }
        self.inProgress = inProgress
        self.done = done
        doneCount = max((owned ?? 0) - open, done.count)
        needingYou = Set(tickets.filter { $0.waitingItems.contains(where: openItems.contains) }.map(\.id))
    }

    public var isEmpty: Bool { inProgress.isEmpty && doneCount == 0 }

    /// "3 in progress, 4 done", "3 in progress" alone, or "4 done" alone.
    public var summary: String {
        switch (inProgress.count, doneCount) {
        case (0, let done): "\(done) done"
        case (let open, 0): "\(open) in progress"
        case (let open, let done): "\(open) in progress, \(done) done"
        }
    }

    public func needsYou(_ ticket: Ticket) -> Bool { needingYou.contains(ticket.id) }

    /// How many done tickets need you, which the folded done row says.
    public var doneNeedingYou: Int { done.count(where: needsYou) }
}

extension Snapshot {
    /// The coordinator's tickets as its pinned panel lists them.
    public func ticketTable(of coordinatorID: String) -> TicketTable {
        TicketTable(
            tickets: tickets.filter { $0.coordinatorID == coordinatorID },
            owned: ticketsOwned[coordinatorID],
            openItems: Set(attention.filter { $0.answer == nil }.map(\.id))
        )
    }
}
