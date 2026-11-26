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
        .environment(\.showSection, ShowSectionAction { [binding = $section] in binding.wrappedValue = $0 })
    }
}

/// Moves to another of the host's tabs, for a screen that leads there, such as Home's "Need you"
/// card leading to the Inbox.
struct ShowSectionAction: Sendable {
    let show: @MainActor @Sendable (HostShell.Section) -> Void

    @MainActor func callAsFunction(_ section: HostShell.Section) {
        show(section)
    }
}

extension EnvironmentValues {
    @Entry var showSection = ShowSectionAction { _ in }
}
