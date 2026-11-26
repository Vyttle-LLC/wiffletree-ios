import Foundation

/// Tries every address of a host at once and keeps the first that completes TLS with the
/// pinned key, as `docs/remote-protocol.md` says under "Finding a host".
///
/// Each address after the first starts `headStart` later than the one before, so the preferred
/// ones (the newest answer, then LAN before Tailscale) win when several answer, while a dead one
/// costs only its head start. Another key at a name or a Tailscale address means the host's key
/// changed and ends the race; another key at any other IP address is another machine on the LAN,
/// and the race goes on. Once an address has shown the pinned key, the host is proven and a
/// later key change elsewhere does not overrule it.
///
/// Not yet done: browsing Bonjour for the host's id when no stored address answers, and the
/// key-change rules that browsing adds.
struct AddressRace: Sendable {
    let dialer: any ChannelDialer
    var headStart: Duration = .milliseconds(250)

    func open(_ addresses: [HostAddress], path: String, hostKey: Data) async throws(ConnectionError) -> (HostAddress, any MessageChannel) {
        let result = await withTaskGroup(of: Attempt.self) { group in
            for (position, address) in addresses.enumerated() {
                group.addTask {
                    do {
                        try await Task.sleep(for: headStart * position)
                        return .opened(address, try await dialer.open(address, path: path, hostKey: hostKey))
                    } catch let error as ConnectionError {
                        return .failed(address, error)
                    } catch {
                        return .failed(address, .closed)
                    }
                }
            }
            var outcome: Result<(HostAddress, any MessageChannel), ConnectionError>?
            var lastFailure = ConnectionError.unreachable("No address is known for this host")
            // Says more than a silent address, so it is the failure reported when there is one.
            var otherMachine: ConnectionError?
            for await attempt in group {
                switch attempt {
                case .opened(let address, let channel):
                    guard outcome == nil else {
                        channel.close()
                        continue
                    }
                    outcome = .success((address, channel))
                    group.cancelAll()
                case .failed(let address, .otherKey) where address.namesOneMachine:
                    guard outcome == nil else { continue }
                    outcome = .failure(.keyChanged)
                    group.cancelAll()
                case .failed(let address, .otherKey):
                    otherMachine = .unreachable("\(address.host) is another machine now")
                case .failed(let address, .unreachable(let reason)):
                    lastFailure = .unreachable(reason.isEmpty ? "\(address.host) did not answer" : reason)
                case .failed(let address, _):
                    lastFailure = .unreachable("\(address.host) did not answer")
                }
            }
            return outcome ?? .failure(otherMachine ?? lastFailure)
        }
        return try result.get()
    }

    private enum Attempt: Sendable {
        case opened(HostAddress, any MessageChannel)
        case failed(HostAddress, ConnectionError)
    }
}

extension Array where Element == HostAddress {
    /// The addresses with `address` first, as the one that answered last.
    func answered(at address: HostAddress) -> [HostAddress] {
        [address] + filter { $0 != address }
    }
}
