import WiffletreeKit

/// What a screen whose actions need the host says while the host is not connected.
struct ConnectionNotice: Equatable {
    let text: String
    /// A try is under way or follows shortly, so the notice shows a spinner.
    let isRetrying: Bool
}

extension LiveHost {
    /// Nil while connected; else whether the app is reconnecting or has stopped.
    var connectionNotice: ConnectionNotice? {
        switch state {
        case .connected: nil
        case .connecting where lastFailure == nil: ConnectionNotice(text: "Connecting to \(name)…", isRetrying: true)
        case .connecting, .waiting: ConnectionNotice(text: "Reconnecting to \(name)…", isRetrying: true)
        case .failed, .closed: ConnectionNotice(text: "Not connected to \(name)", isRetrying: false)
        }
    }

    /// Why a request failed, in words that name this host.
    func failureText(_ error: any Error) -> String {
        error as? ConnectionError == .notConnected
            ? "Not connected to \(name). Try again."
            : error.localizedDescription
    }
}
