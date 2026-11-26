import Foundation
import Testing
@testable import WiffletreeKit

struct FramingTests {
    private func json(_ value: some Encodable) throws -> NSDictionary {
        try JSONSerialization.jsonObject(with: HostJSON.encoder.encode(value)) as! NSDictionary
    }

    @Test func aRequestCarriesItsCommandsFieldsBesideItsType() throws {
        let line = RequestLine(version: 2, id: "r1", command: MessagesCommand(sessionId: "c1", limit: 20))
        #expect(try json(line) == [
            "version": 2, "id": "r1",
            "command": ["type": "messages", "session_id": "c1", "limit": 20]
        ] as NSDictionary)
        #expect(try json(RequestLine(version: 2, id: "r2", command: SnapshotCommand())) == [
            "version": 2, "id": "r2", "command": ["type": "snapshot"]
        ] as NSDictionary)
    }

    @Test func helloNamesTheProtocolAndNoCredential() throws {
        let hello = try json(HelloLine(appVersion: "1.0"))["hello"] as! NSDictionary
        #expect(hello["protocols"] as? [Int] == [2, 2])
        #expect(hello["app_version"] as? String == "1.0")
        #expect(hello["credential"] == nil)
    }

    @Test func eventsDecodeTheirKindAndTolerateNewOnes() throws {
        func event(_ text: String) throws -> HostEvent {
            try HostJSON.decoder.decode(InboundFrame.self, from: Data(text.utf8)).event!
        }
        #expect(try event(#"{"event":{"cursor":{"epoch":"e","seq":42},"kind":"steps","sessions":["s1"]}}"#)
            == HostEvent(cursor: Cursor(epoch: "e", seq: 42), kind: .steps(sessions: ["s1"])))
        #expect(try event(#"{"event":{"cursor":{"epoch":"e","seq":43},"kind":"attention","count":2}}"#).kind == .attention(count: 2))
        #expect(try event(#"{"event":{"cursor":{"epoch":"e","seq":44},"kind":"weather","rain":true}}"#).kind == .unknown("weather"))
    }

    @Test func theChallengeVerdictIsAnObjectOrAWord() throws {
        let decode = { (text: String) in try JSONDecoder().decode(ChallengeVerdict.self, from: Data(text.utf8)) }
        #expect(try decode(#"{"accepted":{"level":"view_only"}}"#) == .accepted(.viewOnly))
        #expect(try decode(#""unpaired""#) == .unpaired)
    }

    @Test func aSnapshotToleratesFieldsAndStatesItDoesNotKnow() throws {
        let data = try JSONSerialization.data(withJSONObject: ["result": FakeHost.snapshot])
        let snapshot = try #require(try HostJSON.decoder.decode(ResultBox<Snapshot>.self, from: data).result)
        #expect(snapshot.projects.map(\.name) == ["iOS app"])
        #expect(snapshot.sessions.first?.role == .projectOrchestrator)
        #expect(snapshot.attention.first?.options == ["Yes", "No"])
        #expect(snapshot.tickets.first?.state.rawValue == "a_state_from_the_future")
        #expect(snapshot.tickets.first?.pullRequest?.checks == .success)
    }
}
