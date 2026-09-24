import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let pollInterval = "pollIntervalSeconds"
        static let warningThreshold = "warningThreshold"
        static let criticalThreshold = "criticalThreshold"
        static let enabledProviders = "enabledProviderIDs"
        static let showPercentInTray = "showPercentInTray"
        static let languagePreference = "languagePreference"
        static let notifyUsageThreshold = "notifyUsageThreshold"
        static let notifyRateLimited = "notifyRateLimited"
        static let notifyLimitReset = "notifyLimitReset"
        static let notifyUsageJump = "notifyUsageJump"
        static let notifySessionExpired = "notifySessionExpired"
        static let notifyLowCredits = "notifyLowCredits"
        static let usageJumpPercent = "usageJumpPercent"
        static let lowCreditsThreshold = "lowCreditsThreshold"
        // Legacy
        static let notificationsEnabled = "notificationsEnabled"
    }

    @Published var pollIntervalSeconds: Double {
        didSet { defaults.set(pollIntervalSeconds, forKey: Keys.pollInterval) }
    }

    @Published var warningThreshold: Double {
        didSet {
            if warningThreshold > criticalThreshold {
                warningThreshold = criticalThreshold
            }
            defaults.set(warningThreshold, forKey: Keys.warningThreshold)
        }
    }

    @Published var criticalThreshold: Double {
        didSet {
            if criticalThreshold < warningThreshold {
                criticalThreshold = warningThreshold
            }
            defaults.set(criticalThreshold, forKey: Keys.criticalThreshold)
        }
    }

    @Published var enabledProviderIDs: [String] {
        didSet { defaults.set(enabledProviderIDs, forKey: Keys.enabledProviders) }
    }

    @Published var showPercentInTray: Bool {
        didSet { defaults.set(showPercentInTray, forKey: Keys.showPercentInTray) }
    }

    @Published var languagePreference: LanguagePreference {
        didSet {
            defaults.set(languagePreference.rawValue, forKey: Keys.languagePreference)
            LanguageStore.shared.apply(preference: languagePreference)
        }
    }

    /// Existing usage % warning/critical alerts — ON by default.
    @Published var notifyUsageThreshold: Bool {
        didSet { defaults.set(notifyUsageThreshold, forKey: Keys.notifyUsageThreshold) }
    }

    @Published var notifyRateLimited: Bool {
        didSet { defaults.set(notifyRateLimited, forKey: Keys.notifyRateLimited) }
    }

    @Published var notifyLimitReset: Bool {
        didSet { defaults.set(notifyLimitReset, forKey: Keys.notifyLimitReset) }
    }

    @Published var notifyUsageJump: Bool {
        didSet { defaults.set(notifyUsageJump, forKey: Keys.notifyUsageJump) }
    }

    @Published var notifySessionExpired: Bool {
        didSet { defaults.set(notifySessionExpired, forKey: Keys.notifySessionExpired) }
    }

    @Published var notifyLowCredits: Bool {
        didSet { defaults.set(notifyLowCredits, forKey: Keys.notifyLowCredits) }
    }

    /// Minimum % jump between refreshes to trigger usage-jump alert.
    @Published var usageJumpPercent: Double {
        didSet { defaults.set(usageJumpPercent, forKey: Keys.usageJumpPercent) }
    }

    /// Credits balance at or below this value triggers low-credits alert.
    @Published var lowCreditsThreshold: Double {
        didSet { defaults.set(lowCreditsThreshold, forKey: Keys.lowCreditsThreshold) }
    }

    var anyNotificationEnabled: Bool {
        notifyUsageThreshold
            || notifyRateLimited
            || notifyLimitReset
            || notifyUsageJump
            || notifySessionExpired
            || notifyLowCredits
    }

    private init() {
        let storedInterval = defaults.object(forKey: Keys.pollInterval) as? Double
        pollIntervalSeconds = storedInterval ?? 60

        var warning = (defaults.object(forKey: Keys.warningThreshold) as? Double) ?? 80
        var critical = (defaults.object(forKey: Keys.criticalThreshold) as? Double) ?? 95
        if warning > critical { warning = critical }
        if critical < warning { critical = warning }
        warningThreshold = warning
        criticalThreshold = critical

        let stored = (defaults.array(forKey: Keys.enabledProviders) as? [String])
            ?? ["codex", "cursor", "claude"]
        // Drop removed ChatGPT provider id from older installs.
        var cleaned = stored.filter { $0 != "gpt" }
        if cleaned.isEmpty {
            cleaned = ["codex", "cursor", "claude"]
        }
        enabledProviderIDs = cleaned

        if defaults.object(forKey: Keys.showPercentInTray) == nil {
            showPercentInTray = true
        } else {
            showPercentInTray = defaults.bool(forKey: Keys.showPercentInTray)
        }

        // Threshold alerts: default ON. Honor legacy master toggle if present.
        if defaults.object(forKey: Keys.notifyUsageThreshold) != nil {
            notifyUsageThreshold = defaults.bool(forKey: Keys.notifyUsageThreshold)
        } else if defaults.object(forKey: Keys.notificationsEnabled) != nil {
            notifyUsageThreshold = defaults.bool(forKey: Keys.notificationsEnabled)
        } else {
            notifyUsageThreshold = true
        }

        notifyRateLimited = Self.bool(defaults, Keys.notifyRateLimited, default: false)
        notifyLimitReset = Self.bool(defaults, Keys.notifyLimitReset, default: false)
        notifyUsageJump = Self.bool(defaults, Keys.notifyUsageJump, default: false)
        notifySessionExpired = Self.bool(defaults, Keys.notifySessionExpired, default: false)
        notifyLowCredits = Self.bool(defaults, Keys.notifyLowCredits, default: false)

        usageJumpPercent = (defaults.object(forKey: Keys.usageJumpPercent) as? Double) ?? 15
        lowCreditsThreshold = (defaults.object(forKey: Keys.lowCreditsThreshold) as? Double) ?? 1

        if let raw = defaults.string(forKey: Keys.languagePreference),
           let preference = LanguagePreference(rawValue: raw)
        {
            languagePreference = preference
        } else {
            languagePreference = .system
        }
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, default defaultValue: Bool) -> Bool {
        if defaults.object(forKey: key) == nil { return defaultValue }
        return defaults.bool(forKey: key)
    }
}
