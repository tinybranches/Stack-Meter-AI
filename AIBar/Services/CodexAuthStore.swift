import Foundation
import Security

struct CodexCredentials: Equatable, Sendable {
    let accessToken: String
    let accountID: String?
    let refreshToken: String?
}

/// Explicit Codex authorization: credentials live in Keychain only after the user authorizes.
enum CodexAuthStore {
    private static let service = "com.stackmeter.ai.codex"
    private static let account = "session"

    static var defaultCLIAuthURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("auth.json")
    }

    static var isAuthorized: Bool {
        (try? loadFromKeychain()) != nil
    }

    static var hasCLILoginAvailable: Bool {
        FileManager.default.fileExists(atPath: defaultCLIAuthURL.path)
    }

    static func loadAuthorized() throws -> CodexCredentials {
        guard let credentials = try loadFromKeychain() else {
            throw ProviderError.notAuthenticated("auth.needed")
        }
        return credentials
    }

    /// User-initiated: copy tokens from Codex CLI `auth.json` into Stack Meter AI Keychain.
    @discardableResult
    static func authorizeFromCLILogin() throws -> CodexCredentials {
        let credentials = try readCLIAuthFile(from: defaultCLIAuthURL)
        try saveToKeychain(credentials)
        return credentials
    }

    static func saveToKeychain(_ credentials: CodexCredentials) throws {
        var payload: [String: Any] = [
            "access_token": credentials.accessToken,
        ]
        if let accountID = credentials.accountID {
            payload["account_id"] = accountID
        }
        if let refreshToken = credentials.refreshToken {
            payload["refresh_token"] = refreshToken
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])

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
            throw ProviderError.badResponse("Could not save Codex credentials to Keychain (\(status)).")
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

    static func readCLIAuthFile(from url: URL) throws -> CodexCredentials {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProviderError.notAuthenticated("auth.cliMissing")
        }

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tokens = json?["tokens"] as? [String: Any]

        guard let accessToken = tokens?["access_token"] as? String, !accessToken.isEmpty else {
            throw ProviderError.notAuthenticated("auth.cliBadToken")
        }

        return CodexCredentials(
            accessToken: accessToken,
            accountID: tokens?["account_id"] as? String,
            refreshToken: tokens?["refresh_token"] as? String
        )
    }

    private static func loadFromKeychain() throws -> CodexCredentials? {
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
        guard status == errSecSuccess, let data = item as? Data else {
            throw ProviderError.badResponse("Could not read Codex credentials from Keychain (\(status)).")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let accessToken = json?["access_token"] as? String, !accessToken.isEmpty else {
            return nil
        }

        return CodexCredentials(
            accessToken: accessToken,
            accountID: json?["account_id"] as? String,
            refreshToken: json?["refresh_token"] as? String
        )
    }
}
