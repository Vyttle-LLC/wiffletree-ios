import SwiftUI
import WiffletreeDesignSystem

/// The host's name as a large title that opens the host menu, the demo tag, and how the host is
/// reached now. Home leads with it.
struct HostHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(LiveHost.self) private var host
    @State private var isShowingHosts = false
    @State private var isAddingHost = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Menu {
                    HostMenu(current: host.id, isShowingHosts: $isShowingHosts, isAddingHost: $isAddingHost)
                } label: {
                    HStack(spacing: 6) {
                        Text(host.name)
                            .font(.largeTitle.bold())
                            .foregroundStyle(Tidal.text)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Tidal.accent)
                    }
                }
                .accessibilityHint("Switches hosts")
                if host.isDemo { DemoTag() }
            }
            if !host.isDemo {
                let status = host.status
                StatusLabel(status.text, systemImage: status.systemImage, tone: status.tone)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isShowingHosts) { HostsView() }
        .pairingFlow(isPresented: $isAddingHost, start: .addHost)
    }
}

/// Every host with how it is reached and what needs you there, then All hosts and Add a Mac.
private struct HostMenu: View {
    @Environment(AppModel.self) private var app
    let current: HostID
    @Binding var isShowingHosts: Bool
    @Binding var isAddingHost: Bool

    var body: some View {
        ForEach(app.listedHosts) { listed in
            Button {
                app.select(listed.id)
            } label: {
                if listed.id == current {
                    Label(listed.name, systemImage: "checkmark")
                } else {
                    Text(listed.name)
                }
                Text(subtitle(listed))
            }
        }
        Divider()
        Button("All hosts…", systemImage: "desktopcomputer") { isShowingHosts = true }
        Button("Add a Mac", systemImage: "qrcode.viewfinder") { isAddingHost = true }
    }

    private func subtitle(_ host: LiveHost) -> String {
        let count = host.openAttentionCount
        return count > 0 ? "\(host.status.title) · \(count) need you" : host.status.title
    }
}

/// The demo's one line on Home, until a Mac is paired (design call 11).
struct DemoStrip: View {
    @State private var isPairing = false

    var body: some View {
        HStack(spacing: 4) {
            Text("Sample data, nothing leaves this iPhone ·")
            Button("Pair your Mac") { isPairing = true }
                .fontWeight(.semibold)
        }
        .font(.footnote)
        .foregroundStyle(Tidal.cyan)
        .tint(Tidal.cyan)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(Tidal.tintCyan)
        .pairingFlow(isPresented: $isPairing, start: .addHost)
    }
}
