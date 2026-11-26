import Foundation
import Security
import Synchronization

/// Where the device's long-term key lives.
public protocol KeyStore: Sendable {
    func load() throws -> DeviceKey?
    func save(_ key: DeviceKey) throws
}

/// Serialises `deviceKey()` across every store, so concurrent first calls create one key.
private let deviceKeyCreation = Mutex(())

extension KeyStore {
    /// The stored key, or a new one, stored first.
    public func deviceKey() throws -> DeviceKey {
        try deviceKeyCreation.withLock { _ in
            if let key = try load() { return key }
            let key = DeviceKey()
            try save(key)
            return key
        }
    }
}

/// The key as a Keychain generic password, readable after the first unlock so reconnects work in
/// the background, and never leaving this device, so a restored or new phone pairs again.
public struct KeychainKeyStore: KeyStore {
    public let service: String
    public let account: String

    public init(service: String = "com.vyttle.wiffletree", account: String = "device-key") {
        self.service = service
        self.account = account
    }

    public func load() throws -> DeviceKey? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let secret = result as? Data else { throw KeychainError(status: status) }
        return try DeviceKey(secret: secret)
    }

    /// Replaces the stored key in place, so a failed write never leaves the device without one.
    public func save(_ key: DeviceKey) throws {
        let attributes: [CFString: Any] = [
            kSecValueData: key.secret,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updated = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        guard updated == errSecItemNotFound else {
            guard updated == errSecSuccess else { throw KeychainError(status: updated) }
            return
        }
        let added = SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true
        ]
    }
}

public struct KeychainError: Error, Equatable, Sendable {
    public let status: OSStatus
}

/// A key held only in memory, for tests and previews.
public final class InMemoryKeyStore: KeyStore {
    private let key: Mutex<DeviceKey?>

    public init(key: DeviceKey? = nil) {
        self.key = Mutex(key)
    }

    public func load() -> DeviceKey? {
        key.withLock { $0 }
    }

    public func save(_ key: DeviceKey) {
        self.key.withLock { $0 = key }
    }
}
