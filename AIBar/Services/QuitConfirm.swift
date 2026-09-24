import AppKit

/// Confirms before quitting the menu-bar app (unless bypassed for uninstall / single-instance).
enum QuitConfirm {
    /// Set to skip the “are you sure?” dialog (uninstall, duplicate-instance exit).
    static var bypass = false

    @MainActor
    static func askUser() -> Bool {
        if bypass { return true }

        let alert = NSAlert()
        alert.messageText = L10n.tr("quit.confirmTitle")
        alert.informativeText = L10n.tr("quit.confirmMessage")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("common.quit"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
