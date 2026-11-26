import Foundation

/// A file going up to the host in pieces with `upload_attachment`, so a message's `uploads` can
/// name it (`docs/remote-protocol.md`, "Uploads"). It remembers how much the host holds, so a
/// cut-off upload resumes there.
public struct Upload: Equatable, Sendable {
    /// The largest piece the host accepts.
    public static let pieceLimit = 128 * 1024
    /// The host's limit for one attachment.
    public static let sizeLimit = 50 * 1024 * 1024

    public let id: String
    public let name: String
    public let data: Data
    /// How many bytes the host holds: where the next piece starts.
    public private(set) var stored = 0
    private var answered = false

    public init(id: String = UUID().uuidString, name: String, data: Data) {
        self.id = id
        self.name = name
        self.data = data
    }

    /// Whether the host holds the whole file, so a message may name it.
    public var isComplete: Bool { answered && stored == data.count }

    public var fraction: Double { data.isEmpty ? (isComplete ? 1 : 0) : Double(stored) / Double(data.count) }

    /// The piece that continues where the host's copy ends, or nil once it holds the whole file.
    /// An empty file is one empty piece.
    public var nextPiece: UploadAttachmentCommand? {
        guard !isComplete else { return nil }
        let end = min(stored + Self.pieceLimit, data.count)
        let piece = data[data.startIndex + stored ..< data.startIndex + end]
        return UploadAttachmentCommand(uploadID: id, name: name, offset: stored, bytes: piece.base64EncodedString())
    }

    /// Takes in the host's answer to a piece.
    public mutating func record(_ uploaded: Uploaded) {
        stored = min(max(uploaded.stored, 0), data.count)
        answered = true
    }
}

/// Sends uploads piece by piece. A piece lost to a dropped connection goes again once the host
/// is back, for up to `patience`; a refusal ends the upload with the host's reason.
public struct Uploader: Sendable {
    private let store: @Sendable (UploadAttachmentCommand) async throws -> Uploaded
    private let pause: Duration
    private let patience: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        connection: any HostConnection,
        pause: Duration = .seconds(1),
        patience: Duration = .seconds(60),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.init(store: { try await connection.request($0) }, pause: pause, patience: patience, sleep: sleep)
    }

    init(
        store: @escaping @Sendable (UploadAttachmentCommand) async throws -> Uploaded,
        pause: Duration,
        patience: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.store = store
        self.pause = pause
        self.patience = patience
        self.sleep = sleep
    }

    /// Sends `upload`'s remaining pieces, telling `progress` after each answer, and returns the
    /// finished upload. Throws the reason it stopped; `progress` last saw where to resume.
    public func send(_ upload: Upload, progress: @Sendable (Upload) async -> Void = { _ in }) async throws -> Upload {
        guard upload.data.count <= Upload.sizeLimit else {
            throw ConnectionError.commandFailed("\(upload.name) is over 50 MB")
        }
        var upload = upload
        var waited = Duration.zero
        while let piece = upload.nextPiece {
            do {
                upload.record(try await store(piece))
                waited = .zero
                await progress(upload)
            } catch let error as ConnectionError where error.isLost && waited < patience {
                try await sleep(pause)
                waited += pause
            }
        }
        return upload
    }
}

extension ConnectionError {
    /// The connection dropped or the host did not answer, rather than refusing: worth sending
    /// again once it is back.
    var isLost: Bool {
        switch self {
        case .closed, .timedOut, .unreachable: true
        default: false
        }
    }
}
