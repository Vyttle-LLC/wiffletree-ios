import Foundation
import Testing
@testable import WiffletreeKit

struct ProtectedBranchTests {
    /// A repository and a ticket merging into `base`, as the host's snapshot has them.
    private func snapshot(base: String, repository: String) throws -> Snapshot {
        let text = #"""
        {"projects":[],"sessions":[],"attention":[],"repositories":[\#(repository)],
         "tickets":[{"id":"t1","coordinator_id":"c1","repository_id":"r1","title":"Retry","brief":"…","worktree":"/w",
          "branch":"wiffletree/retry","state":"accepted",
          "merging":{"id":"m1","caller":"c1","repository":"o/r","number":212,"branch":"wiffletree/retry",
           "base":"\#(base)","head":"abc","cycle":1,"stage":{"kind":"waiting_for_human","item":"a1"}}}]}
        """#
        return try HostJSON.decoder.decode(Snapshot.self, from: Data(text.utf8))
    }

    private let repository = #"""
    {"id":"r1","name":"tidepool","path":"/r","base":"origin/main","protected_branches":["release/*"],
     "github":{"owner":"o","name":"r","facts":{"name_with_owner":"o/r","branches":{"default_branch":"trunk",
      "rulesets":[{"name":"Stable","include":["refs/heads/stable/**"],"exclude":["stable/scratch/*"]}],
      "protection_rules":["hotfix-?"]}}}}
    """#

    @Test func aMergeRequestNamesItsInboxItemAndBase() throws {
        let merging = try #require(try snapshot(base: "feature/sync", repository: repository).tickets.first?.merging)
        #expect(merging.stage.kind == .waitingForHuman)
        #expect(merging.stage.item == "a1")
        #expect(merging.base == "feature/sync")
    }

    @Test(arguments: [
        ("main", true), ("trunk", true), ("release/1.2", true), ("release/1.2/fix", false),
        ("stable/a/b", true), ("stable/scratch/x", false), ("hotfix-1", true), ("hotfix-12", false),
        ("feature/sync", false),
    ])
    func protectionFollowsTheHostsRules(base: String, isProtected: Bool) throws {
        let snapshot = try snapshot(base: base, repository: repository)
        #expect(snapshot.mergesIntoProtectedBranch(snapshot.tickets[0]) == isProtected)
    }

    @Test func aTicketInAnUnlistedRepositoryCountsAsProtected() throws {
        let snapshot = try snapshot(base: "feature/sync", repository: #"{"id":"r2","name":"other","path":"/o","base":"origin/main"}"#)
        #expect(snapshot.mergesIntoProtectedBranch(snapshot.tickets[0]))
    }

    @Test func aQuotaWindowKeepsWhenItWasReadAndItsLength() throws {
        let text = #"""
        [{"provider":"claude","account":null,"observed_at":10,"source":"statusline","error":null,
          "windows":[{"key":"five_hour","label":"5 hours","used_percent":null,"observed_at":9,"duration_mins":300,
           "resets_at":null,"status":null}]}]
        """#
        let window = try #require(try HostJSON.decoder.decode([QuotaReading].self, from: Data(text.utf8)).first?.windows.first)
        #expect(window.usedPercent == nil)
        #expect(window.observedAt == 9)
        #expect(window.durationMinutes == 300)
    }
}
