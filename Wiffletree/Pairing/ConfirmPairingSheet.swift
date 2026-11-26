import SwiftUI
import WiffletreeDesignSystem
import WiffletreeKit

/// What the QR code said, to confirm before pairing: the host's name, how this iPhone will
/// appear on it and the addresses it will try. The Mac sets the access level.
struct ConfirmPairingSheet: View {
    let payload: QRPayload
    let deviceName: String
    let flow: PairingFlow

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                IconTile("desktopcomputer", size: 56)
                Text("Pair with \(payload.hostName)?")
                    .font(.title2.bold())
                    .padding(.top, 6)
                Text("This iPhone will appear on the Mac as **\(Pairing.deviceName(deviceName))**.")
                    .foregroundStyle(Tidal.subtle)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 18)

            VStack(spacing: 0) {
                ForEach(Array(addresses.enumerated()), id: \.offset) { index, address in
                    if index > 0 { Divider().overlay(Tidal.edge) }
                    HStack {
                        Text(address.network.route)
                        Spacer()
                        Text(address.host).foregroundStyle(Tidal.subtle).lineLimit(1).truncationMode(.middle)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                }
            }
            .background(Tidal.surface, in: .rect(cornerRadius: 12))
            .padding(.horizontal, 16)

            Text(flow.error ?? "Your Mac decides what this iPhone can do. You'll see it once paired.")
                .font(.footnote)
                .foregroundStyle(flow.error == nil ? Tidal.subtle : Tidal.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 7)

            Spacer(minLength: 20)

            VStack(spacing: 6) {
                Button {
                    Task { await flow.confirm() }
                } label: {
                    if flow.isPairing { ProgressView().tint(Tidal.onAccent) } else { Text("Pair") }
                }
                .buttonStyle(.tidal(.filled))
                .disabled(flow.isPairing)
                Button("Cancel") { flow.cancelConfirm() }
                    .buttonStyle(.tidal(.plain))
                    .disabled(flow.isPairing)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .foregroundStyle(Tidal.text)
        .background(Tidal.base)
        .presentationDetents([.large])
        .interactiveDismissDisabled(flow.isPairing)
    }

    private var addresses: [HostAddress] {
        payload.addresses.map { HostAddress(host: $0, port: payload.port) }
    }
}
