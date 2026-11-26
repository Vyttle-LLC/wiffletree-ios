import Foundation

/// Everything the demo host holds, and changes as the human uses it.
struct DemoWorkspace: Sendable {
    var projects: [Project]
    var sessions: [Session]
    /// Oldest first, answered ones included, as the host keeps them.
    var attention: [Attention]
    var tickets: [Ticket]
    var repositories: [Repository]
    var messages: [Message]
    /// The week's tokens by project and model, which `usage` adds up for its scope.
    var usage: [DemoUsage]
    var quotas: [QuotaReading]
}

/// One project's tokens on one model over the demo's week.
struct DemoUsage: Sendable {
    let projectID: String
    let usage: ModelUsage
}

/// The ids the demo's behaviour and its tests refer to.
enum DemoID {
    static let tideAlerts = "demo-tide-alerts"
    static let stationMap = "demo-station-map"
    static let flakySyncTest = "demo-flaky-sync-test"

    static let tideCoordinator = "demo-tide-coordinator"
    static let stationCoordinator = "demo-station-coordinator"
    static let flakyCoordinator = "demo-flaky-coordinator"

    static let mapTilesQuestion = "demo-attention-map-tiles"
    static let publishApproval = "demo-attention-publish-thresholds"
    static let mergeApproval = "demo-attention-merge-212"

    static let thresholdsTicket = "demo-ticket-thresholds"
    static let syncRetryTicket = "demo-ticket-sync-retry"

    static let tidepool = "demo-repository-tidepool"
}

/// The demo's starting workspace: the story the approved mockups in `design/mockups/` tell,
/// on a Mac called "Demo Mac". Times count back from `now`, so the demo always looks current.
enum DemoSeed {
    static func workspace(at now: Date) -> DemoWorkspace {
        let clock = SeedClock(now: now)
        return DemoWorkspace(
            projects: projects,
            sessions: sessions,
            attention: attention,
            tickets: tickets,
            repositories: repositories,
            messages: messages(clock),
            usage: usage,
            quotas: quotas(clock)
        )
    }

    /// Every project works in tidepool, whose `main` only the human merges into.
    private static let repositories = [
        Repository(id: DemoID.tidepool, name: "tidepool", base: "origin/main"),
    ]

    private static let projects = [
        Project(id: DemoID.tideAlerts, name: "Tide alerts", parentID: nil),
        Project(id: DemoID.stationMap, name: "Station map", parentID: nil),
        Project(id: DemoID.flakySyncTest, name: "Flaky sync test", parentID: nil),
    ]

    /// Four agents working: Tide alerts' reviewer and station-page implementer, Station map's
    /// implementer and Flaky sync test's tester. Station map's coordinator waits for the human.
    private static let sessions = [
        Session(id: DemoID.tideCoordinator, projectID: DemoID.tideAlerts, parentID: nil, name: "Tide alerts", role: .projectOrchestrator, provider: "claude", status: .ready),
        Session(id: "demo-tide-alert-implementer", projectID: DemoID.tideAlerts, parentID: DemoID.tideCoordinator, name: "Implementer", role: .implementer, provider: "claude", status: .ready),
        Session(id: "demo-tide-alert-reviewer", projectID: DemoID.tideAlerts, parentID: DemoID.tideCoordinator, name: "Reviewer · Correctness", role: .reviewer, provider: "codex", status: .working),
        Session(id: "demo-tide-station-page-implementer", projectID: DemoID.tideAlerts, parentID: DemoID.tideCoordinator, name: "Implementer", role: .implementer, provider: "claude", status: .working),
        Session(id: DemoID.stationCoordinator, projectID: DemoID.stationMap, parentID: nil, name: "Station map", role: .projectOrchestrator, provider: "claude", status: .blocked),
        Session(id: "demo-station-implementer", projectID: DemoID.stationMap, parentID: DemoID.stationCoordinator, name: "Implementer", role: .implementer, provider: "claude", status: .working),
        Session(id: DemoID.flakyCoordinator, projectID: DemoID.flakySyncTest, parentID: nil, name: "Flaky sync test", role: .projectOrchestrator, provider: "claude", status: .ready),
        Session(id: "demo-flaky-tester", projectID: DemoID.flakySyncTest, parentID: DemoID.flakyCoordinator, name: "Tester", role: .tester, provider: "codex", status: .working),
    ]

    /// Three items need the human, one per project; the answered ones are the Inbox's history.
    private static let attention = [
        Attention(
            id: "demo-attention-allow-evaluators", projectID: DemoID.stationMap, sessionID: DemoID.stationCoordinator,
            operationID: "allow-evaluators", prompt: "Allow UI evaluators in this project?",
            options: ["In this project", "Not in this project"], answer: "Not in this project"
        ),
        Attention(
            id: "demo-attention-rename-table", projectID: DemoID.stationMap, sessionID: DemoID.stationCoordinator,
            operationID: "rename-stations-table", prompt: "Rename the stations table?",
            answer: "Dismissed by the human"
        ),
        Attention(
            id: "demo-attention-old-format", projectID: DemoID.tideAlerts, sessionID: DemoID.tideCoordinator,
            operationID: "old-alert-format", prompt: "Keep the old alert format for a release?",
            options: ["Keep it for a release", "Drop it now"], answer: "Keep it for a release"
        ),
        Attention(
            id: DemoID.mergeApproval, projectID: DemoID.flakySyncTest, sessionID: DemoID.flakyCoordinator,
            operationID: "merge:demo-merge-212",
            prompt: "Merge #212 into feature/sync-retry?\n\n“Retry the sync on a lost lock” · checks passed · squash merge."
        ),
        Attention(
            id: DemoID.publishApproval, projectID: DemoID.tideAlerts, sessionID: DemoID.tideCoordinator,
            operationID: "publish:demo-publish-thresholds:pull_request",
            prompt: "Publish “Store alert thresholds per station”?\n\nReview passed. Wiffletree pushes wiffletree/store-alert-thresholds and opens a pull request on Vyttle-LLC/tidepool."
        ),
        Attention(
            id: DemoID.mapTilesQuestion, projectID: DemoID.stationMap, sessionID: DemoID.stationCoordinator,
            operationID: "map-tiles",
            prompt: "Which map tiles should the station page use?\n\nBoth are free for this volume. Apple Maps needs no key on iOS; the web page would need a token.",
            options: ["OpenStreetMap", "Apple Maps"]
        ),
    ]

    private static let tickets = [
        Ticket(
            id: DemoID.thresholdsTicket, coordinatorID: DemoID.tideCoordinator, repositoryID: DemoID.tidepool,
            title: "Store alert thresholds per station",
            brief: "Keep a threshold per station in a `thresholds` table, set and listed with `tidepool threshold`.",
            branch: "wiffletree/store-alert-thresholds", state: .accepted,
            verification: fullReview(outcome: .passed, rounds: [
                round(1, commit: "a91d07b", tests: .passed, correctness: .passed, regressions: .passed, prefix: "demo-thresholds"),
            ])
        ),
        Ticket(
            id: "demo-ticket-alert-command", coordinatorID: DemoID.tideCoordinator, repositoryID: DemoID.tidepool,
            title: "Add the tidepool alert command",
            brief: "`tidepool alert` checks each station against its threshold and sends one alert per crossing.",
            branch: "wiffletree/add-tidepool-alert", state: .verifying,
            verification: fullReview(outcome: .running, rounds: [
                round(1, commit: "8be41a9", tests: .passed, correctness: .failed, regressions: .passed, prefix: "demo-alert"),
                VerificationRound(round: 2, commit: "3f1c2e0", verifiers: [
                    VerifierRun(sessionID: "demo-tide-alert-reviewer", role: .reviewer, focus: "Correctness", result: .pending),
                ]),
            ]),
            ledger: [
                LedgerEntry(
                    id: "F1", severity: .blocking, location: "src/alert.rs:88",
                    summary: "Alert fires twice when a station has two thresholds",
                    focus: "Correctness", cycle: 1, round: 1, status: .open
                ),
            ]
        ),
        Ticket(
            id: "demo-ticket-station-page", coordinatorID: DemoID.tideCoordinator, repositoryID: DemoID.tidepool,
            title: "Show thresholds on the station page",
            brief: "Show each station's threshold and its last alert on the station page, under the map.",
            branch: "wiffletree/show-thresholds-on-station-page", state: .assigned
        ),
        Ticket(
            id: "demo-ticket-draw-stations", coordinatorID: DemoID.stationCoordinator, repositoryID: DemoID.tidepool,
            title: "Draw stations on the map",
            brief: "Put a pin for every station on the station page's map.",
            branch: "wiffletree/draw-stations-on-the-map", state: .assigned
        ),
        Ticket(
            id: "demo-ticket-station-pins", coordinatorID: DemoID.stationCoordinator, repositoryID: DemoID.tidepool,
            title: "Open a station's page from its pin",
            brief: "Tapping a station's pin opens its page.",
            branch: "wiffletree/open-station-from-pin", state: .planned
        ),
        Ticket(
            id: DemoID.syncRetryTicket, coordinatorID: DemoID.flakyCoordinator, repositoryID: DemoID.tidepool,
            title: "Retry the sync on a lost lock",
            brief: "When the sync lock times out mid-sync, retry once instead of starting a second sync.",
            branch: "wiffletree/retry-sync-on-lost-lock", state: .accepted,
            verification: fullReview(outcome: .passed, rounds: [
                round(1, commit: "5d2a9f4", tests: .passed, correctness: .passed, regressions: .passed, prefix: "demo-sync-retry"),
            ]),
            pullRequest: PullRequest(
                number: 212, url: "https://github.com/Vyttle-LLC/tidepool/pull/212", state: .open, draft: false,
                base: "feature/sync-retry", mergeState: "clean", checks: .success
            ),
            merging: MergeRequest(
                number: 212, base: "feature/sync-retry",
                stage: MergeRequest.Stage(kind: .waitingForHuman, item: DemoID.mergeApproval)
            )
        ),
        Ticket(
            id: "demo-ticket-lock-log", coordinatorID: DemoID.flakyCoordinator, repositoryID: DemoID.tidepool,
            title: "Log who holds the sync lock",
            brief: "Log the lock's holder and age when a sync waits on it, so the next flake is easy to read.",
            branch: "wiffletree/log-sync-lock-holder", state: .verifying,
            verification: fullReview(outcome: .running, rounds: [
                VerificationRound(round: 1, commit: "c40e9d2", verifiers: [
                    VerifierRun(sessionID: "demo-flaky-tester", role: .tester, focus: "Tests", result: .pending),
                ]),
            ])
        ),
    ]

    private static func fullReview(outcome: Verification.Outcome, rounds: [VerificationRound]) -> Verification {
        Verification(cycle: 1, level: CycleLevel(name: "Full", kind: .fullReview), maxRounds: 3, outcome: outcome, rounds: rounds)
    }

    /// A round of the demo's three verifiers: Tests, Correctness and Regressions.
    private static func round(
        _ number: Int, commit: String,
        tests: VerifierRun.Result, correctness: VerifierRun.Result, regressions: VerifierRun.Result,
        prefix: String
    ) -> VerificationRound {
        VerificationRound(round: number, commit: commit, verifiers: [
            VerifierRun(sessionID: "\(prefix)-tester", role: .tester, focus: "Tests", result: tests),
            VerifierRun(sessionID: "\(prefix)-correctness", role: .reviewer, focus: "Correctness", result: correctness),
            VerifierRun(sessionID: "\(prefix)-regressions", role: .reviewer, focus: "Regressions", result: regressions),
        ])
    }

    /// The coordinators' conversations. A coordinator's own words are kept as messages it sends
    /// itself, since the client reads no turn output yet.
    private static func messages(_ clock: SeedClock) -> [Message] {
        let lines: [(minutesAgo: Int, sender: String?, recipient: String, body: String)] = [
            (190, nil, DemoID.flakyCoordinator, "The sync test fails about one run in ten. Find out why."),
            (178, DemoID.flakyCoordinator, DemoID.flakyCoordinator, """
                It's a lost lock: when the lock times out mid-sync, a second sync starts and the test sees both. I've planned two tickets:

                - **Retry the sync on a lost lock**
                - **Log who holds the sync lock**, so the next flake is easy to read
                """),
            (80, DemoID.flakyCoordinator, DemoID.flakyCoordinator, """
                **Retry the sync on a lost lock** is accepted and published as #212 into `feature/sync-retry`; checks passed.

                Merging it waits for you in the Inbox.
                """),
            (65, DemoID.tideCoordinator, DemoID.tideCoordinator, """
                Welcome to the demo. I'm the coordinator for Tide alerts: I plan tickets, hand them to agents and ask you when a decision is yours.

                Try it: answer a question in the **Inbox**, or reply here.
                """),
            (55, nil, DemoID.stationCoordinator, "Let's put the stations on a map on the station page."),
            (50, DemoID.stationCoordinator, DemoID.stationCoordinator, """
                I've planned two tickets, **Draw stations on the map** and **Open a station's page from its pin**. The implementer has started on the first.
                """),
            (40, DemoID.tideCoordinator, DemoID.tideCoordinator, """
                **Store alert thresholds per station** passed its Full review, and I've accepted it.

                - **Change:** a thresholds table with `tidepool threshold set`, and a migration for existing stores.
                - **Tests:** 14 passed; thresholds set and listed against a scratch store.

                Nothing has been pushed; publishing it waits for you in the Inbox.
                """),
            (32, "demo-tide-alert-implementer", DemoID.tideCoordinator, "Ready for testing: Add the tidepool alert command at 3f1c2e0, which fixes the double alert."),
            (31, "demo-tide-alert-reviewer", DemoID.tideCoordinator, "Round 2 started: checking 3f1c2e0 for F1."),
            (28, nil, DemoID.tideCoordinator, "Good. Can the alert also go to the station page?"),
            (22, DemoID.tideCoordinator, DemoID.tideCoordinator, """
                Yes. I'll fold it into **Show thresholds on the station page** rather than open a new ticket, and tell its implementer now.
                """),
            (12, DemoID.stationCoordinator, DemoID.stationCoordinator, """
                One decision before the map goes further: which map tiles? I've put the choice in your Inbox.
                """),
        ]
        return lines.enumerated().map { index, line in
            Message(
                id: "demo-message-\(index + 1)",
                sequence: Int64(index + 1),
                projectID: sessions.first { $0.id == line.recipient }!.projectID,
                sender: line.sender,
                recipient: line.recipient,
                body: line.body,
                receipt: "completed",
                createdAt: clock.milliseconds(minutesAgo: line.minutesAgo)
            )
        }
    }

    /// The last week: 8.8M tokens in 127 requests across the three projects. Station map's
    /// team runs only on Claude.
    private static let usage: [DemoUsage] = [
        spent(on: .opus, in: DemoID.tideAlerts, uncached: 700_000, cacheRead: 2_050_000, cacheWrite: 150_000, output: 210_000, requests: 46),
        spent(on: .codex, in: DemoID.tideAlerts, uncached: 420_000, cacheRead: 960_000, cacheWrite: 54_000, output: 114_000, requests: 21),
        spent(on: .opus, in: DemoID.stationMap, uncached: 420_000, cacheRead: 1_230_000, cacheWrite: 90_000, output: 126_000, requests: 28),
        spent(on: .opus, in: DemoID.flakySyncTest, uncached: 280_000, cacheRead: 820_000, cacheWrite: 60_000, output: 84_000, requests: 18),
        spent(on: .codex, in: DemoID.flakySyncTest, uncached: 280_000, cacheRead: 640_000, cacheWrite: 36_000, output: 76_000, requests: 14),
    ]

    private static func spent(
        on model: PricedModel, in projectID: String,
        uncached: UInt64, cacheRead: UInt64, cacheWrite: UInt64, output: UInt64, requests: UInt64
    ) -> DemoUsage {
        let counts = TokenTotals(input: uncached + cacheRead + cacheWrite, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite, requests: requests)
        let perToken = 1e-6
        let cost = Cost(
            input: Double(uncached) * model.input * perToken,
            cacheRead: Double(cacheRead) * model.cacheRead * perToken,
            cacheWrite: Double(cacheWrite) * model.cacheWrite * perToken,
            output: Double(output) * model.output * perToken
        )
        return DemoUsage(projectID: projectID, usage: ModelUsage(provider: model.provider, model: model.name, counts: counts, cost: cost))
    }

    /// A model with its list prices per million tokens.
    private struct PricedModel {
        let provider: String
        let name: String
        let input, cacheRead, cacheWrite, output: Double

        static let opus = Self(provider: "claude", name: "claude-opus-5-5", input: 15, cacheRead: 1.5, cacheWrite: 18.75, output: 75)
        static let codex = Self(provider: "codex", name: "gpt-5-codex", input: 1.25, cacheRead: 0.125, cacheWrite: 0, output: 10)
    }

    /// Claude has 58% of its 5-hour window left; Codex's week is nearly spent.
    private static func quotas(_ clock: SeedClock) -> [QuotaReading] {
        let observed = clock.milliseconds(minutesAgo: 1)
        let week: UInt64 = 7 * 24 * 60
        return [
            QuotaReading(provider: "claude", account: nil, observedAt: observed, windows: [
                QuotaWindow(key: "five_hour", label: "5 hours", usedPercent: 42, observedAt: observed, durationMinutes: 300, resetsAt: clock.milliseconds(minutesAgo: -118)),
                QuotaWindow(key: "weekly", label: "Weekly", usedPercent: 61, observedAt: observed, durationMinutes: week, resetsAt: clock.milliseconds(minutesAgo: -2 * 24 * 60)),
            ], error: nil),
            QuotaReading(provider: "codex", account: nil, observedAt: observed, windows: [
                QuotaWindow(key: "five_hour", label: "5 hours", usedPercent: 18, observedAt: observed, durationMinutes: 300, resetsAt: clock.milliseconds(minutesAgo: -178)),
                QuotaWindow(key: "weekly", label: "Weekly", usedPercent: 88, observedAt: observed, durationMinutes: week, resetsAt: clock.milliseconds(minutesAgo: -4 * 24 * 60)),
            ], error: nil),
        ]
    }
}

/// Times relative to when the demo starts.
private struct SeedClock {
    let now: Date

    /// Milliseconds since the epoch; a negative count is in the future.
    func milliseconds(minutesAgo minutes: Int) -> Int64 {
        Int64((now.timeIntervalSince1970 - Double(minutes * 60)) * 1000)
    }
}
