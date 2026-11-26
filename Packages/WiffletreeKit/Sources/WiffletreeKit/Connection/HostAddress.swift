import Foundation
import Network

/// Where a host may answer: a DNS name or an IP address, and a port.
public struct HostAddress: Hashable, Codable, Sendable, CustomStringConvertible {
    /// The port a host listens on unless an address names another.
    public static let defaultPort: UInt16 = 47821

    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16 = Self.defaultPort) {
        self.host = host
        self.port = port
    }

    /// A typed address: `name`, `name:port`, `address:port` or `[ipv6]:port`, the port
    /// defaulting to 47821, as the host's `split_address` reads it.
    public init(parsing text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            let host = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...]
            let port = rest.hasPrefix(":") ? UInt16(rest.dropFirst()) : nil
            self.init(host: host, port: port ?? Self.defaultPort)
        } else if let colon = text.lastIndex(of: ":"), !text[..<colon].contains(":"),
                  let port = UInt16(text[text.index(after: colon)...]) {
            self.init(host: String(text[..<colon]), port: port)
        } else {
            self.init(host: text)
        }
    }

    public var description: String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    /// Whether the address always names the same machine: a DNS name, as a Tailscale name or
    /// `.local`, or a Tailscale address (`100.64.0.0/10`, `fd7a:115c:a1e0::/48`). Another key
    /// there means the host's key changed; any other IP address may pass to another machine.
    public var namesOneMachine: Bool {
        if let ip = IPv4Address(host) {
            let octets = Array(ip.rawValue)
            return octets[0] == 100 && octets[1] & 0xc0 == 64
        }
        if let ip = IPv6Address(host) {
            return Array(ip.rawValue.prefix(6)) == [0xfd, 0x7a, 0x11, 0x5c, 0xa1, 0xe0]
        }
        return true
    }
}
