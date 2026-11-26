import Foundation
import WiffletreeKit

/// A provider's limits as the Usage card shows them: what is left of each window, as the
/// desktop does.
struct ProviderQuota: Identifiable {
    let provider: String
    let lines: [QuotaLine]
    /// Why the provider has no reading, such as the host's error.
    let note: String?

    var id: String { provider }

    var title: String { Self.name(of: provider) }

    static func name(of provider: String) -> String {
        switch provider {
        case "claude": "Claude"
        case "codex": "Codex"
        default: provider.capitalized
        }
    }

    /// Claude and Codex always, in that order, then any other provider the host reports. A
    /// provider without a reading reads Unavailable, never zero.
    static func all(_ readings: [QuotaReading], now: Date) -> [ProviderQuota] {
        let known = ["claude", "codex"]
        let others = readings.map(\.provider).filter { !known.contains($0) }
        return (known + others).map { provider in
            let reading = readings.first { $0.provider == provider }
            let lines = QuotaLine.Window.allCases.map { window in
                QuotaLine(window, reading?.busiest(window), now: now)
            }
            let note = reading == nil ? "No reading from \(name(of: provider)) yet." : reading?.error
            return ProviderQuota(provider: provider, lines: lines, note: note)
        }
    }
}

/// One window's line: its name, what is left, the bar, and when it resets.
struct QuotaLine: Identifiable {
    enum Window: CaseIterable {
        case fiveHour, weekly

        var minutes: UInt64 {
            switch self {
            case .fiveHour: 5 * 60
            case .weekly: 7 * 24 * 60
            }
        }

        var title: String {
            switch self {
            case .fiveHour: "5-hour"
            case .weekly: "Weekly"
            }
        }
    }

    /// A reading older than this reads as stale, as on the desktop.
    static let staleAfter: TimeInterval = 15 * 60
    /// Below this share left, the line warns.
    static let lowShare = 25.0

    let window: Window
    /// What is left, 0 to 100; nil when the provider has not reported it.
    let percentLeft: Double?
    /// Such as "Resets in 1 h 58 min" or "Resets Friday 14:00", then the reading's age when
    /// stale.
    let detail: String?

    var id: Window { window }
    var title: String { window.title }
    var leftText: String { percentLeft.map { "\(Int($0.rounded()))% left" } ?? "Unavailable" }
    var isLow: Bool { percentLeft.map { $0 < Self.lowShare } ?? false }

    init(_ window: Window, _ reading: QuotaWindow?, now: Date) {
        self.window = window
        percentLeft = reading?.usedPercent.map { min(max(100 - $0, 0), 100) }
        guard let reading else {
            detail = nil
            return
        }
        let observed = Date(milliseconds: reading.observedAt)
        let resets = reading.resetsAt.map { Date(milliseconds: $0) }
        let isStale = now.timeIntervalSince(observed) > Self.staleAfter || resets.map { $0 <= now } ?? false
        detail = [
            resets.map { Self.resetText($0, now: now) },
            isStale ? "read \(Self.age(of: observed, now: now))" : nil,
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
        .nilIfEmpty
    }

    private static func resetText(_ date: Date, now: Date) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes <= 0 { return "Reset due" }
        if minutes < 24 * 60 {
            return minutes < 60 ? "Resets in \(minutes) min" : "Resets in \(minutes / 60) h \(minutes % 60) min"
        }
        return "Resets \(date.formatted(.dateTime.weekday(.wide))) \(date.formatted(date: .omitted, time: .shortened))"
    }

    private static func age(of date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<60: return "\(minutes) min ago"
        case ..<(24 * 60): return "\(minutes / 60) h ago"
        default: return "\(minutes / (24 * 60)) d ago"
        }
    }
}

private extension QuotaReading {
    /// The most-used window of that length; Codex can report several per length.
    func busiest(_ window: QuotaLine.Window) -> QuotaWindow? {
        windows
            .filter { $0.durationMinutes == window.minutes }
            .max { ($0.usedPercent ?? -1) < ($1.usedPercent ?? -1) }
    }
}

private extension Date {
    init(milliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
