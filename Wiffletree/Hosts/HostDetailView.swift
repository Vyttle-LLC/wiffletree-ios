import SwiftUI
import WiffletreeDesignSystem
import WiffletreeKit

/// One host: how it is reached, or why it can't be, its access level, and Remove.
struct HostDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let host: LiveHost
    @State private var removing: LiveHost?

    var body: some View {
        List {
            if host.status.kind == .unreachable {
                Section {
                    UnreachableCard(host: host)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                addresses(header: "Addresses tried", footer: host.lastFailure?.localizedDescription)
            } else if !host.isDemo {
                Section("Connection") {
                    LabeledContent("Now") {
                        StatusLabel(host.status.text, systemImage: host.status.systemImage, tone: host.status.tone)
                    }
                    .listRowBackground(Tidal.surface)
                }
                addresses(header: "Addresses", footer: nil)
            }

            if host.isDemo {
                Section {
                    Button("Start the demo over") { app.restartDemo() }
                        .listRowBackground(Tidal.surface)
                } header: {
                    Text("Demo")
                } footer: {
                    Text("Sample projects that stay on this iPhone. Replies are simulated.")
                }
            } else {
                Section("Access") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host.level.title)
                        Text(host.level.explanation).font(.subheadline).foregroundStyle(Tidal.subtle)
                    }
                    .listRowBackground(Tidal.surface)
                }
            }

            if host.id != app.selectedID {
                Section {
                    Button("Open \(host.name)") { app.select(host.id) }
                        .listRowBackground(Tidal.surface)
                }
            }

            if !host.isDemo {
                Section {
                    Button("Remove \(host.name)", role: .destructive) { removing = host }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Tidal.surface)
                }
            }
        }
        .tidalList()
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmingRemoval(of: $removing) { dismiss() }
    }

    private func addresses(header: String, footer: String?) -> some View {
        Section {
            ForEach(host.paired?.addresses ?? [], id: \.self) { address in
                VStack(alignment: .leading, spacing: 2) {
                    Text(address.host)
                    Text(address.network.title).font(.subheadline).foregroundStyle(Tidal.subtle)
                }
                .listRowBackground(Tidal.surface)
            }
        } header: {
            Text(header)
        } footer: {
            if let footer { Text(footer) }
        }
    }
}

/// A host that can't be reached: when it was last seen, the usual causes, and Try again.
struct UnreachableCard: View {
    let host: LiveHost

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(Tidal.subtle)
            Text("Can't reach \(host.name)")
                .font(.headline)
                .padding(.top, 6)
            Text(lastSeen)
                .foregroundStyle(Tidal.subtle)
            Text("Is the Mac awake, with Wiffletree open and remote access on? Away from home, turn on Tailscale or your VPN on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(Tidal.subtle)
                .padding(.top, 8)
            Button("Try again") { host.restart() }
                .buttonStyle(.tidal(.tinted))
                .frame(width: 140)
                .padding(.top, 14)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Tidal.text)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(Tidal.surface, in: .rect(cornerRadius: 14))
    }

    private var lastSeen: String {
        guard let seen = host.lastSeen else { return "Not reached yet from this iPhone." }
        let network = host.paired?.addresses.first.map { ", on \($0.network.title)" } ?? ""
        return "Last seen \(seen.formatted(.relative(presentation: .named)))\(network)."
    }
}
