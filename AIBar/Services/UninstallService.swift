import Foundation
import AppKit
import UserNotifications

enum UninstallService {
    static let bundleID = "com.stackmeter.ai"
    static let applicationsURL = URL(fileURLWithPath: "/Applications/Stack Meter AI.app")

    /// Full wipe: credentials, prefs, caches, support files, notifications, app bundle.
    /// Call only after the user confirms. Quits the process at the end.
    @MainActor
    static func uninstallCompletely() throws {
        // 1) Credentials (Keychain)
        CodexAuthStore.clear()
        CursorAuthStore.clear()
        ClaudeAuthStore.clear()

        // 2) In-memory + disk preferences
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.removeObject(forKey: "notificationPermissionPrompted")
        UserDefaults.standard.synchronize()

        // 3) Notifications currently scheduled / delivered by this app
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        // 4) Library leftovers for this bundle id (known paths only — no full Library walk)
        removeLibraryLeftovers(bundleID: bundleID)

        // 5) Login Items best-effort
        removeLoginItemBestEffort()

        // 6) Delete installed app from /Applications (and this bundle if it lives there)
        let fm = FileManager.default
        let runningBundle = Bundle.main.bundleURL
        let isInApplications = runningBundle.path.hasPrefix("/Applications/")
            || runningBundle.standardizedFileURL == applicationsURL.standardizedFileURL

        if fm.fileExists(atPath: applicationsURL.path) {
            try? fm.removeItem(at: applicationsURL)
        }
        if isInApplications, fm.fileExists(atPath: runningBundle.path) {
            try? fm.removeItem(at: runningBundle)
        }

        // 7) Best-effort: reset notification TCC entry so it drops from System Settings
        resetNotificationAuthorization(bundleID: bundleID)

        // 8) Quit — DMG remains available for a fresh install anytime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    /// Deletes preference plists, caches, HTTP storage, support folders, etc.
    private static func removeLibraryLeftovers(bundleID: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        let candidates: [URL] = [
            library.appendingPathComponent("Preferences/\(bundleID).plist"),
            library.appendingPathComponent("Preferences/\(bundleID).plist.lockfile"),
            library.appendingPathComponent("Caches/\(bundleID)"),
            library.appendingPathComponent("HTTPStorages/\(bundleID)"),
            library.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"),
            library.appendingPathComponent("Application Support/\(bundleID)"),
            library.appendingPathComponent("Application Support/\(bundleID)/instance.lock"),
            library.appendingPathComponent("Saved Application State/\(bundleID).savedState"),
            library.appendingPathComponent("WebKit/\(bundleID)"),
            library.appendingPathComponent("Logs/\(bundleID)"),
            library.appendingPathComponent("Containers/\(bundleID)"),
            library.appendingPathComponent("Group Containers/\(bundleID)"),
        ]

        let fm = FileManager.default
        for url in candidates {
            try? fm.removeItem(at: url)
        }
    }

    private static func resetNotificationAuthorization(bundleID: String) {
        // `tccutil` removes the System Settings → Notifications row when it succeeds.
        // Run off the calling thread so a slow/hanging tccutil cannot freeze the UI.
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Notifications", bundleID]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
    }

    private static func removeLoginItemBestEffort() {
        // No SMAppService registration yet; placeholder for future Launch at Login.
    }

    /// Human-readable summary for the confirmation dialog.
    @MainActor
    static var confirmationDetails: String {
        var lines: [String] = [
            L10n.tr("uninstall.intro"),
            L10n.tr("uninstall.keychain"),
            L10n.tr("uninstall.settings"),
            L10n.tr("uninstall.caches"),
            L10n.tr("uninstall.notifications"),
        ]
        if FileManager.default.fileExists(atPath: applicationsURL.path)
            || Bundle.main.bundleURL.path.hasPrefix("/Applications/")
        {
            lines.append(L10n.tr("uninstall.app"))
        } else {
            lines.append(L10n.tr("uninstall.quitOnly"))
        }
        lines.append("")
        lines.append(L10n.tr("uninstall.irreversible"))
        return lines.joined(separator: "\n")
    }
}
