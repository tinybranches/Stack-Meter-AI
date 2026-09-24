import Foundation
import Security
import CommonCrypto

/// Reads `sessionKey` / `lastActiveOrg` from the Claude Desktop Chromium cookie DB
/// (same approach as other Claude usage trackers on macOS).
enum ClaudeDesktopSession {
    static let cookiesURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/Cookies")

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: cookiesURL.path)
    }

    static func readCredentials() throws -> ClaudeCredentials {
        guard isAvailable else {
            throw ProviderError.notAuthenticated("auth.claude.noDesktop")
        }

        let key = try deriveAESKey(from: try readSafeStorageSecret())
        let encrypted = try readEncryptedCookies()
        guard let sessionBlob = encrypted["sessionKey"] else {
            throw ProviderError.notAuthenticated("auth.claude.noDesktopSession")
        }

        let sessionKey = try decryptCookieValue(sessionBlob, key: key)
        guard sessionKey.hasPrefix("sk-ant-"), !sessionKey.isEmpty else {
            throw ProviderError.badResponse("Claude Desktop sessionKey looks invalid.")
        }

        var orgID: String?
        if let orgBlob = encrypted["lastActiveOrg"] {
            let org = (try? decryptCookieValue(orgBlob, key: key))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let org, !org.isEmpty {
                orgID = org
            }
        }

        return ClaudeCredentials(sessionKey: sessionKey, organizationID: orgID)
    }

    // MARK: - Keychain / OSCrypt

    private static func readSafeStorageSecret() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecAttrAccount as String: "Claude Key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, !data.isEmpty else {
            // Fallback: `security -w` (string password form) if SecItem returns differently.
            if let fallback = try? readSafeStorageSecretViaSecurityCLI(), !fallback.isEmpty {
                return fallback
            }
            throw ProviderError.notAuthenticated("auth.claude.keychainDenied")
        }
        return data
    }

    private static func readSafeStorageSecretViaSecurityCLI() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", "Claude Safe Storage",
            "-a", "Claude Key",
            "-w",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ProviderError.notAuthenticated("auth.claude.keychainDenied")
        }
        let raw = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: raw, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw ProviderError.notAuthenticated("auth.claude.keychainDenied")
        }
        return Data(text.utf8)
    }

    private static func deriveAESKey(from secret: Data) throws -> Data {
        var derived = Data(count: kCCKeySizeAES128)
        let salt = Data("saltysalt".utf8)
        let status: Int32 = derived.withUnsafeMutableBytes { derivedBytes in
            secret.withUnsafeBytes { secretBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        secretBytes.bindMemory(to: Int8.self).baseAddress,
                        secret.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        kCCKeySizeAES128
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw ProviderError.badResponse("Could not derive Claude cookie key (\(status)).")
        }
        return derived
    }

    private static func decryptCookieValue(_ blob: Data, key: Data) throws -> String {
        guard blob.count > 3, String(data: blob.prefix(3), encoding: .utf8) == "v10" else {
            throw ProviderError.badResponse("Claude cookie is missing v10 prefix.")
        }
        let cipher = blob.dropFirst(3)
        var outCount = cipher.count + kCCBlockSizeAES128
        var out = Data(count: outCount)
        let iv = Data(repeating: UInt8(ascii: " "), count: kCCBlockSizeAES128)

        let status: CCCryptorStatus = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                cipher.withUnsafeBytes { cipherBytes in
                    out.withUnsafeMutableBytes { outBytes in
                        var moved = 0
                        let st = CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            cipher.count,
                            outBytes.baseAddress,
                            outCount,
                            &moved
                        )
                        outCount = moved
                        return st
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw ProviderError.badResponse("Could not decrypt Claude cookie (\(status)).")
        }
        out.count = outCount

        // Chromium cookie plaintext is often `[32-byte prefix][value]`.
        if out.count > 32,
           let prefixed = String(data: out.dropFirst(32), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !prefixed.isEmpty
        {
            return prefixed
        }
        guard let plain = String(data: out, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !plain.isEmpty
        else {
            throw ProviderError.badResponse("Claude cookie plaintext is empty.")
        }
        return plain
    }

    // MARK: - SQLite

    private static func readEncryptedCookies() throws -> [String: Data] {
        // Copy — Claude Desktop may hold a WAL lock on the live DB.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("stackmeter-claude-cookies-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.copyItem(at: cookiesURL, to: temp)
        // Best-effort WAL/SHM companions
        let wal = URL(fileURLWithPath: cookiesURL.path + "-wal")
        let shm = URL(fileURLWithPath: cookiesURL.path + "-shm")
        if FileManager.default.fileExists(atPath: wal.path) {
            try? FileManager.default.copyItem(at: wal, to: URL(fileURLWithPath: temp.path + "-wal"))
        }
        if FileManager.default.fileExists(atPath: shm.path) {
            try? FileManager.default.copyItem(at: shm, to: URL(fileURLWithPath: temp.path + "-shm"))
        }
        defer {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: temp.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: temp.path + "-shm"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            temp.path,
            """
            SELECT name, hex(encrypted_value) FROM cookies
            WHERE name IN ('sessionKey', 'lastActiveOrg')
              AND host_key LIKE '%claude.ai%';
            """,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ProviderError.badResponse("Could not read Claude Desktop cookies DB.")
        }

        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var result: [String: Data] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let data = Data(hexString: parts[1]), !data.isEmpty else { continue }
            result[parts[0]] = data
        }
        return result
    }
}

private extension Data {
    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count.isMultiple(of: 2), !cleaned.isEmpty else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index ..< next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
