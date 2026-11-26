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
    @ObservationIgnored private var browser: NWBrowser?

    enum Start { case firstRun, addHost }

    init(app: AppModel, start: Start) {
        self.app = app
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
            found = try QRPayload(scanned: text)
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

    /// Cancel on the confirm sheet: back to the camera for a fresh code.
    func cancelConfirm() {
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
