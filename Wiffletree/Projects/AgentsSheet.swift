import SwiftUI
import WiffletreeDesignSystem
import WiffletreeKit

/// Who is working on what, by project: the agents taking a turn and each coordinator. A glance,
/// not a control panel (design call 6): stopping and restarting stay on the Mac.
struct AgentsSheet: View {
    @Environment(LiveHost.self) private var host
    @Environment(\.dismiss) private var dismiss
    /// One project's agents, or every project's when nil.
    let projectID: String?

    var body: some View {
        NavigationStack {
            TidalList {
                if let snapshot = host.snapshot {
                    ForEach(projects(snapshot)) { project in
                        let agents = Self.agents(of: project.id, in: snapshot)
                        if !agents.isEmpty {
                            Section(project.name) {
                                ForEach(agents) { AgentRow(agent: $0, detail: detail($0, in: snapshot)) }
                            }
                        }
                    }
                }
                Section {
                } footer: {
                    Text("Read-only on iPhone. Stop and restart agents on the Mac.")
                }
            }
            .navigationTitle("Agents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func projects(_ snapshot: Snapshot) -> [Project] {
        snapshot.projects.filter { projectID == nil || $0.id == projectID }
    }

    /// A project's working agents, then its coordinator.
    static func agents(of projectID: String, in snapshot: Snapshot) -> [Session] {
        let sessions = snapshot.sessions.filter { $0.projectID == projectID && !$0.archived }
        let working = sessions.filter { $0.status == .working && $0.role != .projectOrchestrator }
        return working + sessions.filter { $0.role == .projectOrchestrator }
    }

    /// Such as "Add the tidepool alert command · Codex", or "Waiting for your answer · Claude Opus".
    private func detail(_ agent: Session, in snapshot: Snapshot) -> String {
        let runtime = snapshot.runtime(of: agent.id)
        let model = runtime?.profile?.displayName ?? agent.provider.uppercasedFirst
        let work = agent.status == .blocked ? "Waiting for your answer" : snapshot.ticket(runtime?.ticketID)?.title
        return [work, model].compactMap { $0 }.joined(separator: " · ")
    }
}
