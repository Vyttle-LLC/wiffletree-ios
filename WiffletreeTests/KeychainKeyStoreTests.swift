import Foundation
import Security
import Testing
import WiffletreeKit

/// Hosted in the app, because the Keychain needs a signed app's entitlements; a bare package
/// test bundle gets `errSecMissingEntitlement`.
struct KeychainKeyStoreTests {
    @Test func keepsTheKeyAndReplacesIt() throws {
        let store = KeychainKeyStore(service: "com.vyttle.wiffletree.tests.\(UUID())")
        defer {
            SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: store.service] as CFDictionary)
        }
        #expect(try store.load() == nil)
        let created = try store.deviceKey()
        #expect(try store.load()?.id == created.id)
        let replacement = DeviceKey()
        try store.save(replacement)
        #expect(try store.load()?.id == replacement.id)
    }
}
