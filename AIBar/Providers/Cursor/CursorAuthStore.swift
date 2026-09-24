import Foundation
import Security

struct CursorCredentials: Equatable, Sendable {
    let accessToken: String
}

enum CursorAuthStore {
    private static let service = "com.stackmeter.ai.cursor"
    private static let account = "session"

    static var defaultStateDB: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    static var isAuthorized: Bool {
        (try? loadFromKeychain()) != nil
    }

    static var hasLocalCursorLogin: Bool {
        FileManager.default.fileExists(atPath: defaultStateDB.path)
    }

    static func loadAuthorized() throws -> CursorCredentials {
        guard let credentials = try loadFromKeychain() else {
            throw ProviderError.notAuthenticated("auth.cursor.needed")
        }
        return credentials
    }

    @discardableResult
    static func authorizeFromLocalIDE() async throws -> CursorCredentials {
        let dbURL = defaultStateDB
        let token = try await Task.detached(priority: .userInitiated) {
            try readAccessToken(from: dbURL)
        }.value
        let credentials = CursorCredentials(accessToken: token)
        try saveToKeychain(credentials)
        return credentials
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func readAccessToken(from dbURL: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw ProviderError.notAuthenticated("auth.cursor.noIDE")
        }

        // Prefer sqlite3 CLI for reliability without shipping a SQLite wrapper.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            dbURL.path,
            "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            throw ProviderError.notAuthenticated("auth.cursor.noToken")
        }
        // VS Code sometimes stores strings as JSON-quoted values.
        if token.hasPrefix("\""), let decoded = try? JSONDecoder().decode(String.self, from: Data(token.utf8)) {
            return decoded
        }
        return token
    }

    private static func saveToKeychain(_ credentials: CursorCredentials) throws {
        let data = Data(credentials.accessToken.utf8)
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
            throw ProviderError.badResponse("Could not save Cursor credentials (\(status)).")
        }
    }

    private static func loadFromKeychain() throws -> CursorCredentials? {
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
              let token = String(data: data, encoding: .utf8), !token.isEmpty
        else {
            throw ProviderError.badResponse("Could not read Cursor credentials (\(status)).")
        }
        return CursorCredentials(accessToken: token)
    }
}
