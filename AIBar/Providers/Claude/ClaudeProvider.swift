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
            var orgID = credentials.organizationID
            if orgID == nil || orgID?.isEmpty == true {
                let orgs = try await api.fetchOrganizations(sessionKey: credentials.sessionKey)
                orgID = orgs.first?.uuid
                if let orgID {
                    try? ClaudeAuthStore.save(
                        ClaudeCredentials(sessionKey: credentials.sessionKey, organizationID: orgID)
                    )
                }
            }

            guard let organizationID = orgID, !organizationID.isEmpty else {
                return .authNeeded(providerID: id, providerName: displayName, message: "auth.claude.noOrg")
            }

            let usage = try await api.fetchUsage(
                sessionKey: credentials.sessionKey,
                organizationID: organizationID
            )
            return map(usage)
        } catch ProviderError.unauthorized {
            ClaudeAuthStore.clear()
            return .authNeeded(providerID: id, providerName: displayName, message: "auth.claude.expired")
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
        // utilization is typically 0...1 fraction
        let raw = dto.utilization ?? 0
        let usedPercent = raw <= 1.0001 ? raw * 100 : raw
        return RateWindow(
            id: id,
            name: name,
            usedPercent: min(100, max(0, usedPercent)),
            resetAt: parseISO(dto.resetsISO),
            resetAfterSeconds: nil,
            limitReached: usedPercent >= 99.5
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
