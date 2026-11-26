import Foundation

// The commands the first screens send, as `docs/host-protocol.md` lists them.

/// The live workspace: projects, agents, the Inbox and tickets.
public struct SnapshotCommand: HostCommand {
    public typealias Reply = Snapshot
    public static let type = "snapshot"
    public init() {}
}

/// A page of the messages sent to a session, oldest first: those before `before`, a sequence,
/// or the newest when it is nil.
public struct MessagesCommand: HostCommand {
    public typealias Reply = [Message]
    public static let type = "messages"
    public let sessionID: String
    public let before: Int64?
    public let limit: Int

    public init(sessionID: String, before: Int64? = nil, limit: Int = 50) {
        self.sessionID = sessionID
        self.before = before
        self.limit = limit
    }

    private enum CodingKeys: String, CodingKey { case sessionID = "sessionId", before, limit }
}

/// A message from the human to an agent, usually its project's coordinator. Sent again with the
/// same `id`, it is stored once, so a retry after a drop is safe.
public struct SendCommand: HostCommand {
    public typealias Reply = Message
    public static let type = "send"
    public let id: String
    public let recipient: String
    public let body: String
    /// The ids of finished uploads to attach; a host without the `uploads` capability never
    /// sees the field.
    public let uploads: [String]

    public init(id: String = UUID().uuidString, recipient: String, body: String, uploads: [String] = []) {
        self.id = id
        self.recipient = recipient
        self.body = body
        self.uploads = uploads
    }

    private enum CodingKeys: String, CodingKey { case id, recipient, body, uploads }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(recipient, forKey: .recipient)
        try container.encode(body, forKey: .body)
        if !uploads.isEmpty { try container.encode(uploads, forKey: .uploads) }
    }
}

/// One piece of a file the device attaches, at most `Upload.pieceLimit` bytes. The host keeps a
/// piece only where the upload ends, so one sent again changes nothing. Needs `uploads`.
public struct UploadAttachmentCommand: HostCommand, Equatable {
    public typealias Reply = Uploaded
    public static let type = "upload_attachment"
    public let uploadID: String
    public let name: String
    public let offset: Int
    /// The piece, base64.
    public let bytes: String

    public init(uploadID: String, name: String, offset: Int, bytes: String) {
        self.uploadID = uploadID
        self.name = name
        self.offset = offset
        self.bytes = bytes
    }

    private enum CodingKeys: String, CodingKey { case uploadID = "uploadId", name, offset, bytes }
}

/// A file under the host's roots, such as a sent message's attachment, refused when larger than
/// `maxBytes`. Needs `files`.
public struct ReadFileCommand: HostCommand {
    public typealias Reply = FileContents
    public static let type = "read_file"
    public let path: String
    public let maxBytes: Int

    public init(path: String, maxBytes: Int) {
        self.path = path
        self.maxBytes = maxBytes
    }
}

/// Answers an Inbox item: a question with its answer, an approval with `approved` or anything
/// else as denied.
public struct ResolveAttentionCommand: HostCommand {
    public typealias Reply = Attention
    public static let type = "resolve_attention"
    public let id: String
    public let answer: String

    public init(id: String, answer: String) {
        self.id = id
        self.answer = answer
    }
}

/// Clears an Inbox question without answering it or waking its asker.
public struct DismissAttentionCommand: HostCommand {
    public typealias Reply = Attention
    public static let type = "dismiss_attention"
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

/// Tokens and their cost over the last `days` days.
public struct UsageCommand: HostCommand {
    public typealias Reply = UsageReport
    public static let type = "usage"
    public let days: Int
    public let projectID: String?
    public let provider: String?
    /// An IANA name, such as `Europe/London`, that decides where days start.
    public let timezone: String

    public init(days: Int, projectID: String? = nil, provider: String? = nil, timezone: String = TimeZone.current.identifier) {
        self.days = days
        self.projectID = projectID
        self.provider = provider
        self.timezone = timezone
    }

    private enum CodingKeys: String, CodingKey { case days, projectID = "projectId", provider, timezone }
}

/// Each provider's quota windows.
public struct QuotasCommand: HostCommand {
    public typealias Reply = [QuotaReading]
    public static let type = "quotas"
    public init() {}
}

/// Answered by the connection itself, so it tells a quiet host from one that is gone.
public struct PingCommand: HostCommand {
    public typealias Reply = NoReply
    public static let type = "ping"
    public init() {}
}

/// Turns the connection into a subscriber, after the events following `after` when the host
/// still holds them, or after a `resync`. `RemoteHostConnection` sends it; a caller never needs to.
struct SubscribeCommand: HostCommand {
    struct Subscribed: Decodable, Sendable {
        let cursor: Cursor
    }
    typealias Reply = Subscribed
    static let type = "subscribe"
    let after: Cursor?
}
