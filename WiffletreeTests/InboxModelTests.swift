import Foundation
import Testing
import WiffletreeKit
@testable import Wiffletree

/// The demo host with replies at once, as a live host the Inbox reads.
@MainActor
private func demoHost() async throws -> LiveHost {
    var options = DemoHostConnection.Options()
    options.sleep = { _ in }
    let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { DemoHostConnection(options: options) })
    try await eventually { host.snapshot != nil }
    return host
}

/// Waits for the main actor to apply what a connection sent.
@MainActor
private func eventually(_ condition: () -> Bool) async throws {
    for _ in 0..<200 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}

private let mapTiles = "demo-attention-map-tiles"
private let publish = "demo-attention-publish-thresholds"
private let merge = "demo-attention-merge-212"

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct InboxModelTests {
    private func item(_ id: String, in model: InboxModel) throws -> InboxItem {
        try #require(model.open.first { $0.id == id })
    }

    @Test func theDemoInboxListsItsOpenItemsNewestFirstWithTheirKinds() async throws {
        let model = InboxModel(host: try await demoHost())
        #expect(model.open.map(\.id) == [mapTiles, publish, merge])
        #expect(model.host.openAttentionCount == 3)
        #expect(try item(mapTiles, in: model).isQuestion)
        #expect(try item(mapTiles, in: model).title == "Which map tiles should the station page use?")
        #expect(try item(mapTiles, in: model).kindTitle == "Coordinator")
        #expect(try item(publish, in: model).kind == .publish)
        #expect(try item(merge, in: model).kind == .merge(isProtected: false, pullRequestURL: URL(string: "https://github.com/Vyttle-LLC/tidepool/pull/212")))
        #expect(try item(merge, in: model).approveTitle == "Merge")
        // The seed's decided items, decided before this iPhone saw them.
        #expect(model.history.map(\.outcome) == [.answered("Not in this project"), .dismissed, .answered("Keep it for a release")])
        #expect(model.history.allSatisfy { $0.at == nil })
    }

    @Test func answeringAQuestionMovesItToAnsweredAndLowersTheBadge() async throws {
        let model = InboxModel(host: try await demoHost())
        await model.answer(try item(mapTiles, in: model), with: "OpenStreetMap")
        #expect(model.open.map(\.id) == [publish, merge])
        #expect(model.history.first?.outcome == .chose("OpenStreetMap"))
        #expect(model.history.first?.summary.hasPrefix("Station map · you chose OpenStreetMap · ") == true)
        try await eventually { model.host.openAttentionCount == 2 }
        #expect(model.history.count { $0.id == mapTiles } == 1)
    }

    @Test func approvingAPublishOpensItsPullRequest() async throws {
        let model = InboxModel(host: try await demoHost())
        await model.approve(try item(publish, in: model))
        #expect(model.history.first?.outcome == .approved)
        try await eventually { model.host.snapshot?.tickets.contains { $0.pullRequest?.number == 214 } == true }
        #expect(model.host.openAttentionCount == 2)
    }

    @Test func denyingAPublishOpensNoPullRequest() async throws {
        let model = InboxModel(host: try await demoHost())
        await model.deny(try item(publish, in: model))
        #expect(model.history.first?.outcome == .denied)
        try await eventually { model.host.openAttentionCount == 2 }
        #expect(model.host.snapshot?.tickets.first { $0.id == "demo-ticket-thresholds" }?.pullRequest == nil)
    }

    @Test func startingTheDemoOverReopensWhatWasDecided() async throws {
        let model = InboxModel(host: try await demoHost())
        await model.approve(try item(publish, in: model))
        try await eventually { model.host.openAttentionCount == 2 }

        model.host.restart()
        try await eventually { model.host.snapshot != nil && model.open.count == 3 }
        #expect(model.open.map(\.id) == [mapTiles, publish, merge])
        #expect(model.open.count == model.host.openAttentionCount)
        #expect(!model.history.contains { $0.id == publish })
    }

    @Test func dismissingAQuestionClearsIt() async throws {
        let model = InboxModel(host: try await demoHost())
        await model.dismiss(try item(mapTiles, in: model))
        #expect(model.history.first?.outcome == .dismissed)
        #expect(model.history.first?.summary.contains("dismissed, not answered") == true)
        try await eventually { model.host.openAttentionCount == 2 }
    }

    @Test func dismissingAnApprovalIsRefusedOnItsCard() async throws {
        let model = InboxModel(host: try await demoHost())
        await model.dismiss(try item(publish, in: model))
        #expect(model.errors[publish] == "Approve or deny a permission request")
        #expect(model.open.map(\.id) == [mapTiles, publish, merge])
        #expect(!model.history.contains { $0.id == publish })
        #expect(model.host.openAttentionCount == 3)
    }

    @Test func aStaleAnswerShowsTheHostsErrorOnTheCard() async throws {
        let model = InboxModel(host: try await demoHost())
        let question = try item(mapTiles, in: model)
        _ = try await model.host.connection.request(ResolveAttentionCommand(id: mapTiles, answer: "Apple Maps"))
        await model.answer(question, with: "OpenStreetMap")
        #expect(model.errors[mapTiles] == "Request already resolved; stale answer rejected")
        // The answer from elsewhere lands in the history once the snapshot shows it.
        try await eventually { model.history.first?.outcome == .answered("Apple Maps") }
        #expect(model.history.first?.at != nil)
    }

    @Test func anItemThatLeavesTheInboxWasAnsweredOnTheMac() async throws {
        let connection = FakeConnection(snapshot: .with(open: 2))
        let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { connection })
        connection.yield(.connected(address: HostAddress(host: "studio.local"), level: .control))
        try await eventually { host.snapshot != nil }
        let model = InboxModel(host: host)
        #expect(model.open.map(\.id) == ["a1", "a0"])

        connection.set(.with(open: 1))
        connection.yield(.attention(count: 1))
        try await eventually { model.history.first?.outcome == .elsewhere }
        #expect(model.history.first?.id == "a1")
        #expect(model.history.first?.summary.contains("answered on the Mac") == true)
        #expect(model.open.map(\.id) == ["a0"])
    }

    @Test func aMergeIntoAProtectedBranchOpensGitHub() throws {
        let json = #"""
        {"projects": [{"id": "p", "name": "Tide alerts"}], "sessions": [],
         "attention": [{"id": "m", "projectId": "p", "sessionId": "c", "operationId": "merge:r1", "prompt": "Merge #9 into main?"}],
         "repositories": [{"id": "r", "name": "tidepool", "base": "origin/main"}],
         "tickets": [{"id": "t", "coordinatorId": "c", "repositoryId": "r", "title": "T", "brief": "…", "branch": "b", "state": "accepted",
          "pullRequest": {"number": 9, "url": "https://github.com/o/r/pull/9", "state": "open", "draft": false, "base": "main",
           "mergeState": "clean", "checks": "success"},
          "merging": {"number": 9, "base": "main", "stage": {"kind": "waiting_for_human", "item": "m"}}}]}
        """#
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        let item = InboxItem(snapshot.attention[0], in: snapshot)
        #expect(item.kind == .merge(isProtected: true, pullRequestURL: URL(string: "https://github.com/o/r/pull/9")))
        #expect(!item.canDismiss)
    }

    @Test func onlyQuestionsOfferDismissAndAStartCardIsNotOne() throws {
        let json = #"""
        {"projects": [{"id": "p", "name": "Station map"}], "sessions": [],
         "attention": [
          {"id": "q", "projectId": "p", "sessionId": "c", "operationId": "map-tiles", "prompt": "Which tiles?"},
          {"id": "allow", "projectId": "p", "sessionId": "c", "operationId": "evaluation:allow:p:", "prompt": "Allow UI evaluators?"},
          {"id": "start", "projectId": "p", "sessionId": "c", "operationId": "evaluation:start:r1", "prompt": "Start the run?",
           "options": ["Start now", "Later", "Skip these runs"]},
          {"id": "perm", "projectId": "p", "sessionId": "c", "operationId": "permission:x", "prompt": "Allow?"}]}
        """#
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        let dismissable = snapshot.attention.map { InboxItem($0, in: snapshot) }.filter(\.canDismiss).map(\.id)
        #expect(dismissable == ["q", "allow"])
    }
}
