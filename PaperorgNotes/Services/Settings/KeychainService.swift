import Foundation
import Security

enum KeychainKey: String {
    case openAIAPIKey = "com.paperorg.notes.openai.apikey"
    case elevenLabsAPIKey = "com.paperorg.notes.elevenlabs.apikey"
    case luxASRAPIKey = "com.paperorg.notes.luxasr.apikey"
    case smtpPassword = "com.paperorg.notes.smtp.password"
    case proAccessToken = "com.paperorg.notes.pro.access"
    case deviceID = "com.paperorg.notes.device.id"
}

final class KeychainService: Sendable {
    func save(_ value: String, for key: KeychainKey) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    func retrieve(for key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func delete(for key: KeychainKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    func deleteAll() {
        for key in [KeychainKey.openAIAPIKey, .elevenLabsAPIKey, .luxASRAPIKey, .smtpPassword, .proAccessToken, .deviceID] {
            delete(for: key)
        }
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
}
