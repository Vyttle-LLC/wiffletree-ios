import SwiftUI
import WiffletreeDesignSystem
import WiffletreeKit

/// Shown once before iOS's one-shot local network prompt, saying why to allow it.
struct LocalNetworkExplainer: View {
    let onContinue: () -> Void

    var body: some View {
        ExplainerLayout(art: ExplainerArt("wifi"), title: "Find your Mac on this network") {
            Text("Next, iOS asks whether Wiffletree may use your local network. Allow it so your iPhone can reach your Mac.")
        } points: {
            Point(systemImage: "lock.shield", title: "Only Macs you pair", detail: "The QR code carries your Mac's key. Wiffletree talks to that Mac and nothing else.")
            Point(systemImage: "eye.slash", title: "Nothing collected", detail: "No account and no analytics. Traffic is encrypted between your iPhone and your Mac.")
            Point(systemImage: "network.badge.shield.half.filled", title: "Away from home", detail: "Turn on Tailscale or your VPN on both devices. Wiffletree tries every address it knows.")
        } action: {
            Button("Continue", action: onContinue)
                .buttonStyle(.tidal(.filled))
        }
    }
}

/// Add a Mac: the three steps on the Mac, then the camera.
struct AddHostInstructions: View {
    let onScan: () -> Void

    var body: some View {
        ExplainerLayout(art: ExplainerArt("desktopcomputer"), title: "Add a Mac") {
            EmptyView()
        } points: {
            Point(step: 1, title: "Open Wiffletree on the Mac", detail: "Download it from GitHub Releases if it isn't there yet.")
            Point(step: 2, title: "Settings › Remote access", detail: "Turn on “Let other devices use this Mac's Wiffletree”.")
            Point(step: 3, title: "Choose Connect a phone", detail: "A QR code appears. Scan it here.")
        } action: {
            Button("Scan QR code", systemImage: "qrcode.viewfinder", action: onScan)
                .buttonStyle(.tidal(.filled))
        }
    }
}

/// The access level the Mac gave, shown, not chosen (design call 13).
struct PairedView: View {
    let name: String
    let level: AccessLevel
    let onOpen: () -> Void

    var body: some View {
        ExplainerLayout(art: ExplainerArt("checkmark", tone: .green), title: "\(name) is paired") {
            Text("Your Mac gave this iPhone **\(level.title)**. \(level.explanation)")
        } points: {
            EmptyView()
        } action: {
            Button("Open \(name)", action: onOpen)
                .buttonStyle(.tidal(.filled))
        }
    }
}

/// Art, a title, a lead paragraph, points and one action at the foot, as the mockups' explainers.
private struct ExplainerLayout<Lead: View, Points: View, Action: View>: View {
    let art: ExplainerArt
    let title: String
    @ViewBuilder let lead: Lead
    @ViewBuilder let points: Points
    @ViewBuilder let action: Action

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    art.padding(.top, 40).padding(.bottom, 22)
                    Text(title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)
                    lead
                        .foregroundStyle(Tidal.subtle)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 24)
                    VStack(alignment: .leading, spacing: 18) { points }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            action.padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .foregroundStyle(Tidal.text)
        .background(Tidal.base)
    }
}

/// One point of an explainer, led by a glyph or a step number.
private struct Point: View {
    private enum Lead { case symbol(String), step(Int) }
    private let lead: Lead
    private let title: String
    private let detail: String

    init(systemImage: String, title: String, detail: String) {
        self.init(.symbol(systemImage), title: title, detail: detail)
    }

    init(step: Int, title: String, detail: String) {
        self.init(.step(step), title: title, detail: detail)
    }

    private init(_ lead: Lead, title: String, detail: String) {
        self.lead = lead
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                switch lead {
                case .symbol(let name):
                    Image(systemName: name).font(.title2).foregroundStyle(Tidal.accent)
                case .step(let number):
                    Text(number, format: .number)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tidal.onAccent)
                        .frame(width: 24, height: 24)
                        .background(Tidal.accent, in: .circle)
                }
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).foregroundStyle(Tidal.subtle)
            }
            .font(.subheadline)
        }
    }
}
