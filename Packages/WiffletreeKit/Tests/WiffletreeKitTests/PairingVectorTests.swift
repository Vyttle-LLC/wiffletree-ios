import CryptoKit
import Foundation
import Testing
@testable import WiffletreeKit

/// The host's pairing test vectors. `Fixtures/pairing_vectors.json` is a byte-for-byte copy of
/// `crates/workspace-core/tests/fixtures/pairing_vectors.json` in Vyttle-LLC/wiffletree, last
/// changed there in ff7bd8bd9c2abeba38e3735ffb98d14736136d63 and copied at main 7bb272b30f7e.
/// The host's Rust test fails if they change; copy them again if it ever does.
struct PairingVectorTests {
    private let vectors = Vectors.load()

    private var deviceKey: DeviceKey {
        get throws { try DeviceKey(secret: vectors.bytes("keys", "device_secret")) }
    }

    private var transcript: Data {
        get throws {
            Pairing.transcript(
                hostKey: try vectors.bytes("keys", "host_public"),
                deviceKey: try vectors.bytes("keys", "device_public"),
                deviceName: vectors["transcript", "device_name"],
                hostName: vectors["transcript", "host_name"]
            )
        }
    }

    @Test func deviceKeyAndIdComeFromTheSecret() throws {
        let key = try deviceKey
        #expect(key.publicKey.hex == vectors["keys", "device_public"])
        #expect(key.id.hex == vectors["keys", "device_id"])
    }

    @Test func hostIdAndShortIdComeFromThePublicKey() throws {
        let id = KeyID(publicKey: try vectors.bytes("keys", "host_public"))
        #expect(id.hex == vectors["keys", "host_id"])
        #expect(id.short == vectors["keys", "host_short_id"])
    }

    @Test func transcriptMatches() throws {
        #expect(try transcript.hex == vectors["transcript", "bytes"])
    }

    @Test(arguments: [(Pairing.Side.device, "device_proof"), (.host, "host_proof")])
    func qrProofMatches(side: Pairing.Side, name: String) throws {
        let secret = try vectors.bytes("qr", "secret")
        let proof = Pairing.confirmation(key: secret, side: side, transcript: try transcript)
        #expect(proof.hex == vectors["qr", name])
        #expect(Pairing.confirms(proof, key: secret, side: side, transcript: try transcript))
    }

    @Test func qrPairingSendsTheDeviceProofAndAcceptsTheHostsConfirmation() throws {
        let payload = try QRPayload(scanned: qrCode(
            hostKey: vectors.bytes("keys", "host_public"),
            hostName: vectors["transcript", "host_name"],
            secret: vectors.bytes("qr", "secret")
        ))
        let pairing = QRPairing(payload: payload, deviceKey: try deviceKey, deviceName: vectors["transcript", "device_name"])
        #expect(pairing.proof.hex == vectors["qr", "device_proof"])
        let confirmation = try vectors.bytes("qr", "host_proof")
        #expect(pairing.acceptsHost(confirmation: confirmation, hostID: vectors["keys", "host_id"]))
        #expect(!pairing.acceptsHost(confirmation: confirmation, hostID: vectors["keys", "device_id"]))
        #expect(!pairing.acceptsHost(confirmation: try vectors.bytes("qr", "device_proof"), hostID: vectors["keys", "host_id"]))
    }

    @Test func challengeMessageMatches() throws {
        let message = Pairing.challengeMessage(
            challenge: try vectors.bytes("challenge", "challenge"),
            hostID: try #require(KeyID(hex: vectors["keys", "host_id"])),
            deviceID: try deviceKey.id
        )
        #expect(message.hex == vectors["challenge", "signed"])
    }

    /// ECDSA signatures are randomized, so the device's own differs from the recorded one; both
    /// must verify under the device's public key.
    @Test func challengeSignaturesVerify() throws {
        let signed = try vectors.bytes("challenge", "signed")
        let publicKey = try P256.Signing.PublicKey(x963Representation: vectors.bytes("keys", "device_public"))
        let recorded = try P256.Signing.ECDSASignature(rawRepresentation: vectors.bytes("challenge", "signature"))
        #expect(publicKey.isValidSignature(recorded, for: signed))

        let ours = try deviceKey.sign(signed)
        #expect(ours.count == 64)
        #expect(publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: ours), for: signed))
    }
}

/// `pairing_vectors.json`: sections of named hex strings, and the transcript's names.
struct Vectors {
    private let sections: [String: [String: String]]

    static func load() -> Vectors {
        let url = Bundle.module.url(forResource: "pairing_vectors", withExtension: "json")!
        return Vectors(sections: try! JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: url)))
    }

    subscript(section: String, name: String) -> String {
        sections[section]![name]!
    }

    func bytes(_ section: String, _ name: String) throws -> Data {
        try #require(Data(hex: self[section, name]))
    }
}

func qrCode(
    hostKey: Data,
    hostName: String = "Studio Mac",
    addresses: [String] = ["192.168.1.20", "studio.tail4c2e.ts.net"],
    port: Int = 47821,
    secret: Data
) -> String {
    let object: [String: Any] = [
        "host_key": hostKey.base64EncodedString(),
        "host_name": hostName,
        "addresses": addresses,
        "port": port,
        "secret": secret.base64EncodedString()
    ]
    return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}
