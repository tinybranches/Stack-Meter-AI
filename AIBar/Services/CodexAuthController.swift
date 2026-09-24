import Foundation
import AppKit
import SwiftUI

@MainActor
final class CodexAuthController: ObservableObject {
    @Published private(set) var isAuthorized = CodexAuthStore.isAuthorized
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private var loginWindow: NSWindow?

    var hasCLILoginAvailable: Bool {
        CodexAuthStore.hasCLILoginAvailable
    }

    func refreshState() {
        isAuthorized = CodexAuthStore.isAuthorized
    }

    func openBrowserLogin() {
        presentLoginWindow()
    }

    func authorizeFromCLILogin() async -> Bool {
        isBusy = true
        errorMessage = nil
        statusMessage = L10n.tr("auth.connecting")
        defer { isBusy = false }

        do {
            _ = try CodexAuthStore.authorizeFromCLILogin()
            isAuthorized = true
            statusMessage = L10n.tr("auth.chatgpt.success")
            return true
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
            isAuthorized = false
            return false
        }
    }

    func authorizeWithSession(accessToken: String, accountID: String?) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let trimmed = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = L10n.tr("auth.chatgpt.emptyToken")
            return false
        }

        do {
            try CodexAuthStore.saveToKeychain(
                CodexCredentials(
                    accessToken: trimmed,
                    accountID: accountID,
                    refreshToken: nil
                )
            )
            isAuthorized = true
            statusMessage = L10n.tr("auth.chatgpt.success")
            closeLoginWindow()
            return true
        } catch {
            errorMessage = error.localizedDescription
            isAuthorized = false
            return false
        }
    }

    func signOut() {
        CodexAuthStore.clear()
        ChatGPTWebLoginStore.clear()
        isAuthorized = false
        statusMessage = nil
        errorMessage = nil
        closeLoginWindow()
    }

    private func presentLoginWindow() {
        if loginWindow != nil {
            loginWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = ChatGPTLoginView(
            onSuccess: { [weak self] token, accountID in
                Task { @MainActor in
                    _ = await self?.authorizeWithSession(accessToken: token, accountID: accountID)
                }
            },
            onCancel: { [weak self] in
                self?.closeLoginWindow()
            }
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.tr("auth.chatgpt.loginTitle")
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 780, height: 680))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        loginWindow = window
    }

    private func closeLoginWindow() {
        loginWindow?.close()
        loginWindow = nil
    }
}
