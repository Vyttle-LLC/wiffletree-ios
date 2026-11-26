import SwiftUI
import WiffletreeDesignSystem
import WiffletreeKit

/// Where the Projects tab's stack goes from Home.
enum ProjectRoute: Hashable {
    case chat(projectID: String)
    case ticket(id: String)
}

/// Home (mockup 3): the host's projects grouped by Space, what needs you, and the agents working.
struct ProjectsTab: View {
    @Environment(AppModel.self) private var app
    @Environment(LiveHost.self) private var host
    @Environment(\.showSection) private var showSection
    @State private var isShowingAgents = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HostHeader()
                        .padding(.horizontal, 16)
                    if host.isDemo && !app.hasPairedHost {
                        DemoStrip()
                    }
                    switch host.status.kind {
                    case .keyChanged:
                        KeyChangedCard(host: host)
                            .padding(.horizontal, 16)
                    case .unreachable:
                        UnreachableCard(host: host)
                            .padding(.horizontal, 16)
                    default:
                        if let snapshot = host.snapshot {
                            content(snapshot)
                        } else {
                            ProgressView("Loading \(host.name)…")
                                .frame(maxWidth: .infinity, minHeight: 200)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Tidal.base)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ProjectRoute.self) { route in
                switch route {
                case .chat(let projectID): ProjectChatView(projectID: projectID)
                case .ticket(let id): TicketDetailView(ticketID: id)
                }
            }
            .sheet(isPresented: $isShowingAgents) { AgentsSheet(projectID: nil) }
        }
    }

    @ViewBuilder
    private func content(_ snapshot: Snapshot) -> some View {
        if host.openAttentionCount > 0 {
            NeedsYouCard(count: host.openAttentionCount, summary: snapshot.needsYouSummary) { showSection(.inbox) }
                .padding(.horizontal, 16)
        }
        if snapshot.projects.isEmpty {
            ContentUnavailableView("No projects", systemImage: "square.grid.2x2", description: Text("Start a project on your Mac."))
        }
        ForEach(snapshot.projectGroups, id: \.space?.id) { group in
            RowGroup(title: group.space?.name) {
                ForEach(group.projects) { overview in
                    NavigationLink(value: ProjectRoute.chat(projectID: overview.id)) {
                        ProjectRow(overview: overview)
                    }
                }
            }
        }
        RowGroup {
            Button { isShowingAgents = true } label: {
                AgentsWorkingRow(snapshot: snapshot, isDemo: host.isDemo)
            }
        }
    }
}

/// The card that leads to the Inbox when something waits for the human.
private struct NeedsYouCard: View {
    let count: Int
    let summary: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Text(count, format: .number)
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(Tidal.onAccent)
                    .frame(width: 40, height: 40)
                    .background(Tidal.yellow, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Need you").font(.headline).foregroundStyle(Tidal.text)
                    Text(summary).font(.subheadline).foregroundStyle(Tidal.subtle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Tidal.muted)
            }
            .multilineTextAlignment(.leading)
            .padding(14)
            .background(Tidal.tintYellow, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Inbox")
    }
}

private struct ProjectRow: View {
    let overview: ProjectOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(overview.project.name).font(.body.weight(.medium)).foregroundStyle(Tidal.text)
                if !overview.openItems.isEmpty { CountBadge(overview.openItems.count) }
            }
            Text(overview.summary).font(.subheadline).foregroundStyle(Tidal.subtle)
            TicketProgressBar(overview: overview)
                .padding(.top, 4)
        }
    }
}

private struct AgentsWorkingRow: View {
    let snapshot: Snapshot
    let isDemo: Bool

    var body: some View {
        let working = snapshot.workingAgents
        HStack(spacing: 12) {
            IconTile("person.2.fill", fill: Tidal.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(working.count == 1 ? "1 agent working" : "\(working.count) agents working")
                    .foregroundStyle(Tidal.text)
                Text(isDemo ? "Simulated · replies arrive in a few seconds" : projects(working))
                    .font(.subheadline)
                    .foregroundStyle(Tidal.subtle)
            }
        }
    }

    private func projects(_ working: [Session]) -> String {
        let count = Set(working.map(\.projectID)).count
        return count == 1 ? "On 1 project" : "On \(count) projects"
    }
}

/// A project's tickets as a bar: accepted in green, in progress in teal, the rest still to do.
struct TicketProgressBar: View {
    let overview: ProjectOverview

    var body: some View {
        GeometryReader { geometry in
            let total = CGFloat(max(overview.tickets.count, 1))
            HStack(spacing: 0) {
                Rectangle().fill(Tidal.green).frame(width: geometry.size.width * CGFloat(overview.accepted) / total)
                Rectangle().fill(Tidal.cyan).frame(width: geometry.size.width * CGFloat(overview.inProgress) / total)
                Spacer(minLength: 0)
            }
            .background(Tidal.overlay)
            .clipShape(.capsule)
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("\(overview.accepted) of \(overview.tickets.count) tickets accepted, \(overview.inProgress) in progress")
    }
}

/// Tappable rows on the surface, as an inset grouped list draws a section, with an optional
/// heading.
struct RowGroup<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.footnote)
                    .textCase(.uppercase)
                    .foregroundStyle(Tidal.subtle)
                    .padding(.horizontal, 16)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows.indices, id: \.self) { index in
                        rows[index]
                        if index < rows.count - 1 {
                            Divider().overlay(Tidal.edge).padding(.leading, 16)
                        }
                    }
                }
            }
            .buttonStyle(RowButtonStyle())
            .background(Tidal.surface, in: .rect(cornerRadius: 14))
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}

/// A tappable row: full width, with a disclosure chevron and the pressed highlight.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Tidal.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(.rect)
        .background(configuration.isPressed ? Tidal.overlay : .clear)
    }
}
