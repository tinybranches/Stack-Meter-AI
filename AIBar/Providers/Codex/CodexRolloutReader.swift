import Foundation

/// Best-effort token totals from local Codex session/rollout JSONL files.
struct CodexRolloutReader: Sendable {
    private let sessionsDirectory: URL

    init(sessionsDirectory: URL? = nil) {
        if let sessionsDirectory {
            self.sessionsDirectory = sessionsDirectory
        } else {
            self.sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex")
                .appendingPathComponent("sessions")
        }
    }

    func tokenSummary() async -> TokenSummary {
        await Task.detached(priority: .utility) { [sessionsDirectory] in
            Self.scan(sessionsDirectory: sessionsDirectory)
        }.value
    }

    private static func scan(sessionsDirectory: URL) -> TokenSummary {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDirectory.path) else {
            return TokenSummary()
        }

        let calendar = Calendar.current
        let now = Date()
        guard let startOfDay = calendar.dateInterval(of: .day, for: now)?.start,
              let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start
        else {
            return TokenSummary()
        }

        var today = 0
        var month = 0
        var found = false
        var filesRead = 0
        let maxFiles = 250

        let enumerator = fm.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension == "jsonl" || item.lastPathComponent.contains("rollout") else {
                continue
            }

            let values = try? item.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let modified = values?.contentModificationDate ?? .distantPast
            if modified < startOfMonth { continue }

            filesRead += 1
            if filesRead > maxFiles { break }

            let tokens = extractTokens(from: item)
            guard tokens > 0 else { continue }
            found = true
            month += tokens
            if modified >= startOfDay {
                today += tokens
            }
        }

        guard found else { return TokenSummary() }
        return TokenSummary(today: today, month: month)
    }

    private static func extractTokens(from url: URL) -> Int {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }

        var total = 0
        // Read up to 2 MB from the end for recent events.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > 2_000_000 {
            try? handle.seek(toOffset: UInt64(size - 2_000_000))
        }

        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else {
            return 0
        }

        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            total += deepestTokenCount(obj)
        }
        return total
    }

    private static func deepestTokenCount(_ value: Any) -> Int {
        if let dict = value as? [String: Any] {
            let keys = ["total_tokens", "token_count", "input_tokens", "output_tokens", "tokens"]
            var sum = 0
            for key in keys {
                if let number = dict[key] as? Int {
                    sum += number
                } else if let number = dict[key] as? Double {
                    sum += Int(number)
                }
            }
            if sum > 0 { return sum }
            return dict.values.reduce(0) { $0 + deepestTokenCount($1) }
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + deepestTokenCount($1) }
        }
        return 0
    }
}
