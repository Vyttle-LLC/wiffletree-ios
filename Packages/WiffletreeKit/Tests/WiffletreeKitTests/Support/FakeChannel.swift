import Foundation
import Synchronization
@testable import WiffletreeKit

/// One end of an in-memory WebSocket; `pipe()` makes a connected pair.
final class PipeEnd: MessageChannel {
    private let inbox: Mailbox
    private let outbox: Mailbox

    private init(inbox: Mailbox, outbox: Mailbox) {
        self.inbox = inbox
        self.outbox = outbox
    }

    static func pipe() -> (device: PipeEnd, host: PipeEnd) {
        let toHost = Mailbox(), toDevice = Mailbox()
        return (PipeEnd(inbox: toDevice, outbox: toHost), PipeEnd(inbox: toHost, outbox: toDevice))
    }

    func send(_ text: String) async throws(ConnectionError) {
        try outbox.put(text)
    }

    func receive() async throws(ConnectionError) -> String {
        try await inbox.take()
    }

    func close() {
        close(with: .closed)
    }

    /// Closes both ways; the other end's `receive` throws `error`, as a close reason gives it.
    func close(with error: ConnectionError) {
        inbox.finish(.closed)
        outbox.finish(error)
    }
}

/// Messages one way, in order, until finished.
private final class Mailbox: Sendable {
    private struct State {
        var messages: [String] = []
        var waiter: CheckedContinuation<String, any Error>?
        var finished: ConnectionError?
    }

    private let state = Mutex(State())

    func put(_ text: String) throws(ConnectionError) {
        let result: Result<CheckedContinuation<String, any Error>?, ConnectionError> = state.withLock { state in
            if let finished = state.finished { return .failure(finished) }
            guard let waiter = state.waiter else {
                state.messages.append(text)
                return .success(nil)
            }
            state.waiter = nil
            return .success(waiter)
        }
        try result.get()?.resume(returning: text)
    }

    func take() async throws(ConnectionError) -> String {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let ready: Result<String, ConnectionError>? = state.withLock { state in
                    if !state.messages.isEmpty { return .success(state.messages.removeFirst()) }
                    if let finished = state.finished { return .failure(finished) }
                    state.waiter = continuation
                    return nil
                }
                if let ready { continuation.resume(with: ready.mapError { $0 }) }
            }
        } catch {
            throw error as? ConnectionError ?? .closed
        }
    }

    func finish(_ error: ConnectionError) {
        let waiter = state.withLock { state in
            if state.finished == nil { state.finished = error }
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(throwing: error)
    }
}

/// A dialer whose addresses answer, fail, answer slowly or show another key, by host name.
final class FakeDialer: ChannelDialer {
    enum Behaviour: Sendable {
        case answer
        case fail
        case otherKey
        case slow(Duration)
    }

    private let behaviours: [String: Behaviour]
    private let host: FakeHost?

    /// With a `host`, answering addresses reach it; without, they reach nothing.
    init(_ behaviours: [String: Behaviour], host: FakeHost? = nil) {
        self.behaviours = behaviours
        self.host = host
    }

    func open(_ address: HostAddress, path: String, hostKey: Data) async throws(ConnectionError) -> any MessageChannel {
        switch behaviours[address.host] ?? .fail {
        case .fail:
            throw .unreachable("")
        case .otherKey:
            throw .otherKey
        case .slow(let delay):
            do { try await Task.sleep(for: delay) } catch { throw .closed }
        case .answer:
            break
        }
        if let host, host.publicKey != hostKey { throw .otherKey }
        let (device, server) = PipeEnd.pipe()
        if let host { host.serve(server, path: path) }
        return device
    }
}
