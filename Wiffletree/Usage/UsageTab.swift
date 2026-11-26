import SwiftUI
import WiffletreeDesignSystem

/// Provider limits and tokens. A placeholder until the Usage screen is built.
struct UsageTab: View {
    @Environment(LiveHost.self) private var host

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Usage",
                systemImage: "gauge.with.dots.needle.33percent",
                description: Text("Account limits and tokens on \(host.name).")
            )
            .background(Tidal.base)
            .navigationTitle("Usage")
        }
    }
}
