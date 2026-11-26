import Foundation
import Synchronization
import Testing
@testable import WiffletreeKit

struct UploadTests {
    private func json(_ value: some Encodable) throws -> NSDictionary {
        try JSONSerialization.jsonObject(with: HostJSON.encoder.encode(value)) as! NSDictionary
    }

    /// Bytes that differ piece to piece, so a piece out of place shows.
    private func file(_ count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 * 7) })
    }

    /// The host's side of `upload_attachment`: a piece is kept only where the upload ends.
    private final class FakeStore: Sendable {
        let held = Mutex(Data())
        let offsets = Mutex<[Int]>([])
        /// Answers each call with this when it returns an error, after the host stored the piece.
        let fail: @Sendable (_ call: Int) -> ConnectionError?

        init(fail: @escaping @Sendable (_ call: Int) -> ConnectionError? = { _ in nil }) {
            self.fail = fail
        }

        func store(_ piece: UploadAttachmentCommand) throws -> Uploaded {
            let call = offsets.withLock { $0.append(piece.offset); return $0.count }
            let stored = held.withLock { held in
                if piece.offset == held.count { held.append(Data(base64Encoded: piece.bytes)!) }
                return held.count
            }
            if let error = fail(call) { throw error }
            return Uploaded(uploadID: piece.uploadID, stored: stored)
        }

        func uploader() -> Uploader {
            Uploader(store: { try self.store($0) }, pause: .seconds(1), patience: .seconds(5), sleep: { _ in })
        }
    }

    @Test func aPieceAndASendWithUploadsAreHostShaped() throws {
        let piece = UploadAttachmentCommand(uploadID: "u1", name: "Photo 1.jpg", offset: 131_072, bytes: "AAEC")
        #expect(try json(RequestLine(version: 2, id: "r1", command: piece)) == [
            "version": 2, "id": "r1",
            "command": ["type": "upload_attachment", "upload_id": "u1", "name": "Photo 1.jpg", "offset": 131_072, "bytes": "AAEC"]
        ] as NSDictionary)
        let send = SendCommand(id: "m1", recipient: "c1", body: "See the photo", uploads: ["u1", "u2"])
        #expect(try json(RequestLine(version: 2, id: "r2", command: send)) == [
            "version": 2, "id": "r2",
            "command": ["type": "send", "id": "m1", "recipient": "c1", "body": "See the photo", "uploads": ["u1", "u2"]]
        ] as NSDictionary)
    }

    @Test func aSendWithoutUploadsLeavesTheFieldOut() throws {
        let send = SendCommand(id: "m1", recipient: "c1", body: "Hi")
        #expect(try json(send) == ["id": "m1", "recipient": "c1", "body": "Hi"] as NSDictionary)
    }

    @Test func theHostsAnswersDecode() throws {
        let uploaded = try HostJSON.decoder.decode(Uploaded.self, from: Data(#"{"upload_id":"u1","stored":131072}"#.utf8))
        #expect(uploaded == Uploaded(uploadID: "u1", stored: 131_072))
        let message = try HostJSON.decoder.decode(Message.self, from: Data(#"""
            {"sequence":9,"id":"m1","project_id":"p1","sender":null,"recipient":"c1","body":"See","receipt":"Delivered",
             "created_at":1,"attachments":[{"path":"/data/projects/p1/attachments/m1/Photo 1.jpg","size":2048,"image":"jpeg"},
             {"path":"/data/projects/p1/attachments/m1/notes.md","size":10,"image":null}]}
            """#.utf8))
        #expect(message.attachments.map(\.name) == ["Photo 1.jpg", "notes.md"])
        #expect(message.attachments.map(\.image) == ["jpeg", nil])
        let plain = try HostJSON.decoder.decode(Message.self, from: Data(#"""
            {"sequence":1,"id":"m2","project_id":"p1","sender":"c1","recipient":"c1","body":"Hi","receipt":"Delivered","created_at":1}
            """#.utf8))
        #expect(plain.attachments.isEmpty)
    }

    @Test func aFileGoesUpInPiecesOfAtMost128KiBAtTheirOffsets() async throws {
        let data = file(Upload.pieceLimit * 2 + 10)
        let host = FakeStore()
        let done = try await host.uploader().send(Upload(name: "Photo 1.jpg", data: data))
        #expect(done.isComplete)
        #expect(host.offsets.withLock { $0 } == [0, Upload.pieceLimit, Upload.pieceLimit * 2])
        #expect(host.held.withLock { $0 } == data)
    }

    @Test func aPieceWhoseAnswerIsLostGoesAgainAndIsStoredOnce() async throws {
        let data = file(Upload.pieceLimit * 3 + 1)
        // The second piece reaches the host, but the connection drops before its answer.
        let host = FakeStore(fail: { $0 == 2 ? .closed : nil })
        let fractions = Mutex<[Double]>([])
        let done = try await host.uploader().send(Upload(name: "a.jpg", data: data)) { upload in
            fractions.withLock { $0.append(upload.fraction) }
        }
        #expect(done.isComplete)
        #expect(host.held.withLock { $0 } == data, "each byte stored once, in order")
        // The lost piece went again at the same offset; the host's answer moved on past it.
        #expect(host.offsets.withLock { $0 } == [0, Upload.pieceLimit, Upload.pieceLimit, Upload.pieceLimit * 2, Upload.pieceLimit * 3])
        #expect(fractions.withLock { $0 }.last == 1)
    }

    @Test func aRefusalStopsTheUploadAndRetryResumesFromWhatTheHostHolds() async throws {
        let data = file(Upload.pieceLimit * 2 + 5)
        let refusing = FakeStore(fail: { $0 == 2 ? .commandFailed("The disk is full") : nil })
        let last = Mutex<Upload?>(nil)
        await #expect(throws: ConnectionError.commandFailed("The disk is full")) {
            try await refusing.uploader().send(Upload(id: "u1", name: "a.jpg", data: data)) { upload in
                last.withLock { $0 = upload }
            }
        }
        let resumed = try #require(last.withLock { $0 })
        #expect(resumed.stored == Upload.pieceLimit)

        let host = FakeStore()
        host.held.withLock { $0 = data.prefix(Upload.pieceLimit) }
        let done = try await host.uploader().send(resumed)
        #expect(done.isComplete)
        #expect(host.offsets.withLock { $0 } == [Upload.pieceLimit, Upload.pieceLimit * 2])
        #expect(host.held.withLock { $0 } == data)
    }

    @Test func aHostThatStaysAwayEndsTheUploadAfterItsPatience() async throws {
        let host = FakeStore(fail: { _ in .unreachable("No route to host") })
        await #expect(throws: ConnectionError.unreachable("No route to host")) {
            try await host.uploader().send(Upload(name: "a.jpg", data: file(10)))
        }
        // One try, then one more after each of the five one-second pauses.
        #expect(host.offsets.withLock { $0.count } == 6)
    }

    @Test func aFileOver50MBIsRefusedBeforeAnyPiece() async throws {
        let host = FakeStore()
        await #expect(throws: ConnectionError.self) {
            try await host.uploader().send(Upload(name: "big.mov", data: Data(count: Upload.sizeLimit + 1)))
        }
        #expect(host.offsets.withLock { $0 }.isEmpty)
    }

    @Test func theDemoKeepsUploadsAndAttachesThemToTheMessage() async throws {
        let demo = DemoHostConnection()
        defer { demo.close() }
        let data = Data([0xFF, 0xD8, 0xFF]) + file(Upload.pieceLimit + 100)
        let upload = try await Uploader(connection: demo).send(Upload(id: "u1", name: "Photo 1.jpg", data: data))
        #expect(upload.isComplete)
        let sent = try await demo.request(SendCommand(recipient: DemoID.tideCoordinator, body: "", uploads: [upload.id]))
        let attachment = try #require(sent.attachments.first)
        #expect(attachment.name == "Photo 1.jpg")
        #expect(attachment.size == UInt64(data.count))
        #expect(attachment.image == "jpeg")
        let contents = try await demo.request(ReadFileCommand(path: attachment.path, maxBytes: Upload.sizeLimit))
        #expect(contents.bytes == data)
        // A message used the upload, so another cannot.
        await #expect(throws: ConnectionError.self) {
            try await demo.request(SendCommand(recipient: DemoID.tideCoordinator, body: "Again", uploads: [upload.id]))
        }
    }
}
