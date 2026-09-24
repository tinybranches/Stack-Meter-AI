import SwiftUI
import WebKit
import AppKit

/// ChatGPT login: in-app browser (best-effort) + reliable Codex CLI import.
struct ChatGPTLoginView: View {
    var onSuccess: (_ accessToken: String, _ accountID: String?) -> Void
    var onCancel: () -> Void
    var onImportCLI: (() -> Void)?

    @State private var status = L10n.tr("auth.chatgpt.loginHint")
    @State private var isLoading = true
    @State private var loadFailed = false
    @StateObject private var bridge = ChatGPTWebBridge()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("auth.chatgpt.loginTitle"))
                    .font(.headline)
                Spacer()
                Button(L10n.tr("common.cancel")) { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)

            Divider()

            // Reliable path first — WebView Google OAuth often blanks out.
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("auth.chatgpt.cliPrimary"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://chatgpt.com/auth/login")!)
                    } label: {
                        Label(L10n.tr("auth.chatgpt.openSafari"), systemImage: "safari")
                    }
                    .controlSize(.small)

                    Button {
                        copyCLICommand()
                        openTerminalHint()
                    } label: {
                        Label(L10n.tr("auth.chatgpt.copyCLI"), systemImage: "terminal")
                    }
                    .controlSize(.small)

                    Button {
                        onImportCLI?()
                    } label: {
                        Label(L10n.tr("auth.chatgpt.fromCLI"), systemImage: "key.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))

            Divider()

            ZStack {
                ChatGPTWebView(
                    bridge: bridge,
                    status: $status,
                    isLoading: $isLoading,
                    loadFailed: $loadFailed,
                    onSession: onSuccess
                )

                if isLoading && !loadFailed {
                    ProgressView(L10n.tr("auth.chatgpt.loadingPage"))
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }

                if loadFailed {
                    VStack(spacing: 10) {
                        Text(L10n.tr("auth.chatgpt.loadFailed"))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button(L10n.tr("auth.chatgpt.reload")) {
                            loadFailed = false
                            isLoading = true
                            bridge.reload()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                }
            }
            .frame(minWidth: 720, minHeight: 420)

            Divider()
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .onAppear {
            bridge.startLoadWatchdog { stuck in
                if stuck {
                    isLoading = false
                    loadFailed = true
                    status = L10n.tr("auth.chatgpt.loadFailed")
                }
            }
        }
        .onDisappear {
            bridge.cancelWatchdog()
        }
    }

    private func copyCLICommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("codex login", forType: .string)
        status = L10n.tr("auth.chatgpt.cliCopied")
    }

    private func openTerminalHint() {
        // Best-effort: open Terminal; user pastes `codex login`.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

@MainActor
final class ChatGPTWebBridge: ObservableObject {
    weak var webView: WKWebView?
    private var watchdog: Task<Void, Never>?

    func reload() {
        webView?.stopLoading()
        webView?.load(URLRequest(url: URL(string: "https://chatgpt.com/")!))
    }

    func startLoadWatchdog(onStuck: @escaping (Bool) -> Void) {
        cancelWatchdog()
        watchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 18_000_000_000)
            guard !Task.isCancelled else { return }
            // Still no meaningful title / blank → treat as stuck.
            let title = webView?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let loading = webView?.isLoading == true
            if loading || title.isEmpty {
                onStuck(true)
            }
        }
    }

    func cancelWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    func markLoaded() {
        cancelWatchdog()
    }
}

enum ChatGPTWebLoginStore {
    static var dataStore: WKWebsiteDataStore { .default() }

    static func clear() {
        let store = dataStore
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let openai = records.filter {
                let name = $0.displayName.lowercased()
                return name.contains("openai") || name.contains("chatgpt") || name.contains("google")
            }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: openai.isEmpty ? records : openai) {}
        }
    }
}

private struct ChatGPTWebView: NSViewRepresentable {
    @ObservedObject var bridge: ChatGPTWebBridge
    @Binding var status: String
    @Binding var isLoading: Bool
    @Binding var loadFailed: Bool
    var onSession: (_ accessToken: String, _ accountID: String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "stackMeterAuth")

        let config = WKWebViewConfiguration()
        config.websiteDataStore = ChatGPTWebLoginStore.dataStore
        config.userContentController = contentController
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        // Keep system UA — spoofing Safari often yields a blank Google page in WKWebView.
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.observeLoading(webView)
        bridge.webView = webView
        // Land on home; login UI is linked from there and redirects more reliably than /auth/login.
        webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        bridge.webView = nsView
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: ChatGPTWebView
        private var didEmit = false
        private var pollTask: Task<Void, Never>?
        private var loadingObservation: NSKeyValueObservation?
        private var popupWindows: [NSWindow] = []

        init(parent: ChatGPTWebView) {
            self.parent = parent
        }

        deinit {
            pollTask?.cancel()
            loadingObservation?.invalidate()
        }

        func observeLoading(_ webView: WKWebView) {
            loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    self?.parent.isLoading = view.isLoading
                    if !view.isLoading, !(view.title ?? "").isEmpty {
                        self?.parent.loadFailed = false
                        self?.parent.bridge.markLoaded()
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.loadFailed = false
            parent.status = L10n.tr("auth.chatgpt.loadingPage")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.loadFailed = false
            parent.bridge.markLoaded()
            updateStatusForURL(webView.url)
            startPolling()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            handleLoadError(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleLoadError(error)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            updateStatusForURL(navigationAction.request.url)
            decisionHandler(.allow)
        }

        /// Real popup window — loading Google OAuth into the same view often leaves a white screen.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            configuration.websiteDataStore = ChatGPTWebLoginStore.dataStore
            let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 720, height: 640), configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self

            let hosting = NSViewController()
            hosting.view = popup
            let window = NSWindow(contentViewController: hosting)
            window.title = L10n.tr("auth.chatgpt.loginTitle")
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 720, height: 640))
            window.center()
            window.makeKeyAndOrderFront(nil)
            popupWindows.append(window)

            if let url = navigationAction.request.url {
                popup.load(URLRequest(url: url))
            }
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            popupWindows.removeAll { $0.contentView === webView || $0.contentViewController?.view === webView }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "stackMeterAuth", !didEmit else { return }
            guard let body = message.body as? [String: Any],
                  let token = body["accessToken"] as? String,
                  !token.isEmpty
            else { return }

            didEmit = true
            pollTask?.cancel()
            let accountID = body["accountID"] as? String
            DispatchQueue.main.async {
                self.parent.status = L10n.tr("auth.chatgpt.success")
                self.parent.onSession(token, accountID)
                for window in self.popupWindows { window.close() }
                self.popupWindows.removeAll()
            }
        }

        private func handleLoadError(_ error: Error) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return }
            parent.isLoading = false
            parent.loadFailed = true
            parent.status = L10n.tr("auth.chatgpt.loadFailed")
        }

        private func updateStatusForURL(_ url: URL?) {
            guard let host = url?.host?.lowercased() else { return }
            if host.contains("accounts.google.com") {
                parent.status = L10n.tr("auth.chatgpt.googleHint")
            } else if host.contains("chatgpt.com") || host.contains("openai.com") {
                parent.status = L10n.tr("auth.chatgpt.checkingSession")
            }
        }

        private func startPolling() {
            pollTask?.cancel()
            pollTask = Task { @MainActor in
                while !Task.isCancelled && !didEmit {
                    await probeSession(in: parent.bridge.webView)
                    for window in popupWindows {
                        if let popup = window.contentView as? WKWebView {
                            await probeSession(in: popup)
                        }
                    }
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }
            }
        }

        @MainActor
        private func probeSession(in webView: WKWebView?) async {
            guard let webView, !didEmit else { return }
            let host = webView.url?.host?.lowercased() ?? ""
            guard host.contains("chatgpt.com") || host.contains("openai.com") else { return }

            let js = """
            (async function() {
              try {
                const res = await fetch('/api/auth/session', { credentials: 'include' });
                if (!res.ok) return null;
                const data = await res.json();
                if (!data || !data.accessToken) return null;
                const accountID = (data.account && (data.account.id || data.account.account_id))
                  || data.accountId
                  || null;
                window.webkit.messageHandlers.stackMeterAuth.postMessage({
                  accessToken: data.accessToken,
                  accountID: accountID
                });
                return true;
              } catch (e) {
                return null;
              }
            })();
            """
            _ = try? await webView.evaluateJavaScript(js)
        }
    }
}
