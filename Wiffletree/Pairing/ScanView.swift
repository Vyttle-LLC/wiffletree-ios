import SwiftUI
import WiffletreeDesignSystem
import WiffletreeKit

/// The camera with a framing square, always dark as the iOS camera is. A code read opens the
/// confirm sheet.
struct ScanView: View {
    @Environment(AppModel.self) private var app
    @Bindable var flow: PairingFlow
    @State private var access: CameraAccess?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Tidal.tide, Tidal.blueTeal, Tidal.deepTeal], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if access == .allowed {
                QRScanner(isScanning: flow.found == nil) { flow.scanned($0) }
                    .ignoresSafeArea()
                Viewfinder()
            }
            VStack(spacing: 16) {
                Spacer()
                message
                #if DEBUG
                // The Simulator has no camera: paste the QR code's text from the Mac instead.
                Button("Paste pairing code", systemImage: "doc.on.clipboard") {
                    if let text = UIPasteboard.general.string { flow.scanned(text) }
                }
                .buttonStyle(.tidal(.gray))
                #endif
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .foregroundStyle(Tidal.paper)
        .environment(\.colorScheme, .dark)
        .navigationTitle("Scan the QR code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { access = await CameraAccess.request() }
        .sheet(isPresented: Binding(get: { flow.found != nil }, set: { if !$0 { flow.cancelConfirm() } })) {
            if let payload = flow.found {
                ConfirmPairingSheet(payload: payload, deviceName: app.deviceName, flow: flow)
            }
        }
    }

    @ViewBuilder private var message: some View {
        if let error = flow.error, flow.found == nil {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
        }
        switch access {
        case .allowed, nil:
            Text("On your Mac, open Wiffletree, go to **Settings › Remote access** and choose **Connect a phone**.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
        case .denied:
            VStack(spacing: 12) {
                Text("Wiffletree needs the camera to scan the pairing code your Mac shows.")
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.tidal(.filled))
            }
        case .unsupported:
            Text("This device has no camera that can scan the code.")
                .multilineTextAlignment(.center)
        }
    }
}

/// The square a code locks into, with the camera dimmed around it.
private struct Viewfinder: View {
    private let side: CGFloat = 250

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Tidal.deepTeal.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .frame(width: side, height: side)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .ignoresSafeArea()
            Corners()
                .stroke(Tidal.paper, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: side, height: side)
        }
        .allowsHitTesting(false)
    }
}

/// The four corner marks of the viewfinder.
private struct Corners: Shape {
    func path(in rect: CGRect) -> Path {
        let arm: CGFloat = 46
        let radius: CGFloat = 28
        var path = Path()
        for (corner, angle) in [
            (CGPoint(x: rect.minX, y: rect.minY), 180.0),
            (CGPoint(x: rect.maxX, y: rect.minY), 270.0),
            (CGPoint(x: rect.maxX, y: rect.maxY), 0.0),
            (CGPoint(x: rect.minX, y: rect.maxY), 90.0),
        ] {
            let inward = CGPoint(x: corner.x == rect.minX ? 1 : -1, y: corner.y == rect.minY ? 1 : -1)
            let center = CGPoint(x: corner.x + inward.x * radius, y: corner.y + inward.y * radius)
            path.move(to: CGPoint(x: corner.x, y: corner.y + inward.y * arm))
            path.addLine(to: CGPoint(x: corner.x, y: center.y))
            path.addArc(center: center, radius: radius, startAngle: .degrees(angle), endAngle: .degrees(angle + 90), clockwise: false)
            path.addLine(to: CGPoint(x: corner.x + inward.x * arm, y: corner.y))
        }
        return path
    }
}
