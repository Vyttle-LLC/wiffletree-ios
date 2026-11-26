import SwiftUI
import WiffletreeDesignSystem

extension View {
    /// Presents pairing a Mac over the whole screen.
    func pairingFlow(isPresented: Binding<Bool>, start: PairingFlow.Start) -> some View {
        fullScreenCover(isPresented: isPresented) {
            PairingFlowPresenter(start: start)
        }
    }
}

/// Reads the app model from the environment, which the flow needs from its start.
private struct PairingFlowPresenter: View {
    @Environment(AppModel.self) private var app
    let start: PairingFlow.Start

    var body: some View {
        PairingFlowView(flow: PairingFlow(app: app, start: start))
    }
}

private struct PairingFlowView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var flow: PairingFlow

    init(flow: PairingFlow) {
        _flow = State(initialValue: flow)
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    if !isPaired {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
                }
        }
        .onDisappear { flow.finish() }
    }

    @ViewBuilder private var content: some View {
        switch flow.step {
        case .instructions:
            AddHostInstructions { flow.startScanning() }
        case .localNetwork:
            LocalNetworkExplainer { flow.allowLocalNetwork() }
        case .scanning:
            ScanView(flow: flow)
        case .paired(let host):
            PairedView(name: host.name, level: app.host(.paired(host.id))?.level ?? host.level) {
                app.select(.paired(host.id))
                dismiss()
            }
        }
    }

    private var isPaired: Bool {
        if case .paired = flow.step { true } else { false }
    }
}
