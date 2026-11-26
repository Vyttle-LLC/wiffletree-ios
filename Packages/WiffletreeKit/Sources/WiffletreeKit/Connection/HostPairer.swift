import Foundation

/// Pairs with a host by the `qr` method on `/pair`, and keeps the host in a store.
public struct HostPairer: Sendable {
    /// How long each pairing step may wait for the host.
    static let stepLimit: Duration = .seconds(30)

    private let race: AddressRace
    private let store: any PairedHostStore

    public init(store: any PairedHostStore, dialer: any ChannelDialer = NetworkDialer()) {
        self.init(store: store, race: AddressRace(dialer: dialer))
    }

    init(store: any PairedHostStore, race: AddressRace) {
        self.store = store
        self.race = race
    }

    /// Pairs with the host a scanned QR code names. TLS is pinned to the code's `host_key` from
    /// the first connection, so no machine in the middle can answer.
    public func pair(_ payload: QRPayload, deviceKey: DeviceKey, deviceName: String) async throws -> PairedHost {
        let addresses = payload.addresses.map { HostAddress(host: $0, port: payload.port) }
        let (address, channel) = try await race.open(addresses, path: ChannelPath.pair, hostKey: payload.hostKey)
        defer { channel.close() }
        let pairing = QRPairing(payload: payload, deviceKey: deviceKey, deviceName: deviceName)
        try await channel.send(json: PairStart(
            method: "qr",
            deviceName: pairing.deviceName,
            deviceKey: deviceKey.publicKey.base64EncodedString(),
            proof: pairing.proof.base64EncodedString()
        ))
        switch try await channel.receive(json: PairReply.self, within: Self.stepLimit) {
        case .refused(let reason):
            throw ConnectionError.pairingRefused(reason)
        case .paired(let confirm, let hostID):
            guard let confirm = Data(base64Encoded: confirm), pairing.acceptsHost(confirmation: confirm, hostID: hostID) else {
                throw ConnectionError.confirmationFailed
            }
            let host = PairedHost(
                name: payload.hostName,
                publicKey: payload.hostKey,
                addresses: addresses.answered(at: address),
                level: .control
            )
            try store.save(host)
            return host
        }
    }
}
