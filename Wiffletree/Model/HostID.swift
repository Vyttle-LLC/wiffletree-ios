import WiffletreeKit

/// Which host the app shows: the built-in demo or a paired Mac.
enum HostID: Hashable, Sendable {
    case demo
    case paired(KeyID)

    /// As preferences store it: `demo`, or the key id in hex.
    init?(stored: String) {
        if stored == "demo" {
            self = .demo
        } else if let id = KeyID(hex: stored) {
            self = .paired(id)
        } else {
            return nil
        }
    }

    var stored: String {
        switch self {
        case .demo: "demo"
        case .paired(let id): id.hex
        }
    }
}

extension AccessLevel {
    var title: String {
        switch self {
        case .control: "Control"
        case .viewOnly: "View only"
        }
    }

    var explanation: String {
        switch self {
        case .control: "Anything you can do in Wiffletree on the Mac, you can do here."
        case .viewOnly: "This iPhone can read but not answer or send. Change it on the Mac in Remote access."
        }
    }
}

extension HostAddress.Network {
    /// The network's name beside an address, as in "192.168.1.20 · Wi-Fi".
    var title: String {
        switch self {
        case .local: "Wi-Fi"
        case .tailscale: "Tailscale"
        case .otherVPN: "VPN"
        }
    }

    /// How a host is reached over it, in the words of design call 12.
    var route: String {
        switch self {
        case .local: "On Wi-Fi"
        case .tailscale: "Via Tailscale"
        case .otherVPN: "Via VPN"
        }
    }

    var systemImage: String {
        switch self {
        case .local: "wifi"
        case .tailscale, .otherVPN: "network.badge.shield.half.filled"
        }
    }
}
