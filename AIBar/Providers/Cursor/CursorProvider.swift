import Foundation

struct CursorProvider: UsageProvider {
    let id = "cursor"
    let displayName = "Cursor"

    private let api: CursorAPIClient

    init(api: CursorAPIClient = CursorAPIClient()) {
        self.api = api
    }

    func fetch() async throws -> UsageSnapshot {
        let credentials: CursorCredentials
        do {
            credentials = try CursorAuthStore.loadAuthorized()
        } catch let error as ProviderError {
            if case .notAuthenticated(let message) = error {
                return .authNeeded(providerID: id, providerName: displayName, message: message)
            }
            throw error
        }

        do {
            let summary = try await api.fetchUsageSummary(credentials: credentials)
            return map(summary)
        } catch ProviderError.unauthorized {
            CursorAuthStore.clear()
            return .authNeeded(providerID: id, providerName: displayName, message: "auth.cursor.expired")
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

    private func map(_ summary: CursorUsageSummaryDTO) -> UsageSnapshot {
        var windows: [RateWindow] = []

        if let plan = summary.individualUsage?.plan, plan.enabled != false {
            let usedPercent: Double
            if let total = plan.totalPercentUsed {
                usedPercent = min(100, max(0, total))
            } else if let used = plan.used, let limit = plan.limit, limit > 0 {
                usedPercent = min(100, max(0, (used / limit) * 100))
            } else {
                usedPercent = 0
            }
            let resetAt = parseISO(summary.billingCycleEnd)
            windows.append(
                RateWindow(
                    id: "plan",
                    name: "window.plan",
                    usedPercent: usedPercent,
                    resetAt: resetAt,
                    resetAfterSeconds: nil,
                    limitReached: usedPercent >= 99.5
                )
            )
        }

        if let overall = summary.individualUsage?.overall, overall.enabled == true,
           let used = overall.used, let limit = overall.limit, limit > 0
        {
            let usedPercent = min(100, max(0, (used / limit) * 100))
            windows.append(
                RateWindow(
                    id: "overall",
                    name: "window.overall",
                    usedPercent: usedPercent,
                    resetAt: parseISO(summary.billingCycleEnd),
                    resetAfterSeconds: nil,
                    limitReached: usedPercent >= 99.5
                )
            )
        }

        var spend = SpendSummary(currency: "USD")
        if let onDemand = summary.individualUsage?.onDemand, onDemand.enabled == true,
           let usedCents = onDemand.used
        {
            spend.spendUSD = usedCents / 100.0
        }

        let limited = windows.contains(where: \.limitReached)
        return UsageSnapshot(
            providerID: id,
            providerName: displayName,
            fetchedAt: Date(),
            status: limited ? .rateLimited : .active,
            windows: windows,
            spend: spend,
            tokens: TokenSummary(),
            planName: summary.membershipType,
            message: nil
        )
    }

    private func parseISO(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
