import Foundation
import Network
import Observation
import WiffletreeKit

/// Pairing a Mac, from the steps on the Mac or the local network explainer to the Paired screen.
@MainActor
@Observable
final class PairingFlow {
    enum Step: Equatable {
        /// Add a Mac: the three steps on the Mac.
        case instructions
        /// Shown once, before iOS's one-shot local network prompt.
        case localNetwork
        case scanning
        case paired(PairedHost)
    }

    private(set) var step: Step
    /// A code read and waiting for the person to confirm.
    var found: QRPayload?
    private(set) var isPairing = false
    /// Why the last code or pairing failed.
    private(set) var error: String?

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let replacing: KeyID?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var browser: NWBrowser?
    /// A code the person cancelled, ignored for a moment so the camera, still on it, doesn't
    /// reopen the sheet at once.
    @ObservationIgnored private var declined: (payload: QRPayload, until: Date)?

    /// How long a cancelled code is ignored.
    static let declinePause: TimeInterval = 3

    enum Start: Equatable {
        case firstRun, addHost
        /// Pairing a host whose key changed; the new pairing replaces it.
        case pairAgain(KeyID)
    }

    init(app: AppModel, start: Start, now: @escaping () -> Date = Date.init) {
        self.app = app
        self.now = now
        if case .pairAgain(let id) = start { replacing = id } else { replacing = nil }
        step = .instructions
        if start == .firstRun { step = nextAfterInstructions }
    }

    /// The Add a Mac sheet's Scan QR code.
    func startScanning() {
        step = nextAfterInstructions
    }

    /// The explainer's Continue: asks iOS for local network access, which its prompt then
    /// shows over the camera.
    func allowLocalNetwork() {
        app.preferences.hasExplainedLocalNetwork = true
        let browser = NWBrowser(for: .bonjour(type: "_wiffletree._tcp", domain: nil), using: .tcp)
        browser.start(queue: .main)
        self.browser = browser
        step = .scanning
    }

    /// A QR code's text: a pairing code opens the confirm sheet; anything else says so and
    /// keeps scanning.
    func scanned(_ text: String) {
        guard found == nil, !isPairing else { return }
        do {
            let payload = try QRPayload(scanned: text)
            if let declined, declined.payload == payload, now() < declined.until { return }
            found = payload
            error = nil
        } catch {
            self.error = "That isn't a Wiffletree pairing code. On your Mac, choose Connect a phone."
        }
    }

    func confirm() async {
        guard let payload = found, !isPairing else { return }
        isPairing = true
        defer { isPairing = false }
        do {
            let host = try await app.pair(payload)
            found = nil
            error = nil
            step = .paired(host)
            finish()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// The Paired screen's Open: shows the new host, then forgets the one whose key changed.
    /// The old host stays until now, so the shell presenting this flow isn't torn down first.
    func open() {
        guard case .paired(let host) = step else { return }
        app.select(.paired(host.id))
        if let replacing, replacing != host.id { app.remove(replacing) }
    }

    /// Cancel on the confirm sheet: back to the camera for a fresh code.
    func cancelConfirm() {
        guard let payload = found else { return }
        declined = (payload, now().addingTimeInterval(Self.declinePause))
        found = nil
        error = nil
    }

    /// Stops asking for the local network.
    func finish() {
        browser?.cancel()
        browser = nil
    }

    private var nextAfterInstructions: Step {
        app.preferences.hasExplainedLocalNetwork ? .scanning : .localNetwork
    }
}
