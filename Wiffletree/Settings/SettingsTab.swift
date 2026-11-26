import SwiftUI
import WiffletreeDesignSystem

/// The app's settings (mockup 7): paired hosts, notifications, the demo host and about.
struct SettingsTab: View {
    @Environment(AppModel.self) private var app
    @Environment(LiveHost.self) private var current
    @State private var isAddingHost = false

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            TidalList {
                Section("Hosts") {
                    ForEach(app.listedHosts) { host in
                        NavigationLink {
                            HostDetailView(host: host)
                        } label: {
                            HostRow(host: host, isCurrent: false, detail: .access)
                        }
                    }
                    AddHostRow(title: app.hasPairedHost ? "Add a Mac" : "Pair your Mac") { isAddingHost = true }
                }

                Section {
                    LabeledContent("Notifications", value: "Coming soon")
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Alerts when a coordinator needs you arrive once Wiffletree is set up with Apple.")
                }

                Section {
                    if current.isDemo {
                        Button("Start the demo over") { app.restartDemo() }
                    }
                    Toggle("Show the demo host", isOn: $app.showsDemoHost)
                        .tint(Tidal.green)
                } header: {
                    Text("Demo")
                } footer: {
                    Text("The demo host stays in Hosts after you pair a Mac, unless you hide it here.")
                }

                Section("About") {
                    LabeledContent("Version", value: Self.version)
                    LabeledContent("Privacy", value: "Data not collected")
                    Link("Source code", destination: URL(string: "https://github.com/Vyttle-LLC/wiffletree-ios")!)
                }
            }
            .navigationTitle("Settings")
        }
        .pairingFlow(isPresented: $isAddingHost, start: .addHost)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
