import Foundation
import Testing
@testable import WiffletreeKit

struct FramingTests {
    private func json(_ value: some Encodable) throws -> NSDictionary {
        try JSONSerialization.jsonObject(with: HostJSON.encoder.encode(value)) as! NSDictionary
    }

    @Test func aRequestCarriesItsCommandsFieldsBesideItsType() throws {
        let line = RequestLine(version: 2, id: "r1", command: MessagesCommand(sessionID: "c1", limit: 20))
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
        #expect(snapshot.sessions.first?.projectID == "p1")
        #expect(snapshot.attention.first?.sessionID == "c1")
        #expect(snapshot.tickets.first?.coordinatorID == "c1")
        #expect(snapshot.attention.first?.options == ["Yes", "No"])
        #expect(snapshot.tickets.first?.state.rawValue == "a_state_from_the_future")
        #expect(snapshot.tickets.first?.pullRequest?.checks == .success)
        #expect(snapshot.tickets.first?.verification == nil)
        #expect(snapshot.tickets.first?.ledger.isEmpty == true)
    }

    @Test func aTicketCarriesItsReviewCyclesAndFindings() throws {
        let text = #"""
        {"id":"t1","coordinator_id":"c1","title":"Alert","brief":"…","worktree":"/w","branch":"b","state":"verifying",
         "verification":{"cycle":2,"level":{"name":"Full","kind":"full_review"},"max_rounds":3,"outcome":"running",
          "rounds":[{"round":1,"commit":"8be41a9","verifiers":[{"session_id":"v1","role":"reviewer","focus":"Correctness",
           "message_id":"m1","result":"failed","report_id":"m2"}]}],"small":false},
         "previous_cycles":[{"cycle":1,"max_rounds":3,"outcome":"blocked","rounds":[]}],
         "ledger":[{"id":"F1","severity":"blocking","location":"src/alert.rs:88","summary":"Fires twice","trigger":"two thresholds",
          "evidence":"…","focus":"Correctness","cycle":2,"round":1,"status":"open"}]}
        """#
        let ticket = try HostJSON.decoder.decode(Ticket.self, from: Data(text.utf8))
        let round = try #require(ticket.verification?.rounds.first)
        #expect(ticket.verification?.level?.kind == .fullReview)
        #expect(ticket.verification?.outcome == .running)
        #expect(round.verifiers.first?.result == .failed)
        #expect(ticket.previousCycles.first?.level == nil)
        #expect(ticket.ledger.first?.severity == .blocking)
        #expect(ticket.ledger.first?.status == .open)
    }
}
