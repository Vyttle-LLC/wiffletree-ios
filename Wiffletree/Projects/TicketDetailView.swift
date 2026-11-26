import SwiftUI
import WiffletreeDesignSystem
import WiffletreeKit

/// A ticket (mockup 6): its state, branch and pull request, each review cycle's verdicts per
/// verifier and round, the findings, and the agents on it. Read-only, apart from leading to the
/// Inbox or GitHub.
struct TicketDetailView: View {
    @Environment(LiveHost.self) private var host
    let ticketID: String

    var body: some View {
        Group {
            if let snapshot = host.snapshot, let ticket = snapshot.ticket(ticketID) {
                TicketContent(ticket: ticket, snapshot: snapshot)
            } else {
                ContentUnavailableView("Ticket closed", systemImage: "checkmark.circle", description: Text("It's no longer open on the Mac."))
            }
        }
        .background(Tidal.base)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TicketContent: View {
    let ticket: Ticket
    let snapshot: Snapshot

    var body: some View {
        TidalList {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ticket.title).font(.title2.bold()).foregroundStyle(Tidal.text)
                    let state = ticket.stateLabel
                    Chip(state.text, tone: state.tone)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
            }
            Section {
                LabeledContent("Branch") {
                    Text(ticket.branch).font(.footnote.monospaced()).lineLimit(1).truncationMode(.middle)
                }
                if ticket.pullRequest == nil {
                    LabeledContent("Pull request", value: "Not published")
                }
            }
            if let pullRequest = ticket.pullRequest {
                PullRequestSection(pullRequest: pullRequest, waitsInInbox: mergeWaitsInInbox)
            }
            ReviewSections(ticket: ticket)
            AgentsSection(ticket: ticket, snapshot: snapshot)
        }
        .foregroundStyle(Tidal.text)
    }

    /// Whether the merge is approved in the Inbox: only into a branch that is not protected
    /// (design call 7). Every other pull request is merged on GitHub.
    // TODO: `!snapshot.isProtected(ticket)` and an open `merge:` approval for this ticket, once the
    // Inbox ticket's Snapshot.isProtected and Ticket.merging land; until then every merge opens GitHub.
    private var mergeWaitsInInbox: Bool { false }
}

private struct PullRequestSection: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.showSection) private var showSection
    let pullRequest: PullRequest
    let waitsInInbox: Bool

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("#\(pullRequest.number) · \(state)").font(.headline)
                    Spacer()
                    if waitsInInbox { Chip("Waiting for you", systemImage: "exclamationmark.circle", tone: .yellow) }
                }
                Text("\(checks) · into \(Text(pullRequest.base).monospaced())")
                    .font(.subheadline)
                    .foregroundStyle(Tidal.subtle)
                HStack(spacing: 10) {
                    if waitsInInbox {
                        Button("Merge in Inbox") { showSection(.inbox) }
                            .buttonStyle(.tidal(.filled))
                        Button("GitHub", action: openOnGitHub)
                            .buttonStyle(.tidal(.tinted))
                    } else {
                        Button("Open in GitHub", systemImage: "arrow.up.right.square", action: openOnGitHub)
                            .buttonStyle(.tidal(.tinted))
                    }
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 6)
        }
    }

    private func openOnGitHub() {
        if let url = URL(string: pullRequest.url) { openURL(url) }
    }

    private var state: String {
        if pullRequest.draft && pullRequest.state == .open { return "Draft" }
        return switch pullRequest.state {
        case .open: "Open"
        case .merged: "Merged"
        case .closed: "Closed"
        default: pullRequest.state.rawValue.uppercasedFirst
        }
    }

    private var checks: String {
        switch pullRequest.checks {
        case .success: "Checks passed"
        case .failure: "Checks failed"
        case .pending: "Checks running"
        default: "No checks"
        }
    }
}

/// The review: a running cycle's verifiers and its earlier rounds' findings, then every finished
/// cycle in a line, then the findings not shown above.
private struct ReviewSections: View {
    let ticket: Ticket

    var body: some View {
        if let running = ticket.verification, running.outcome == .running, let latest = running.rounds.last {
            Section("Review cycle \(running.cycle) · round \(latest.round)") {
                ForEach(Self.latestVerdicts(of: running), id: \.focus) { run in
                    VerifierRow(run: run)
                }
            }
            ForEach(running.rounds.dropLast(), id: \.round) { round in
                let findings = ticket.ledger.filter { $0.cycle == running.cycle && $0.round == round.round }
                if !findings.isEmpty {
                    Section("Round \(round.round)") {
                        ForEach(findings, id: \.id) { FindingRow(entry: $0) }
                    }
                }
            }
        }
        if !finishedCycles.isEmpty {
            Section("Review cycles") {
                ForEach(finishedCycles, id: \.cycle) { CycleRow(cycle: $0) }
            }
        }
        if !otherFindings.isEmpty {
            Section("Findings") {
                ForEach(otherFindings, id: \.id) { FindingRow(entry: $0) }
            }
        }
    }

    private var runningCycle: Int? {
        ticket.verification?.outcome == .running ? ticket.verification?.cycle : nil
    }

    private var finishedCycles: [Verification] {
        (ticket.previousCycles + [ticket.verification].compactMap { $0 }).filter { $0.outcome != .running }
    }

    private var otherFindings: [LedgerEntry] {
        ticket.ledger.filter { $0.cycle != runningCycle }
    }

    /// Each verifier's latest verdict in the cycle: only failed verifiers run again, so one that
    /// passed an earlier round stays passed.
    static func latestVerdicts(of cycle: Verification) -> [VerifierRun] {
        var latest: [String: VerifierRun] = [:]
        var order: [String] = []
        for run in cycle.rounds.flatMap(\.verifiers) {
            if latest[run.focus] == nil { order.append(run.focus) }
            latest[run.focus] = run
        }
        return order.compactMap { latest[$0] }
    }
}

private struct VerifierRow: View {
    let run: VerifierRun

    var body: some View {
        HStack {
            Text(run.focus)
            Spacer()
            let label = verdict
            StatusLabel(label.text, systemImage: label.systemImage, tone: label.tone)
        }    }

    private var verdict: (text: String, systemImage: String, tone: Tone) {
        switch run.result {
        case .passed: ("Passed", "checkmark.circle", .green)
        case .failed: ("Failed", "xmark.circle", .red)
        case .blocked: ("Blocked", "exclamationmark.octagon", .red)
        case .pending: ("Running", "circle.dotted.circle", .cyan)
        default: (run.result.rawValue.uppercasedFirst, "circle", .subtle)
        }
    }
}

private struct CycleRow: View {
    let cycle: Verification

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(["Cycle \(cycle.cycle)", cycle.level?.name].compactMap { $0 }.joined(separator: " · "))
                Text(detail).font(.subheadline).foregroundStyle(Tidal.subtle)
            }
            Spacer()
            let label = outcome
            StatusLabel(label.text, systemImage: label.systemImage, tone: label.tone)
        }    }

    /// Such as "Tests, Correctness, Regressions · 1 round".
    private var detail: String {
        let focuses = ReviewSections.latestVerdicts(of: cycle).map(\.focus)
        let rounds = cycle.rounds.count == 1 ? "1 round" : "\(cycle.rounds.count) rounds"
        return focuses.isEmpty ? rounds : "\(focuses.joined(separator: ", ")) · \(rounds)"
    }

    private var outcome: (text: String, systemImage: String, tone: Tone) {
        switch cycle.outcome {
        case .passed: ("Passed", "checkmark.circle", .green)
        case .blocked: ("Blocked", "exclamationmark.octagon", .red)
        default: (cycle.outcome.rawValue.uppercasedFirst, "circle", .subtle)
        }
    }
}

private struct FindingRow: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.summary)
                Text("\(entry.id) · \(entry.location) · \(severity)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(Tidal.subtle)
            }
            Spacer()
            let label = status
            Chip(label.text, tone: label.tone)
        }    }

    private var severity: String {
        switch entry.severity {
        case .blocking: "blocking"
        case .nonBlocking: "non-blocking"
        case .preExisting: "pre-existing"
        default: entry.severity.rawValue
        }
    }

    private var status: (text: String, tone: Tone) {
        switch entry.status {
        case .open: ("Open", .red)
        case .fixNow: ("Fix now", .yellow)
        case .untriaged: ("Untriaged", .yellow)
        case .fixed: ("Fixed", .green)
        case .followUp: ("Follow-up", .subtle)
        case .wontFix: ("Won't fix", .subtle)
        case .noted: ("Noted", .subtle)
        default: (entry.status.rawValue.uppercasedFirst, .subtle)
        }
    }
}

private struct AgentsSection: View {
    let ticket: Ticket
    let snapshot: Snapshot

    var body: some View {
        let agents = snapshot.sessions.filter { snapshot.runtime(of: $0.id)?.ticketID == ticket.id }
        if !agents.isEmpty {
            Section("Agents") {
                ForEach(agents) { agent in
                    AgentRow(agent: agent, detail: snapshot.runtime(of: agent.id)?.profile?.displayName ?? agent.provider.uppercasedFirst)
                }
            }
        }
    }
}

/// An agent with what it works on and its state in words (design call 6: read-only).
struct AgentRow: View {
    let agent: Session
    let detail: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName).foregroundStyle(Tidal.text)
                Text(detail).font(.subheadline).foregroundStyle(Tidal.subtle)
            }
            Spacer()
            let label = agent.statusLabel
            StatusLabel(label.text, systemImage: label.systemImage, tone: label.tone)
        }    }
}
