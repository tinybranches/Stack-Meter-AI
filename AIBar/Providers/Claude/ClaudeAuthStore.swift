import Foundation
import Security

struct ClaudeCredentials: Equatable, Sendable {
    let sessionKey: String
    let organizationID: String?
}

enum ClaudeAuthStore {
    private static let service = "com.stackmeter.ai.claude"
    private static let account = "session"

    static var isAuthorized: Bool {
        (try? loadFromKeychain()) != nil
    }

    static func loadAuthorized() throws -> ClaudeCredentials {
        guard let credentials = try loadFromKeychain() else {
            throw ProviderError.notAuthenticated("auth.claude.needed")
        }
        return credentials
    }

    static func save(_ credentials: ClaudeCredentials) throws {
        var payload: [String: Any] = ["session_key": credentials.sessionKey]
        if let org = credentials.organizationID {
            payload["organization_id"] = org
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ProviderError.badResponse("Could not save Claude credentials (\(status)).")
        }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func loadFromKeychain() throws -> ClaudeCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionKey = json["session_key"] as? String, !sessionKey.isEmpty
        else {
            throw ProviderError.badResponse("Could not read Claude credentials (\(status)).")
        }
        return ClaudeCredentials(
            sessionKey: sessionKey,
            organizationID: json["organization_id"] as? String
        )
    }
}
