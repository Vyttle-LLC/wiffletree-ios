import SwiftUI

/// First run until a host is chosen, then that host's tabs.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var isPairingAgain = false

    var body: some View {
        Group {
            if let host = app.selected {
                HostShell(host: host)
                    .id(host.id)
            } else {
                WelcomeView()
            }
        }
        .alert(
            "Pair \(app.notice?.hostName ?? "the Mac") again",
            isPresented: Binding(get: { app.notice != nil }, set: { if !$0 { app.notice = nil } }),
            presenting: app.notice
        ) { _ in
            Button("Scan QR code") { isPairingAgain = true }
            Button("Not now", role: .cancel) {}
        } message: { notice in
            Text("\(notice.reason) This iPhone has forgotten it.")
        }
        .pairingFlow(isPresented: $isPairingAgain, start: .addHost)
    }
}
