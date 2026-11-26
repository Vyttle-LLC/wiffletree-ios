import Foundation
import Testing
import WiffletreeKit

/// Pairs with a real host and lists its projects over the network. `scripts/e2e/host-e2e.sh`
/// starts the host and runs this with the QR code's payload; without it, it is skipped.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WIFFLETREE_E2E_QR"] != nil), .timeLimit(.minutes(1)))
struct EndToEndTests {
    @Test func pairsByQRCodeAndListsProjects() async throws {
        let environment = ProcessInfo.processInfo.environment
        let payload = try QRPayload(scanned: try #require(environment["WIFFLETREE_E2E_QR"]))
        let store = InMemoryPairedHostStore()
        let device = DeviceKey()

        let host = try await HostPairer(store: store).pair(payload, deviceKey: device, deviceName: "WiffletreeKit end-to-end")
        #expect(host.id == payload.hostID)

        let connection = RemoteHostConnection(host: host, deviceKey: device, store: store, appVersion: "e2e")
        defer { connection.close() }
        let snapshot = try await connection.request(SnapshotCommand())
        print("Connected at \(connection.host.addresses[0]); projects: \(snapshot.projects.map(\.name))")
        #expect(snapshot.projects.contains { $0.name == environment["WIFFLETREE_E2E_PROJECT"] })
        _ = try await connection.request(PingCommand())
    }
}
