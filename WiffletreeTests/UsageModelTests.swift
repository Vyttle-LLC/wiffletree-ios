import Foundation
import Synchronization
import Testing
import WiffletreeKit
@testable import Wiffletree

/// A connection that answers the Usage tab's reads, counts them, and sends the states and
/// events the test says.
private final class UsageConnection: HostConnection {
    let events: AsyncStream<HostEvent>
    let states: AsyncStream<ConnectionState>
    private let eventSink: AsyncStream<HostEvent>.Continuation
    private let stateSink: AsyncStream<ConnectionState>.Continuation
    private let quotaReads = Mutex(0)

    init() {
        (events, eventSink) = AsyncStream.makeStream()
        (states, stateSink) = AsyncStream.makeStream()
    }

    var reads: Int { quotaReads.withLock { $0 } }

    func yield(_ state: ConnectionState) { stateSink.yield(state) }

    func yield(_ kind: HostEvent.Kind) {
        eventSink.yield(HostEvent(cursor: Cursor(epoch: "test", seq: 1), kind: kind))
    }

    func request<Command: HostCommand>(_ command: Command) async throws -> Command.Reply {
        switch command {
        case is SnapshotCommand:
            return Snapshot(projects: [], sessions: [], attention: [], tickets: []) as! Command.Reply
        case is QuotasCommand:
            quotaReads.withLock { $0 += 1 }
            return [QuotaReading]() as! Command.Reply
        case is UsageCommand:
            let json = #"""
            {"startDate": "2026-11-20", "endDate": "2026-11-26", "coordinators": [],
             "totals": {"input": 10, "output": 5, "cacheRead": 0, "cacheWrite": 0, "requests": 1}}
            """#
            return try JSONDecoder().decode(UsageReport.self, from: Data(json.utf8)) as! Command.Reply
        default:
            throw ConnectionError.commandFailed("Not faked")
        }
    }

    func close() {
        stateSink.yield(.closed)
        stateSink.finish()
        eventSink.finish()
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

private let studio = ConnectionState.connected(address: HostAddress(host: "studio.local"), level: .control)

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct UsageModelTests {
    @Test func usageIsReadAgainOnAReconnectAResyncAndAUsageChange() async throws {
        let connection = UsageConnection()
        let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { connection })
        let model = UsageModel(host: host)
        let following = Task { await model.follow() }
        defer { following.cancel() }
        try await eventually { connection.reads == 1 }

        connection.yield(studio)
        try await eventually { connection.reads == 2 }
        connection.yield(.waiting(attempt: 1, error: .unreachable("No address answered.")))
        connection.yield(studio)
        try await eventually { connection.reads == 3 }
        connection.yield(.resync)
        try await eventually { connection.reads == 4 }
        connection.yield(.usage)
        try await eventually { connection.reads == 5 }
        #expect(model.weekTotal == "15")
    }

    @Test func usageFollowsTheNewConnectionAfterARestart() async throws {
        var connections: [UsageConnection] = []
        let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: {
            let connection = UsageConnection()
            connections.append(connection)
            return connection
        })
        let model = UsageModel(host: host)
        let following = Task { await model.follow() }
        defer { following.cancel() }
        let first = try #require(connections.first)
        try await eventually { first.reads == 1 }

        host.restart()
        let second = try #require(connections.last)
        #expect(second !== first)
        second.yield(studio)
        try await eventually { second.reads == 1 }
        second.yield(.usage)
        try await eventually { second.reads == 2 }
    }
}
