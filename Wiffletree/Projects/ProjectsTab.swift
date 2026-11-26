import SwiftUI
import WiffletreeDesignSystem

/// Home: the host's projects. A placeholder until the Projects screens are built.
struct ProjectsTab: View {
    @Environment(AppModel.self) private var app
    @Environment(LiveHost.self) private var host

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
                        ContentUnavailableView(
                            "Projects",
                            systemImage: "square.grid.2x2",
                            description: Text(summary)
                        )
                    }
                }
            }
            .background(Tidal.base)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var summary: String {
        guard let snapshot = host.snapshot else { return "Loading \(host.name)…" }
        return "\(snapshot.projects.count) projects, \(host.openAttentionCount) need you."
    }
}
