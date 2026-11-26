import Foundation
import WiffletreeDesignSystem
import WiffletreeKit

/// How a host is reached now, in the words of design call 12: "On Wi-Fi", "Via Tailscale" or
/// "Via VPN", and "Unreachable · last seen …". Always a glyph and words, never colour alone.
struct HostStatus: Equatable {
    enum Kind: Equatable {
        case demo, connecting, connected, unreachable, needsUpdate
    }

    let kind: Kind
    /// Such as "On Wi-Fi" or "Unreachable".
    let title: String
    /// Such as "last seen 3 days ago".
    let detail: String?
    let systemImage: String
    let tone: Tone

    var text: String {
        [title, detail].compactMap(\.self).joined(separator: " · ")
    }

    /// - Parameter lastFailure: Why the last try failed, if none has connected since. A retry
    ///   after a failure still reads Unreachable.
    init(state: ConnectionState, isDemo: Bool, lastSeen: Date?, lastFailure: ConnectionError? = nil, now: Date = Date()) {
        if isDemo {
            self.init(.demo, "Built in", detail: "sample data", systemImage: "sparkles", tone: .cyan)
            return
        }
        switch state {
        case .connected(let address, _):
            let network = address.network
            self.init(.connected, network.route, systemImage: network.systemImage, tone: network == .local ? .green : .cyan)
        case .connecting where lastFailure == nil:
            self.init(.connecting, "Connecting…", systemImage: "ellipsis", tone: .subtle)
        case .failed(.incompatible):
            self.init(.needsUpdate, "Needs an update", systemImage: "exclamationmark.triangle", tone: .yellow)
        case .connecting, .waiting, .failed, .closed:
            let seen = lastSeen.map { "last seen \(Self.relative.localizedString(for: $0, relativeTo: now))" }
            self.init(.unreachable, "Unreachable", detail: seen, systemImage: "wifi.slash", tone: .subtle)
        }
    }

    private static var relative: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter
    }

    private init(_ kind: Kind, _ title: String, detail: String? = nil, systemImage: String, tone: Tone) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tone = tone
    }
}
