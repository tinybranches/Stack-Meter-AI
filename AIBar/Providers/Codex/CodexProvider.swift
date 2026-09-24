import Foundation

struct CodexProvider: UsageProvider {
    let id = "codex"
    let displayName = "Codex"

    private let api: CodexAPIClient
    private let rolloutReader: CodexRolloutReader

    init(
        api: CodexAPIClient = CodexAPIClient(),
        rolloutReader: CodexRolloutReader = CodexRolloutReader()
    ) {
        self.api = api
        self.rolloutReader = rolloutReader
    }

    func fetch() async throws -> UsageSnapshot {
        let credentials: CodexCredentials
        do {
            credentials = try CodexAuthStore.loadAuthorized()
        } catch let error as ProviderError {
            if case .notAuthenticated = error {
                return .authNeeded(providerID: id, providerName: displayName, message: "auth.chatgpt.needed")
            }
            throw error
        }

        do {
            let response = try await api.fetchUsage(credentials: credentials)
            let tokensFromAPI = TokenSummary(
                today: response.tokenUsage?.todayCount,
                month: response.tokenUsage?.monthCount
            )
            let tokens = tokensFromAPI.hasAnyValue
                ? tokensFromAPI
                : await rolloutReader.tokenSummary()

            return map(response: response, tokens: tokens)
        } catch ProviderError.unauthorized {
            CodexAuthStore.clear()
            return .authNeeded(
                providerID: id,
                providerName: displayName,
                message: "auth.chatgpt.expired"
            )
        } catch ProviderError.rateLimited {
            return UsageSnapshot(
                providerID: id,
                providerName: displayName,
                fetchedAt: Date(),
                status: .rateLimited,
                windows: [],
                spend: SpendSummary(),
                tokens: TokenSummary(),
                planName: nil,
                message: "auth.rateLimitedTemp"
            )
        }
    }

    private func map(response: CodexUsageResponse, tokens: TokenSummary) -> UsageSnapshot {
        var windows: [RateWindow] = []

        if let primary = response.rateLimit?.primaryWindow {
            windows.append(makeWindow(
                id: "primary",
                dto: primary,
                fallbackName: "window.primary",
                globalLimitReached: response.rateLimit?.limitReached ?? false
            ))
        }

        if let secondary = response.rateLimit?.secondaryWindow {
            windows.append(makeWindow(
                id: "secondary",
                dto: secondary,
                fallbackName: "window.weekly",
                globalLimitReached: response.rateLimit?.limitReached ?? false
            ))
        }

        let anyLimitReached = (response.rateLimit?.limitReached ?? false)
            || windows.contains(where: \.limitReached)

        let status: SessionStatus = anyLimitReached ? .rateLimited : .active

        let spend = SpendSummary(
            creditsBalance: response.credits?.balance?.value,
            spendUSD: nil,
            currency: "USD"
        )

        let plan = response.planName ?? response.planType

        return UsageSnapshot(
            providerID: id,
            providerName: displayName,
            fetchedAt: Date(),
            status: status,
            windows: windows,
            spend: spend,
            tokens: tokens,
            planName: plan,
            message: nil
        )
    }

    private func makeWindow(
        id: String,
        dto: CodexRateWindowDTO,
        fallbackName: String,
        globalLimitReached: Bool
    ) -> RateWindow {
        let name = windowName(seconds: dto.limitWindowSeconds, fallback: fallbackName)
        let resetAt: Date?
        if let resetAtValue = dto.resetAt {
            resetAt = Date(timeIntervalSince1970: resetAtValue)
        } else if let after = dto.resetAfterSeconds {
            resetAt = Date().addingTimeInterval(TimeInterval(after))
        } else {
            resetAt = nil
        }

        return RateWindow(
            id: id,
            name: name,
            usedPercent: dto.normalizedUsedPercent,
            resetAt: resetAt,
            resetAfterSeconds: dto.resetAfterSeconds,
            limitReached: dto.limitReached ?? globalLimitReached
        )
    }

    private func windowName(seconds: Int?, fallback: String) -> String {
        guard let seconds else { return fallback }
        switch seconds {
        case 0 ..< 3_600:
            return "\(max(1, seconds / 60))m"
        case 3_600 ..< 86_400:
            let hours = seconds / 3_600
            return hours == 5 ? "window.5h" : "\(hours)h"
        case 86_400 ..< 604_800:
            let days = seconds / 86_400
            return days == 1 ? "window.daily" : "\(days)-day"
        case 604_800 ..< 2_678_400:
            return "window.weekly"
        default:
            return "window.monthly"
        }
    }
}
