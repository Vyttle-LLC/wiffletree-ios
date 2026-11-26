import Foundation
import Testing
@testable import WiffletreeKit

struct DeviceNameTests {
    @Test func trimsUnicodeWhiteSpace() {
        #expect(Pairing.deviceName(" \t\u{3000}Michael's iPhone\u{85}\n") == "Michael's iPhone")
        #expect(Pairing.deviceName(" \n ").isEmpty)
    }

    /// The host counts Rust `char`s, which are Unicode scalars, not the characters a person sees.
    @Test func cutsToOneHundredScalars() {
        let accented = String(repeating: "e\u{301}", count: 60)
        let name = Pairing.deviceName(accented)
        #expect(name.unicodeScalars.count == 100)
        #expect(name.count == 50)
    }

    @Test func transcriptHoldsTheNormalisedName() {
        let key = Data([4])
        #expect(
            Pairing.transcript(hostKey: key, deviceKey: key, deviceName: "  iPhone ", hostName: "Mac")
                == Pairing.transcript(hostKey: key, deviceKey: key, deviceName: "iPhone", hostName: "Mac")
        )
    }
}

struct ConfirmationTests {
    private let transcript = Pairing.transcript(hostKey: Data([1]), deviceKey: Data([2]), deviceName: "iPhone", hostName: "Mac")
    private let secret = Data(repeating: 7, count: QRPayload.secretLength)

    @Test func aChangedByteOrLengthDoesNotConfirm() {
        let proof = Pairing.confirmation(key: secret, side: .device, transcript: transcript)
        var flipped = proof
        flipped[31] ^= 1
        #expect(!Pairing.confirms(flipped, key: secret, side: .device, transcript: transcript))
        #expect(!Pairing.confirms(proof.prefix(31), key: secret, side: .device, transcript: transcript))
        #expect(!Pairing.confirms(Data(), key: secret, side: .device, transcript: transcript))
    }

    @Test func oneSidesProofDoesNotConfirmTheOther() {
        let proof = Pairing.confirmation(key: secret, side: .device, transcript: transcript)
        #expect(!Pairing.confirms(proof, key: secret, side: .host, transcript: transcript))
    }
}

struct KeyIDTests {
    @Test func parsesOnlyThirtyTwoBytesOfHex() {
        let hex = String(repeating: "ab", count: 32)
        #expect(KeyID(hex: hex)?.hex == hex)
        #expect(KeyID(hex: hex.uppercased())?.hex == hex)
        #expect(KeyID(hex: String(hex.dropLast(2))) == nil)
        #expect(KeyID(hex: String(hex.dropLast()) + "z") == nil)
    }

    @Test func aKeyRoundTripsThroughItsSecret() throws {
        let key = DeviceKey()
        #expect(key.publicKey.count == 65)
        #expect(try DeviceKey(secret: key.secret).id == key.id)
    }
}

struct KeyStoreTests {
    @Test func deviceKeyIsCreatedOnceThenLoaded() throws {
        let store = InMemoryKeyStore()
        #expect(store.load() == nil)
        let created = try store.deviceKey()
        #expect(try store.deviceKey().id == created.id)
        #expect(store.load()?.id == created.id)
    }
}
