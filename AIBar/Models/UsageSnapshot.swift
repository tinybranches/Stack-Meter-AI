import Foundation

enum SessionStatus: String, Equatable, Sendable {
    case active
    case rateLimited
    case authNeeded
    case unavailable
    case loading

    var title: String {
        switch self {
        case .active: return L10n.tr("status.active")
        case .rateLimited: return L10n.tr("status.rateLimited")
        case .authNeeded: return L10n.tr("status.authNeeded")
        case .unavailable: return L10n.tr("status.unavailable")
        case .loading: return L10n.tr("status.loading")
        }
    }
}

struct RateWindow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let usedPercent: Double
    let resetAt: Date?
    let resetAfterSeconds: Int?
    let limitReached: Bool

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct SpendSummary: Equatable, Sendable {
    var creditsBalance: Double?
    var spendUSD: Double?
    var currency: String?

    var hasAnyValue: Bool {
        creditsBalance != nil || spendUSD != nil
    }
}

struct TokenSummary: Equatable, Sendable {
    var today: Int?
    var month: Int?

    var hasAnyValue: Bool {
        today != nil || month != nil
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let providerID: String
    let providerName: String
    let fetchedAt: Date
    let status: SessionStatus
    let windows: [RateWindow]
    let spend: SpendSummary
    let tokens: TokenSummary
    let planName: String?
    let message: String?

    var primaryUsedPercent: Double? {
        windows.first?.usedPercent
    }

    var isLimited: Bool {
        status == .rateLimited || windows.contains(where: \.limitReached)
    }

    static func loading(providerID: String, providerName: String) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            providerName: providerName,
            fetchedAt: Date(),
            status: .loading,
            windows: [],
            spend: SpendSummary(),
            tokens: TokenSummary(),
            planName: nil,
            message: nil
        )
    }

    static func authNeeded(providerID: String, providerName: String, message: String) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            providerName: providerName,
            fetchedAt: Date(),
            status: .authNeeded,
            windows: [],
            spend: SpendSummary(),
            tokens: TokenSummary(),
            planName: nil,
            message: message
        )
    }
}
