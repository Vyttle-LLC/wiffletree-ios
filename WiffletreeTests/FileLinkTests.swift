import Foundation
import Testing
import WiffletreeKit
@testable import Wiffletree

@MainActor
private func eventually(_ condition: () -> Bool) async throws {
    for _ in 0..<200 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}

/// Station map's conversation on the demo, loaded.
@MainActor
private func stationMapChat(on connection: any HostConnection = DemoHostConnection()) async throws -> ProjectChat {
    let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { connection })
    try await eventually { host.snapshot != nil && host.isConnected }
    let chat = ProjectChat(host: host, projectID: "demo-station-map")
    await chat.reloadAll()
    return chat
}

/// The demo, saying every file it finds would run when opened.
private final class RunnableFiles: HostConnection {
    let demo = DemoHostConnection()

    var events: AsyncStream<HostEvent> { demo.events }
    var states: AsyncStream<ConnectionState> { demo.states }
    var isDemo: Bool { true }

    func request<Command: HostCommand>(_ command: Command) async throws -> Command.Reply {
        let reply = try await demo.request(command)
        guard let resolved = reply as? [ResolvedPath?] else { return reply }
        return resolved.map { $0.map { ResolvedPath(path: $0.path, runsWhenOpened: true) } } as! Command.Reply
    }

    func close() {
        demo.close()
    }
}

@MainActor
struct FileLinkTests {
    private let mockup = "/Users/demo/dev/tidepool/design/station-page.html"
    private let screenshot = "/Users/demo/dev/tidepool/design/station-map.png"

    private func linkingMessage(in chat: ProjectChat) throws -> Message {
        try #require(chat.messages.first { $0.body.contains("station-page.html") })
    }

    @Test func aMessagesFilesResolveIntoLinksAndItsImageIntoAThumbnail() async throws {
        let chat = try await stationMapChat()
        let message = try linkingMessage(in: chat)
        await chat.resolveFiles(of: message)

        let files = try #require(chat.fileLinks[message.id])
        // The relative screenshot resolves in the coordinator's checkout.
        #expect(files.markdown.contains("[station-page.html](<\(FileLinks.url(for: mockup).absoluteString)>)"))
        #expect(files.markdown.contains("[`design/station-map.png`](<\(FileLinks.url(for: screenshot).absoluteString)>)"))
        #expect(files.images == [screenshot])

        await chat.loadThumbnail(of: screenshot)
        #expect(chat.thumbnails[screenshot] != nil)
    }

    @Test func anOpenedFileIsATemporaryCopyThatGoesWhenClosed() async throws {
        let chat = try await stationMapChat()
        let copy = try await chat.copy(of: mockup)
        #expect(copy.lastPathComponent == "station-page.html")
        #expect(try String(contentsOf: copy, encoding: .utf8).contains("<html"))
        chat.removeCopy(copy)
        #expect(!FileManager.default.fileExists(atPath: copy.path))

        await #expect(throws: ConnectionError.self) { try await chat.copy(of: "/Users/demo/gone.md") }
    }

    @Test func aFileThatWouldRunStaysPlainText() async throws {
        let chat = try await stationMapChat(on: RunnableFiles())
        let message = try linkingMessage(in: chat)
        await chat.resolveFiles(of: message)

        let files = try #require(chat.fileLinks[message.id])
        #expect(!files.markdown.contains(FileLinks.scheme))
        #expect(files.markdown.contains("this layout: station-page.html."))
        #expect(files.images.isEmpty)
    }
}
