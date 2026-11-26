import Foundation
import WiffletreeKit

/// What the app remembers between launches, besides the paired hosts themselves.
struct Preferences {
    private let defaults: UserDefaults

    init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedHost: HostID? {
        get { defaults.string(forKey: Key.selectedHost).flatMap(HostID.init(stored:)) }
        nonmutating set { defaults.set(newValue?.stored, forKey: Key.selectedHost) }
    }

    /// The demo host stays in Hosts unless hidden in Settings.
    var showsDemoHost: Bool {
        get { defaults.object(forKey: Key.showsDemoHost) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.showsDemoHost) }
    }

    /// Whether the local network explainer was shown; iOS asks only once.
    var hasExplainedLocalNetwork: Bool {
        get { defaults.bool(forKey: Key.hasExplainedLocalNetwork) }
        nonmutating set { defaults.set(newValue, forKey: Key.hasExplainedLocalNetwork) }
    }

    func lastSeen(_ id: KeyID) -> Date? {
        (defaults.dictionary(forKey: Key.lastSeen)?[id.hex] as? Double).map(Date.init(timeIntervalSince1970:))
    }

    func setLastSeen(_ date: Date?, for id: KeyID) {
        var seen = defaults.dictionary(forKey: Key.lastSeen) ?? [:]
        seen[id.hex] = date?.timeIntervalSince1970
        defaults.set(seen, forKey: Key.lastSeen)
    }

    private enum Key {
        static let selectedHost = "selectedHost"
        static let showsDemoHost = "showsDemoHost"
        static let hasExplainedLocalNetwork = "hasExplainedLocalNetwork"
        static let lastSeen = "lastSeen"
    }
}
