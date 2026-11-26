import SwiftUI
import WiffletreeDesignSystem

/// The host's questions and approvals. A placeholder until the Inbox screen is built.
struct InboxTab: View {
    @Environment(LiveHost.self) private var host

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Inbox",
                systemImage: "tray",
                description: Text("\(host.openAttentionCount) questions and approvals need you on \(host.name).")
            )
            .background(Tidal.base)
            .navigationTitle("Inbox")
        }
    }
}
