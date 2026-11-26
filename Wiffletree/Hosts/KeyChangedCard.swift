import SwiftUI
import WiffletreeDesignSystem

/// A host that answered with another key. Nothing connects until the person pairs it again or
/// removes it; the app never forgets it on its own, so one spoofed answer can't erase a Mac.
struct KeyChangedCard: View {
    let host: LiveHost
    var onRemoved: () -> Void = {}
    @State private var isPairingAgain = false
    @State private var removing: LiveHost?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "exclamationmark.shield")
                .font(.largeTitle)
                .foregroundStyle(Tidal.red)
            Text("This Mac's key changed")
                .font(.headline)
                .padding(.top, 6)
            Text("Wiffletree won't connect to \(host.name) until you pair again. If you didn't reinstall or reset Wiffletree on the Mac, another machine may be answering at its address.")
                .font(.subheadline)
                .foregroundStyle(Tidal.subtle)
                .padding(.top, 4)
            VStack(spacing: 6) {
                Button("Pair again", systemImage: "qrcode.viewfinder") { isPairingAgain = true }
                    .buttonStyle(.tidal(.filled))
                Button("Remove \(host.name)", role: .destructive) { removing = host }
                    .buttonStyle(.tidal(.plain))
                    .foregroundStyle(Tidal.red)
            }
            .padding(.top, 14)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Tidal.text)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(Tidal.surface, in: .rect(cornerRadius: 14))
        .confirmingRemoval(of: $removing, onRemoved: onRemoved)
        .pairingFlow(isPresented: $isPairingAgain, start: replacing)
    }

    private var replacing: PairingFlow.Start {
        if case .paired(let id) = host.id { .pairAgain(id) } else { .addHost }
    }
}
