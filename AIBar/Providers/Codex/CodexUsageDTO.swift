import Foundation

/// Defensive DTOs for undocumented ChatGPT Codex usage endpoints.
struct CodexUsageResponse: Decodable, Sendable {
    let rateLimit: CodexRateLimit?
    let credits: CodexCredits?
    let planType: String?
    let planName: String?
    let tokenUsage: CodexTokenUsage?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
        case credits
        case planType = "plan_type"
        case planName = "plan_name"
        case tokenUsage = "token_usage"
    }
}

struct CodexRateLimit: Decodable, Sendable {
    let primaryWindow: CodexRateWindowDTO?
    let secondaryWindow: CodexRateWindowDTO?
    let limitReached: Bool?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
        case limitReached = "limit_reached"
    }
}

struct CodexRateWindowDTO: Decodable, Sendable {
    let usedPercent: Double?
    let remainingPercent: Double?
    let resetAfterSeconds: Int?
    let resetAt: Double?
    let limitWindowSeconds: Int?
    let limitReached: Bool?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case remainingPercent = "remaining_percent"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
        case limitReached = "limit_reached"
    }

    var normalizedUsedPercent: Double {
        if let usedPercent {
            return clamp(usedPercent)
        }
        if let remainingPercent {
            return clamp(100 - remainingPercent)
        }
        return 0
    }

    private func clamp(_ value: Double) -> Double {
        max(0, min(100, value))
    }
}

struct CodexCredits: Decodable, Sendable {
    let balance: FlexibleNumber?
    let hasCredits: Bool?

    enum CodingKeys: String, CodingKey {
        case balance
        case hasCredits = "has_credits"
    }
}

struct CodexTokenUsage: Decodable, Sendable {
    let today: Int?
    let month: Int?
    let daily: Int?
    let monthly: Int?

    enum CodingKeys: String, CodingKey {
        case today
        case month
        case daily
        case monthly
    }

    var todayCount: Int? { today ?? daily }
    var monthCount: Int? { month ?? monthly }
}

/// Accepts JSON number or numeric string (credits.balance is often a string).
struct FlexibleNumber: Decodable, Sendable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let int = try? container.decode(Int.self) {
            value = Double(int)
        } else if let string = try? container.decode(String.self) {
            value = Double(string.replacingOccurrences(of: ",", with: ""))
        } else {
            value = nil
        }
    }
}
