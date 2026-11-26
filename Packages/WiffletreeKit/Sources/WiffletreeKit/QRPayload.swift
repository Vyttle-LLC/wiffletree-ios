import Foundation

/// What a host's pairing QR code holds:
/// `{"host_key": "…", "host_name": "Studio Mac", "addresses": ["192.168.1.20", "studio.tail4c2e.ts.net"], "port": 47821, "secret": "…"}`,
/// with the key and the secret in standard base64.
public struct QRPayload: Sendable, Equatable {
    /// The host's public key, SEC1 uncompressed; TLS is pinned to it from the first connection.
    public let hostKey: Data
    public let hostName: String
    /// LAN addresses first, then Tailscale ones and names, in the order the host gave them.
    public let addresses: [String]
    public let port: UInt16
    /// The one-time secret that keys the proof and the host's confirmation.
    public let secret: Data

    public static let secretLength = 16

    public var hostID: KeyID { KeyID(publicKey: hostKey) }

    /// Parses a scanned QR code's text, refusing anything that would not pair.
    public init(scanned text: String) throws(QRPayloadError) {
        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: Data(text.utf8))
        } catch {
            throw .notAPairingCode
        }
        guard let hostKey = Data(base64Encoded: wire.hostKey), isPublicKey(hostKey) else { throw .invalidHostKey }
        guard let secret = Data(base64Encoded: wire.secret), secret.count == Self.secretLength else { throw .invalidSecret }
        guard !wire.hostName.isEmpty else { throw .missingHostName }
        let addresses = wire.addresses.filter { !$0.isEmpty }
        guard !addresses.isEmpty else { throw .noAddresses }
        guard let port = UInt16(exactly: wire.port), port != 0 else { throw .invalidPort }
        self.hostKey = hostKey
        self.hostName = wire.hostName
        self.addresses = addresses
        self.port = port
        self.secret = secret
    }

    private struct Wire: Decodable {
        let hostKey: String
        let hostName: String
        let addresses: [String]
        let port: Int
        let secret: String

        enum CodingKeys: String, CodingKey {
            case hostKey = "host_key", hostName = "host_name", addresses, port, secret
        }
    }
}

public enum QRPayloadError: Error, Equatable, Sendable {
    /// Not JSON, or a field is missing or of the wrong type.
    case notAPairingCode
    case invalidHostKey
    case invalidSecret
    case missingHostName
    case noAddresses
    case invalidPort
}

/// The device's side of one `qr` pairing: the proof it sends and the check of the host's answer.
public struct QRPairing: Sendable {
    public let payload: QRPayload
    /// The name to send in `PairStart`, normalised as the transcript holds it.
    public let deviceName: String
    public let transcript: Data

    public init(payload: QRPayload, deviceKey: DeviceKey, deviceName: String) {
        self.payload = payload
        self.deviceName = Pairing.deviceName(deviceName)
        transcript = Pairing.transcript(
            hostKey: payload.hostKey,
            deviceKey: deviceKey.publicKey,
            deviceName: self.deviceName,
            hostName: payload.hostName
        )
    }

    /// The `proof` for `PairStart`.
    public var proof: Data {
        Pairing.confirmation(key: payload.secret, side: .device, transcript: transcript)
    }

    /// Whether the host's `paired` answer comes from the holder of the secret and names the
    /// pinned key's id.
    public func acceptsHost(confirmation: Data, hostID: String) -> Bool {
        let confirmed = Pairing.confirms(confirmation, key: payload.secret, side: .host, transcript: transcript)
        return confirmed && KeyID(hex: hostID) == payload.hostID
    }
}
