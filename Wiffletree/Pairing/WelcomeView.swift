import SwiftUI
import WiffletreeDesignSystem

/// First run: Scan QR code, or Try a demo, with the note that away from home it works over a VPN.
struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @State private var isPairing = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                WiffletreeSymbol()
                    .frame(width: 112)
                Text("Wiffletree")
                    .font(.largeTitle.bold())
                    .padding(.top, 6)
                Text("Answer your coordinators, follow tickets and approve pull requests from your iPhone. Your Mac does the work.")
                    .foregroundStyle(Tidal.subtle)
                    .frame(maxWidth: 300)
            }
            .multilineTextAlignment(.center)
            .frame(maxHeight: .infinity)

            VStack(spacing: 10) {
                Button("Scan QR code") { isPairing = true }
                    .buttonStyle(.tidal(.filled))
                Button("Try a demo") { app.openDemo() }
                    .buttonStyle(.tidal(.gray))
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.body)
                    .foregroundStyle(Tidal.cyan)
                Text("At home it connects over Wi-Fi. Away from home it works over Tailscale or any VPN you already use. No account, and no servers of ours in between.")
            }
            .font(.footnote)
            .foregroundStyle(Tidal.subtle)
            .padding(.top, 14)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .foregroundStyle(Tidal.text)
        .background(Tidal.base)
        .pairingFlow(isPresented: $isPairing, start: .firstRun)
    }
}
