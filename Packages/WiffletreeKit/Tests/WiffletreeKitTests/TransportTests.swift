import Foundation
import Security
import Testing
@testable import WiffletreeKit

struct HostAddressTests {
    @Test func takesTheDefaultPortUnlessOneIsNamed() {
        #expect(HostAddress(parsing: "studio.local") == HostAddress(host: "studio.local", port: 47821))
        #expect(HostAddress(parsing: "studio.tail4c2e.ts.net:9000") == HostAddress(host: "studio.tail4c2e.ts.net", port: 9000))
        #expect(HostAddress(parsing: "[fe80::1]:9000") == HostAddress(host: "fe80::1", port: 9000))
        #expect(HostAddress(parsing: "[fe80::1]") == HostAddress(host: "fe80::1", port: 47821))
        #expect(HostAddress(parsing: "fd7a:115c:a1e0::1") == HostAddress(host: "fd7a:115c:a1e0::1", port: 47821))
        #expect(HostAddress(host: "fe80::1").description == "[fe80::1]:47821")
    }

    @Test func namesAndTailscaleAddressesNameOneMachine() {
        #expect(HostAddress(host: "studio.tail4c2e.ts.net").namesOneMachine)
        #expect(HostAddress(host: "studio.local").namesOneMachine)
        #expect(HostAddress(host: "100.64.0.1").namesOneMachine)
        #expect(HostAddress(host: "100.127.255.254").namesOneMachine)
        #expect(HostAddress(host: "fd7a:115c:a1e0::5").namesOneMachine)
        #expect(!HostAddress(host: "100.128.0.1").namesOneMachine)
        #expect(!HostAddress(host: "192.168.1.20").namesOneMachine)
        #expect(!HostAddress(host: "fe80::1").namesOneMachine)
    }

    @Test func tellsTheLocalNetworkFromTailscaleAndOtherVPNs() {
        for local in ["192.168.1.20", "10.0.0.4", "172.20.1.1", "169.254.3.3", "studio.local", "fe80::1", "fd12::4"] {
            #expect(HostAddress(host: local).network == .local, "\(local)")
        }
        for tailscale in ["100.101.102.103", "fd7a:115c:a1e0::5", "studio.tail4c2e.ts.net"] {
            #expect(HostAddress(host: tailscale).network == .tailscale, "\(tailscale)")
        }
        for other in ["172.32.0.1", "100.128.0.1", "studio.example.com", "2001:db8::1"] {
            #expect(HostAddress(host: other).network == .otherVPN, "\(other)")
        }
    }
}

struct CertificatePinTests {
    /// The fixture is a self-signed P-256 certificate whose private key was discarded; this is
    /// its public key, as `openssl ec -pubout -conv_form uncompressed` gives it.
    private let certificateKey = Data(hex: "04645f2ae4f1f987a1cae8750d23190a833c3bfeaf46a710c6608b7f2119e205519e706c0ca59c43a3e1e71064b4b210907c5a3646b28024c8002bd93592447571")!

    private func trust() throws -> SecTrust {
        let url = try #require(Bundle.module.url(forResource: "host_certificate", withExtension: "der"))
        let certificate = try #require(SecCertificateCreateWithData(nil, try Data(contentsOf: url) as CFData))
        var trust: SecTrust?
        #expect(SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust) == errSecSuccess)
        return try #require(trust)
    }

    @Test func readsTheKeyAsSEC1Uncompressed() throws {
        let certificate = try #require((SecTrustCopyCertificateChain(try trust()) as? [SecCertificate])?.first)
        #expect(CertificatePin.publicKey(of: certificate) == certificateKey)
    }

    @Test func acceptsOnlyThePinnedKey() throws {
        let pinned = CertificatePin(hostKey: certificateKey)
        #expect(pinned.accepts(try trust()))
        #expect(!pinned.sawOtherKey)

        let other = CertificatePin(hostKey: DeviceKey().publicKey)
        #expect(!other.accepts(try trust()))
        #expect(other.sawOtherKey)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct AddressRaceTests {
    private let lan = HostAddress(host: "192.168.1.20")
    private let tailscale = HostAddress(host: "100.101.1.2")
    private let name = HostAddress(host: "studio.tail4c2e.ts.net")
    private let key = DeviceKey().publicKey

    private func race(_ behaviours: [String: FakeDialer.Behaviour]) async throws(ConnectionError) -> HostAddress {
        // Wide enough that a loaded machine still starts the addresses in order.
        let race = AddressRace(dialer: FakeDialer(behaviours), headStart: .milliseconds(100))
        let (address, channel) = try await race.open([lan, tailscale, name], path: ChannelPath.v1, hostKey: key)
        channel.close()
        return address
    }

    @Test func theFirstAddressWinsWhenEveryOneAnswers() async throws {
        #expect(try await race(["192.168.1.20": .answer, "100.101.1.2": .answer, "studio.tail4c2e.ts.net": .answer]) == lan)
    }

    @Test func aLaterAddressWinsWhileAnEarlierOneIsSlowOrDead() async throws {
        #expect(try await race(["192.168.1.20": .slow(.seconds(5)), "100.101.1.2": .answer]) == tailscale)
        #expect(try await race(["192.168.1.20": .fail, "studio.tail4c2e.ts.net": .answer]) == name)
    }

    @Test func anotherKeyAtALANAddressIsAnotherMachine() async throws {
        #expect(try await race(["192.168.1.20": .otherKey, "100.101.1.2": .answer]) == tailscale)
        await #expect(throws: ConnectionError.unreachable("192.168.1.20 is another machine now")) {
            try await race(["192.168.1.20": .otherKey])
        }
    }

    @Test func anotherKeyAtATailscaleAddressOrANameIsTheKeyChanged() async throws {
        await #expect(throws: ConnectionError.keyChanged) {
            try await race(["192.168.1.20": .slow(.seconds(5)), "100.101.1.2": .otherKey, "studio.tail4c2e.ts.net": .slow(.seconds(5))])
        }
        await #expect(throws: ConnectionError.keyChanged) {
            try await race(["studio.tail4c2e.ts.net": .otherKey])
        }
    }

    @Test func nothingAnsweringIsUnreachable() async throws {
        let error = await #expect(throws: ConnectionError.self) { try await race([:]) }
        guard case .unreachable(let reason) = error else {
            Issue.record("\(String(describing: error))")
            return
        }
        #expect(reason.hasSuffix("did not answer"))
    }

    @Test func theAddressThatAnsweredComesFirstNextTime() {
        #expect([lan, tailscale, name].answered(at: name) == [name, lan, tailscale])
    }
}

struct BackoffTests {
    @Test func doublesUpToTheLongest() {
        let backoff = Backoff(first: .milliseconds(500), longest: .seconds(30))
        #expect((1...8).map { backoff.delay(after: $0) } == [
            .milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30), .seconds(30)
        ])
        #expect(backoff.delay(after: 1000) == .seconds(30))
    }
}
