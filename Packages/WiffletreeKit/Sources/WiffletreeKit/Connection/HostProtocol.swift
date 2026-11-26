import Foundation

// The host protocol of `docs/host-protocol.md` after the challenge: `Hello`, requests matched to
// responses by id, and events. Field names are snake_case on the wire; `HostJSON` converts them.

enum HostJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

/// The protocol version this client speaks; the host accepts its own and the one before.
let hostProtocolVersion = 2

struct HelloLine: Encodable {
    struct Hello: Encodable {
        struct Client: Encodable {
            let name: String
            let kind: String
        }
        let protocols: [Int]
        let appVersion: String
        let client: Client
        let capabilities: [String]
    }
    let hello: Hello

    init(appVersion: String) {
        hello = Hello(
            protocols: [hostProtocolVersion, hostProtocolVersion],
            appVersion: appVersion,
            client: .init(name: "Wiffletree for iPhone", kind: "iphone"),
            capabilities: []
        )
    }
}

/// `{"welcome": {...}}` or `{"refused": {...}}`.
struct HelloAnswer: Decodable {
    struct Refusal: Decodable {
        let hostVersion: String
    }
    let welcome: Welcome?
    let refused: Refusal?
}

/// The host's welcome: the protocol every later request uses, and what the host supports.
struct Welcome: Decodable {
    let `protocol`: Int
    let capabilities: [String]
}

/// Where a subscriber is in the host's event stream.
public struct Cursor: Codable, Equatable, Sendable {
    public let epoch: String
    /// Grows by one per event within an epoch.
    public let seq: UInt64

    public init(epoch: String, seq: UInt64) {
        self.epoch = epoch
        self.seq = seq
    }
}

/// An event from the host: what to fetch again. Events never carry workspace state.
public struct HostEvent: Decodable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Reload the snapshot.
        case state
        /// Fetch these sessions' steps.
        case steps(sessions: [String])
        /// Fetch progress.
        case progress
        /// Fetch usage and quotas.
        case usage
        /// How many things need the human: Inbox items and workspace notes.
        case attention(count: Int)
        /// Events were lost: take a fresh snapshot, then continue.
        case resync
        /// A kind this client does not know yet.
        case unknown(String)
    }

    public let cursor: Cursor
    public let kind: Kind

    public init(cursor: Cursor, kind: Kind) {
        self.cursor = cursor
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case cursor, kind, sessions, count }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try container.decode(Cursor.self, forKey: .cursor)
        kind = switch try container.decode(String.self, forKey: .kind) {
        case "state": .state
        case "steps": .steps(sessions: try container.decode([String].self, forKey: .sessions))
        case "progress": .progress
        case "usage": .usage
        case "attention": .attention(count: try container.decode(Int.self, forKey: .count))
        case "resync": .resync
        case let other: .unknown(other)
        }
    }
}

/// A command of the host protocol, encoded as its fields beside `"type"`, with the type of its
/// reply's `result`.
public protocol HostCommand: Encodable, Sendable {
    associatedtype Reply: Decodable & Sendable
    /// The command's `type`, such as `snapshot`.
    static var type: String { get }
}

/// The reply of a command the host answers with nothing.
public struct NoReply: Decodable, Equatable, Sendable {
    public init() {}
    public init(from decoder: any Decoder) throws {}
}

struct RequestLine<Command: HostCommand>: Encodable {
    let version: Int
    let id: String
    let command: Command

    private enum CodingKeys: String, CodingKey { case version, id, command }
    private enum TypeKey: String, CodingKey { case type }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(id, forKey: .id)
        let commandEncoder = container.superEncoder(forKey: .command)
        var type = commandEncoder.container(keyedBy: TypeKey.self)
        try type.encode(Command.type, forKey: .type)
        try command.encode(to: commandEncoder)
    }
}

/// What a frame from the host is: a response by `id`, or an event.
struct InboundFrame: Decodable {
    let id: String?
    let error: String?
    let event: HostEvent?
}

/// A response's `result`, as the command's reply type.
struct ResultBox<Reply: Decodable>: Decodable {
    let result: Reply?
}
