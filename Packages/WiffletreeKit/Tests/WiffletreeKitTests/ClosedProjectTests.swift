import Foundation
import Testing
@testable import WiffletreeKit

struct ClosedProjectTests {
    /// "open" has an unarchived coordinator. "closed" has none in `sessions`, as the host leaves an
    /// archived coordinator out, yet still reports its open item and an archived agent of its open
    /// ticket. "stale" has a coordinator that is archived and still shown.
    private let snapshot: Snapshot = {
        let json = #"""
        {"projects":[{"id":"open","name":"Open"},{"id":"closed","name":"Closed"},{"id":"stale","name":"Stale"}],
         "sessions":[
          {"id":"c-open","project_id":"open","name":"Open","role":"project_orchestrator","provider":"claude","status":"ready"},
          {"id":"w-open","project_id":"open","parent_id":"c-open","name":"Implementer","role":"implementer","provider":"claude","status":"working"},
          {"id":"w-closed","project_id":"closed","parent_id":"c-closed","name":"Implementer","role":"implementer","provider":"claude","status":"working","archived":true},
          {"id":"c-stale","project_id":"stale","name":"Stale","role":"project_orchestrator","provider":"claude","status":"working","archived":true}],
         "attention":[
          {"id":"a-open","project_id":"open","session_id":"c-open","operation_id":"question:1","prompt":"Which?"},
          {"id":"a-closed","project_id":"closed","session_id":"c-closed","operation_id":"question:2","prompt":"Which?"}],
         "tickets":[]}
        """#
        return try! HostJSON.decoder.decode(Snapshot.self, from: Data(json.utf8))
    }()

    @Test func aProjectIsOpenWhileItHasAnUnarchivedCoordinator() {
        #expect(snapshot.openProjects.map(\.id) == ["open"])
    }

    @Test func closedProjectsLoseTheirSessionsAndInboxItems() {
        let open = snapshot.withoutClosedProjects()
        #expect(open.projects.map(\.id) == ["open"])
        #expect(open.sessions.map(\.id) == ["c-open", "w-open"])
        #expect(open.attention.map(\.id) == ["a-open"])
    }
}
