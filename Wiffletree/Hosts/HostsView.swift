import SwiftUI
import WiffletreeDesignSystem

/// Every paired Mac with how it is reached now, the demo host and Add a Mac (mockup 2).
struct HostsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var removing: LiveHost?
    @State private var isAddingHost = false

    var body: some View {
        NavigationStack {
            List {
                if app.hasPairedHost {
                    Section {
                        ForEach(app.hosts) { host in
                            link(host)
                                .swipeActions {
                                    Button("Remove", systemImage: "trash", role: .destructive) { removing = host }
                                }
                        }
                    } header: {
                        Text("Paired")
                    } footer: {
                        Text("Badges count what needs you on each Mac. Swipe a host to remove it.")
                    }
                }
                if let demo = app.demo {
                    Section("Explore") { link(demo) }
                }
                Section {
                    AddHostRow { isAddingHost = true }
                }
            }
            .tidalList()
            .navigationTitle("Hosts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add a Mac", systemImage: "plus") { isAddingHost = true }
                }
            }
        }
        .confirmingRemoval(of: $removing)
        .pairingFlow(isPresented: $isAddingHost, start: .addHost)
    }

    private func link(_ host: LiveHost) -> some View {
        NavigationLink {
            HostDetailView(host: host)
        } label: {
            HostRow(host: host, isCurrent: host.id == app.selectedID)
        }
        .listRowBackground(Tidal.surface)
    }
}

/// The accent action row that starts pairing a Mac.
struct AddHostRow: View {
    var title = "Add a Mac"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile("qrcode.viewfinder", fill: Tidal.accent)
                Text(title).foregroundStyle(Tidal.accent)
            }
        }
        .listRowBackground(Tidal.surface)
    }
}
