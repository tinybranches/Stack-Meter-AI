import Foundation
import AppKit
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    private enum Keys {
        static let prompted = "notificationPermissionPrompted"
    }

    enum PermissionKind: Equatable {
        case unknown
        case notAsked      // first-launch "Not Now" — system never prompted
        case notDetermined
        case authorized
        case denied       // system denied — must open Settings
    }

    @Published private(set) var permission: PermissionKind = .unknown

    private var lastThresholdLevel: [String: Int] = [:]
    private var lastWasRateLimited: [String: Bool] = [:]
    private var lastAuthNeeded: [String: Bool] = [:]
    private var sawNonAuthState: [String: Bool] = [:]
    private var lastUsedPercent: [String: Double] = [:]
    private var lastCreditsLow: [String: Bool] = [:]
    private var awaitingResetWindowIDs: [String: Set<String>] = [:]
    private var isPrompting = false

    private var hasPromptedUser: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.prompted) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.prompted) }
    }

    var needsEnableButton: Bool {
        switch permission {
        case .authorized: return false
        case .unknown, .notAsked, .notDetermined, .denied: return true
        }
    }

    /// Call once after the menu bar UI is alive. Shows our consent dialog first;
    /// only then talks to UserNotifications (so the app is not silently registered).
    func promptOnFirstLaunchIfNeeded() {
        Task { @MainActor in
            await refreshPermissionState()
            guard !hasPromptedUser, !isPrompting else { return }
            isPrompting = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            await showFirstLaunchPrompt()
            isPrompting = false
            await refreshPermissionState()
        }
    }

    /// Settings: user explicitly wants to allow notifications after declining earlier.
    @discardableResult
    func enableFromSettings() async -> Bool {
        hasPromptedUser = true
        await refreshPermissionState()

        switch permission {
        case .authorized:
            return true
        case .denied:
            openSystemNotificationSettings()
            return false
        case .notAsked, .notDetermined, .unknown:
            let granted = await requestSystemAuthorization()
            await refreshPermissionState()
            if !granted, permission == .denied {
                openSystemNotificationSettings()
            }
            return granted
        }
    }

    /// When the user turns a notification toggle ON in Settings.
    func requestAuthorizationAfterUserEnabledToggle() {
        Task { @MainActor in
            _ = await enableFromSettings()
        }
    }

    func refreshPermissionState() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            permission = .authorized
        case .denied:
            permission = .denied
        case .notDetermined:
            permission = hasPromptedUser ? .notAsked : .notDetermined
        @unknown default:
            permission = .unknown
        }
    }

    func evaluate(snapshot: UsageSnapshot, settings: AppSettings) {
        guard settings.anyNotificationEnabled else { return }
        // Never register with Notification Center until the user has been asked.
        guard hasPromptedUser else { return }
        // Use cached permission — avoid hitting UNUserNotificationCenter on every poll.
        guard permission == .authorized else { return }
        evaluateAuthorized(snapshot: snapshot, settings: settings)
    }

    // MARK: - First-launch prompt

    private func showFirstLaunchPrompt() async {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = L10n.tr("notify.prompt.title")
        alert.informativeText = L10n.tr("notify.prompt.body")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("notify.prompt.allow"))
        alert.addButton(withTitle: L10n.tr("notify.prompt.notNow"))

        let response = alert.runModal()
        hasPromptedUser = true

        if response == .alertFirstButtonReturn {
            _ = await requestSystemAuthorization()
        }
        // "Not Now" — do not call requestAuthorization, so we stay out of System Settings.
    }

    private func requestSystemAuthorization() async -> Bool {
        AppIcon.applyToRunningApplication()
        NSApp.activate(ignoringOtherApps: true)
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            return granted
        } catch {
            return false
        }
    }

    private func openSystemNotificationSettings() {
        // Deep-link to this app's notification settings when possible.
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.stackmeter.ai",
            "x-apple.systempreferences:com.apple.preference.notifications",
            "x-apple.systempreferences:com.apple.Notifications-Settings",
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: - Evaluation (only when authorized)

    private func evaluateAuthorized(snapshot: UsageSnapshot, settings: AppSettings) {
        let id = snapshot.providerID

        if settings.notifyUsageThreshold {
            evaluateUsageThreshold(snapshot: snapshot, settings: settings)
        }
        if settings.notifyRateLimited {
            evaluateRateLimited(snapshot: snapshot)
        }
        if settings.notifyLimitReset {
            evaluateLimitReset(snapshot: snapshot)
        }
        if settings.notifyUsageJump {
            evaluateUsageJump(snapshot: snapshot, settings: settings)
        }
        if settings.notifySessionExpired {
            evaluateSessionExpired(snapshot: snapshot)
        }
        if settings.notifyLowCredits {
            evaluateLowCredits(snapshot: snapshot, settings: settings)
        }

        if let used = snapshot.primaryUsedPercent {
            lastUsedPercent[id] = used
        }

        if snapshot.status != .authNeeded && snapshot.status != .loading {
            sawNonAuthState[id] = true
        }
        lastAuthNeeded[id] = (snapshot.status == .authNeeded)
    }

    // MARK: - Usage threshold

    private func evaluateUsageThreshold(snapshot: UsageSnapshot, settings: AppSettings) {
        guard let used = snapshot.primaryUsedPercent else { return }
        let id = snapshot.providerID

        let level: Int
        if used >= settings.criticalThreshold {
            level = 2
        } else if used >= settings.warningThreshold {
            level = 1
        } else {
            lastThresholdLevel[id] = 0
            return
        }

        let previous = lastThresholdLevel[id] ?? 0
        guard level > previous else { return }
        lastThresholdLevel[id] = level

        post(
            provider: snapshot.providerName,
            body: level == 2
                ? L10n.tr("notify.critical", Int(used.rounded()))
                : L10n.tr("notify.warning", Int(used.rounded())),
            kind: level == 2 ? "critical" : "warning"
        )
    }

    // MARK: - Rate limited

    private func evaluateRateLimited(snapshot: UsageSnapshot) {
        let id = snapshot.providerID
        let limited = snapshot.isLimited
        let was = lastWasRateLimited[id] ?? false
        lastWasRateLimited[id] = limited
        guard limited, !was else { return }

        post(
            provider: snapshot.providerName,
            body: L10n.tr("notify.rateLimited"),
            kind: "rate-limited"
        )
    }

    // MARK: - Limit reset

    private func evaluateLimitReset(snapshot: UsageSnapshot) {
        let id = snapshot.providerID
        var awaiting = awaitingResetWindowIDs[id] ?? []
        var newlyReset: [String] = []

        for window in snapshot.windows {
            let exhausted = window.limitReached || window.usedPercent >= 99.5
            if exhausted {
                awaiting.insert(window.id)
            } else if awaiting.contains(window.id) {
                awaiting.remove(window.id)
                newlyReset.append(L10n.text(window.name) ?? window.name)
            }
        }

        awaitingResetWindowIDs[id] = awaiting
        guard !newlyReset.isEmpty else { return }

        post(
            provider: snapshot.providerName,
            body: L10n.tr("notify.limitReset", newlyReset.joined(separator: ", ")),
            kind: "limit-reset"
        )
    }

    // MARK: - Usage jump

    private func evaluateUsageJump(snapshot: UsageSnapshot, settings: AppSettings) {
        guard let used = snapshot.primaryUsedPercent else { return }
        let id = snapshot.providerID
        guard let previous = lastUsedPercent[id] else { return }

        let jump = used - previous
        guard jump >= settings.usageJumpPercent else { return }

        post(
            provider: snapshot.providerName,
            body: L10n.tr("notify.usageJump", Int(jump.rounded())),
            kind: "usage-jump"
        )
    }

    // MARK: - Session expired

    private func evaluateSessionExpired(snapshot: UsageSnapshot) {
        let id = snapshot.providerID
        let needed = snapshot.status == .authNeeded
        let sawOK = sawNonAuthState[id] == true
        let wasNeeded = lastAuthNeeded[id] ?? false
        guard needed, sawOK, !wasNeeded else { return }

        post(
            provider: snapshot.providerName,
            body: L10n.tr("notify.sessionExpired"),
            kind: "session-expired"
        )
    }

    // MARK: - Low credits

    private func evaluateLowCredits(snapshot: UsageSnapshot, settings: AppSettings) {
        guard let balance = snapshot.spend.creditsBalance else { return }
        let id = snapshot.providerID
        let isLow = balance <= settings.lowCreditsThreshold
        let wasLow = lastCreditsLow[id] ?? false
        lastCreditsLow[id] = isLow
        guard isLow, !wasLow else { return }

        post(
            provider: snapshot.providerName,
            body: L10n.tr("notify.lowCredits", balance),
            kind: "low-credits"
        )
    }

    private func post(provider: String, body: String, kind: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.tr("notify.title", provider)
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "stackmeter.\(provider).\(kind).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
