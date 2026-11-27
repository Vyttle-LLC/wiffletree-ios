import SwiftUI
import WiffletreeDesignSystem
import WiffletreeKit

/// The line pinned above a project's conversation, "Tickets · 3 in progress, 4 done", saying
/// when a ticket needs you (design call 15). Tapping it opens the tickets sheet.
struct PinnedTicketsLine: View {
    let table: TicketTable
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                TicketsSummary(table: table)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !table.needingYou.isEmpty {
                    NeedsYouMark(text: "\(table.needingYou.count) needs you")
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Tidal.muted)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Tidal.surface, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tidal.edge, lineWidth: 0.5))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Lists the tickets")
    }
}

/// The desktop's pinned tickets panel as a sheet (design calls 16–20): tickets in progress, then
/// the done ones folded. A row's pull request link opens GitHub; the rest of it pushes the
/// ticket's detail inside the sheet. It follows the snapshot while open.
struct TicketsSheet: View {
    @Environment(LiveHost.self) private var host
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showSection) private var showSection
    let coordinatorID: String
    @State private var isShowingDone = false

    var body: some View {
        NavigationStack {
            let table = host.snapshot?.ticketTable(of: coordinatorID)
            TidalList {
                if let table {
                    Section {
                        ForEach(table.inProgress) { TicketRow(ticket: $0, needsYou: table.needsYou($0)) }
                        if table.doneCount > 0 && !isShowingDone {
                            doneToggle(table)
                        }
                    } header: {
                        header(table)
                    }
                    if table.doneCount > 0 && isShowingDone {
                        Section {
                            ForEach(table.done) { TicketRow(ticket: $0, needsYou: table.needsYou($0)) }
                        } header: {
                            doneToggle(table)
                        } footer: {
                            if table.done.count < table.doneCount {
                                Text("\(table.doneCount - table.done.count) more in the archive on the Mac.")
                            }
                        }
                    }
                }
                Section {
                } footer: {
                    Text("Planned tickets without an open pull request are not listed until work starts, as on the desktop.")
                }
            }
            .navigationTitle("Tickets")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ProjectRoute.self) { route in
                if case .ticket(let id) = route { TicketDetailView(ticketID: id) }
            }
        }
        // Leading to the Inbox from a ticket closes the sheet first.
        .environment(\.showSection, ShowSectionAction { [dismiss, showSection] section in
            dismiss()
            showSection(section)
        })
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Tidal.base)
    }

    private func header(_ table: TicketTable) -> some View {
        HStack(alignment: .firstTextBaseline) {
            TicketsSummary(table: table).font(.subheadline)
            Spacer()
            Text("Live from Wiffletree").font(.caption).foregroundStyle(Tidal.subtle)
        }
        .textCase(nil)
        .lineLimit(1)
        .padding(.top, 12)
    }

    /// "› 4 done", which unfolds the done tickets, saying when one of them needs you.
    private func doneToggle(_ table: TicketTable) -> some View {
        Button {
            withAnimation(.snappy) { isShowingDone.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isShowingDone ? "chevron.down" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                Text("\(table.doneCount) done")
                Spacer()
                if table.doneNeedingYou > 0 {
                    NeedsYouMark(text: "\(table.doneNeedingYou) needs you")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Tidal.subtle)
            .textCase(nil)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(isShowingDone ? "Hides the done tickets" : "Lists the done tickets")
    }
}

/// "Tickets · 3 in progress, 4 done".
private struct TicketsSummary: View {
    let table: TicketTable

    var body: some View {
        Text("\(Text("Tickets").fontWeight(.semibold).foregroundStyle(Tidal.text)) · \(table.summary)")
            .foregroundStyle(Tidal.subtle)
    }
}

/// One ticket on two lines: its title, then its status word in its colour and its pull request.
private struct TicketRow: View {
    @Environment(\.openURL) private var openURL
    let ticket: Ticket
    let needsYou: Bool

    var body: some View {
        NavigationLink(value: ProjectRoute.ticket(id: ticket.id)) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(ticket.title).foregroundStyle(Tidal.text).lineLimit(1)
                    if needsYou {
                        Spacer(minLength: 0)
                        NeedsYouMark(text: "Needs you")
                    }
                }
                HStack(spacing: 8) {
                    Text(ticket.statusWord).foregroundStyle(ticket.statusRole.tone.color)
                    Spacer(minLength: 0)
                    pullRequest
                }
                .font(.subheadline)
                .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var pullRequest: some View {
        if let url = ticket.pullRequest.flatMap({ URL(string: $0.url) }) {
            Button { openURL(url) } label: {
                Text("\(Text(ticket.pullRequestLabel).underline()) \(Text("↗").font(.caption))")
                    .foregroundStyle(Tidal.blue)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Pull request \(ticket.pullRequestLabel)")
            .accessibilityHint("Opens GitHub")
        } else {
            Text(ticket.pullRequestLabel).foregroundStyle(Tidal.subtle)
        }
    }
}

/// "1 needs you" in yellow, with a question glyph.
struct NeedsYouMark: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "questionmark.circle")
            .labelStyle(.tight)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Tidal.yellow)
            .lineLimit(1)
            .fixedSize()
    }
}
