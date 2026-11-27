import Foundation
import Testing
@testable import WiffletreeKit

struct TicketTableTests {
    private func ticket(
        _ id: String = "t", state: Ticket.State, pullRequest: PullRequest.State? = nil, draft: Bool = false,
        verification: Verification? = nil, publishWaits: String? = nil, mergeWaits: String? = nil
    ) -> Ticket {
        Ticket(
            id: id, coordinatorID: "c1", title: id, brief: "", branch: "b", state: state, verification: verification,
            pullRequest: pullRequest.map {
                PullRequest(number: 212, url: "https://github.com/o/r/pull/212", state: $0, draft: draft, base: "main", mergeState: "clean", checks: .none)
            },
            publishing: publishWaits.map { PublishRequest(waiting: $0) },
            merging: mergeWaits.map { MergeRequest(number: 212, base: "main", stage: .init(kind: .waitingForHuman, item: $0)) }
        )
    }

    private func cycle(_ outcome: Verification.Outcome, rounds: Int) -> Verification {
        Verification(
            cycle: 1, level: nil, maxRounds: 3, outcome: outcome,
            rounds: (1...max(rounds, 1)).prefix(rounds).map { VerificationRound(round: $0, commit: "c", verifiers: []) }
        )
    }

    @Test func publishingDecodesTheInboxItemItWaitsOn() throws {
        let text = #"""
        {"projects":[],"sessions":[],"attention":[],"tickets_owned":{"c1":7},
         "tickets":[{"id":"t1","coordinator_id":"c1","title":"Retry","brief":"…","branch":"b","state":"accepted",
          "publishing":{"id":"p1","caller":"c1","repository":"o/r","push_url":"u","branch":"b","base":"main",
           "commit":"abc","cycle":1,"outcome":"passed","size":"1 commit","step":"pull_request","waiting":"a1","approvals":0}},
          {"id":"t2","coordinator_id":"c1","title":"Log","brief":"…","branch":"c","state":"verifying"}]}
        """#
        let snapshot = try HostJSON.decoder.decode(Snapshot.self, from: Data(text.utf8))
        #expect(snapshot.tickets[0].publishing?.waiting == "a1")
        #expect(snapshot.tickets[1].publishing == nil)
        #expect(snapshot.ticketsOwned == ["c1": 7])
    }

    @Test(arguments: [
        (Ticket.State.planned, "Planned", Ticket.StatusRole.subtle),
        (.assigned, "Assigned", .focus),
        (.readyForTesting, "Ready for testing", .focus),
        (.verifying, "Verifying", .subtle),
        (.passed, "Passed", .green),
        (.failed, "Failed", .red),
        (.blocked, "Blocked", .red),
        (.completed, "Completed", .focus),
        (.accepted, "Accepted", .green),
        (.closed, "Closed", .subtle),
        (Ticket.State(rawValue: "on_hold"), "On hold", .subtle),
    ])
    func statusWordsAndColoursAreTheDesktops(state: Ticket.State, word: String, role: Ticket.StatusRole) {
        let ticket = ticket(state: state)
        #expect(ticket.statusWord == word)
        #expect(ticket.statusRole == role)
    }

    @Test func aRunningCycleAddsItsRound() {
        #expect(ticket(state: .verifying, verification: cycle(.running, rounds: 2)).statusWord == "Verifying · round 2")
        #expect(ticket(state: .verifying, verification: cycle(.running, rounds: 0)).statusWord == "Verifying")
        #expect(ticket(state: .passed, verification: cycle(.passed, rounds: 2)).statusWord == "Passed")
    }

    @Test func thePullRequestReadsItsNumberAndState() {
        #expect(ticket(state: .accepted).pullRequestLabel == "Not published")
        #expect(ticket(state: .accepted, pullRequest: .open).pullRequestLabel == "#212 open")
        #expect(ticket(state: .assigned, pullRequest: .open, draft: true).pullRequestLabel == "#212 draft")
        #expect(ticket(state: .accepted, pullRequest: .merged).pullRequestLabel == "#212 merged")
        #expect(ticket(state: .closed, pullRequest: .closed).pullRequestLabel == "#212 closed")
    }

    @Test func plannedTicketsWaitUntilWorkStartsAndSettledOnesAreDone() {
        let table = TicketTable(tickets: [
            ticket("planned", state: .planned),
            ticket("planned-open", state: .planned, pullRequest: .open),
            ticket("planned-merged", state: .planned, pullRequest: .merged),
            ticket("verifying", state: .verifying, pullRequest: .open),
            ticket("accepted-open", state: .accepted, pullRequest: .open),
            ticket("closed", state: .closed),
        ], owned: nil, openItems: [])
        #expect(table.inProgress.map(\.id) == ["planned-open", "verifying"])
        #expect(table.done.map(\.id) == ["accepted-open", "closed"])
        #expect(table.doneCount == 2)
    }

    @Test func doneCountsTheTicketsOnlyInTheArchive() {
        let tickets = [ticket("a", state: .assigned), ticket("p", state: .planned), ticket("d", state: .accepted)]
        #expect(TicketTable(tickets: tickets, owned: 7, openItems: []).doneCount == 5)
        #expect(TicketTable(tickets: tickets, owned: 1, openItems: []).doneCount == 1)
    }

    @Test func theSummaryUsesTheDesktopsForms() {
        let open = ticket("a", state: .assigned)
        let done = ticket("d", state: .accepted)
        #expect(TicketTable(tickets: [open, done], owned: nil, openItems: []).summary == "1 in progress, 1 done")
        #expect(TicketTable(tickets: [open], owned: nil, openItems: []).summary == "1 in progress")
        #expect(TicketTable(tickets: [done], owned: 4, openItems: []).summary == "4 done")
        #expect(TicketTable(tickets: [ticket(state: .planned)], owned: 1, openItems: []).isEmpty)
    }

    @Test func aWaitingPublishOrMergeNeedsYouUntilItsItemIsAnswered() {
        let tickets = [
            ticket("publish", state: .accepted, publishWaits: "a1"),
            ticket("merge", state: .accepted, pullRequest: .open, mergeWaits: "a2"),
            ticket("resolved", state: .passed, publishWaits: "a3"),
            ticket("quiet", state: .assigned),
        ]
        let table = TicketTable(tickets: tickets, owned: nil, openItems: ["a1", "a2"])
        #expect(table.needingYou == ["publish", "merge"])
        #expect(table.doneNeedingYou == 2)
    }
}
