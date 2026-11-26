import SwiftUI
import WiffletreeDesignSystem

/// A host in a list: its name with how it is reached now, or its access level as Settings
/// shows it, and what needs you there.
struct HostRow: View {
    enum Detail { case status, access }

    let host: LiveHost
    let isCurrent: Bool
    var detail = Detail.status

    var body: some View {
        HStack(spacing: 12) {
            IconTile(host.isDemo ? "sparkles" : "desktopcomputer", fill: host.isConnected && !host.isDemo ? Tidal.cyan : nil)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(host.name)
                    if host.isDemo { DemoTag(size: .small) }
                }
                subtitle
            }
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Tidal.accent)
                    .accessibilityLabel("Current host")
            } else if host.openAttentionCount > 0 {
                CountBadge(host.openAttentionCount)
            }
        }
    }

    @ViewBuilder private var subtitle: some View {
        let status = host.status
        switch (detail, host.isDemo) {
        case (_, true):
            Text(detail == .access ? "Built in · sample data" : "Sample projects, no Mac needed")
                .font(.subheadline)
                .foregroundStyle(Tidal.subtle)
        case (.status, false):
            StatusLabel(status.text, systemImage: status.systemImage, tone: status.tone)
        case (.access, false):
            Text("\(host.level.title) · \(status.title)")
                .font(.subheadline)
                .foregroundStyle(Tidal.subtle)
        }
    }
}

extension View {
    /// Asks before forgetting a host, saying what happens on each side.
    func confirmingRemoval(of host: Binding<LiveHost?>, onRemoved: @escaping () -> Void = {}) -> some View {
        modifier(RemoveHostConfirmation(host: host, onRemoved: onRemoved))
    }
}

private struct RemoveHostConfirmation: ViewModifier {
    @Environment(AppModel.self) private var app
    @Binding var host: LiveHost?
    let onRemoved: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Remove \(host?.name ?? "this Mac")?",
            isPresented: Binding(get: { host != nil }, set: { if !$0 { host = nil } }),
            titleVisibility: .visible,
            presenting: host
        ) { host in
            Button("Remove \(host.name)", role: .destructive) {
                if case .paired(let id) = host.id { app.remove(id) }
                onRemoved()
            }
        } message: { _ in
            Text("This iPhone forgets its key. To use it again, scan a new QR code on that Mac. The Mac still lists this iPhone until you remove it there too.")
        }
    }
}
