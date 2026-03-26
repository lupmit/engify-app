import Foundation
import Security

final class KeychainService {
    private let service = "app.engify.desktop"
    private let account = "ai-api-key"

    func saveAPIKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw NSError(domain: "KeychainService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid key"])
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        let status = SecItemAdd(insert as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainService", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Could not store API key"])
        }
    }

    func getAPIKey() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainService", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "API key not found"])
        }

        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "KeychainService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid API key data"])
        }

        return key
    }
}
