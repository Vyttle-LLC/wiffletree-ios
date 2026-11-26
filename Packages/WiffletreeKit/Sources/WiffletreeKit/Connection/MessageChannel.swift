import Foundation

/// A WebSocket to a host over pinned TLS, carrying one JSON message per text frame.
public protocol MessageChannel: Sendable {
    func send(_ text: String) async throws(ConnectionError)
    /// The next text message. Throws `closed` when the host closes the connection, or
    /// `unpaired` when it closes with that reason.
    func receive() async throws(ConnectionError) -> String
    func close()
}

/// Opens channels to a host.
public protocol ChannelDialer: Sendable {
    /// TLS 1.3 to `address`, accepted only when the certificate carries `hostKey`, then a
    /// WebSocket on `path`. Throws `otherKey` when the certificate carries another key, before
    /// anything is sent. Cancelling the calling task abandons the attempt.
    func open(_ address: HostAddress, path: String, hostKey: Data) async throws(ConnectionError) -> any MessageChannel
}

/// The WebSocket paths of `docs/remote-protocol.md`.
public enum ChannelPath {
    public static let pair = "/pair"
    public static let v1 = "/v1"
}

/// How long each step of the handshake may wait for the host: each pairing step on `/pair`, and
/// on `/v1` the challenge, `Hello` and the subscription that follows. The host allows each step
/// before `Hello` 30 seconds.
let handshakeStepLimit: Duration = .seconds(30)

/// Why talking to a host failed. The descriptions are sentences for a person.
public enum ConnectionError: Error, Equatable, Sendable {
    /// The certificate at one address carried another key than the pinned one. Address racing
    /// decides whether that means the host's key changed.
    case otherKey
    /// The host's key has changed; nothing connects until the device pairs again.
    case keyChanged
    /// The host no longer knows this device.
    case unpaired
    /// The host refused pairing, with its reason.
    case pairingRefused(String)
    /// The host's pairing confirmation did not hold: a stale QR code, or a machine in the middle.
    case confirmationFailed
    /// No address answered; carries the last failure.
    case unreachable(String)
    /// The host and this app share no protocol version.
    case incompatible(hostVersion: String)
    /// The host answered a command with an error, a sentence for a person.
    case commandFailed(String)
    /// The host sent something this client cannot read.
    case unexpectedMessage(String)
    /// The connection closed or dropped.
    case closed
    /// A step waited too long for the host.
    case timedOut
}

extension ConnectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .otherKey: "Another machine answered at this address."
        case .keyChanged: "The host's key has changed. Wiffletree won't connect until you pair again."
        case .unpaired: "The host no longer accepts this iPhone. Pair again from the host."
        case .pairingRefused(let reason), .commandFailed(let reason): reason
        case .confirmationFailed: "The host could not confirm the pairing code. Scan a fresh code."
        case .unreachable(let reason): reason
        case .incompatible(let version): "The host runs Wiffletree \(version), which this app cannot talk to."
        case .unexpectedMessage(let detail): "The host sent an unexpected message: \(detail)"
        case .closed: "The connection to the host closed."
        case .timedOut: "The host took too long to answer."
        }
    }

    /// Whether trying again cannot help: the human has to pair again or update.
    var isFinal: Bool {
        switch self {
        case .keyChanged, .unpaired, .incompatible: true
        default: false
        }
    }
}
