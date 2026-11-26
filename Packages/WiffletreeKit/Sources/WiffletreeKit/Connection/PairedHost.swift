import Foundation
import Synchronization

/// A host this device paired with.
public struct PairedHost: Codable, Equatable, Identifiable, Sendable {
    public let id: KeyID
    public var name: String
    /// SEC1 uncompressed; every connection's TLS is pinned to it.
    public let publicKey: Data
    /// Where the host answered, the last answer first, then the rest in the order the host gave.
    public var addresses: [HostAddress]
    /// What the host lets this device do, as its last connection said.
    public var level: AccessLevel

    public init(name: String, publicKey: Data, addresses: [HostAddress], level: AccessLevel) {
        id = KeyID(publicKey: publicKey)
        self.name = name
        self.publicKey = publicKey
        self.addresses = addresses
        self.level = level
    }
}

/// Where paired hosts are kept. Nothing in a `PairedHost` is secret; the device's key lives in
/// the `KeyStore`.
public protocol PairedHostStore: Sendable {
    func hosts() throws -> [PairedHost]
    /// Adds the host, or replaces the one with its id.
    func save(_ host: PairedHost) throws
    func remove(id: KeyID) throws
}

/// The hosts as one JSON file, by default in Application Support.
public final class FilePairedHostStore: PairedHostStore {
    public let url: URL
    private let lock = Mutex(())

    public init(url: URL = URL.applicationSupportDirectory.appending(path: "Wiffletree/paired-hosts.json")) {
        self.url = url
    }

    public func hosts() throws -> [PairedHost] {
        try lock.withLock { _ in try read() }
    }

    public func save(_ host: PairedHost) throws {
        try lock.withLock { _ in try write(read().replacing(host)) }
    }

    public func remove(id: KeyID) throws {
        try lock.withLock { _ in try write(read().filter { $0.id != id }) }
    }

    private func read() throws -> [PairedHost] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([PairedHost].self, from: Data(contentsOf: url))
    }

    private func write(_ hosts: [PairedHost]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Readable after the first unlock, so reconnects work in the background.
        try JSONEncoder().encode(hosts).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Hosts held only in memory, for tests, previews and the demo.
public final class InMemoryPairedHostStore: PairedHostStore {
    private let stored: Mutex<[PairedHost]>

    public init(_ hosts: [PairedHost] = []) {
        stored = Mutex(hosts)
    }

    public func hosts() -> [PairedHost] {
        stored.withLock { $0 }
    }

    public func save(_ host: PairedHost) {
        stored.withLock { $0 = $0.replacing(host) }
    }

    public func remove(id: KeyID) {
        stored.withLock { $0.removeAll { $0.id == id } }
    }
}

extension [PairedHost] {
    fileprivate func replacing(_ host: PairedHost) -> [PairedHost] {
        guard let index = firstIndex(where: { $0.id == host.id }) else { return self + [host] }
        var hosts = self
        hosts[index] = host
        return hosts
    }
}

extension KeyID: Codable {
    public init(from decoder: any Decoder) throws {
        let hex = try decoder.singleValueContainer().decode(String.self)
        guard let id = KeyID(hex: hex) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a key id: \(hex)"))
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
