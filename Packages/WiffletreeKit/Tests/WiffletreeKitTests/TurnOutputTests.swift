import Foundation
import Testing
@testable import WiffletreeKit

struct TurnOutputTests {
    private func decode<Value: Decodable>(_ type: Value.Type, _ text: String) throws -> Value {
        try HostJSON.decoder.decode(type, from: Data(text.utf8))
    }

    @Test func aStepsRequestNamesTheSessionRunAndRevision() throws {
        let line = RequestLine(version: 2, id: "r1", command: StepsCommand(sessionID: "c1", after: 7))
        let object = try JSONSerialization.jsonObject(with: HostJSON.encoder.encode(line)) as! [String: Any]
        let command = try #require(object["command"] as? [String: Any])
        #expect(command["type"] as? String == "steps")
        #expect(command["session_id"] as? String == "c1")
        #expect(command["after"] as? Int == 7)
        #expect(command.keys.contains("run_id") == false)
    }

    /// A `StepPage` as `workspace-core` serialises it, with fields and kinds this client ignores.
    @Test func aStepPageDecodesAsTheHostWritesIt() throws {
        let page = try decode(StepPage.self, #"""
        {"run_id":"run-9","running":true,"started_at":1795000000000,"finished_at":null,"revision":42,"omitted_steps":0,
         "steps":[
          {"run_id":"run-9","id":"text-2","kind":"narration","state":"running","title":"Second, still going",
           "detail":"Second, still going.\n\n- **one**","omitted":0,"seq":3,"revision":42,"started_at":1795000000300,"finished_at":null},
          {"run_id":"run-9","id":"tool-1","kind":"command","state":"succeeded","title":"swift test","note":"exit 0",
           "paths":[],"omitted":0,"seq":2,"revision":40,"started_at":1795000000200,"finished_at":1795000000250},
          {"run_id":"run-9","id":"text-1","kind":"narration","state":"succeeded","title":"First","omitted":0,"seq":1,
           "revision":39,"started_at":1795000000100,"finished_at":1795000000150},
          {"run_id":"run-9","id":"x","kind":"telepathy","state":"pondering","title":"?","omitted":0,"seq":4,"revision":41,
           "started_at":1795000000400}
         ]}
        """#)
        #expect(page.runID == "run-9")
        #expect(page.running)
        #expect(page.revision == 42)
        #expect(page.steps.count == 4)
        #expect(page.narration.map(\.id) == ["text-1", "text-2"])
        #expect(page.narration.map(\.text) == ["First", "Second, still going.\n\n- **one**"])
        #expect(page.steps.last?.kind == Step.Kind(rawValue: "telepathy"))
    }

    @Test func aNewerPageUpdatesTheStepsItChangedAndAddsNewOnes() {
        func step(_ id: String, _ state: Step.State, seq: UInt32, revision: UInt64, run: String = "r1") -> Step {
            Step(id: id, runID: run, kind: .narration, state: state, title: id, detail: nil, seq: seq, revision: revision)
        }
        let page = StepPage(runID: "r1", running: true, revision: 3, steps: [
            step("a", .succeeded, seq: 1, revision: 1), step("b", .running, seq: 2, revision: 3),
        ])
        let merged = page.merging(StepPage(runID: "r1", running: false, revision: 5, steps: [
            step("b", .succeeded, seq: 2, revision: 5), step("c", .succeeded, seq: 3, revision: 4),
        ]))
        #expect(merged.steps.map(\.id) == ["a", "b", "c"])
        #expect(merged.steps.map(\.state) == [.succeeded, .succeeded, .succeeded])
        #expect(merged.revision == 5)
        #expect(!merged.running)

        let unchanged = page.merging(StepPage(runID: "r1", running: true, revision: 3, steps: []))
        #expect(unchanged.steps.map(\.id) == ["a", "b"])
        #expect(unchanged.revision == 3)

        let nextRun = page.merging(StepPage(runID: "r2", running: true, revision: 6, steps: [step("x", .running, seq: 1, revision: 6, run: "r2")]))
        #expect(nextRun.runID == "r2")
        #expect(nextRun.steps.map(\.id) == ["x"])
    }

    @Test func aSessionThatNeverRanHasAnEmptyPage() throws {
        let page = try decode(StepPage.self, #"{"run_id":null,"running":false,"started_at":null,"finished_at":null,"revision":0,"steps":[],"omitted_steps":0}"#)
        #expect(page.runID == nil)
        #expect(page.narration.isEmpty)
    }

    @Test func aConversationsMessagesAreToldApartAsTheDesktopDoes() throws {
        func message(_ id: String, sender: String?) throws -> Message {
            let sender = sender.map { #""\#($0)""# } ?? "null"
            return try decode(Message.self, #"""
            {"sequence":1,"id":"\#(id)","project_id":"p","sender":\#(sender),"recipient":"c1","body":"…","receipt":"completed","created_at":0}
            """#)
        }
        let reply = try message("output:run-9", sender: "c1")
        #expect(reply.kind == .reply)
        #expect(reply.runID == "run-9")
        #expect(try message("2f1c-uuid", sender: nil).kind == .human)
        #expect(try message("verification:t1:2", sender: nil).kind == .notice)
        #expect(try message("pr:t1:merged", sender: nil).kind == .notice)
        #expect(try message("timer:c1:1", sender: "c1").kind == .notice)
        #expect(try message("compaction:run-3", sender: "c1").kind == .notice)
        #expect(try message("m-7", sender: "implementer").kind == .agent)
        #expect(try message("m-7", sender: "implementer").runID == nil)
    }

    @Test func anApprovalIsToldByItsOperationIDsPrefix() {
        func item(_ operationID: String) -> Attention {
            Attention(id: "a", projectID: "p", sessionID: "c", operationID: operationID, prompt: "?")
        }
        #expect(item("repository:req-1").approval == .repository)
        #expect(item("repository:req-1").isApproval)
        #expect(item("publish:t1:pull_request").approval == .publish)
        #expect(item("merge:m1").approval == .merge)
        #expect(item("permission:p1").approval == .permission)
        #expect(item("retarget:r1").approval == .retarget)
        #expect(item("map-tiles").approval == nil)
        #expect(item("repositories-to-add").approval == nil)
    }

    @Test func aSnapshotCarriesSpacesRuntimesAndArchivedAgents() throws {
        let snapshot = try decode(Snapshot.self, #"""
        {"projects":[{"id":"p1","name":"Tide alerts","space":"s1","added_repositories":[]}],
         "spaces":[{"id":"s1","name":"Vyttle","created_at":0}],
         "repositories":[{"id":"r1","name":"tidepool","path":"/r","base":"main","github":{"owner":"Vyttle-LLC","name":"tidepool"},
          "protected_branches":[]}],
         "sessions":[{"id":"c1","project_id":"p1","parent_id":null,"repository_id":null,"name":"Tide alerts",
          "role":"project_orchestrator","provider":"claude","status":"ready","archived":false},
          {"id":"i1","project_id":"p1","parent_id":"c1","name":"Implementer","role":"implementer","provider":"claude",
           "status":"done","archived":true}],
         "runtimes":[{"session_id":"i1","provider_session_id":null,"ticket_id":"t1",
          "profile":{"provider":"claude","model":"opus","effort":"high"},"held":false}],
         "attention":[],
         "tickets":[{"id":"t1","coordinator_id":"c1","repository_id":"r1","title":"Retry","brief":"…","worktree":"/w",
          "branch":"b","state":"accepted"}]}
        """#)
        #expect(snapshot.projects.first?.space == "s1")
        #expect(snapshot.spaces.first?.name == "Vyttle")
        #expect(snapshot.sessions.map(\.archived) == [false, true])
        #expect(snapshot.runtimes.first?.ticketID == "t1")
        #expect(snapshot.runtimes.first?.profile?.model == "opus")
    }
}
