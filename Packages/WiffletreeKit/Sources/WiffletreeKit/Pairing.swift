import CryptoKit
import Foundation

/// The cryptography of pairing and of the `/v1` challenge, as `docs/remote-protocol.md` in the
/// host repository specifies it. The iPhone pairs only by the `qr` method, so SPAKE2 is absent.
public enum Pairing {
    /// Which side computes a confirmation or proof.
    public enum Side: Sendable {
        case device, host

        var label: Data {
            switch self {
            case .device: Data("device".utf8)
            case .host: Data("host".utf8)
            }
        }
    }

    /// The longest device name a host keeps, in Unicode scalars, as the host counts them.
    public static let maxDeviceNameLength = 100

    /// A device's name as both sides put it in the transcript: trimmed of Unicode white space and
    /// cut to `maxDeviceNameLength` scalars, matching the host's Rust `trim` and `chars`.
    public static func deviceName(_ name: String) -> String {
        let scalars = name.unicodeScalars
        guard let first = scalars.firstIndex(where: { !$0.properties.isWhitespace }),
              let last = scalars.lastIndex(where: { !$0.properties.isWhitespace })
        else { return "" }
        return String(String.UnicodeScalarView(scalars[first...last].prefix(maxDeviceNameLength)))
    }

    /// What the confirmations cover: a label, then the host's public key as the device saw it,
    /// the device's public key, the device's name (normalised here) and the host's name, each
    /// behind its length as 4 bytes big-endian.
    public static func transcript(hostKey: Data, deviceKey: Data, deviceName: String, hostName: String) -> Data {
        var transcript = Data("wiffletree-pair-v1".utf8)
        for field in [hostKey, deviceKey, Data(Self.deviceName(deviceName).utf8), Data(hostName.utf8)] {
            withUnsafeBytes(of: UInt32(field.count).bigEndian) { transcript.append(contentsOf: $0) }
            transcript.append(field)
        }
        return transcript
    }

    /// HMAC-SHA256 under `key` over the side's label and the transcript. The `qr` method keys it
    /// with the QR code's one-time secret, giving the device's proof and the host's confirmation.
    public static func confirmation(key: Data, side: Side, transcript: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: side.label + transcript, using: SymmetricKey(data: key)))
    }

    /// Checks a confirmation in time that does not depend on where it differs.
    public static func confirms(_ given: Data, key: Data, side: Side, transcript: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(given, authenticating: side.label + transcript, using: SymmetricKey(data: key))
    }

    /// What a device signs on `/v1`: a label, the host's challenge, and the host's and the
    /// device's ids as raw bytes.
    public static func challengeMessage(challenge: Data, hostID: KeyID, deviceID: KeyID) -> Data {
        Data("wiffletree-challenge-v1".utf8) + challenge + hostID.bytes + deviceID.bytes
    }
}
