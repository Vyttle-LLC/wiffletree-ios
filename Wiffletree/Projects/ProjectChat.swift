import Foundation
import Observation
import UIKit
import WiffletreeKit

/// A row of the conversation: the human's message, the coordinator's reply, or one burst of
/// agent-to-agent traffic and notices folded into one line (design call 4).
enum ChatEntry: Identifiable {
    case human(Message)
    case reply(Message)
    case activity([Message])

    var id: String {
        switch self {
        case .human(let message), .reply(let message): message.id
        case .activity(let messages): "activity-\(messages[0].id)"
        }
    }

    var messages: [Message] {
        switch self {
        case .human(let message), .reply(let message): [message]
        case .activity(let messages): messages
        }
    }

    /// The conversation's messages in order, each unbroken run of agent messages and notices
    /// folded into one entry.
    static func fold(_ messages: [Message]) -> [ChatEntry] {
        var entries: [ChatEntry] = []
        for message in messages {
            switch message.kind {
            case .human: entries.append(.human(message))
            case .reply: entries.append(.reply(message))
            case .agent, .notice:
                if case .activity(let burst) = entries.last {
                    entries[entries.count - 1] = .activity(burst + [message])
                } else {
                    entries.append(.activity([message]))
                }
            }
        }
        return entries
    }
}

/// A photo in the composer and how much of it the host holds.
struct ComposerPhoto: Identifiable {
    var upload: Upload
    let thumbnail: UIImage

    var id: String { upload.id }
}

/// A project's conversation with its coordinator: the messages loaded so far, the running turn's
/// narration, and sending, with photos. `run()` keeps both current from the host's events; the
/// newest page merges into what is loaded, and earlier pages load on request.
@MainActor
@Observable
final class ProjectChat {
    let projectID: String
    /// Oldest first: the newest page and any earlier pages loaded since.
    private(set) var messages: [Message] = []
    /// Whether the host may hold messages older than the loaded ones.
    private(set) var hasEarlier = false
    private(set) var isLoadingEarlier = false
    /// The coordinator's latest run; its narration shows while it runs.
    private(set) var turn: StepPage?
    /// Why the last load failed, until one succeeds.
    private(set) var failure: String?
    /// Why the last send failed, until a send succeeds; sending again retries it.
    private(set) var sendFailure: String?
    private(set) var isSending = false
    var draft = ""
    /// Photos to send with the draft, in the order chosen.
    private(set) var photos: [ComposerPhoto] = []
    /// Photos chosen but still being converted; Send waits for them.
    private(set) var converting = 0
    /// Sent attachments' thumbnails by path, as far as they have loaded.
    private(set) var thumbnails: [String: UIImage] = [:]
    /// Sent attachments whose image could not be read, shown by name instead.
    private(set) var unreadable: Set<String> = []

    @ObservationIgnored private let host: LiveHost
    /// How many messages one read asks for.
    @ObservationIgnored private let pageSize: Int
    /// Names photos uniquely within a message, which the host requires.
    @ObservationIgnored private var photosNamed = 0
    /// The last send that failed. Retrying the same message reuses its id, so the host stores it
    /// once; a changed message gets a new id, which the host requires.
    @ObservationIgnored private var unsent: SendCommand?

    /// - Parameter pageSize: The host's largest page by default, as the desktop reads.
    init(host: LiveHost, projectID: String, pageSize: Int = 100) {
        self.host = host
        self.projectID = projectID
        self.pageSize = pageSize
    }

    var overview: ProjectOverview? { host.snapshot?.overview(of: projectID) }
    var coordinator: Session? { overview?.coordinator }
    var entries: [ChatEntry] { ChatEntry.fold(messages) }

    /// What the coordinator has said so far in a turn that is still running.
    var liveNarration: [Step] {
        guard let turn, turn.running else { return [] }
        return turn.narration
    }

    var canSend: Bool {
        (!body.isEmpty || !photos.isEmpty) && converting == 0 && !isSending && coordinator != nil
    }

    /// Whether the host takes photos from this iPhone: it offers uploads and lets it make changes.
    var canAttach: Bool {
        host.capabilities.contains("uploads") && host.level == .control
    }

    /// How much of the photos the host holds while sending them, from 0 to 1.
    var uploadProgress: Double? {
        guard isSending, !photos.isEmpty else { return nil }
        let total = photos.reduce(0) { $0 + $1.upload.data.count }
        let stored = photos.reduce(0) { $0 + $1.upload.stored }
        return total == 0 ? 1 : Double(stored) / Double(total)
    }

    private var body: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Loads and converts each chosen photo off the main actor, attaching them in the order chosen.
    func attach(_ loads: [@Sendable () async -> Photo?]) async {
        converting += loads.count
        for load in loads {
            if let photo = await Task.detached(operation: load).value { attach(photo) }
            converting -= 1
        }
    }

    func attach(_ photo: Photo) {
        photosNamed += 1
        photos.append(ComposerPhoto(upload: Upload(name: "Photo \(photosNamed).jpg", data: photo.jpeg), thumbnail: photo.thumbnail))
    }

    func remove(_ photoID: String) {
        guard !isSending else { return }
        photos.removeAll { $0.id == photoID }
    }

    /// Loads the conversation, then follows the host's events until the task is cancelled.
    func run() async {
        let events = host.events()
        await reloadAll()
        for await event in events {
            switch event.kind {
            case .steps(let sessions) where sessions.contains(coordinator?.id ?? ""):
                await refreshTurn()
            case .state:
                await reloadMessages()
            case .resync:
                await reloadAll()
            default:
                break
            }
        }
    }

    /// Uploads the photos the host does not hold yet, then sends the draft naming them. The
    /// message shows as soon as the host stores it; the reply follows with the turn it starts.
    /// After a failure, sending again resumes where it stopped.
    func send() async {
        guard canSend, let coordinator else { return }
        isSending = true
        defer { isSending = false }
        sendFailure = nil
        let uploader = Uploader(connection: host.connection)
        for photo in photos where !photo.upload.isComplete {
            do {
                let uploaded = try await uploader.send(photo.upload) { @MainActor upload in self.update(upload) }
                update(uploaded)
            } catch {
                sendFailure = "Couldn't upload \(photo.upload.name): \(error.localizedDescription)"
                return
            }
        }
        let uploads = photos.map(\.upload.id)
        let retried = unsent.flatMap { $0.recipient == coordinator.id && $0.body == body && $0.uploads == uploads ? $0.id : nil }
        let command = SendCommand(id: retried ?? UUID().uuidString, recipient: coordinator.id, body: body, uploads: uploads)
        do {
            let sent = try await host.connection.request(command)
            for (photo, attachment) in zip(photos, sent.attachments) { thumbnails[attachment.path] = photo.thumbnail }
            draft = ""
            photos = []
            photosNamed = 0
            unsent = nil
            if !messages.contains(where: { $0.id == sent.id }) { messages.append(sent) }
        } catch {
            unsent = command
            sendFailure = error.localizedDescription
        }
    }

    /// Fetches a sent image attachment's thumbnail once, from a host that serves files.
    func loadThumbnail(of attachment: Attachment) async {
        let path = attachment.path
        guard thumbnails[path] == nil, !unreadable.contains(path) else { return }
        guard host.capabilities.contains("files"),
              let contents = try? await host.connection.request(ReadFileCommand(path: path, maxBytes: Self.thumbnailSourceLimit)),
              let image = contents.bytes.flatMap(Photo.thumbnail(of:))
        else {
            unreadable.insert(path)
            return
        }
        thumbnails[path] = image
    }

    /// The largest image the conversation fetches to show.
    private static let thumbnailSourceLimit = 10 * 1024 * 1024

    private func update(_ upload: Upload) {
        guard let index = photos.firstIndex(where: { $0.id == upload.id }) else { return }
        photos[index].upload = upload
    }

    /// The page of messages before the oldest loaded one, added above it.
    func loadEarlier() async {
        guard hasEarlier, !isLoadingEarlier, let oldest = messages.first else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        await load { coordinator in
            let page = try await host.connection.request(MessagesCommand(sessionID: coordinator, before: oldest.sequence, limit: pageSize))
            // A newest page that landed meanwhile may have replaced what this page continues.
            guard messages.first?.id == oldest.id else { return }
            messages = page + messages
            hasEarlier = page.count == pageSize
        }
    }

    /// The newest messages and the whole latest turn: on opening, and after events were lost.
    private func reloadAll() async {
        await load { coordinator in
            try await reloadMessages(of: coordinator)
            turn = try await host.connection.request(StepsCommand(sessionID: coordinator))
        }
    }

    private func reloadMessages() async {
        await load(reloadMessages(of:))
    }

    private func reloadMessages(of coordinator: String) async throws {
        let page = try await host.connection.request(MessagesCommand(sessionID: coordinator, limit: pageSize))
        mergeNewest(page)
    }

    /// Takes the newest page as the truth from its oldest message on, keeping the loaded messages
    /// before it. A page short of full holds the whole conversation; a full one that does not
    /// reach back to the loaded messages leaves a gap, so it starts the history again from itself
    /// and "Load earlier" fills the rest.
    private func mergeNewest(_ page: [Message]) {
        let isFull = page.count == pageSize
        let older: [Message]
        if let first = page.first, isFull, let newest = messages.last, newest.sequence >= first.sequence {
            older = messages.filter { $0.sequence < first.sequence }
        } else {
            older = []
        }
        messages = older + page
        if older.isEmpty { hasEarlier = isFull }
    }

    /// Only the steps changed since the turn last read, merged into it.
    private func refreshTurn() async {
        await load { coordinator in
            let newer = try await host.connection.request(StepsCommand(sessionID: coordinator, after: turn?.revision ?? 0))
            turn = turn.map { $0.merging(newer) } ?? newer
        }
    }

    private func load(_ fetch: (_ coordinator: String) async throws -> Void) async {
        guard let coordinator else { return }
        do {
            try await fetch(coordinator.id)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}
