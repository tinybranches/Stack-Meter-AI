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
        if !isAuthorized {
            statusMessage = nil
        }
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

    var hasLocalDesktopLogin: Bool {
        ClaudeAuthStore.hasLocalDesktopLogin
    }

    func refreshState() {
        isAuthorized = ClaudeAuthStore.isAuthorized
        if !isAuthorized {
            statusMessage = nil
        }
    }

    func openBrowserLogin() {
        showLoginWindow = true
        presentLoginWindow()
    }

    func authorizeFromLocalDesktop() async -> Bool {
        isBusy = true
        errorMessage = nil
        statusMessage = L10n.tr("auth.connecting")
        defer { isBusy = false }

        do {
            let credentials = try await ClaudeAuthStore.authorizeFromLocalDesktop()
            // Validate against usage API before claiming success.
            let api = ClaudeAPIClient()
            let orgs = try await api.fetchOrganizations(sessionKey: credentials.sessionKey)
            guard let orgID = ClaudeAPIClient.resolveOrganizationID(
                in: orgs,
                preferredID: credentials.organizationID
            ) else {
                errorMessage = L10n.tr("auth.claude.noOrg")
                statusMessage = nil
                isAuthorized = false
                return false
            }
            _ = try await api.fetchUsage(sessionKey: credentials.sessionKey, organizationID: orgID)
            try ClaudeAuthStore.save(
                ClaudeCredentials(sessionKey: credentials.sessionKey, organizationID: orgID)
            )
            isAuthorized = true
            statusMessage = L10n.tr("auth.claude.success")
            return true
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
            isAuthorized = false
            return false
        }
    }

    func authorizeWithSessionKey(_ sessionKey: String) async -> Bool {
        isBusy = true
        errorMessage = nil
        statusMessage = L10n.tr("auth.connecting")
        defer { isBusy = false }

        let trimmed = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = L10n.tr("auth.claude.emptyKey")
            statusMessage = nil
            return false
        }

        do {
            let api = ClaudeAPIClient()
            let orgs = try await api.fetchOrganizations(sessionKey: trimmed)
            guard let orgID = ClaudeAPIClient.resolveOrganizationID(in: orgs) else {
                errorMessage = L10n.tr("auth.claude.noOrg")
                statusMessage = nil
                isAuthorized = false
                return false
            }
            // Prove the session can read usage before claiming success.
            _ = try await api.fetchUsage(sessionKey: trimmed, organizationID: orgID)
            try ClaudeAuthStore.save(ClaudeCredentials(sessionKey: trimmed, organizationID: orgID))
            isAuthorized = true
            statusMessage = L10n.tr("auth.claude.success")
            closeLoginWindow()
            return true
        } catch ProviderError.unauthorized {
            errorMessage = L10n.tr("auth.claude.expired")
            statusMessage = nil
            isAuthorized = false
            return false
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
            isAuthorized = false
            return false
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
            },
            onImportDesktop: { [weak self] in
                Task { @MainActor in
                    let ok = await self?.authorizeFromLocalDesktop() ?? false
                    if ok {
                        self?.closeLoginWindow()
                    }
                }
            }
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.tr("auth.claude.loginTitle")
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 500))
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
