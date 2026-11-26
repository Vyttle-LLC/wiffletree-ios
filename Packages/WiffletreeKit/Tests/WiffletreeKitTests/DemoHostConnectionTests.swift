import Foundation
import Testing
@testable import WiffletreeKit

@Suite(.timeLimit(.minutes(1)))
struct DemoHostConnectionTests {
    private static let now = Date(timeIntervalSince1970: 1_795_000_000)

    /// A demo whose replies come at once, at a fixed time.
    private let demo: DemoHostConnection = {
        var options = DemoHostConnection.Options()
        options.now = { now }
        options.sleep = { _ in }
        return DemoHostConnection(options: options)
    }()

    private func snapshot() async throws -> Snapshot {
        try await demo.request(SnapshotCommand())
    }

    private func openCount(_ snapshot: Snapshot, in projectID: String? = nil) -> Int {
        snapshot.attention.count { $0.answer == nil && (projectID == nil || $0.projectID == projectID) }
    }

    private func ticket(_ id: String) async throws -> Ticket {
        try #require(try await snapshot().tickets.first { $0.id == id })
    }

    private func next(_ count: Int, of events: AsyncStream<HostEvent>) async -> [HostEvent] {
        var iterator = events.makeAsyncIterator()
        var received: [HostEvent] = []
        while received.count < count, let event = await iterator.next() { received.append(event) }
        return received
    }

    @Test func theSeedTellsTheMockupsStory() async throws {
        let snapshot = try await snapshot()
        let projectIDs = Set(snapshot.projects.map(\.id))
        let coordinators = Set(snapshot.sessions.filter { $0.role == .projectOrchestrator }.map(\.id))
        #expect(snapshot.projects.map(\.name) == ["Tide alerts", "Station map", "Flaky sync test", "Legacy importer"])
        #expect(snapshot.openProjects.map(\.name) == ["Tide alerts", "Station map", "Flaky sync test"])
        #expect(snapshot.sessions.count { $0.status == .working } == 4)
        #expect(snapshot.sessions.allSatisfy { projectIDs.contains($0.projectID) })
        #expect(snapshot.attention.allSatisfy { projectIDs.contains($0.projectID) && coordinators.contains($0.sessionID) })
        #expect(snapshot.tickets.allSatisfy { coordinators.contains($0.coordinatorID) })
        #expect(snapshot.tickets.contains { $0.verification?.outcome == .running && !$0.ledger.isEmpty })
        #expect(snapshot.tickets.contains { $0.pullRequest?.number == 212 })

        let conversation = try await demo.request(MessagesCommand(sessionID: DemoID.tideCoordinator))
        #expect(conversation.map(\.sequence) == conversation.map(\.sequence).sorted())
        #expect(conversation.allSatisfy { $0.createdAt < Int64(Self.now.timeIntervalSince1970 * 1000) })
        #expect(try await demo.request(UsageCommand(days: 7)).totals.input > 0)
        #expect(try await demo.request(QuotasCommand()).map(\.provider) == ["claude", "codex"])
        #expect(demo.isDemo)
        #expect(DemoHostConnection.name == "Demo Mac")
    }

    @Test func inboxCountsMatchThePerProjectBadges() async throws {
        let snapshot = try await snapshot()
        let badges = snapshot.openProjects.map { openCount(snapshot, in: $0.id) }
        #expect(badges == [1, 1, 1])
        #expect(openCount(snapshot) == badges.reduce(0, +))
    }

    @Test func answeringAQuestionResolvesItAndTheCoordinatorReplies() async throws {
        let answered = try await demo.request(ResolveAttentionCommand(id: DemoID.mapTilesQuestion, answer: "OpenStreetMap"))
        #expect(answered.answer == "OpenStreetMap")
        let events = await next(5, of: demo.events)
        let steps = HostEvent.Kind.steps(sessions: [DemoID.stationCoordinator])
        #expect(events.map(\.kind) == [.state, .attention(count: 2), steps, .state, steps])

        let snapshot = try await snapshot()
        #expect(openCount(snapshot) == 2)
        #expect(openCount(snapshot, in: DemoID.stationMap) == 0)
        #expect(snapshot.sessions.first { $0.id == DemoID.stationCoordinator }?.status == .ready)
        let reply = try await demo.request(MessagesCommand(sessionID: DemoID.stationCoordinator)).last
        #expect(reply?.sender == DemoID.stationCoordinator)
        #expect(reply?.body.contains("OpenStreetMap") == true)

        await #expect(throws: ConnectionError.commandFailed("Request already resolved; stale answer rejected")) {
            try await demo.request(ResolveAttentionCommand(id: DemoID.mapTilesQuestion, answer: "Apple Maps"))
        }
    }

    @Test func approvingAPublishOpensItsPullRequest() async throws {
        #expect(try await ticket(DemoID.thresholdsTicket).pullRequest == nil)
        _ = try await demo.request(ResolveAttentionCommand(id: DemoID.publishApproval, answer: "approved"))
        let pullRequest = try await ticket(DemoID.thresholdsTicket).pullRequest
        #expect(pullRequest?.number == 214)
        #expect(pullRequest?.state == .open)
        #expect(await next(2, of: demo.events).map(\.kind) == [.state, .attention(count: 2)])
    }

    @Test func denyingAPublishOpensNoPullRequest() async throws {
        let denied = try await demo.request(ResolveAttentionCommand(id: DemoID.publishApproval, answer: "denied"))
        #expect(denied.answer == "denied")
        #expect(try await ticket(DemoID.thresholdsTicket).pullRequest == nil)
        #expect(openCount(try await snapshot()) == 2)
    }

    @Test func theMergeApprovalBelongsToAnUnprotectedMerge() async throws {
        let snapshot = try await snapshot()
        let ticket = try #require(snapshot.tickets.first { $0.merging?.stage.item == DemoID.mergeApproval })
        #expect(ticket.id == DemoID.syncRetryTicket)
        #expect(!snapshot.mergesIntoProtectedBranch(ticket))
    }

    @Test func approvingAMergeMergesThePullRequest() async throws {
        _ = try await demo.request(ResolveAttentionCommand(id: DemoID.mergeApproval, answer: "approved"))
        let ticket = try await ticket(DemoID.syncRetryTicket)
        #expect(ticket.pullRequest?.state == .merged)
        #expect(ticket.merging == nil)
    }

    @Test func usageHonoursTheProjectAndProvider() async throws {
        let week = try await demo.request(UsageCommand(days: 7))
        #expect(week.totals.total == 8_800_000)
        #expect(week.totals.requests == 127)
        #expect(week.coordinators.map(\.project) == ["Tide alerts", "Station map", "Flaky sync test"])
        #expect(week.models?.map(\.model) == ["claude-opus-5-5", "gpt-5-codex"])

        let stationMap = try await demo.request(UsageCommand(days: 7, projectID: DemoID.stationMap))
        #expect(stationMap.totals.requests == 28)
        #expect(stationMap.coordinators.map(\.id) == [DemoID.stationCoordinator])
        #expect(stationMap.models?.map(\.provider) == ["claude"])

        let codex = try await demo.request(UsageCommand(days: 7, provider: "codex"))
        #expect(codex.totals.requests == 35)
        #expect(codex.coordinators.map(\.project) == ["Tide alerts", "Flaky sync test"])

        let none = try await demo.request(UsageCommand(days: 7, projectID: DemoID.stationMap, provider: "codex"))
        #expect(none.totals.total == 0)
        #expect(none.coordinators.isEmpty)
    }

    @Test func denyingAMergeLeavesThePullRequestOpen() async throws {
        let denied = try await demo.request(ResolveAttentionCommand(id: DemoID.mergeApproval, answer: "wait for the release"))
        #expect(denied.answer == "wait for the release")
        #expect(try await ticket(DemoID.syncRetryTicket).pullRequest?.state == .open)
        #expect(openCount(try await snapshot()) == 2)
    }

    @Test func onlyAQuestionCanBeDismissedAndNobodyIsWoken() async throws {
        await #expect(throws: ConnectionError.commandFailed("Approve or deny a permission request")) {
            try await demo.request(DismissAttentionCommand(id: DemoID.publishApproval))
        }
        let dismissed = try await demo.request(DismissAttentionCommand(id: DemoID.mapTilesQuestion))
        #expect(dismissed.answer == "Dismissed by the human")
        #expect(await next(2, of: demo.events).map(\.kind) == [.state, .attention(count: 2)])
        #expect(try await demo.request(MessagesCommand(sessionID: DemoID.stationCoordinator)).last?.sender == DemoID.stationCoordinator)
        #expect(try await demo.request(MessagesCommand(sessionID: DemoID.stationCoordinator)).count == 3)
    }

    @Test func aMessageIsStoredOnceAndGetsAReply() async throws {
        let send = SendCommand(recipient: DemoID.tideCoordinator, body: "Ship it?")
        let sent = try await demo.request(send)
        #expect(sent.sender == nil)
        #expect(try await demo.request(send).sequence == sent.sequence)
        let events = await next(4, of: demo.events)
        let steps = HostEvent.Kind.steps(sessions: [DemoID.tideCoordinator])
        #expect(events.map(\.kind) == [.state, steps, .state, steps])

        let conversation = try await demo.request(MessagesCommand(sessionID: DemoID.tideCoordinator))
        #expect(conversation.suffix(2).map(\.kind) == [.human, .reply])
        #expect(conversation.count { $0.id == send.id } == 1)
        #expect(conversation.last?.createdAt == Int64(Self.now.timeIntervalSince1970 * 1000))
    }

    /// The coordinator's words come as the host's do: narration while its turn runs, then the
    /// turn's reply as an `output:<run>` message.
    @Test func aCoordinatorsWordsAreItsTurnOutput() async throws {
        let released = AsyncStream<Void>.makeStream()
        var options = DemoHostConnection.Options()
        options.sleep = { _ in for await _ in released.stream { return } }
        let demo = DemoHostConnection(options: options)
        defer { demo.close() }
        #expect(try await demo.request(StepsCommand(sessionID: DemoID.tideCoordinator)).runID == nil)

        _ = try await demo.request(SendCommand(recipient: DemoID.tideCoordinator, body: "Status?"))
        let running = try await demo.request(StepsCommand(sessionID: DemoID.tideCoordinator))
        let runID = try #require(running.runID)
        #expect(running.running)
        #expect(running.narration.map(\.state) == [.running])
        #expect(try await demo.request(StepsCommand(sessionID: DemoID.tideCoordinator, after: running.revision)).steps.isEmpty)

        released.continuation.yield()
        _ = await next(4, of: demo.events)
        let finished = try await demo.request(StepsCommand(sessionID: DemoID.tideCoordinator, after: running.revision))
        let reply = try #require(try await demo.request(MessagesCommand(sessionID: DemoID.tideCoordinator)).last)
        #expect(!finished.running)
        #expect(finished.narration.map(\.text) == [reply.body])
        #expect(reply.kind == .reply)
        #expect(reply.runID == runID)
    }

    @Test func theSeedsCoordinatorLinesAreReplies() async throws {
        let conversation = try await demo.request(MessagesCommand(sessionID: DemoID.tideCoordinator))
        #expect(conversation.map(\.kind) == [.reply, .reply, .notice, .agent, .agent, .human, .reply])
        #expect(conversation.filter { $0.kind == .reply }.allSatisfy { $0.sender == DemoID.tideCoordinator })
    }

    @Test func aCoordinatorWaitingOnlyForAnApprovalIsReadyAfterItsReply() async throws {
        _ = try await demo.request(SendCommand(recipient: DemoID.tideCoordinator, body: "Status?"))
        _ = await next(4, of: demo.events)
        let snapshot = try await snapshot()
        #expect(snapshot.attention.contains { $0.sessionID == DemoID.tideCoordinator && $0.answer == nil })
        #expect(snapshot.sessions.first { $0.id == DemoID.tideCoordinator }?.status == .ready)
    }

    @Test func aCoordinatorWithAQuestionOpenIsBlockedAfterItsReply() async throws {
        _ = try await demo.request(SendCommand(recipient: DemoID.stationCoordinator, body: "Status?"))
        _ = await next(4, of: demo.events)
        #expect(try await snapshot().sessions.first { $0.id == DemoID.stationCoordinator }?.status == .blocked)
    }

    @Test func aNegativeLimitIsRefused() async throws {
        await #expect(throws: ConnectionError.commandFailed("The limit can't be negative.")) {
            try await demo.request(MessagesCommand(sessionID: DemoID.tideCoordinator, limit: -1))
        }
        #expect(try await demo.request(MessagesCommand(sessionID: DemoID.tideCoordinator, limit: 0)).isEmpty)
    }

    @Test func aReplyWaitsForTheDelay() async throws {
        let released = AsyncStream<Void>.makeStream()
        var options = DemoHostConnection.Options()
        options.sleep = { _ in for await _ in released.stream { return } }
        let demo = DemoHostConnection(options: options)
        defer { demo.close() }

        _ = try await demo.request(SendCommand(recipient: DemoID.flakyCoordinator, body: "Status?"))
        let before = try await demo.request(MessagesCommand(sessionID: DemoID.flakyCoordinator))
        #expect(before.last?.sender == nil)
        released.continuation.yield()
        #expect(await next(4, of: demo.events).last?.kind == .steps(sessions: [DemoID.flakyCoordinator]))
    }

    @Test func resumingAfterACursorReplaysNothingTwice() async throws {
        _ = try await demo.request(DismissAttentionCommand(id: DemoID.mapTilesQuestion))
        _ = try await demo.request(ResolveAttentionCommand(id: DemoID.mergeApproval, answer: "approved"))
        let seen = await next(2, of: demo.events)

        let resumed = demo.events(after: seen.last?.cursor)
        _ = try await demo.request(ResolveAttentionCommand(id: DemoID.publishApproval, answer: "approved"))
        let rest = await next(4, of: resumed)
        let seqs = (seen + rest).map(\.cursor.seq)
        #expect(seqs == Array(1...6))

        let stale = demo.events(after: Cursor(epoch: "another demo", seq: 3))
        #expect(await next(1, of: stale).first?.kind == .resync)
    }

    @Test func whatTheDemoCannotDoIsRefusedPlainly() async throws {
        await #expect(throws: DemoHostConnection.notAvailable) { try await demo.request(StopCommand()) }
        #expect(DemoHostConnection.notAvailable.localizedDescription == "Not available in the demo.")
    }

    @Test func closingEndsTheStreamsAndRequests() async throws {
        var states: [ConnectionState] = []
        demo.close()
        for await state in demo.states { states.append(state) }
        #expect(states == [.connecting, .connected(address: DemoHostConnection.address, level: .control), .closed])
        #expect(await next(1, of: demo.events).isEmpty)
        await #expect(throws: ConnectionError.closed) { try await demo.request(SnapshotCommand()) }
    }
}

/// A command the demo does not simulate.
private struct StopCommand: HostCommand {
    typealias Reply = NoReply
    static let type = "stop"
}
