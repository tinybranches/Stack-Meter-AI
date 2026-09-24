import Foundation
import AppKit
import SwiftUI

@MainActor
final class CursorAuthController: ObservableObject {
    @Published private(set) var isAuthorized = CursorAuthStore.isAuthorized
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    var hasLocalCursorLogin: Bool {
        CursorAuthStore.hasLocalCursorLogin
    }

    func refreshState() {
        isAuthorized = CursorAuthStore.isAuthorized
    }

    func authorizeFromLocalIDE() async -> Bool {
        isBusy = true
        errorMessage = nil
        statusMessage = L10n.tr("auth.connecting")
        defer { isBusy = false }

        do {
            _ = try await CursorAuthStore.authorizeFromLocalIDE()
            isAuthorized = true
            statusMessage = L10n.tr("auth.cursor.success")
            return true
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
            isAuthorized = false
            return false
        }
    }

    func signOut() {
        CursorAuthStore.clear()
        isAuthorized = false
        statusMessage = nil
        errorMessage = nil
    }
}

@MainActor
final class ClaudeAuthController: ObservableObject {
    @Published private(set) var isAuthorized = ClaudeAuthStore.isAuthorized
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var showLoginWindow = false

    private var loginWindow: NSWindow?

    func refreshState() {
        isAuthorized = ClaudeAuthStore.isAuthorized
    }

    func openBrowserLogin() {
        showLoginWindow = true
        presentLoginWindow()
    }

    func authorizeWithSessionKey(_ sessionKey: String) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let trimmed = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = L10n.tr("auth.claude.emptyKey")
            return false
        }

        do {
            // Resolve org up-front when possible.
            let api = ClaudeAPIClient()
            let orgs = try await api.fetchOrganizations(sessionKey: trimmed)
            let orgID = orgs.first?.uuid
            try ClaudeAuthStore.save(ClaudeCredentials(sessionKey: trimmed, organizationID: orgID))
            isAuthorized = true
            statusMessage = L10n.tr("auth.claude.success")
            closeLoginWindow()
            return true
        } catch {
            // Still save session key so provider can retry org lookup.
            do {
                try ClaudeAuthStore.save(ClaudeCredentials(sessionKey: trimmed, organizationID: nil))
                isAuthorized = true
                statusMessage = L10n.tr("auth.claude.success")
                closeLoginWindow()
                return true
            } catch {
                errorMessage = error.localizedDescription
                isAuthorized = false
                return false
            }
        }
    }

    func signOut() {
        ClaudeAuthStore.clear()
        isAuthorized = false
        statusMessage = nil
        errorMessage = nil
    }

    private func presentLoginWindow() {
        if loginWindow != nil {
            loginWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = ClaudeLoginView(
            onSuccess: { [weak self] key in
                Task { @MainActor in
                    _ = await self?.authorizeWithSessionKey(key)
                }
            },
            onCancel: { [weak self] in
                self?.closeLoginWindow()
            }
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.tr("auth.claude.loginTitle")
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 600))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        loginWindow = window
    }

    private func closeLoginWindow() {
        showLoginWindow = false
        loginWindow?.close()
        loginWindow = nil
    }
}
