import Foundation
import Observation
import WiffletreeKit

/// The host's account limits and its last week of tokens, read again when the host says usage
/// changed. Both cover the whole host, every project and provider.
@MainActor
@Observable
final class UsageModel {
    static let days = 7

    let host: LiveHost
    private(set) var quotas: [QuotaReading]?
    private(set) var week: UsageReport?
    /// Why the last read failed, until one succeeds.
    private(set) var error: String?

    init(host: LiveHost) {
        self.host = host
    }

    /// Reads now, then each time the host reports a usage change, until cancelled.
    func follow() async {
        await load()
        for await event in host.events() where event.kind == .usage {
            await load()
        }
    }

    func load() async {
        do {
            async let quotas = host.connection.request(QuotasCommand())
            async let week = host.connection.request(UsageCommand(days: Self.days))
            (self.quotas, self.week) = try await (quotas, week)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// The week's tokens as the row says them, such as "8.8M"; nil until read.
    var weekTotal: String? {
        week.map { Int($0.totals.total).formatted(.number.notation(.compactName)) }
    }

    /// Such as "127 requests across 3 projects".
    var weekDetail: String? {
        guard let week else { return nil }
        let projects = Set(week.coordinators.map(\.project)).count
        let requests = "\(week.totals.requests.formatted()) \(week.totals.requests == 1 ? "request" : "requests")"
        return projects == 0 ? requests : "\(requests) across \(projects) \(projects == 1 ? "project" : "projects")"
    }
}
