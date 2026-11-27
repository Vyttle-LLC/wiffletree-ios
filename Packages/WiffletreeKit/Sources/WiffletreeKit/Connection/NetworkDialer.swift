import Foundation
import Network
import Security
import Synchronization

/// Opens channels with Network.framework: TLS 1.3 pinned to the host's key, then a WebSocket.
///
/// Network.framework rather than URLSession, because it pins cleanly: a verify block on each
/// connection sees the certificate's key, so the client can tell "another key here" from "no
/// answer", which address racing needs; it names the TLS server `wiffletree-host` while
/// connecting to an IP address; it holds TLS to 1.3 exactly; and each raced attempt is its own
/// connection to cancel, with no shared session pooling them.
public struct NetworkDialer: ChannelDialer {
    /// How long one address may take to complete TLS and the WebSocket handshake.
    public var timeout: Duration

    public init(timeout: Duration = .seconds(10)) {
        self.timeout = timeout
    }

    public func open(_ address: HostAddress, path: String, hostKey: Data) async throws(ConnectionError) -> any MessageChannel {
        guard let url = URL(string: "wss://\(address)\(path)") else {
            throw .unreachable("\(address) is not an address")
        }
        let pin = CertificatePin(hostKey: hostKey)
        let queue = DispatchQueue(label: "com.vyttle.wiffletree.connection")
        let connection = NWConnection(to: .url(url), using: Self.parameters(pin: pin, queue: queue))
        do {
            try await Self.start(connection, queue: queue, timeout: timeout)
        } catch {
            if pin.sawOtherKey { throw .otherKey }
            throw error == .timedOut ? .unreachable("\(address) did not answer") : error
        }
        return NetworkChannel(connection: connection)
    }

    private static func parameters(pin: CertificatePin, queue: DispatchQueue) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(security, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(security, .TLSv13)
        sec_protocol_options_set_tls_server_name(security, "wiffletree-host")
        // Replaces trust evaluation only: TLS still checks the handshake's signature against
        // the certificate's key, so only the holder of the pinned key completes it.
        sec_protocol_options_set_verify_block(security, { _, trust, complete in
            complete(pin.accepts(sec_trust_copy_ref(trust).takeRetainedValue()))
        }, queue)
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        // A `read_file` reply carries up to 50 MB as base64.
        webSocket.maximumMessageSize = 80 << 20
        let parameters = NWParameters(tls: tls)
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        return parameters
    }

    /// Starts `connection` and waits until TLS and the WebSocket handshake complete.
    private static func start(_ connection: NWConnection, queue: DispatchQueue, timeout: Duration) async throws(ConnectionError) {
        let timedOut = Latch()
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    let resumed = Latch()
                    let resume = { @Sendable (result: Result<Void, any Error>) in
                        if resumed.set() { continuation.resume(with: result) }
                    }
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            resume(.success(()))
                        case .waiting(let error), .failed(let error):
                            connection.cancel()
                            resume(.failure(error))
                        case .cancelled:
                            resume(.failure(CancellationError()))
                        default:
                            break
                        }
                    }
                    connection.start(queue: queue)
                    queue.asyncAfter(deadline: .now() + timeout.timeInterval) {
                        guard connection.state != .ready else { return }
                        timedOut.set()
                        connection.cancel()
                    }
                }
            } onCancel: {
                connection.cancel()
            }
        } catch {
            connection.cancel()
            throw timedOut.isSet ? .timedOut : .closed
        }
    }
}

/// Accepts a certificate only when it carries the pinned host key, noting the key it saw.
final class CertificatePin: Sendable {
    let hostKey: Data
    private let seen = Mutex<Data?>(nil)

    init(hostKey: Data) {
        self.hostKey = hostKey
    }

    func accepts(_ trust: SecTrust) -> Bool {
        let key = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first.flatMap(Self.publicKey)
        seen.withLock { $0 = key }
        return key == hostKey
    }

    /// The certificate carried a key, and not the pinned one.
    var sawOtherKey: Bool {
        seen.withLock { $0 != nil && $0 != hostKey }
    }

    /// The certificate's public key; for P-256, SEC1 uncompressed, as the protocol writes keys.
    static func publicKey(of certificate: SecCertificate) -> Data? {
        guard let key = SecCertificateCopyKey(certificate) else { return nil }
        return SecKeyCopyExternalRepresentation(key, nil) as Data?
    }
}

/// A WebSocket on an `NWConnection` that `NetworkDialer` opened.
final class NetworkChannel: MessageChannel {
    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
        // A path that can no longer carry data, such as Wi-Fi gone, holds sends and reads
        // silently; dropping it now lets the client reconnect and say so at once.
        connection.viabilityUpdateHandler = { [weak connection] isViable in
            if !isViable { connection?.forceCancel() }
        }
    }

    func send(_ text: String) async throws(ConnectionError) {
        let context = NWConnection.ContentContext(
            identifier: "text",
            metadata: [NWProtocolWebSocket.Metadata(opcode: .text)]
        )
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                connection.send(content: Data(text.utf8), contentContext: context, isComplete: true, completion: .contentProcessed { error in
                    continuation.resume(with: error.map { .failure($0) } ?? .success(()))
                })
            }
        } catch {
            throw .closed
        }
    }

    func receive() async throws(ConnectionError) -> String {
        while true {
            let frame = await nextFrame()
            switch frame {
            case .text(let text): return text
            case .closed(let reason): throw reason == "unpaired" ? .unpaired : .closed
            case .other: continue
            }
        }
    }

    /// Drops the connection without sending what is still queued: a request the client has
    /// given up on must not reach the host minutes later, when a stalled link recovers.
    func close() {
        connection.forceCancel()
    }

    private enum Frame: Sendable {
        case text(String)
        case closed(reason: String?)
        /// Binary frames, which the protocol ignores, and pings and pongs.
        case other
    }

    private func nextFrame() async -> Frame {
        await withCheckedContinuation { continuation in
            connection.receiveMessage { content, context, _, error in
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                // A close frame arrives with an error too, so its reason is read first.
                switch (error, metadata?.opcode) {
                case (_, .close):
                    continuation.resume(returning: .closed(reason: content.map { String(decoding: $0, as: UTF8.self) }))
                case (.some, _), (nil, nil):
                    continuation.resume(returning: .closed(reason: nil))
                case (nil, .text):
                    continuation.resume(returning: .text(String(decoding: content ?? Data(), as: UTF8.self)))
                case (nil, _):
                    continuation.resume(returning: .other)
                }
            }
        }
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
