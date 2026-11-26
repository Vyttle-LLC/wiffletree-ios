import CryptoKit
import Foundation

/// A key's id: the SHA-256 of its SEC1 uncompressed public key. The protocol writes it in
/// lowercase hex; the challenge signs its raw bytes.
public struct KeyID: Hashable, Sendable, CustomStringConvertible {
    public let bytes: Data

    public init(publicKey: Data) {
        bytes = Data(SHA256.hash(data: publicKey))
    }

    /// An id as the host sends it; nil unless it is 32 bytes of hex.
    public init?(hex: String) {
        guard let bytes = Data(hex: hex), bytes.count == SHA256.byteCount else { return nil }
        self.bytes = bytes
    }

    public var hex: String { bytes.hex }

    /// The first 16 hex characters, as Bonjour and logs show it.
    public var short: String { String(hex.prefix(16)) }

    public var description: String { hex }
}
