import Foundation
import Testing
@testable import WiffletreeKit

struct QRPayloadTests {
    private let hostKey = DeviceKey().publicKey
    private let secret = Data(repeating: 9, count: QRPayload.secretLength)

    @Test func parsesTheSpecifiedPayload() throws {
        let payload = try QRPayload(scanned: qrCode(hostKey: hostKey, secret: secret))
        #expect(payload.hostKey == hostKey)
        #expect(payload.hostID == KeyID(publicKey: hostKey))
        #expect(payload.hostName == "Studio Mac")
        #expect(payload.addresses == ["192.168.1.20", "studio.tail4c2e.ts.net"])
        #expect(payload.port == 47821)
        #expect(payload.secret == secret)
    }

    @Test func ignoresFieldsItDoesNotKnow() throws {
        let text = qrCode(hostKey: hostKey, secret: secret).replacingOccurrences(of: "{", with: #"{"version":2,"#)
        #expect(try QRPayload(scanned: text).hostKey == hostKey)
    }

    @Test(arguments: [
        ("not json", QRPayloadError.notAPairingCode),
        (#"{"host_key":"BA=="}"#, .notAPairingCode),
        ("https://example.com", .notAPairingCode)
    ])
    func refusesWhatIsNotAPairingCode(text: String, error: QRPayloadError) {
        #expect(throws: error) { try QRPayload(scanned: text) }
    }

    @Test func refusesAKeyThatIsNotAPublicKey() {
        var offCurve = hostKey
        offCurve[64] ^= 1
        for key in [Data(), hostKey.prefix(64), offCurve] {
            #expect(throws: QRPayloadError.invalidHostKey) { try QRPayload(scanned: qrCode(hostKey: key, secret: secret)) }
        }
    }

    @Test func refusesASecretOfTheWrongLength() {
        for secret in [Data(), Data(count: 15), Data(count: 32)] {
            #expect(throws: QRPayloadError.invalidSecret) { try QRPayload(scanned: qrCode(hostKey: hostKey, secret: secret)) }
        }
    }

    @Test func refusesAnEmptyHostName() {
        #expect(throws: QRPayloadError.missingHostName) {
            try QRPayload(scanned: qrCode(hostKey: hostKey, hostName: "", secret: secret))
        }
    }

    @Test func refusesNoAddresses() {
        for addresses in [[], [""]] {
            #expect(throws: QRPayloadError.noAddresses) {
                try QRPayload(scanned: qrCode(hostKey: hostKey, addresses: addresses, secret: secret))
            }
        }
    }

    @Test(arguments: [0, -1, 65536])
    func refusesAPortOutOfRange(port: Int) {
        #expect(throws: QRPayloadError.invalidPort) { try QRPayload(scanned: qrCode(hostKey: hostKey, port: port, secret: secret)) }
    }
}
