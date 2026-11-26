import CryptoKit
import Foundation

/// The device's long-term P-256 key pair, which pairs it with hosts and answers their challenges.
public struct DeviceKey: Sendable {
    private let privateKey: P256.Signing.PrivateKey

    /// A new random key.
    public init() {
        privateKey = P256.Signing.PrivateKey()
    }

    /// Restores a key from its 32-byte scalar, as `secret` gives it.
    public init(secret: Data) throws {
        privateKey = try P256.Signing.PrivateKey(rawRepresentation: secret)
    }

    public var secret: Data { privateKey.rawRepresentation }

    /// The public key, SEC1 uncompressed: 65 bytes starting `04`.
    public var publicKey: Data { privateKey.publicKey.x963Representation }

    public var id: KeyID { KeyID(publicKey: publicKey) }

    /// An ECDSA P-256 SHA-256 signature, raw `r ‖ s`: 64 bytes.
    public func sign(_ message: Data) throws -> Data {
        try privateKey.signature(for: message).rawRepresentation
    }
}

/// Whether `key` is a P-256 public key, SEC1 uncompressed.
func isPublicKey(_ key: Data) -> Bool {
    key.count == 65 && (try? P256.Signing.PublicKey(x963Representation: key)) != nil
}
