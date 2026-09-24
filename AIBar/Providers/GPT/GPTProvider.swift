import Foundation

struct GPTProvider: UsageProvider {
    let id = "gpt"
    let displayName = "ChatGPT"

    private let api: GPTAPIClient

    init(api: GPTAPIClient = GPTAPIClient()) {
        self.api = api
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
            let limits = try await api.fetchLimits(credentials: credentials)
            return map(limits)
        } catch ProviderError.unauthorized {
            // Shared ChatGPT session — do not wipe Keychain here. Codex may still be valid
            // if only the conversation/limits endpoint rejected the token.
            return .authNeeded(providerID: id, providerName: displayName, message: "auth.chatgpt.expired")
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

    private func map(_ limits: GPTLimitsResponse) -> UsageSnapshot {
        var windows: [RateWindow] = []

        if let rate = limits.rateLimit {
            if let primary = rate.primaryWindow {
                windows.append(
                    RateWindow(
                        id: "primary",
                        name: "window.primary",
                        usedPercent: primary.normalizedUsedPercent,
                        resetAt: resetDate(primary),
                        resetAfterSeconds: primary.resetAfterSeconds,
                        limitReached: primary.limitReached ?? false
                    )
                )
            }
            if let secondary = rate.secondaryWindow {
                windows.append(
                    RateWindow(
                        id: "secondary",
                        name: "window.weekly",
                        usedPercent: secondary.normalizedUsedPercent,
                        resetAt: resetDate(secondary),
                        resetAfterSeconds: secondary.resetAfterSeconds,
                        limitReached: secondary.limitReached ?? false
                    )
                )
            }
        }

        if windows.isEmpty {
            if let used = limits.usedPercent {
                windows.append(
                    RateWindow(
                        id: "messages",
                        name: "window.messages",
                        usedPercent: max(0, min(100, used)),
                        resetAt: limits.resetTime.map { Date(timeIntervalSince1970: $0) },
                        resetAfterSeconds: limits.messageCapWindow.map { Int($0) },
                        limitReached: limits.rateLimitReached == true || limits.limitReached == true
                    )
                )
            } else if let remaining = limits.remainingPercent {
                windows.append(
                    RateWindow(
                        id: "messages",
                        name: "window.messages",
                        usedPercent: max(0, min(100, 100 - remaining)),
                        resetAt: limits.resetTime.map { Date(timeIntervalSince1970: $0) },
                        resetAfterSeconds: limits.messageCapWindow.map { Int($0) },
                        limitReached: limits.rateLimitReached == true || limits.limitReached == true
                    )
                )
            } else if let cap = limits.messageCap {
                // Remaining-message style payload without a hard max.
                let limited = cap <= 0 || limits.rateLimitReached == true
                windows.append(
                    RateWindow(
                        id: "message_cap",
                        name: "window.messages",
                        usedPercent: limited ? 100 : 5,
                        resetAt: limits.resetTime.map { Date(timeIntervalSince1970: $0) },
                        resetAfterSeconds: limits.messageCapWindow.map { Int($0) },
                        limitReached: limited
                    )
                )
            }
        }

        var spend = SpendSummary(currency: "USD")
        if let balance = limits.credits?.balance?.value {
            spend.creditsBalance = balance
        }

        let limited = windows.contains { $0.limitReached || $0.usedPercent >= 99.5 }
            || limits.rateLimitReached == true
            || limits.limitReached == true

        let remainingNote: String? = {
            guard let cap = limits.messageCap, cap > 0, windows.contains(where: { $0.id == "message_cap" }) else {
                return windows.isEmpty ? "popover.noWindows" : nil
            }
            return nil
        }()

        return UsageSnapshot(
            providerID: id,
            providerName: displayName,
            fetchedAt: Date(),
            status: limited ? .rateLimited : .active,
            windows: windows,
            spend: spend,
            tokens: TokenSummary(),
            planName: limits.planName ?? limits.planType ?? "ChatGPT",
            message: remainingNote ?? (windows.isEmpty ? "popover.noWindows" : nil)
        )
    }

    private func resetDate(_ window: CodexRateWindowDTO) -> Date? {
        if let resetAt = window.resetAt {
            return Date(timeIntervalSince1970: resetAt)
        }
        if let seconds = window.resetAfterSeconds {
            return Date().addingTimeInterval(TimeInterval(seconds))
        }
        return nil
    }
}
