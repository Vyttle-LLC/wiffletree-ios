import Foundation
import Observation
import WiffletreeKit

/// The app's state: the paired hosts, each with a live connection, the demo host unless hidden,
/// and which host the screens show. With no host chosen, the app shows first run.
@MainActor
@Observable
final class AppModel {
    /// What the model reaches outside itself, so tests can swap the network and storage.
    struct Dependencies {
        var store: any PairedHostStore
        var preferences: Preferences
        var connect: (PairedHost) throws -> any HostConnection
        var demo: () -> any HostConnection
        /// Pairs by a scanned QR code; the pairer keeps the host in `store`.
        var pair: @MainActor (QRPayload) async throws -> PairedHost
        /// How this iPhone appears on the Mac.
        var deviceName: String
        var now: () -> Date = Date.init
    }

    /// Why a host was forgotten without being asked, shown once.
    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let hostName: String
        let reason: String
    }

    /// Paired Macs, in the order they were paired.
    private(set) var hosts: [LiveHost] = []
    /// The demo host, while it is shown.
    private(set) var demo: LiveHost?
    private(set) var selectedID: HostID?
    var notice: Notice?
    let deviceName: String

    @ObservationIgnored private let dependencies: Dependencies

    init(_ dependencies: Dependencies) {
        self.dependencies = dependencies
        deviceName = dependencies.deviceName
        hosts = ((try? dependencies.store.hosts()) ?? []).map(live)
        if dependencies.preferences.showsDemoHost { demo = makeDemo() }
        let stored = dependencies.preferences.selectedHost
        selectedID = stored.flatMap { host($0) == nil ? nil : $0 } ?? hosts.first?.id
    }

    var preferences: Preferences { dependencies.preferences }

    var selected: LiveHost? { selectedID.flatMap(host) }

    /// Every host the Hosts list and the host menu show: the paired Macs, then the demo.
    var listedHosts: [LiveHost] { hosts + [demo].compactMap(\.self) }

    var hasPairedHost: Bool { !hosts.isEmpty }

    func host(_ id: HostID) -> LiveHost? {
        listedHosts.first { $0.id == id }
    }

    func select(_ id: HostID?) {
        selectedID = id
        dependencies.preferences.selectedHost = id
    }

    /// "Try a demo": shows the demo host and opens it.
    func openDemo() {
        showsDemoHost = true
        select(.demo)
    }

    /// Resets the demo's sample data.
    func restartDemo() {
        demo?.restart()
    }

    var showsDemoHost: Bool {
        get { demo != nil }
        set {
            guard newValue != showsDemoHost else { return }
            dependencies.preferences.showsDemoHost = newValue
            if newValue {
                demo = makeDemo()
            } else {
                demo?.stop()
                demo = nil
                if selectedID == .demo { select(hosts.first?.id) }
            }
        }
    }

    /// Pairs with the host a QR code names and connects to it. The caller opens it once the
    /// person has seen the access level it was given.
    func pair(_ payload: QRPayload) async throws -> PairedHost {
        let paired = try await dependencies.pair(payload)
        let replacement = live(paired)
        if let index = hosts.firstIndex(where: { $0.id == replacement.id }) {
            hosts[index].stop()
            hosts[index] = replacement
        } else {
            hosts.append(replacement)
        }
        return paired
    }

    /// Forgets a paired host: its key, its connection and when it was seen. The Mac still lists
    /// this iPhone until it is removed there too.
    func remove(_ id: KeyID) {
        try? dependencies.store.remove(id: id)
        dependencies.preferences.setLastSeen(nil, for: id)
        guard let index = hosts.firstIndex(where: { $0.id == .paired(id) }) else { return }
        hosts.remove(at: index).stop()
        if selectedID == .paired(id) { select(hosts.first?.id) }
    }

    // MARK: - Connections

    private func live(_ host: PairedHost) -> LiveHost {
        let id = host.id
        let preferences = dependencies.preferences
        let store = dependencies.store
        let connect = dependencies.connect
        return LiveHost(
            id: .paired(id),
            paired: host,
            lastSeen: preferences.lastSeen(id),
            connect: { try connect(host) },
            reload: { try? store.hosts().first { $0.id == id } },
            now: dependencies.now,
            onSeen: { preferences.setLastSeen($0, for: id) },
            onStopped: { [weak self] error in self?.stopped(id, name: host.name, error: error) }
        )
    }

    private func makeDemo() -> LiveHost {
        LiveHost(id: .demo, paired: nil, lastSeen: nil, connect: dependencies.demo, now: dependencies.now)
    }

    /// A host that no longer knows this iPhone can't be used until it is paired again, so the
    /// app forgets it and says why. A changed key is kept: one spoofed answer must not make the
    /// phone forget its Mac, so only the person removes it or pairs again.
    private func stopped(_ id: KeyID, name: String, error: ConnectionError) {
        guard error == .unpaired else { return }
        remove(id)
        notice = Notice(hostName: name, reason: error.localizedDescription)
    }
}
