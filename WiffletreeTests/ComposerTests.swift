import Foundation
import ImageIO
import Synchronization
import Testing
import UIKit
import UniformTypeIdentifiers
import WiffletreeKit
@testable import Wiffletree

@MainActor
private func eventually(_ condition: () -> Bool) async throws {
    for _ in 0..<200 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}

/// The demo, refusing one upload piece as a full disk would, and recording the offsets of the
/// pieces it stored.
private final class RefusingConnection: HostConnection {
    let demo = DemoHostConnection()
    private let pieces = Mutex(0)
    private let refused: Int
    let offsets = Mutex<[Int]>([])

    /// - Parameter refused: Which piece to refuse, counting from 1.
    init(refusing refused: Int) {
        self.refused = refused
    }

    var events: AsyncStream<HostEvent> { demo.events }
    var states: AsyncStream<ConnectionState> { demo.states }
    var isDemo: Bool { true }

    func request<Command: HostCommand>(_ command: Command) async throws -> Command.Reply {
        if let piece = command as? UploadAttachmentCommand {
            let count = pieces.withLock { $0 += 1; return $0 }
            if count == refused { throw ConnectionError.commandFailed("The disk is full") }
            offsets.withLock { $0.append(piece.offset) }
        }
        return try await demo.request(command)
    }

    func close() {
        demo.close()
    }
}

/// The demo, losing the reply to its first `send` after storing the message, as a drop would.
private final class LosingConnection: HostConnection {
    let demo = DemoHostConnection()
    private let lost = Mutex(false)
    let sentIDs = Mutex<[String]>([])

    var events: AsyncStream<HostEvent> { demo.events }
    var states: AsyncStream<ConnectionState> { demo.states }
    var isDemo: Bool { true }

    func request<Command: HostCommand>(_ command: Command) async throws -> Command.Reply {
        let reply = try await demo.request(command)
        if let send = command as? SendCommand {
            sentIDs.withLock { $0.append(send.id) }
            let first = lost.withLock { lost in defer { lost = true }; return !lost }
            if first { throw ConnectionError.closed }
        }
        return reply
    }

    func close() {
        demo.close()
    }
}

@MainActor
private func demoHost(_ connection: any HostConnection = DemoHostConnection()) async throws -> LiveHost {
    let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { connection })
    try await eventually { host.snapshot != nil }
    return host
}

@MainActor
private func chat(on connection: any HostConnection = DemoHostConnection()) async throws -> ProjectChat {
    ProjectChat(host: try await demoHost(connection), projectID: "demo-tide-alerts")
}

/// A photo the size of a phone camera's, as HEIC.
private func cameraPhoto(width: Int = 4032, height: Int = 3024) throws -> Data {
    let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return format
    }()).image { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(image.cgImage), nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

/// A photo of noise, which compresses so little that it takes several pieces.
private func noisyPhoto() throws -> Data {
    let side = 1024
    var bytes = (0..<side * side * 4).map { _ in UInt8.random(in: 0...255) }
    let context = try #require(CGContext(
        data: &bytes, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    let image = try #require(context.makeImage())
    return try #require(UIImage(cgImage: image).pngData())
}

private func pixelSize(of jpeg: Data) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    return (properties[kCGImagePropertyPixelWidth] as! Int, properties[kCGImagePropertyPixelHeight] as! Int)
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ComposerTests {
    @Test func aHEICPhotoBecomesAJPEGNoLongerThan2048Pixels() throws {
        let photo = try #require(Photo(data: try cameraPhoto()))
        #expect(photo.jpeg.starts(with: [0xFF, 0xD8, 0xFF]))
        let size = try pixelSize(of: photo.jpeg)
        #expect(size.width == 2048)
        #expect(size.height == 1536)
        #expect(max(photo.thumbnail.size.width, photo.thumbnail.size.height) == CGFloat(Photo.thumbnailSide))
    }

    @Test func aSmallPhotoKeepsItsSize() throws {
        let photo = try #require(Photo(data: try cameraPhoto(width: 800, height: 600)))
        let size = try pixelSize(of: photo.jpeg)
        #expect(size.width == 800)
        #expect(size.height == 600)
    }

    @Test func photosAreAttachedAndRemovedAndAloneMakeAMessage() async throws {
        let chat = try await chat()
        #expect(chat.canAttach)
        #expect(!chat.canSend)
        let photo = try #require(Photo(data: try cameraPhoto(width: 400, height: 300)))
        chat.attach(photo)
        chat.attach(photo)
        #expect(chat.photos.map(\.upload.name) == ["Photo 1.jpg", "Photo 2.jpg"])
        #expect(chat.canSend)
        chat.remove(chat.photos[0].id)
        #expect(chat.photos.map(\.upload.name) == ["Photo 2.jpg"])
        chat.remove(chat.photos[0].id)
        #expect(!chat.canSend)
    }

    @Test func sendingUploadsThePhotosThenSendsTheMessageNamingThem() async throws {
        let chat = try await chat()
        let photo = try #require(Photo(data: try cameraPhoto()))
        chat.attach(photo)
        chat.attach(photo)
        chat.draft = "The broken screen"
        await chat.send()

        #expect(chat.sendFailure == nil)
        #expect(chat.photos.isEmpty)
        #expect(chat.draft.isEmpty)
        let sent = try #require(chat.messages.last)
        #expect(sent.body == "The broken screen")
        #expect(sent.attachments.map(\.name) == ["Photo 1.jpg", "Photo 2.jpg"])
        #expect(sent.attachments.map(\.size) == Array(repeating: UInt64(photo.jpeg.count), count: 2))
        // The conversation shows the photos sent without fetching them back.
        #expect(sent.attachments.allSatisfy { chat.thumbnails[$0.path] != nil })

        // The next message's photos are numbered afresh.
        chat.attach(photo)
        #expect(chat.photos.map(\.upload.name) == ["Photo 1.jpg"])
    }

    @Test func aSentAttachmentsThumbnailIsFetchedFromTheHostOrNamedWhenUnreadable() async throws {
        let host = try await demoHost()
        let sender = ProjectChat(host: host, projectID: "demo-tide-alerts")
        sender.attach(try #require(Photo(data: try cameraPhoto(width: 600, height: 400))))
        await sender.send()
        let attachment = try #require(sender.messages.last?.attachments.first)

        // Opened afresh, the conversation has only the host's copy.
        let reader = ProjectChat(host: host, projectID: "demo-tide-alerts")
        await reader.loadThumbnail(of: attachment)
        #expect(reader.thumbnails[attachment.path] != nil)

        let missing = Attachment(path: "demo/attachments/gone/Photo 9.jpg", size: 1, image: "jpeg")
        await reader.loadThumbnail(of: missing)
        #expect(reader.thumbnails[missing.path] == nil)
        #expect(reader.unreadable.contains(missing.path))
    }

    @Test func aFailedUploadIsShownAndRetryResumesIt() async throws {
        let connection = RefusingConnection(refusing: 2)
        let chat = try await chat(on: connection)
        let photo = try #require(Photo(data: try noisyPhoto()))
        let pieces = (photo.jpeg.count + Upload.pieceLimit - 1) / Upload.pieceLimit
        #expect(pieces > 2)
        chat.attach(photo)
        await chat.send()

        #expect(chat.sendFailure == "Couldn't upload Photo 1.jpg: The disk is full")
        #expect(chat.photos.first?.upload.stored == Upload.pieceLimit)
        #expect(chat.messages.last?.attachments.isEmpty != false)

        await chat.send()
        #expect(chat.sendFailure == nil)
        #expect(chat.photos.isEmpty)
        #expect(chat.messages.last?.attachments.map(\.name) == ["Photo 1.jpg"])
        // Each piece stored once: the retry went on from the second.
        #expect(connection.offsets.withLock { $0 } == (0..<pieces).map { $0 * Upload.pieceLimit })
    }

    @Test func aRetryOfTheSameMessageReusesItsID() async throws {
        let connection = LosingConnection()
        let chat = try await chat(on: connection)
        chat.draft = "A"
        await chat.send()
        #expect(chat.sendFailure != nil)
        await chat.send()
        #expect(chat.sendFailure == nil)
        let ids = connection.sentIDs.withLock { $0 }
        #expect(ids.count == 2 && ids[0] == ids[1])
        #expect(chat.messages.filter { $0.body == "A" }.count == 1)
    }

    @Test func anEditedMessageAfterALostReplyGetsANewID() async throws {
        let connection = LosingConnection()
        let chat = try await chat(on: connection)
        chat.draft = "A"
        await chat.send()
        chat.draft = "B"
        await chat.send()
        #expect(chat.sendFailure == nil)
        let ids = connection.sentIDs.withLock { $0 }
        #expect(ids.count == 2 && ids[0] != ids[1])
        #expect(chat.messages.last?.body == "B")
    }

    @Test func viewOnlyHostsAndHostsWithoutUploadsHideThePlus() async throws {
        let connection = FakeConnection()
        let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { connection })
        let chat = ProjectChat(host: host, projectID: "p")
        let address = HostAddress(host: "studio.local")

        connection.yield(.connected(address: address, level: .control, capabilities: ["events"]))
        try await eventually { host.isConnected }
        #expect(!chat.canAttach)

        connection.yield(.connected(address: address, level: .viewOnly, capabilities: ["uploads"]))
        try await eventually { host.level == .viewOnly }
        #expect(!chat.canAttach)

        connection.yield(.connected(address: address, level: .control, capabilities: ["uploads"]))
        try await eventually { host.level == .control }
        #expect(chat.canAttach)
    }
}
