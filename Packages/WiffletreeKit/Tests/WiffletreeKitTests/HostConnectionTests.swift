import Foundation
import Testing
@testable import WiffletreeKit

@Suite(.timeLimit(.minutes(1)))
struct QRPairingFlowTests {
    private let host = FakeHost()
    private let store = InMemoryPairedHostStore()

    private func pair(_ payload: QRPayload, as device: DeviceKey = DeviceKey(), named name: String = "Michael's iPhone") async throws -> PairedHost {
        let dialer = FakeDialer(["192.168.1.20": .fail, "studio.tail4c2e.ts.net": .answer], host: host)
        return try await HostPairer(store: store, race: AddressRace(dialer: dialer, headStart: .milliseconds(10)))
            .pair(payload, deviceKey: device, deviceName: name)
    }

    @Test func pairsAndStoresTheHostWithTheAddressThatAnswered() async throws {
        let device = DeviceKey()
        let paired = try await pair(try host.qrCode(addresses: ["192.168.1.20", "studio.tail4c2e.ts.net"]), as: device, named: "  Michael's iPhone ")
        #expect(paired.id == host.id)
        #expect(paired.name == "Studio Mac")
        #expect(paired.level == .control)
        #expect(paired.addresses.map(\.host) == ["studio.tail4c2e.ts.net", "192.168.1.20"])
        #expect(store.hosts() == [paired])
        #expect(await host.devices[device.id] == device.publicKey)
        #expect(await host.deviceNames == ["Michael's iPhone"])
    }

    @Test func aStaleCodeIsRefusedWithTheHostsReason() async throws {
        let stale = try host.qrCode(addresses: ["studio.tail4c2e.ts.net"], secret: Data(repeating: 1, count: 16))
        await #expect(throws: ConnectionError.pairingRefused("The code did not match")) { try await pair(stale) }
        #expect(store.hosts().isEmpty)
    }

    @Test func aHostThatCannotConfirmIsNotStored() async throws {
        await host.set(confirmsWrongly: true)
        await #expect(throws: ConnectionError.confirmationFailed) {
            try await pair(try host.qrCode(addresses: ["studio.tail4c2e.ts.net"]))
        }
        #expect(store.hosts().isEmpty)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct RemoteHostConnectionTests {
    private let host = FakeHost()
    private let device = DeviceKey()
    private let store = InMemoryPairedHostStore()

    private func connect(
        addresses: [String: FakeDialer.Behaviour] = ["studio.local": .answer],
        heartbeat: Duration = .seconds(3600),
        backoff: Duration = .milliseconds(1)
    ) async -> RemoteHostConnection {
        await host.pairDevice(device)
        let paired = PairedHost(
            name: host.name,
            publicKey: host.publicKey,
            addresses: addresses.keys.sorted().map { HostAddress(host: $0) },
            level: .control
        )
        store.save(paired)
        var options = RemoteHostConnection.Options()
        options.backoff = Backoff(first: backoff, longest: backoff * 5)
        options.heartbeat = heartbeat
        options.pingLimit = .milliseconds(50)
        options.headStart = .milliseconds(10)
        return RemoteHostConnection(
            host: paired, deviceKey: device, store: store, appVersion: "1.0",
            dialer: FakeDialer(addresses, host: host), options: options
        )
    }

    @Test func answersTheChallengeAndReadsTheWorkspace() async throws {
        let connection = await connect()
        defer { connection.close() }
        let snapshot = try await connection.request(SnapshotCommand())
        #expect(snapshot.projects.first?.id == "p1")
        let messages = try await connection.request(MessagesCommand(sessionID: "c1"))
        #expect(messages.map(\.recipient) == ["c1"])
        #expect(await host.commands == ["subscribe", "snapshot", "messages"])
    }

    @Test func remembersTheAddressThatAnswered() async throws {
        let connection = await connect(addresses: ["192.168.1.20": .fail, "studio.local": .answer])
        defer { connection.close() }
        _ = try await connection.request(PingCommand())
        #expect(connection.host.addresses.first?.host == "studio.local")
        #expect(store.hosts().first?.addresses.map(\.host) == ["studio.local", "192.168.1.20"])
    }

    @Test func matchesRepliesToRequestsByID() async throws {
        let connection = await connect()
        defer { connection.close() }
        _ = try await connection.request(PingCommand())
        await host.set(replyInReverseAfter: 2)
        async let snapshot = connection.request(SnapshotCommand())
        async let messages = connection.request(MessagesCommand(sessionID: "c1"))
        #expect(try await snapshot.projects.count == 1)
        #expect(try await messages.count == 1)
    }

    @Test func aRefusedCommandThrowsTheHostsSentence() async throws {
        let connection = await connect()
        defer { connection.close() }
        await #expect(throws: ConnectionError.commandFailed("Unknown command quotas")) {
            try await connection.request(QuotasCommand())
        }
    }

    @Test func aRequestWhileWaitingThrowsTheReasonAtOnce() async throws {
        let connection = await connect(addresses: ["192.168.1.20": .fail], backoff: .seconds(30))
        defer { connection.close() }
        let reason = ConnectionError.unreachable("192.168.1.20 did not answer")
        await #expect(throws: reason) { try await connection.request(PingCommand()) }
        let asked = ContinuousClock.now
        await #expect(throws: reason) { try await connection.request(PingCommand()) }
        #expect(ContinuousClock.now - asked < .seconds(5))
    }

    @Test func aRefusedSubscriptionFailsTheTry() async throws {
        await host.set(refusesSubscribe: true)
        let connection = await connect(backoff: .seconds(30))
        defer { connection.close() }
        await #expect(throws: ConnectionError.commandFailed("No events today")) {
            try await connection.request(PingCommand())
        }
    }

    @Test func resumesEventsFromTheCursorAfterADrop() async throws {
        let connection = await connect()
        defer { connection.close() }
        var events = connection.events.makeAsyncIterator()
        _ = try await connection.request(PingCommand())
        await host.emit("state")
        await host.emit("usage")
        #expect(await events.next()?.cursor.seq == 1)
        #expect(await events.next()?.cursor.seq == 2)

        await host.dropConnections(thenRecord: ["state"])
        #expect(await events.next() == HostEvent(cursor: Cursor(epoch: "epoch-1", seq: 3), kind: .state))
        await host.emit("attention", ["count": 2])
        #expect(await events.next()?.kind == .attention(count: 2))
        #expect(await host.subscribedAfter == [nil, Cursor(epoch: "epoch-1", seq: 2)])
    }

    @Test func aRestartedHostSendsResyncFirst() async throws {
        let connection = await connect()
        defer { connection.close() }
        var events = connection.events.makeAsyncIterator()
        _ = try await connection.request(PingCommand())
        await host.emit("state")
        #expect(await events.next()?.cursor == Cursor(epoch: "epoch-1", seq: 1))

        await host.restart()
        #expect(await events.next() == HostEvent(cursor: Cursor(epoch: "epoch-2", seq: 0), kind: .resync))
        await host.emit("usage")
        #expect(await events.next() == HostEvent(cursor: Cursor(epoch: "epoch-2", seq: 1), kind: .usage))
    }

    @Test func anUnansweredPingDropsTheConnectionAndItReconnects() async throws {
        let connection = await connect(heartbeat: .milliseconds(20))
        defer { connection.close() }
        _ = try await connection.request(PingCommand())
        await host.set(ignoresPings: true)
        var states = connection.states.makeAsyncIterator()
        while let state = await states.next() {
            if case .waiting(_, .closed) = state { break }
        }
        await host.set(ignoresPings: false)
        while let state = await states.next() {
            if case .connected = state { break }
        }
        #expect(await host.commands.filter { $0 == "subscribe" }.count >= 2)
    }

    @Test func aRemovedDeviceStopsWithUnpaired() async throws {
        let connection = await connect()
        _ = try await connection.request(PingCommand())
        var events = connection.events.makeAsyncIterator()
        await host.remove(device.id)
        #expect(await events.next() == nil)
        await #expect(throws: ConnectionError.unpaired) { try await connection.request(PingCommand()) }
        var states = connection.states.makeAsyncIterator()
        var last: ConnectionState?
        while let state = await states.next() { last = state }
        #expect(last == .failed(.unpaired))
    }

    @Test func anUnknownDeviceIsUnpairedAtTheChallenge() async throws {
        let connection = await connect()
        await host.remove(device.id)
        await #expect(throws: ConnectionError.unpaired) { try await connection.request(PingCommand()) }
    }
}
