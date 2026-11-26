import SwiftUI

/// A host's tabs (design call 1). Each tab owns its navigation stack and its folder; they share
/// the host through the environment.
struct HostShell: View {
    enum Section: Hashable { case projects, inbox, usage, settings }

    let host: LiveHost
    @State private var section = Section.projects

    var body: some View {
        TabView(selection: $section) {
            Tab("Projects", systemImage: "square.grid.2x2", value: .projects) {
                ProjectsTab()
            }
            Tab("Inbox", systemImage: "tray", value: .inbox) {
                InboxTab()
            }
            .badge(host.openAttentionCount)
            Tab("Usage", systemImage: "gauge.with.dots.needle.33percent", value: .usage) {
                UsageTab()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsTab()
            }
        }
        .environment(host)
    }
}
