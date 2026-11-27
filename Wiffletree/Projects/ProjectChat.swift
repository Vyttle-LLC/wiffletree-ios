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

/// A message's file references as the host resolved them.
struct MessageFiles {
    /// The message's Markdown with each file it names linked.
    let markdown: String
    /// The linked images, in the order the message names them.
    let images: [String]
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
    /// Whether the last "Load earlier" failed; the row offers it again.
    private(set) var earlierFailed = false
    /// The coordinator's latest run; its narration shows while it runs.
    private(set) var turn: StepPage?
    /// Whether the newest messages have loaded once; until then the chat shows it is loading.
    private(set) var hasLoaded = false
    /// Why the newest messages did not load, until they do.
    private(set) var failure: String?
    /// Why the last send failed, until a send succeeds; sending again retries it.
    private(set) var sendFailure: String?
    private(set) var isSending = false
    var draft = ""
    /// Photos to send with the draft, in the order chosen.
    private(set) var photos: [ComposerPhoto] = []
    /// Photos chosen but still being converted; Send waits for them.
    private(set) var converting = 0
    /// Thumbnails of sent attachments and linked images by path, as far as they have loaded; only
    /// the latest `thumbnailLimit` are kept.
    private(set) var thumbnails: [String: UIImage] = [:]
    /// Images that could not be read, shown by name instead.
    private(set) var unreadable: Set<String> = []
    /// Messages' file links by message id, once the host has said which references are files.
    private(set) var fileLinks: [String: MessageFiles] = [:]

    @ObservationIgnored private let host: LiveHost
    /// How many messages one read asks for.
    @ObservationIgnored private let pageSize: Int
    /// Names photos uniquely within a message, which the host requires.
    @ObservationIgnored private var photosNamed = 0
    /// The last send that failed. Retrying the same message reuses its id, so the host stores it
    /// once; a changed message gets a new id, which the host requires.
    @ObservationIgnored private var unsent: SendCommand?
    /// The newest sequence the last newest page held. A sent message shows before any page holds
    /// it, so it never counts towards whether a page reaches back to the loaded history.
    @ObservationIgnored private var newestPaged: Int64?
    /// The thumbnails' paths, oldest first, so the oldest go first.
    @ObservationIgnored private var thumbnailOrder: [String] = []

    /// - Parameter pageSize: The host's largest page by default, as the desktop reads.
    init(host: LiveHost, projectID: String, pageSize: Int = 100) {
        self.host = host
        self.projectID = projectID
        self.pageSize = pageSize
    }

    var overview: ProjectOverview? { host.snapshot?.overview(of: projectID) }
    var coordinator: Session? { overview?.coordinator }
    var entries: [ChatEntry] { ChatEntry.fold(messages) }

    /// Nothing has loaded and the host is not connected, so the chat waits for it.
    var isWaitingForHost: Bool { !hasLoaded && !host.isConnected }

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
                sendFailure = "Couldn't upload \(photo.upload.name): \(host.failureText(error))"
                return
            }
        }
        let uploads = photos.map(\.upload.id)
        let retried = unsent.flatMap { $0.recipient == coordinator.id && $0.body == body && $0.uploads == uploads ? $0.id : nil }
        let command = SendCommand(id: retried ?? UUID().uuidString, recipient: coordinator.id, body: body, uploads: uploads)
        do {
            let sent = try await host.connection.request(command)
            for (photo, attachment) in zip(photos, sent.attachments) { keep(photo.thumbnail, of: attachment.path) }
            draft = ""
            photos = []
            photosNamed = 0
            unsent = nil
            if !messages.contains(where: { $0.id == sent.id }) { messages.append(sent) }
        } catch {
            unsent = command
            sendFailure = host.failureText(error)
        }
    }

    /// Fetches the thumbnail of an image on the host, a sent attachment or a linked file, from a
    /// host that serves files, unless it is kept already.
    func loadThumbnail(of path: String) async {
        guard thumbnails[path] == nil, !unreadable.contains(path) else { return }
        guard host.capabilities.contains("files"),
              let contents = try? await host.connection.request(ReadFileCommand(path: path, maxBytes: Self.thumbnailSourceLimit)),
              let image = contents.bytes.flatMap(Photo.thumbnail(of:))
        else {
            unreadable.insert(path)
            return
        }
        keep(image, of: path)
    }

    /// The largest image the conversation fetches to show.
    private static let thumbnailSourceLimit = 10 * 1024 * 1024
    /// Enough thumbnails for the messages on screen and a little scrolling.
    private static let thumbnailLimit = 40

    private func keep(_ thumbnail: UIImage, of path: String) {
        thumbnails[path] = thumbnail
        thumbnailOrder.removeAll { $0 == path }
        thumbnailOrder.append(path)
        while thumbnailOrder.count > Self.thumbnailLimit {
            thumbnails[thumbnailOrder.removeFirst()] = nil
        }
    }

    /// Asks the host which of a message's references are files, in one request, and links them.
    /// Only files the host finds become links, and never one that would run when opened. Asked
    /// again the next time the message shows when the host could not answer.
    func resolveFiles(of message: Message) async {
        guard fileLinks[message.id] == nil, host.capabilities.contains("files") else { return }
        let references = FileLinks.references(in: message.body)
        guard !references.isEmpty,
              let resolved = try? await host.connection.request(ResolvePathsCommand(references: references, bases: linkBases(of: message)))
        else { return }
        var files: [String: String] = [:]
        for case let (reference, file?) in zip(references, resolved) where !file.runsWhenOpened {
            files[reference] = file.path
        }
        var images: [String] = []
        for reference in references {
            if let path = files[reference], FileLinks.isImage(path), !images.contains(path) { images.append(path) }
        }
        fileLinks[message.id] = MessageFiles(markdown: FileLinks.linked(message.body, files: files), images: images)
    }

    /// Where a message's relative references resolve, as the desktop has it: its sender's ticket
    /// worktree or directory, then the project's home. The human's resolve as the coordinator's.
    private func linkBases(of message: Message) -> [String] {
        guard let snapshot = host.snapshot else { return [] }
        let runtime = (message.sender ?? coordinator?.id).flatMap(snapshot.runtime(of:))
        let home = snapshot.projects.first { $0.id == projectID }?.home
        return [runtime?.workdir ?? runtime?.directory, home].compactMap(\.self)
    }

    /// Reads a file from the host into a temporary copy to show, at most as large as the host
    /// serves. The copy goes with `removeCopy(_:)`.
    func copy(of path: String) async throws -> URL {
        let contents = try await host.connection.request(ReadFileCommand(path: path, maxBytes: Upload.sizeLimit))
        try Task.checkCancellation()
        guard let bytes = contents.bytes else { throw ConnectionError.unexpectedMessage("the contents of \(path)") }
        let folder = FileManager.default.temporaryDirectory.appending(path: "Opened/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: (path as NSString).lastPathComponent)
        try bytes.write(to: copy, options: .completeFileProtection)
        return copy
    }

    func removeCopy(_ copy: URL) {
        try? FileManager.default.removeItem(at: copy.deletingLastPathComponent())
    }

    private func update(_ upload: Upload) {
        guard let index = photos.firstIndex(where: { $0.id == upload.id }) else { return }
        photos[index].upload = upload
    }

    /// The page of messages before the oldest loaded one, added above it.
    func loadEarlier() async {
        guard hasEarlier, !isLoadingEarlier, let oldest = messages.first else { return }
        guard let coordinator else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        do {
            let page = try await host.connection.request(MessagesCommand(sessionID: coordinator.id, before: oldest.sequence, limit: pageSize))
            earlierFailed = false
            // A newest page that landed meanwhile may have replaced what this page continues.
            guard messages.first?.id == oldest.id else { return }
            messages = page + messages
            hasEarlier = page.count == pageSize
        } catch {
            earlierFailed = true
        }
    }

    /// The newest messages and the whole latest turn: on opening, after events were lost, and
    /// when the person retries a failed load.
    func reloadAll() async {
        await reloadMessages()
        guard let coordinator else { return }
        if let latest = try? await host.connection.request(StepsCommand(sessionID: coordinator.id)) { turn = latest }
    }

    /// The newest page, merged into what is loaded. Only this read sets or clears `failure`; a
    /// failure while the host is disconnected is the connection's, which the host header shows.
    private func reloadMessages() async {
        guard let coordinator else { return }
        do {
            mergeNewest(try await host.connection.request(MessagesCommand(sessionID: coordinator.id, limit: pageSize)))
            hasLoaded = true
            failure = nil
        } catch {
            if host.isConnected { failure = error.localizedDescription }
        }
    }

    /// Takes the newest page as the truth from its oldest message on, keeping the loaded messages
    /// before it and whether earlier ones remain. Otherwise the page starts the history again:
    /// short of full it holds the whole conversation; full, it does not reach back to what pages
    /// held, so "Load earlier" fills the gap.
    private func mergeNewest(_ page: [Message]) {
        if let first = page.first, page.count == pageSize, let newestPaged, newestPaged >= first.sequence {
            messages = messages.filter { $0.sequence < first.sequence } + page
        } else {
            messages = page
            hasEarlier = page.count == pageSize
        }
        newestPaged = page.last?.sequence
    }

    /// Only the steps changed since the turn last read, merged into it. A failed read waits for
    /// the next steps event, leaving the turn as it was.
    private func refreshTurn() async {
        guard let coordinator,
              let newer = try? await host.connection.request(StepsCommand(sessionID: coordinator.id, after: turn?.revision ?? 0))
        else { return }
        turn = turn.map { $0.merging(newer) } ?? newer
    }
}
