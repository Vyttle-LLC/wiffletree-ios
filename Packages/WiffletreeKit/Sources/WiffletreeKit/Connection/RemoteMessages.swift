import Foundation

/// What a paired device may do on a host.
public enum AccessLevel: String, Codable, Sendable {
    /// Every workspace command, as the human at the host could give it.
    case control
    /// Reads, the handshake and the event subscription only.
    case viewOnly = "view_only"
}

// The JSON messages of `/pair` and of the challenge on `/v1`, as the host's `remote.rs` has them.

struct PairStart: Codable {
    let method: String
    let deviceName: String
    /// SEC1 uncompressed, base64.
    let deviceKey: String
    /// The device's confirmation keyed with the QR code's secret, base64.
    let proof: String

    enum CodingKeys: String, CodingKey {
        case method, deviceName = "device_name", deviceKey = "device_key", proof
    }
}

/// `{"paired": {"confirm": "…", "host_id": "…"}}` or `{"refused": {"reason": "…"}}`. The `code`
/// method's `spake` reply never comes to a `qr` pairing.
enum PairReply: Decodable {
    case paired(confirm: String, hostID: String)
    case refused(reason: String)

    private enum CodingKeys: String, CodingKey { case paired, refused }
    private enum PairedKeys: String, CodingKey { case confirm, hostID = "host_id" }
    private enum RefusedKeys: String, CodingKey { case reason }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.paired) {
            let paired = try container.nestedContainer(keyedBy: PairedKeys.self, forKey: .paired)
            self = .paired(confirm: try paired.decode(String.self, forKey: .confirm), hostID: try paired.decode(String.self, forKey: .hostID))
        } else {
            let refused = try container.nestedContainer(keyedBy: RefusedKeys.self, forKey: .refused)
            self = .refused(reason: try refused.decode(String.self, forKey: .reason))
        }
    }
}

struct Challenge: Codable {
    /// base64.
    let challenge: String
    let hostID: String

    enum CodingKeys: String, CodingKey { case challenge, hostID = "host_id" }
}

struct ChallengeAnswer: Codable {
    let deviceID: String
    /// Raw `r ‖ s`, base64.
    let signature: String

    enum CodingKeys: String, CodingKey { case deviceID = "device_id", signature }
}

/// `{"accepted": {"level": "control"}}`, or the string `"unpaired"`.
enum ChallengeVerdict: Decodable, Equatable {
    case accepted(AccessLevel)
    case unpaired

    private struct Accepted: Decodable {
        struct Level: Decodable { let level: AccessLevel }
        let accepted: Level
    }

    init(from decoder: any Decoder) throws {
        if let word = try? decoder.singleValueContainer().decode(String.self), word == "unpaired" {
            self = .unpaired
        } else {
            self = .accepted(try Accepted(from: decoder).accepted.level)
        }
    }
}

extension MessageChannel {
    func send(json value: some Encodable, using encoder: JSONEncoder = JSONEncoder()) async throws(ConnectionError) {
        guard let data = try? encoder.encode(value) else {
            throw .unexpectedMessage("could not encode \(type(of: value))")
        }
        try await send(String(decoding: data, as: UTF8.self))
    }

    /// The next message as `T`, closing the channel if the host takes longer than `limit`.
    func receive<T: Decodable>(json type: T.Type, within limit: Duration, using decoder: JSONDecoder = JSONDecoder()) async throws(ConnectionError) -> T {
        let timedOut = Latch()
        let timer = Task {
            try await Task.sleep(for: limit)
            timedOut.set()
            close()
        }
        defer { timer.cancel() }
        let text: String
        do {
            text = try await receive()
        } catch {
            throw timedOut.isSet ? .timedOut : error
        }
        do {
            return try decoder.decode(type, from: Data(text.utf8))
        } catch {
            throw .unexpectedMessage(String(text.prefix(200)))
        }
    }
}
