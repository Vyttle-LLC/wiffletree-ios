import Foundation
import Synchronization
import WiffletreeKit

/// A host connection the test drives: it says which states and events happen, and answers
/// `snapshot` with whatever the test last set.
final class FakeConnection: HostConnection {
    let events: AsyncStream<HostEvent>
    let states: AsyncStream<ConnectionState>
    private let eventSink: AsyncStream<HostEvent>.Continuation
    private let stateSink: AsyncStream<ConnectionState>.Continuation
    private let shared: Mutex<(snapshot: Snapshot, isClosed: Bool, reconnects: Int, failure: ConnectionError)>

    init(snapshot: Snapshot = .with(open: 0)) {
        (events, eventSink) = AsyncStream.makeStream()
        (states, stateSink) = AsyncStream.makeStream()
        shared = Mutex((snapshot, false, 0, .commandFailed("Not faked")))
        stateSink.yield(.connecting)
    }

    var isClosed: Bool { shared.withLock { $0.isClosed } }
    /// How many times the app asked to reconnect now.
    var reconnects: Int { shared.withLock { $0.reconnects } }

    func reconnectNow() {
        shared.withLock { $0.reconnects += 1 }
    }

    func set(_ snapshot: Snapshot) {
        shared.withLock { $0.snapshot = snapshot }
    }

    func yield(_ state: ConnectionState) {
        stateSink.yield(state)
    }

    func yield(_ kind: HostEvent.Kind) {
        eventSink.yield(HostEvent(cursor: Cursor(epoch: "test", seq: 1), kind: kind))
    }

    /// What every request other than `snapshot` throws.
    var failure: ConnectionError {
        get { shared.withLock { $0.failure } }
        set { shared.withLock { $0.failure = newValue } }
    }

    func request<Command: HostCommand>(_ command: Command) async throws -> Command.Reply {
        guard command is SnapshotCommand else { throw failure }
        return shared.withLock { $0.snapshot } as! Command.Reply
    }

    func close() {
        shared.withLock { $0.isClosed = true }
        stateSink.yield(.closed)
        stateSink.finish()
        eventSink.finish()
    }
}

extension Snapshot {
    /// One project with `open` unanswered questions and one answered one, as the host's JSON
    /// has them.
    static func with(open: Int) -> Snapshot {
        let attention = (0..<open).map { index in
            #"{"id": "a\#(index)", "projectId": "p", "sessionId": "s", "operationId": "question:\#(index)", "prompt": "Which?"}"#
        } + [#"{"id": "done", "projectId": "p", "sessionId": "s", "operationId": "question:x", "prompt": "Done?", "answer": "Yes"}"#]
        let coordinator = #"{"id": "s", "projectId": "p", "name": "Tide alerts", "role": "project_orchestrator", "provider": "claude", "status": "ready"}"#
        let json = #"{"projects": [{"id": "p", "name": "Tide alerts"}], "sessions": [\#(coordinator)], "attention": [\#(attention.joined(separator: ","))]}"#
        return try! JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }
}

extension PairedHost {
    static func fake(_ name: String, addresses: [String] = ["192.168.1.20"]) -> PairedHost {
        PairedHost(name: name, publicKey: DeviceKey().publicKey, addresses: addresses.map { HostAddress(host: $0) }, level: .control)
    }
}
