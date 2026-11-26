import Foundation
import Testing
import WiffletreeKit
@testable import Wiffletree

private let now = Date(timeIntervalSince1970: 1_795_000_000)

/// A window as the host's JSON has it, `minutesAgo` read and resetting in `resetsIn` minutes.
private func window(used: Double?, minutesAgo: Int = 1, resetsIn: Int? = 118, minutes: Int = 300) throws -> QuotaWindow {
    let milliseconds = { (offset: Int) in Int64((now.timeIntervalSince1970 + Double(offset * 60)) * 1000) }
    let json = #"""
    {"key": "k", "label": "5 hours", "usedPercent": \#(used.map { "\($0)" } ?? "null"),
     "observedAt": \#(milliseconds(-minutesAgo)), "durationMins": \#(minutes),
     "resetsAt": \#(resetsIn.map { "\(milliseconds($0))" } ?? "null")}
    """#
    return try JSONDecoder().decode(QuotaWindow.self, from: Data(json.utf8))
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct UsageFormatTests {
    @Test func aFreshReadingShowsWhatIsLeftAndTheReset() throws {
        let line = QuotaLine(.fiveHour, try window(used: 42), now: now)
        #expect(line.leftText == "58% left")
        #expect(line.percentLeft == 58)
        #expect(!line.isLow)
        #expect(line.detail == "Resets in 1 h 58 min")
    }

    @Test func aMissingReadingIsUnavailableNeverZero() throws {
        let line = QuotaLine(.fiveHour, try window(used: nil), now: now)
        #expect(line.leftText == "Unavailable")
        #expect(line.percentLeft == nil)
        #expect(!line.isLow)

        let none = ProviderQuota.all([], now: now)
        #expect(none.map(\.title) == ["Claude", "Codex"])
        #expect(none.allSatisfy { $0.lines.allSatisfy { $0.leftText == "Unavailable" && $0.detail == nil } })
        #expect(none.first?.note == "No reading from Claude yet.")
    }

    @Test func aStaleReadingSaysHowOldItIs() throws {
        #expect(QuotaLine(.fiveHour, try window(used: 42, minutesAgo: 20), now: now).detail == "Resets in 1 h 58 min · read 20 min ago")
        #expect(QuotaLine(.fiveHour, try window(used: 42, minutesAgo: 3 * 60, resetsIn: -5), now: now).detail == "Reset due · read 3 h ago")
        #expect(QuotaLine(.fiveHour, try window(used: 42, minutesAgo: 14), now: now).detail == "Resets in 1 h 58 min")
    }

    @Test func aLowLimitWarns() throws {
        let line = QuotaLine(.weekly, try window(used: 88, resetsIn: 4 * 24 * 60, minutes: 10_080), now: now)
        #expect(line.leftText == "12% left")
        #expect(line.isLow)
        #expect(line.detail?.hasPrefix("Resets ") == true)
        #expect(line.detail?.contains(" in ") == false)
    }

    @Test func theDemoWeekReadsAsTheMockupDoes() async throws {
        var options = DemoHostConnection.Options()
        options.sleep = { _ in }
        let host = LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: { DemoHostConnection(options: options) })
        let model = UsageModel(host: host)
        await model.load()
        #expect(model.error == nil)
        #expect(model.weekTotal == "8.8M")
        #expect(model.weekDetail == "127 requests across 3 projects")
        let quotas = ProviderQuota.all(try #require(model.quotas), now: Date())
        #expect(quotas.map { $0.lines.map(\.leftText) } == [["58% left", "39% left"], ["82% left", "12% left"]])
    }
}
