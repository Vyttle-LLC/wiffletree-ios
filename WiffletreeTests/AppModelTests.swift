import Foundation
import Testing
import WiffletreeKit
@testable import Wiffletree

/// An app model over an in-memory store and fresh preferences, whose paired hosts connect to
/// fake connections the test drives.
@MainActor
private final class Harness {
    let store: InMemoryPairedHostStore
    let preferences = Preferences(UserDefaults(suiteName: "tests.\(UUID())")!)
    private(set) var connections: [KeyID: [FakeConnection]] = [:]
    var paired: PairedHost?
    lazy var app = AppModel(.init(
        store: store,
        preferences: preferences,
        connect: { [unowned self] host in
            let connection = FakeConnection()
            connections[host.id, default: []].append(connection)
            return connection
        },
        demo: { DemoHostConnection(options: Self.instantDemo) },
        pair: { [unowned self] _ in
            guard let host = paired else { throw ConnectionError.unreachable("No address answered.") }
            store.save(host)
            return host
        },
        deviceName: "Test iPhone"
    ))

    init(_ hosts: [PairedHost] = []) {
        store = InMemoryPairedHostStore(hosts)
    }

    /// The latest connection to `host`.
    func connection(_ host: PairedHost) throws -> FakeConnection {
        try #require(connections[host.id]?.last)
    }

    private static var instantDemo: DemoHostConnection.Options {
        var options = DemoHostConnection.Options()
        options.sleep = { _ in }
        return options
    }
}

/// Waits for the main actor to apply what a connection sent.
@MainActor
private func eventually(_ condition: () -> Bool) async throws {
    for _ in 0..<200 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}

private let studio = PairedHost.fake("Studio Mac")
private let office = PairedHost.fake("Office mini", addresses: ["office-mini.tail4c2e.ts.net"])

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppModelTests {
    @Test func opensFirstRunWithNoHostAndTheFirstPairedHostOtherwise() {
        #expect(Harness().app.selected == nil)
        #expect(Harness([studio, office]).app.selectedID == .paired(studio.id))

        let remembered = Harness([studio, office])
        remembered.preferences.selectedHost = .paired(office.id)
        #expect(remembered.app.selectedID == .paired(office.id))

        let forgotten = Harness([studio])
        forgotten.preferences.selectedHost = .paired(office.id)
        #expect(forgotten.app.selectedID == .paired(studio.id))
    }

    @Test func connectingLoadsTheSnapshotAndRemembersWhenTheHostWasSeen() async throws {
        let harness = Harness([studio])
        let host = try #require(harness.app.selected)
        let connection = try harness.connection(studio)
        connection.set(.with(open: 2))
        #expect(host.status.kind == .connecting)

        connection.yield(.connected(address: HostAddress(host: "192.168.1.20"), level: .viewOnly))
        try await eventually { host.snapshot != nil }

        #expect(host.status.text == "On Wi-Fi")
        #expect(host.level == .viewOnly)
        #expect(host.openAttentionCount == 2)
        #expect(harness.preferences.lastSeen(studio.id) != nil)
    }

    @Test func eventsRefreshTheSnapshotAndReachSubscribers() async throws {
        let harness = Harness([studio])
        let host = try #require(harness.app.selected)
        let connection = try harness.connection(studio)
        connection.set(.with(open: 2))
        connection.yield(.connected(address: HostAddress(host: "192.168.1.20"), level: .control))
        try await eventually { host.openAttentionCount == 2 }

        var events = host.events().makeAsyncIterator()
        connection.set(.with(open: 1))
        connection.yield(.attention(count: 1))
        try await eventually { host.openAttentionCount == 1 }
        #expect(await events.next()?.kind == .attention(count: 1))
    }

    @Test func aDroppedConnectionReadsUnreachableWithWhenItWasLastSeen() async throws {
        let harness = Harness([office])
        let host = try #require(harness.app.selected)
        let connection = try harness.connection(office)
        connection.yield(.connected(address: HostAddress(host: "office-mini.tail4c2e.ts.net"), level: .control))
        try await eventually { host.isConnected }
        #expect(host.status.text == "Via Tailscale")

        connection.yield(.waiting(attempt: 1, error: .unreachable("No address answered.")))
        try await eventually { !host.isConnected }
        #expect(host.status.kind == .unreachable)
        #expect(host.status.text.hasPrefix("Unreachable · last seen "))

        connection.yield(.connecting)
        try await eventually { host.state == .connecting }
        #expect(host.status.kind == .unreachable, "A retry after a failure still reads Unreachable")

        host.restart()
        #expect(connection.isClosed)
        #expect(try harness.connection(office) !== connection)
        #expect(host.status.kind == .connecting)
    }

    @Test func aHostThatNoLongerKnowsThisIPhoneLeadsBackToPairing() async throws {
        let harness = Harness([studio])
        let app = harness.app
        let connection = try harness.connection(studio)

        connection.yield(.failed(.unpaired))
        try await eventually { app.notice != nil }

        #expect(app.hosts.isEmpty)
        #expect(app.selected == nil)
        #expect(harness.store.hosts().isEmpty)
        #expect(connection.isClosed)
        #expect(app.notice?.hostName == "Studio Mac")
    }

    @Test func aChangedKeyKeepsTheHostUntilThePersonDecides() async throws {
        let harness = Harness([studio])
        let host = try #require(harness.app.selected)
        try harness.connection(studio).yield(.failed(.keyChanged))
        try await eventually { host.status.kind == .keyChanged }

        #expect(harness.app.hosts.map(\.id) == [.paired(studio.id)])
        #expect(harness.store.hosts().map(\.id) == [studio.id])
        #expect(harness.app.selectedID == .paired(studio.id))
        #expect(harness.app.notice == nil)
    }

    @Test func otherFailuresKeepTheHost() async throws {
        let harness = Harness([studio])
        let host = try #require(harness.app.selected)
        try harness.connection(studio).yield(.failed(.incompatible(hostVersion: "0.1")))
        try await eventually { host.status.kind == .needsUpdate }
        #expect(harness.app.hosts.count == 1)
        #expect(harness.app.notice == nil)
    }

    @Test func removingTheCurrentHostOpensTheNextAndForgetsIt() throws {
        let harness = Harness([studio, office])
        let app = harness.app
        let connection = try harness.connection(studio)
        harness.preferences.setLastSeen(Date(), for: studio.id)

        app.remove(studio.id)

        #expect(app.hosts.map(\.name) == ["Office mini"])
        #expect(app.selectedID == .paired(office.id))
        #expect(harness.store.hosts().map(\.id) == [office.id])
        #expect(harness.preferences.lastSeen(studio.id) == nil)
        #expect(connection.isClosed)

        app.remove(office.id)
        #expect(app.selected == nil)
    }

    @Test func pairingAddsTheHostAndPairingAgainReplacesItsConnection() async throws {
        let harness = Harness()
        let app = harness.app
        harness.paired = studio
        let payload = try QRPayload(scanned: qrCode(for: studio))

        _ = try await app.pair(payload)
        let first = try harness.connection(studio)
        #expect(app.hosts.map(\.name) == ["Studio Mac"])
        #expect(app.selected == nil, "Opened only after the Paired screen")

        _ = try await app.pair(payload)
        #expect(app.hosts.count == 1)
        #expect(first.isClosed)
    }

    @Test func theDemoOpensWithItsSampleWorkspaceAndHidingItReturnsToFirstRun() async throws {
        let harness = Harness()
        let app = harness.app
        app.openDemo()
        let demo = try #require(app.selected)
        #expect(demo.isDemo)
        #expect(demo.status.text == "Built in · sample data")
        try await eventually { demo.snapshot != nil }
        #expect(demo.openAttentionCount == 3)

        app.showsDemoHost = false
        #expect(app.selected == nil)
        #expect(app.demo == nil)
        #expect(!harness.preferences.showsDemoHost)
    }

    @Test func startingTheDemoOverRestoresItsSampleData() async throws {
        let app = Harness().app
        app.openDemo()
        let demo = try #require(app.demo)
        try await eventually { demo.openAttentionCount == 3 }
        let question = try #require(demo.snapshot?.attention.first { $0.answer == nil && !$0.operationID.contains(":") })
        _ = try await demo.connection.request(DismissAttentionCommand(id: question.id))
        try await eventually { demo.openAttentionCount == 2 }

        app.restartDemo()
        try await eventually { demo.openAttentionCount == 3 }
    }
}

@MainActor
struct PairingFlowTests {
    @Test func aCodeThatIsNotForPairingSaysSoAndKeepsScanning() {
        let flow = PairingFlow(app: Harness().app, start: .firstRun)
        flow.scanned("https://example.com")
        #expect(flow.found == nil)
        #expect(flow.error != nil)
    }

    @Test func firstRunExplainsTheLocalNetworkOnceAndAddHostShowsTheStepsOnTheMac() {
        let harness = Harness()
        #expect(PairingFlow(app: harness.app, start: .firstRun).step == .localNetwork)
        #expect(PairingFlow(app: harness.app, start: .addHost).step == .instructions)

        harness.preferences.hasExplainedLocalNetwork = true
        let flow = PairingFlow(app: harness.app, start: .addHost)
        flow.startScanning()
        #expect(flow.step == .scanning)
    }

    @Test func confirmingAScannedCodePairsAndShowsThePairedScreen() async throws {
        let harness = Harness()
        harness.paired = studio
        let flow = PairingFlow(app: harness.app, start: .firstRun)
        flow.scanned(qrCode(for: studio))
        #expect(flow.found?.hostName == "Studio Mac")

        await flow.confirm()

        #expect(flow.step == .paired(studio))
        #expect(flow.found == nil)
        #expect(harness.app.hosts.map(\.name) == ["Studio Mac"])
    }

    @Test func pairingAgainAHostWhoseKeyChangedReplacesIt() async throws {
        let harness = Harness([office, studio])
        harness.app.select(.paired(studio.id))
        let reinstalled = PairedHost.fake("Studio Mac")
        harness.paired = reinstalled
        let flow = PairingFlow(app: harness.app, start: .pairAgain(studio.id))
        #expect(flow.step == .instructions)
        flow.scanned(qrCode(for: reinstalled))

        await flow.confirm()
        #expect(flow.step == .paired(reinstalled))
        #expect(harness.app.selectedID == .paired(studio.id), "The shell showing the Paired screen stays up")

        flow.open()
        #expect(harness.app.selectedID == .paired(reinstalled.id))
        #expect(harness.app.hosts.map(\.id) == [.paired(office.id), .paired(reinstalled.id)])
        #expect(harness.store.hosts().map(\.id) == [office.id, reinstalled.id])
    }

    @Test func aCancelledCodeIsIgnoredForAMomentWhileOthersOpenAtOnce() {
        var now = Date()
        let flow = PairingFlow(app: Harness().app, start: .firstRun, now: { now })
        flow.scanned(qrCode(for: studio))
        flow.cancelConfirm()

        flow.scanned(qrCode(for: studio))
        #expect(flow.found == nil, "The camera is still on the code just cancelled")

        flow.scanned(qrCode(for: office))
        #expect(flow.found?.hostName == "Office mini")
        flow.cancelConfirm()

        now += PairingFlow.declinePause + 1
        flow.scanned(qrCode(for: office))
        #expect(flow.found?.hostName == "Office mini")
    }

    @Test func aFailedPairingStaysOnTheConfirmSheetWithTheReason() async {
        let harness = Harness()
        let flow = PairingFlow(app: harness.app, start: .firstRun)
        flow.scanned(qrCode(for: studio))

        await flow.confirm()

        #expect(flow.found != nil)
        #expect(flow.error != nil)
        #expect(!flow.isPairing)
    }
}

struct HostStatusTests {
    @Test func namesTheRouteAsDesignCall12Does() {
        let connected = { (host: String) in
            HostStatus(state: .connected(address: HostAddress(host: host), level: .control), isDemo: false, lastSeen: nil).text
        }
        #expect(connected("192.168.1.20") == "On Wi-Fi")
        #expect(connected("100.101.102.103") == "Via Tailscale")
        #expect(connected("studio.example.com") == "Via VPN")

        let now = Date()
        let unreachable = HostStatus(state: .waiting(attempt: 2, error: .timedOut), isDemo: false, lastSeen: nil, now: now)
        #expect(unreachable.text == "Unreachable")
        let seen = HostStatus(state: .waiting(attempt: 2, error: .timedOut), isDemo: false, lastSeen: now.addingTimeInterval(-3 * 86_400), now: now)
        #expect(seen.text == "Unreachable · last seen 3 days ago")
    }
}

private func qrCode(for host: PairedHost) -> String {
    let secret = Data(repeating: 7, count: QRPayload.secretLength).base64EncodedString()
    return #"{"host_key": "\#(host.publicKey.base64EncodedString())", "host_name": "\#(host.name)", "addresses": ["192.168.1.20"], "port": 47821, "secret": "\#(secret)"}"#
}
