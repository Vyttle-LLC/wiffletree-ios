import UIKit
import WiffletreeKit

extension AppModel.Dependencies {
    /// The real network, the Keychain and Application Support.
    @MainActor
    static func live() -> Self {
        let store = FilePairedHostStore()
        let keyStore = KeychainKeyStore()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let deviceName = UIDevice.current.name
        return Self(
            store: store,
            preferences: Preferences(),
            connect: { host in
                RemoteHostConnection(host: host, deviceKey: try keyStore.deviceKey(), store: store, appVersion: appVersion)
            },
            demo: { DemoHostConnection() },
            pair: { payload in
                try await HostPairer(store: store).pair(payload, deviceKey: try keyStore.deviceKey(), deviceName: deviceName)
            },
            deviceName: deviceName
        )
    }
}
