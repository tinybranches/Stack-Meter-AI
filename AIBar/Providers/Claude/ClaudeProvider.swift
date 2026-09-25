import Foundation

struct ClaudeProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude"

    private let api: ClaudeAPIClient

    init(api: ClaudeAPIClient = ClaudeAPIClient()) {
        self.api = api
    }

    func fetch() async throws -> UsageSnapshot {
        let credentials: ClaudeCredentials
        do {
            credentials = try ClaudeAuthStore.loadAuthorized()
        } catch let error as ProviderError {
            if case .notAuthenticated(let message) = error {
                return .authNeeded(providerID: id, providerName: displayName, message: message)
            }
            throw error
        }

        do {
            let (usage, orgID) = try await api.fetchUsageResolvingOrg(
                sessionKey: credentials.sessionKey,
                preferredOrganizationID: credentials.organizationID
            )
            if orgID != credentials.organizationID {
                try? ClaudeAuthStore.save(
                    ClaudeCredentials(sessionKey: credentials.sessionKey, organizationID: orgID)
                )
            }
            return map(usage)
        } catch ProviderError.unauthorized {
            ClaudeAuthStore.clear()
            return .authNeeded(providerID: id, providerName: displayName, message: "auth.claude.expired")
        } catch ProviderError.wrongOrganization {
            return .authNeeded(providerID: id, providerName: displayName, message: "auth.claude.noOrg")
        } catch let error as ProviderError {
            if case .notAuthenticated(let message) = error {
                return .authNeeded(providerID: id, providerName: displayName, message: message)
            }
            if case .rateLimited = error {
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
            throw error
        }
    }

    private func map(_ usage: ClaudeUsageResponse) -> UsageSnapshot {
        var windows: [RateWindow] = []

        if let five = usage.fiveHourWindow {
            windows.append(makeWindow(id: "five_hour", name: "window.5h", dto: five))
        }
        if let week = usage.sevenDayWindow {
            windows.append(makeWindow(id: "seven_day", name: "window.weekly", dto: week))
        }
        if let sonnet = usage.seven_day_sonnet {
            windows.append(makeWindow(id: "seven_day_sonnet", name: "window.sonnet", dto: sonnet))
        }
        if let opus = usage.seven_day_opus {
            windows.append(makeWindow(id: "seven_day_opus", name: "window.opus", dto: opus))
        }
        if let oauth = usage.seven_day_oauth_apps {
            windows.append(makeWindow(id: "seven_day_oauth_apps", name: "window.oauthApps", dto: oauth))
        }
        if let cowork = usage.seven_day_cowork {
            windows.append(makeWindow(id: "seven_day_cowork", name: "window.cowork", dto: cowork))
        }

        // Red status only when a window that can block chat is exhausted.
        let limited = windows.contains { $0.usedPercent >= 99.5 || $0.limitReached }
        return UsageSnapshot(
            providerID: id,
            providerName: displayName,
            fetchedAt: Date(),
            status: limited ? .rateLimited : .active,
            windows: windows,
            spend: SpendSummary(),
            tokens: TokenSummary(),
            planName: "Claude",
            message: windows.isEmpty ? "popover.noWindows" : nil
        )
    }

    private func makeWindow(id: String, name: String, dto: ClaudeUsageWindowDTO) -> RateWindow {
        let usedPercent = Self.normalizeUtilization(dto.utilization)
        return RateWindow(
            id: id,
            name: name,
            usedPercent: usedPercent,
            resetAt: parseISO(dto.resetsISO),
            resetAfterSeconds: nil,
            limitReached: usedPercent >= 99.5
        )
    }

    /// Claude.ai `/usage` returns percents (0…100). Some legacy payloads used
    /// fractions (0…1). Never treat exactly `1` as “100%” — that misreads 1% as full.
    static func normalizeUtilization(_ raw: Double?) -> Double {
        guard let raw else { return 0 }
        let value: Double
        if raw > 0, raw < 1 {
            value = raw * 100
        } else {
            value = raw
        }
        return min(100, max(0, value))
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
