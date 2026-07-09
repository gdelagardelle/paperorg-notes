import Foundation
import CryptoKit
import Security

final class EncryptionService: Sendable {
    private let keyTag = "com.paperorg.notes.encryption.key"
    
    func encrypt(data: Data) throws -> Data {
        let key = try getOrCreateKey()
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw EncryptionError.sealFailed
        }
        return combined
    }
    
    func decrypt(data: Data) throws -> Data {
        let key = try getOrCreateKey()
        let sealed = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealed, using: key)
    }
    
    private func getOrCreateKey() throws -> SymmetricKey {
        if let existing = loadKeyFromKeychain() {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try saveKeyToKeychain(keyData)
        return key
    }
    
    private func loadKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }
    
    private func saveKeyToKeychain(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw EncryptionError.keyStorageFailed
        }
    }
}

enum EncryptionError: Error {
    case sealFailed
    case keyStorageFailed
}
