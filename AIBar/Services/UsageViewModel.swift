import Foundation
import Combine
import AppKit

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshots: [String: UsageSnapshot] = [:]
    @Published private(set) var selectedProviderID: String = "codex"
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published var settingsOpen = false

    let registry: ProviderRegistry
    let settings: AppSettings
    let codexAuth: CodexAuthController
    let cursorAuth: CursorAuthController
    let claudeAuth: ClaudeAuthController

    let notifications = NotificationService()
    private var pollTask: Task<Void, Never>?
    private var authWaitTask: Task<Void, Never>?
    private var settingsCancellable: AnyCancellable?
    private var authCancellables = Set<AnyCancellable>()
    private var didStart = false
    private var pendingRefresh = false

    init(
        registry: ProviderRegistry? = nil,
        settings: AppSettings? = nil,
        codexAuth: CodexAuthController? = nil,
        cursorAuth: CursorAuthController? = nil,
        claudeAuth: ClaudeAuthController? = nil
    ) {
        self.registry = registry ?? ProviderRegistry()
        self.settings = settings ?? .shared
        self.codexAuth = codexAuth ?? CodexAuthController()
        self.cursorAuth = cursorAuth ?? CursorAuthController()
        self.claudeAuth = claudeAuth ?? ClaudeAuthController()

        for provider in self.registry.providers {
            snapshots[provider.id] = .loading(providerID: provider.id, providerName: provider.displayName)
        }
        selectedProviderID = self.registry.enabledProviders.first?.id
            ?? self.registry.providers.first?.id
            ?? "codex"

        settingsCancellable = self.settings.$pollIntervalSeconds
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.didStart else { return }
                    self.restartPolling()
                }
            }

        self.codexAuth.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &authCancellables)

        self.cursorAuth.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &authCancellables)

        self.claudeAuth.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &authCancellables)

        self.notifications.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &authCancellables)
    }

    var selectedSnapshot: UsageSnapshot? {
        snapshots[selectedProviderID]
    }

    var trayTitle: String {
        guard settings.showPercentInTray,
              let snapshot = selectedSnapshot,
              let used = snapshot.primaryUsedPercent
        else {
            return "✦"
        }
        return "✦ \(Int(used.rounded()))%"
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        notifications.promptOnFirstLaunchIfNeeded()
        Task {
            await importLocalSessionsIfNeeded()
            restartPolling()
        }
    }

    /// Pick up sessions already present on this Mac (Codex CLI / Cursor IDE)
    /// without forcing a separate browser login. Safari/Chrome cookies are NOT shared.
    private func importLocalSessionsIfNeeded() async {
        var imported = false

        if !codexAuth.isAuthorized, CodexAuthStore.hasCLILoginAvailable {
            if await codexAuth.authorizeFromCLILogin() {
                imported = true
            }
        }

        if !cursorAuth.isAuthorized, CursorAuthStore.hasLocalCursorLogin {
            if await cursorAuth.authorizeFromLocalIDE() {
                imported = true
            }
        }

        if !claudeAuth.isAuthorized, ClaudeAuthStore.hasLocalDesktopLogin {
            if await claudeAuth.authorizeFromLocalDesktop() {
                imported = true
            }
        }

        if imported {
            codexAuth.refreshState()
            cursorAuth.refreshState()
            claudeAuth.refreshState()
        }
    }

    func requestNotificationPermissionFromSettings() {
        Task {
            _ = await notifications.enableFromSettings()
        }
    }

    func refreshNotificationPermissionState() {
        Task {
            await notifications.refreshPermissionState()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        authWaitTask?.cancel()
        authWaitTask = nil
    }

    func selectProvider(_ id: String) {
        selectedProviderID = id
    }

    func refreshNow() {
        Task { await refreshAll() }
    }

    func authorizeChatGPTBrowser() {
        codexAuth.openBrowserLogin()
        waitForAuthorization(isReady: { [weak self] in self?.codexAuth.isAuthorized == true }, attempts: 180)
    }

    func authorizeChatGPTFromCLI() {
        Task {
            let ok = await codexAuth.authorizeFromCLILogin()
            if ok { await refreshAll() }
        }
    }

    func authorizeCursor() {
        Task {
            let ok = await cursorAuth.authorizeFromLocalIDE()
            if ok { await refreshAll() }
        }
    }

    func authorizeClaudeBrowser() {
        claudeAuth.openBrowserLogin()
        waitForAuthorization(isReady: { [weak self] in self?.claudeAuth.isAuthorized == true }, attempts: 120)
    }

    func authorizeClaudeFromDesktop() {
        Task {
            let ok = await claudeAuth.authorizeFromLocalDesktop()
            if ok { await refreshAll() }
        }
    }

    func signOutCodex() {
        authWaitTask?.cancel()
        authWaitTask = nil
        codexAuth.signOut()
        snapshots["codex"] = .authNeeded(providerID: "codex", providerName: "Codex", message: "auth.chatgpt.needed")
    }

    func signOutCursor() {
        cursorAuth.signOut()
        snapshots["cursor"] = .authNeeded(providerID: "cursor", providerName: "Cursor", message: "auth.cursor.needed")
    }

    func signOutClaude() {
        authWaitTask?.cancel()
        authWaitTask = nil
        claudeAuth.signOut()
        snapshots["claude"] = .authNeeded(providerID: "claude", providerName: "Claude", message: "auth.claude.needed")
    }

    func uninstallCompletely() {
        do {
            try UninstallService.uninstallCompletely()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openSettings() {
        settingsOpen = true
        NSApp.activate(ignoringOtherApps: true)
    }

    func quit() {
        guard QuitConfirm.askUser() else { return }
        QuitConfirm.bypass = true
        stop()
        NSApp.terminate(nil)
    }

    private func waitForAuthorization(isReady: @escaping @MainActor () -> Bool, attempts: Int) {
        authWaitTask?.cancel()
        authWaitTask = Task { [weak self] in
            for _ in 0 ..< attempts {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                if isReady() {
                    await self.refreshAll()
                    return
                }
            }
        }
    }

    private func restartPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshAll()
            while !Task.isCancelled {
                let interval = max(15, self.settings.pollIntervalSeconds)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                await self.refreshAll()
            }
        }
    }

    private func refreshAll() async {
        if isRefreshing {
            pendingRefresh = true
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
            if pendingRefresh {
                pendingRefresh = false
                Task { await self.refreshAll() }
            }
        }

        let providers = registry.enabledProviders
        // Fetch off the main actor so Keychain/network work cannot stall the menu bar UI.
        let results: [(id: String, name: String, result: Result<UsageSnapshot, Error>)] = await withTaskGroup(
            of: (String, String, Result<UsageSnapshot, Error>).self,
            returning: [(String, String, Result<UsageSnapshot, Error>)].self
        ) { group in
            for provider in providers {
                let id = provider.id
                let name = provider.displayName
                group.addTask {
                    do {
                        let snapshot = try await provider.fetch()
                        return (id, name, .success(snapshot))
                    } catch {
                        return (id, name, .failure(error))
                    }
                }
            }

            var collected: [(String, String, Result<UsageSnapshot, Error>)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        if Task.isCancelled { return }

        for (id, name, result) in results {
            switch result {
            case .success(let snapshot):
                snapshots[id] = snapshot
                lastError = nil
                notifications.evaluate(snapshot: snapshot, settings: settings)
            case .failure(let error):
                lastError = error.localizedDescription
                snapshots[id] = UsageSnapshot(
                    providerID: id,
                    providerName: name,
                    fetchedAt: Date(),
                    status: .unavailable,
                    windows: snapshots[id]?.windows ?? [],
                    spend: snapshots[id]?.spend ?? SpendSummary(),
                    tokens: snapshots[id]?.tokens ?? TokenSummary(),
                    planName: snapshots[id]?.planName,
                    message: error.localizedDescription
                )
            }
        }

        codexAuth.refreshState()
        cursorAuth.refreshState()
        claudeAuth.refreshState()
    }
}
