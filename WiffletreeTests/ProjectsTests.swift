import Foundation
import Synchronization
import Testing
import WiffletreeKit
@testable import Wiffletree

/// Waits for the main actor to apply what the demo sent.
@MainActor
private func eventually(_ condition: () -> Bool) async throws {
    for _ in 0..<200 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}

/// Waits for the demo to reach a state only a request can read.
@MainActor
private func eventuallyAsync(_ condition: () async throws -> Bool) async throws {
    for _ in 0..<200 {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(try await condition())
}

/// The demo host as Home sees it, with replies that come when `sleep` lets them.
@MainActor
private func demoHost(sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }) async throws -> LiveHost {
    var options = DemoHostConnection.Options()
    options.sleep = sleep
    let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { DemoHostConnection(options: options) })
    try await eventually { host.snapshot != nil }
    return host
}

/// Ids of the demo seed, which the app's tests cannot reach as `DemoID`.
private enum Seed {
    static let tideAlerts = "demo-tide-alerts"
    static let tideCoordinator = "demo-tide-coordinator"
    static let stationMap = "demo-station-map"
    static let legacyImporter = "demo-legacy-importer"
}

/// The demo host, recording the conversation reads sent to it.
private final class RecordingConnection: HostConnection {
    private let demo: DemoHostConnection
    private let log = Mutex<[String]>([])

    init(_ demo: DemoHostConnection) {
        self.demo = demo
    }

    var events: AsyncStream<HostEvent> { demo.events }
    var states: AsyncStream<ConnectionState> { demo.states }
    var isDemo: Bool { true }
    var sent: [String] { log.withLock { $0 } }

    func request<Command: HostCommand>(_ command: Command) async throws -> Command.Reply {
        if let steps = command as? StepsCommand { log.withLock { $0.append("steps after \(steps.after)") } }
        if let messages = command as? MessagesCommand {
            log.withLock { $0.append(messages.before.map { "messages before \($0)" } ?? "messages") }
        }
        return try await demo.request(command)
    }

    func close() {
        demo.close()
    }
}

/// The demo host failing its next `messages` reads, as a host does while the connection is down,
/// with events the test sends instead of the demo's.
private final class FlakyConnection: HostConnection {
    let events: AsyncStream<HostEvent>
    private let eventSink: AsyncStream<HostEvent>.Continuation
    private let demo = DemoHostConnection()
    private let failingReads: Mutex<Int>

    init(failingReads: Int = 1) {
        (events, eventSink) = AsyncStream.makeStream()
        self.failingReads = Mutex(failingReads)
    }

    func failNextRead() {
        failingReads.withLock { $0 = 1 }
    }

    var states: AsyncStream<ConnectionState> { demo.states }
    var isDemo: Bool { true }

    func yield(_ kind: HostEvent.Kind) {
        eventSink.yield(HostEvent(cursor: Cursor(epoch: "test", seq: 1), kind: kind))
    }

    func request<Command: HostCommand>(_ command: Command) async throws -> Command.Reply {
        let fails = command is MessagesCommand && failingReads.withLock { left in
            defer { left = max(left - 1, 0) }
            return left > 0
        }
        if fails { throw ConnectionError.closed }
        return try await demo.request(command)
    }

    func close() {
        eventSink.finish()
        demo.close()
    }
}

private func message(_ id: String, from sender: String?, to recipient: String = "c1") -> Message {
    let sender = sender.map { #""\#($0)""# } ?? "null"
    let json = #"{"id":"\#(id)","sequence":1,"project_id":"p","sender":\#(sender),"recipient":"\#(recipient)","body":"…","receipt":"completed","created_at":0}"#
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(Message.self, from: Data(json.utf8))
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HomeTests {
    @Test func eachProjectsBadgeCountsItsOpenInboxItems() async throws {
        let host = try await demoHost()
        let snapshot = try #require(host.snapshot)
        let overviews = snapshot.projectGroups.flatMap(\.projects)
        #expect(overviews.map(\.openItems.count) == [1, 1, 1])
        #expect(overviews.map(\.openItems.count).reduce(0, +) == host.openAttentionCount)

        let question = try #require(snapshot.attention.first { $0.projectID == Seed.stationMap && $0.answer == nil })
        _ = try await host.connection.request(ResolveAttentionCommand(id: question.id, answer: "Apple Maps"))
        try await eventually { host.snapshot?.overview(of: Seed.stationMap)?.openItems.isEmpty == true }
        #expect(host.openAttentionCount == 2)
    }

    @Test func projectsAreGroupedBySpaceWithTheirStateInWords() async throws {
        let snapshot = try #require(try await demoHost().snapshot)
        let groups = snapshot.projectGroups
        #expect(groups.map(\.space?.name) == ["Sample Space"])
        #expect(groups[0].projects.map(\.summary) == [
            "Implementing · 1 of 3 tickets accepted",
            "Implementing · coordinator asked a question",
            "Verifying · 1 of 2 tickets accepted",
        ])
    }

    @Test func aClosedProjectIsHiddenAndLeftOutOfTheCounts() async throws {
        let host = try await demoHost()
        let snapshot = try #require(host.snapshot)
        #expect(snapshot.projects.map(\.name) == ["Tide alerts", "Station map", "Flaky sync test"])
        #expect(snapshot.projectGroups.flatMap(\.projects).map(\.project.name) == ["Tide alerts", "Station map", "Flaky sync test"])
        #expect(!snapshot.sessions.contains { $0.projectID == Seed.legacyImporter })
        #expect(snapshot.workingAgents.count == 4)
        #expect(host.openAttentionCount == 3)
    }

    @Test func theNeedYouCardNamesTheQuestionAndTheApprovals() async throws {
        let snapshot = try #require(try await demoHost().snapshot)
        #expect(snapshot.needsYouSummary == "Station map asks “Which map tiles should the station page use?”, and a merge and a publish wait for your approval.")
    }

    @Test func theAgentsSheetListsWhoIsWorkingThenTheCoordinator() async throws {
        let snapshot = try #require(try await demoHost().snapshot)
        let agents = AgentsSheet.agents(of: Seed.tideAlerts, in: snapshot)
        #expect(agents.map(\.displayName) == ["Reviewer · Correctness", "Implementer", "Coordinator"])
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProjectChatTests {
    @Test func sendingShowsTheMessageAndThenTheReply() async throws {
        let host = try await demoHost()
        let chat = ProjectChat(host: host, projectID: Seed.tideAlerts)
        let running = Task { await chat.run() }
        defer { running.cancel() }
        try await eventually { !chat.messages.isEmpty }

        chat.draft = "Can you ship it?"
        await chat.send()
        #expect(chat.draft.isEmpty)
        let sent = try #require(chat.messages.last { $0.kind == .human })
        #expect(sent.body == "Can you ship it?")
        try await eventually { chat.messages.last?.kind == .reply && chat.messages.last?.sequence ?? 0 > sent.sequence }
        #expect(chat.liveNarration.isEmpty)
    }

    @Test func theRunningTurnsNarrationShowsUntilItsReplyLands() async throws {
        let released = AsyncStream<Void>.makeStream()
        let host = try await demoHost(sleep: { _ in for await _ in released.stream { return } })
        let chat = ProjectChat(host: host, projectID: Seed.tideAlerts)
        let running = Task { await chat.run() }
        defer { running.cancel() }
        try await eventually { !chat.messages.isEmpty }

        chat.draft = "Status?"
        await chat.send()
        try await eventually { !chat.liveNarration.isEmpty }
        #expect(chat.coordinator?.status == .working)

        released.continuation.yield()
        try await eventually { chat.liveNarration.isEmpty && chat.messages.last?.kind == .reply }
        #expect(chat.turn?.narration.last?.text == chat.messages.last?.body)
    }

    /// A steps event fetches only the newer steps and no messages; a state event fetches messages.
    @Test func aStepsEventFetchesOnlyTheNewerSteps() async throws {
        let released = AsyncStream<Void>.makeStream()
        var options = DemoHostConnection.Options()
        options.sleep = { _ in for await _ in released.stream { return } }
        let recording = RecordingConnection(DemoHostConnection(options: options))
        let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { recording })
        try await eventually { host.snapshot != nil }
        let chat = ProjectChat(host: host, projectID: Seed.tideAlerts)
        let running = Task { await chat.run() }
        defer { running.cancel() }
        try await eventually { chat.turn != nil }
        #expect(recording.sent == ["messages", "steps after 0"])

        chat.draft = "Status?"
        await chat.send()
        try await eventually { !chat.liveNarration.isEmpty }
        let started = try #require(chat.turn?.revision)
        released.continuation.yield()
        try await eventually { chat.liveNarration.isEmpty && chat.messages.last?.kind == .reply }

        // The send and the reply each brought a state event and a steps event.
        try await eventually { recording.sent.count == 6 }
        #expect(recording.sent.filter { $0 == "messages" }.count == 3)
        #expect(recording.sent.filter { $0.hasPrefix("steps") } == ["steps after 0", "steps after 0", "steps after \(started)"])
        #expect(chat.turn?.narration.map(\.text) == chat.messages.last.map { [$0.body] })
    }

    /// Tide alerts' seeded conversation holds 7 messages; a page of 3 shows the newest 3.
    @Test func loadEarlierAsksForThePageBeforeTheOldestLoadedMessage() async throws {
        let recording = RecordingConnection(DemoHostConnection())
        let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { recording })
        try await eventually { host.snapshot != nil }
        let chat = ProjectChat(host: host, projectID: Seed.tideAlerts, pageSize: 3)
        let running = Task { await chat.run() }
        defer { running.cancel() }
        try await eventually { chat.turn != nil }
        #expect(chat.messages.count == 3)
        #expect(chat.hasEarlier)

        let oldest = try #require(chat.messages.first)
        await chat.loadEarlier()
        #expect(recording.sent.last == "messages before \(oldest.sequence)")
        #expect(chat.messages.count == 6)
        #expect(chat.hasEarlier)

        await chat.loadEarlier()
        #expect(chat.messages.count == 7)
        #expect(!chat.hasEarlier)
        #expect(chat.messages.map(\.sequence) == chat.messages.map(\.sequence).sorted())
        #expect(chat.messages.first?.body.hasPrefix("Welcome to the demo.") == true)
    }

    /// The bug from the iPhone: each change replaced the conversation with the newest page, so
    /// older messages vanished as it grew.
    @Test func theNewestPageMergesWithoutDroppingEarlierMessages() async throws {
        let host = try await demoHost()
        let chat = ProjectChat(host: host, projectID: Seed.tideAlerts, pageSize: 3)
        let running = Task { await chat.run() }
        defer { running.cancel() }
        try await eventually { chat.messages.count == 3 }
        await chat.loadEarlier()
        await chat.loadEarlier()
        let loaded = chat.messages.map(\.id)
        #expect(loaded.count == 7)

        for body in ["One", "Two"] {
            chat.draft = body
            await chat.send()
            try await eventually { chat.messages.last?.kind == .reply }
        }
        try await eventually { chat.messages.count == 11 }
        #expect(Array(chat.messages.map(\.id).prefix(7)) == loaded)
        #expect(chat.messages.suffix(4).map(\.kind) == [.human, .reply, .human, .reply])
        #expect(Set(chat.messages.map(\.id)).count == 11)
        #expect(!chat.hasEarlier)
    }

    /// More messages arrive than a page holds while the chat is not reading them, then the person
    /// sends. The sent message must not make the next newest page look continuous with the old
    /// history: the page starts the history again, and "Load earlier" reaches every message.
    @Test func aSendBeforeARefreshLeavesNoHoleInTheHistory() async throws {
        let host = try await demoHost()
        let chat = ProjectChat(host: host, projectID: Seed.tideAlerts, pageSize: 3)
        await chat.reloadAll()
        #expect(chat.messages.count == 3)

        func everything() async throws -> [String] {
            try await host.connection.request(MessagesCommand(sessionID: Seed.tideCoordinator, limit: 100)).map(\.id)
        }
        for body in ["Unseen one", "Unseen two"] {
            _ = try await host.connection.request(SendCommand(recipient: Seed.tideCoordinator, body: body))
        }
        try await eventuallyAsync { try await everything().count == 11 }
        chat.draft = "Mine"
        await chat.send()
        try await eventuallyAsync { try await everything().count == 13 }

        await chat.reloadAll()
        #expect(chat.messages.count == 3)
        while chat.hasEarlier { await chat.loadEarlier() }
        #expect(chat.messages.map(\.id) == (try await everything()))
    }

    /// A restart drops the snapshot; the conversation stays on screen and refreshes once the
    /// coordinator is back, as the view runs the chat again.
    @Test func aRestartKeepsTheHistoryVisible() async throws {
        let host = try await demoHost()
        let chat = ProjectChat(host: host, projectID: Seed.tideAlerts)
        var running = Task { await chat.run() }
        try await eventually { chat.turn != nil }
        chat.draft = "Before the restart"
        await chat.send()
        try await eventually { chat.messages.last?.kind == .reply }
        let loaded = chat.messages.map(\.id)
        #expect(loaded.count == 9)

        host.restart()
        await running.value
        #expect(chat.coordinator == nil)
        #expect(chat.messages.map(\.id) == loaded)

        try await eventually { chat.coordinator != nil }
        running = Task { await chat.run() }
        defer { running.cancel() }
        // The restarted demo starts over from its seed, which the refresh shows.
        try await eventually { chat.messages.count == 7 }
        #expect(chat.messages.map(\.id) == Array(loaded.prefix(7)))
    }

    /// The blank chat from the iPhone: the conversation failed to load while the connection was
    /// down, then the busy coordinator's steps loaded and cleared the error, leaving no messages
    /// and nothing saying why.
    @Test func aFailedLoadStaysShownUntilTheMessagesLoad() async throws {
        let flaky = FlakyConnection()
        let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { flaky })
        try await eventually { host.snapshot != nil }
        let chat = ProjectChat(host: host, projectID: Seed.tideAlerts)
        let running = Task { await chat.run() }
        defer { running.cancel() }
        try await eventually { chat.failure != nil }
        #expect(chat.messages.isEmpty)
        #expect(!chat.hasLoaded)

        flaky.yield(.steps(sessions: [Seed.tideCoordinator]))
        try await eventually { chat.turn != nil }
        #expect(chat.failure != nil)

        await chat.reloadAll()
        #expect(chat.failure == nil)
        #expect(chat.hasLoaded)
        #expect(!chat.messages.isEmpty)
    }

    @Test func reopeningAChatShowsTheHistoryItLoaded() async throws {
        let host = try await demoHost()
        let chat = host.chat(of: Seed.tideAlerts)
        let running = Task { await chat.run() }
        try await eventually { chat.hasLoaded }
        let loaded = chat.messages.map(\.id)
        running.cancel()
        await running.value

        host.restart()
        let reopened = host.chat(of: Seed.tideAlerts)
        #expect(reopened === chat)
        #expect(reopened.messages.map(\.id) == loaded)
        #expect(host.chat(of: Seed.stationMap) !== chat)
    }

    @Test func aLoadWhileDisconnectedShowsNoConversationError() async throws {
        let fake = FakeConnection()
        let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { fake })
        let address = HostAddress(host: "studio.local")
        fake.yield(.connected(address: address, level: .control))
        try await eventually { host.snapshot != nil }
        let chat = ProjectChat(host: host, projectID: "p")

        fake.yield(.waiting(attempt: 1, error: .unreachable("No address answered.")))
        try await eventually { !host.isConnected }
        await chat.reloadAll()
        #expect(chat.failure == nil)

        fake.yield(.connected(address: address, level: .control))
        try await eventually { host.isConnected }
        await chat.reloadAll()
        #expect(chat.failure != nil)
    }

    @Test func beforeAnythingLoadsTheChatWaitsForAHostThatIsNotConnected() async throws {
        let fake = FakeConnection()
        let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { fake })
        let chat = host.chat(of: "p")
        #expect(chat.isWaitingForHost)

        fake.yield(.connected(address: HostAddress(host: "studio.local"), level: .control))
        try await eventually { host.isConnected }
        #expect(!chat.isWaitingForHost)

        let demo = try await demoHost()
        let loaded = demo.chat(of: Seed.tideAlerts)
        await loaded.reloadAll()
        demo.restart()
        #expect(!demo.isConnected)
        #expect(!loaded.isWaitingForHost)
    }

    @Test func aFailedLoadEarlierOffersItAgainWithoutTheConversationError() async throws {
        let flaky = FlakyConnection(failingReads: 0)
        let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { flaky })
        try await eventually { host.snapshot != nil }
        let chat = ProjectChat(host: host, projectID: Seed.tideAlerts, pageSize: 3)
        await chat.reloadAll()

        flaky.failNextRead()
        await chat.loadEarlier()
        #expect(chat.earlierFailed)
        #expect(chat.failure == nil)
        #expect(chat.messages.count == 3)

        await chat.loadEarlier()
        #expect(!chat.earlierFailed)
        #expect(chat.messages.count == 6)
    }

    /// Tide alerts' seeded conversation holds exactly a page of 7.
    @Test func anEmptyEarlierPageEndsLoadEarlierAcrossReloads() async throws {
        let host = try await demoHost()
        let chat = ProjectChat(host: host, projectID: Seed.tideAlerts, pageSize: 7)
        await chat.reloadAll()
        #expect(chat.hasEarlier)

        await chat.loadEarlier()
        #expect(!chat.hasEarlier)
        await chat.reloadAll()
        #expect(!chat.hasEarlier)
        #expect(chat.messages.count == 7)
    }

    @Test func anEmptyDraftCannotBeSent() async throws {
        let chat = ProjectChat(host: try await demoHost(), projectID: Seed.tideAlerts)
        chat.draft = "  \n "
        #expect(!chat.canSend)
    }

    @Test func agentTrafficFoldsIntoOneLinePerBurst() {
        let entries = ChatEntry.fold([
            message("output:r1", from: "c1"),
            message("m2", from: "implementer"),
            message("verification:t1", from: nil),
            message("m4", from: "reviewer"),
            message("m5", from: nil),
            message("m6", from: "implementer"),
            message("output:r2", from: "c1"),
        ])
        let shapes = entries.map { entry -> String in
            switch entry {
            case .reply: "reply"
            case .human: "human"
            case .activity(let burst): "activity \(burst.count)"
            }
        }
        #expect(shapes == ["reply", "activity 3", "human", "activity 1", "reply"])
    }

    @Test func theSeededConversationReadsAsTheMockupDrawsIt() async throws {
        let host = try await demoHost()
        let chat = ProjectChat(host: host, projectID: Seed.tideAlerts)
        let running = Task { await chat.run() }
        defer { running.cancel() }
        try await eventually { !chat.messages.isEmpty }
        let tail = Array(chat.entries.suffix(3))
        guard case .activity(let burst) = tail.first else {
            Issue.record("Expected the agents' burst before the human's message")
            return
        }
        #expect(burst.map(\.kind) == [.notice, .agent, .agent])
        if case .human = tail[1] {} else { Issue.record("Expected the human's message") }
        if case .reply = tail[2] {} else { Issue.record("Expected the coordinator's reply") }
    }
}

/// Merge in Inbox shows only for a merge waiting on the human into a branch that is not protected.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MergeInInboxTests {
    /// Two tickets in a repository whose base is `main`, each with its merge waiting in the Inbox:
    /// one into a feature branch, one into `main`, plus one whose approval was already answered.
    private let snapshot: Snapshot = {
        func ticket(_ id: String, base: String) -> String {
            #"""
            {"id":"\#(id)","coordinator_id":"c1","repository_id":"r1","title":"T","brief":"…","branch":"b","state":"accepted",
             "merging":{"number":1,"base":"\#(base)","stage":{"kind":"waiting_for_human","item":"a-\#(id)"}}}
            """#
        }
        func approval(_ id: String, answer: String?) -> String {
            let answer = answer.map { #""\#($0)""# } ?? "null"
            return #"""
            {"id":"a-\#(id)","project_id":"p","session_id":"c1","operation_id":"merge:m-\#(id)","prompt":"Merge?","answer":\#(answer)}
            """#
        }
        let json = #"""
        {"projects":[],"sessions":[],
         "repositories":[{"id":"r1","name":"tidepool","base":"origin/main","protected_branches":[]}],
         "tickets":[\#(ticket("feature", base: "feature/sync")),\#(ticket("main", base: "main")),\#(ticket("answered", base: "feature/x"))],
         "attention":[\#(approval("feature", answer: nil)),\#(approval("main", answer: nil)),\#(approval("answered", answer: "approved"))]}
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(Snapshot.self, from: Data(json.utf8))
    }()

    private func waits(_ id: String) throws -> Bool {
        snapshot.mergeWaitsInInbox(try #require(snapshot.ticket(id)))
    }

    @Test func aMergeIntoAnUnprotectedBranchWaitsInTheInbox() throws {
        #expect(try waits("feature"))
    }

    @Test func aMergeIntoAProtectedBranchOpensGitHubInstead() throws {
        #expect(try !waits("main"))
    }

    @Test func anAnsweredApprovalNoLongerWaits() throws {
        #expect(try !waits("answered"))
    }

    @Test func theDemosFeatureBranchMergeWaitsInTheInbox() async throws {
        let snapshot = try #require(try await demoHost().snapshot)
        let syncRetry = try #require(snapshot.ticket("demo-ticket-sync-retry"))
        #expect(snapshot.mergeWaitsInInbox(syncRetry))
    }
}

struct MarkdownBlockTests {
    @Test func aReplySplitsIntoParagraphsListsAndCode() {
        let blocks = MarkdownBlock.parse("""
            **Done**, and accepted.

            - **Change:** a table
            - **Tests:** 14 passed
            2. Then this

            ```
            swift test
            ```
            Last line
            """)
        #expect(blocks == [
            .paragraph("**Done**, and accepted."),
            .item(marker: "•", text: "**Change:** a table"),
            .item(marker: "•", text: "**Tests:** 14 passed"),
            .item(marker: "2.", text: "Then this"),
            .code("swift test"),
            .paragraph("Last line"),
        ])
    }
}
