import Foundation
import Observation
import WiffletreeKit

/// The host's Inbox (design call 2): its open items newest first, sent at once when answered
/// (design call 8), and the Answered history.
///
/// A host's snapshot lists only open items, so the history is what this iPhone saw: what it
/// answered, and the items that left the Inbox otherwise, which were answered on the Mac.
@MainActor
@Observable
final class InboxModel {
    /// A decided item, newest first in `history`.
    struct Decided: Identifiable {
        enum Outcome: Equatable {
            /// A question answered here, with a choice or in the human's own words.
            case chose(String)
            case approved
            case denied
            case dismissed
            /// Answered before this iPhone saw it, with the answer the host kept.
            case answered(String)
            /// Gone from the Inbox while this iPhone watched, so answered on the Mac.
            case elsewhere
        }

        let item: InboxItem
        let outcome: Outcome
        /// When this iPhone saw it decided; nil when it was decided before.
        let at: Date?

        var id: String { item.id }

        /// Where it was asked, what was decided and when, as in "Tide alerts · approved · 8:10".
        var summary: String {
            [item.projectName, outcomeText, at?.formatted(date: .omitted, time: .shortened)]
                .compactMap(\.self)
                .joined(separator: " · ")
        }

        private var outcomeText: String {
            switch outcome {
            case .chose(let answer): "you chose \(answer)"
            case .approved: "approved"
            case .denied: "denied"
            case .dismissed: "dismissed, not answered"
            case .answered(let answer): "answered “\(answer)”"
            case .elsewhere: "answered on the Mac"
            }
        }
    }

    /// The answers the host takes for an approval: `approved`, or anything else as denied.
    static let approved = "approved"
    static let denied = "denied"
    /// What the host records for a dismissed question.
    static let dismissedAnswer = "Dismissed by the human"

    let host: LiveHost
    private(set) var history: [Decided] = []
    /// The host's refusal for each item, such as a stale answer, until it is tried again.
    private(set) var errors: [String: String] = [:]
    /// Items whose answer is on its way.
    private(set) var sending: Set<String> = []

    /// Items this iPhone has seen open, to notice those that leave the Inbox.
    @ObservationIgnored private var seenOpen: [String: InboxItem] = [:]
    @ObservationIgnored private var decidedIDs: Set<String> = []
    @ObservationIgnored private let now: () -> Date

    init(host: LiveHost, now: @escaping () -> Date = Date.init) {
        self.host = host
        self.now = now
        watchSnapshot()
    }

    /// Open items, newest first, without those just decided here.
    var open: [InboxItem] {
        guard let snapshot = host.snapshot else { return [] }
        return snapshot.attention.reversed()
            .filter { $0.answer == nil && !decidedIDs.contains($0.id) }
            .map { InboxItem($0, in: snapshot) }
    }

    var canAnswer: Bool { host.level == .control }

    /// Sends a question's answer: one of its options or the human's own words.
    func answer(_ item: InboxItem, with text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await send(item, .chose(text)) { try await $0.request(ResolveAttentionCommand(id: item.id, answer: text)) }
    }

    func approve(_ item: InboxItem) async {
        await send(item, .approved) { try await $0.request(ResolveAttentionCommand(id: item.id, answer: Self.approved)) }
    }

    func deny(_ item: InboxItem) async {
        await send(item, .denied) { try await $0.request(ResolveAttentionCommand(id: item.id, answer: Self.denied)) }
    }

    /// Clears a question without answering it or waking its asker. The host refuses it for an
    /// approval, and the refusal shows on the card.
    func dismiss(_ item: InboxItem) async {
        await send(item, .dismissed) { try await $0.request(DismissAttentionCommand(id: item.id)) }
    }

    private func send(
        _ item: InboxItem, _ outcome: Decided.Outcome,
        _ request: (any HostConnection) async throws -> Attention
    ) async {
        guard !sending.contains(item.id) else { return }
        sending.insert(item.id)
        errors[item.id] = nil
        defer { sending.remove(item.id) }
        do {
            _ = try await request(host.connection)
            decide(item, outcome, at: now())
        } catch {
            errors[item.id] = error.localizedDescription
        }
    }

    // MARK: - History

    private func watchSnapshot() {
        withObservationTracking {
            _ = host.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.noteSnapshot()
                self?.watchSnapshot()
            }
        }
        noteSnapshot()
    }

    /// Moves to the history the items decided since the last snapshot, and remembers the open ones.
    /// A restarted connection has no snapshot, and the Inbox starts over with it: the demo started
    /// over reopens the items it decided.
    private func noteSnapshot() {
        guard let snapshot = host.snapshot else {
            history = []
            errors = [:]
            seenOpen = [:]
            decidedIDs = []
            return
        }
        for attention in snapshot.attention {
            if let answer = attention.answer {
                // A host that keeps decided items, such as the demo, says how.
                let item = InboxItem(attention, in: snapshot)
                decide(item, Self.outcome(of: answer, for: item), at: seenOpen[attention.id] == nil ? nil : now())
            } else {
                seenOpen[attention.id] = InboxItem(attention, in: snapshot)
            }
        }
        let listed = Set(snapshot.attention.map(\.id))
        for (id, item) in seenOpen where !listed.contains(id) {
            decide(item, .elsewhere, at: now())
        }
    }

    private func decide(_ item: InboxItem, _ outcome: Decided.Outcome, at date: Date?) {
        seenOpen[item.id] = nil
        guard decidedIDs.insert(item.id).inserted else { return }
        errors[item.id] = nil
        let decided = Decided(item: item, outcome: outcome, at: date)
        // Newest first; those decided before this iPhone saw them go last.
        if date == nil { history.append(decided) } else { history.insert(decided, at: 0) }
    }

    private static func outcome(of answer: String, for item: InboxItem) -> Decided.Outcome {
        if answer == dismissedAnswer { return .dismissed }
        if item.isQuestion { return .answered(answer) }
        return answer == approved ? .approved : .denied
    }
}
