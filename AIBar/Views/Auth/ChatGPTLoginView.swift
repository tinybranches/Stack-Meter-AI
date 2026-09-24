import SwiftUI
import WebKit
import AppKit

/// Browser login for ChatGPT — captures `accessToken` from `/api/auth/session` after sign-in.
struct ChatGPTLoginView: View {
    var onSuccess: (_ accessToken: String, _ accountID: String?) -> Void
    var onCancel: () -> Void

    @State private var status = L10n.tr("auth.chatgpt.loginHint")

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

            // Google Passkeys (Bluetooth / phone) often fail inside WKWebView.
            Text(L10n.tr("auth.chatgpt.passkeyHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04))

            Divider()

            ChatGPTWebView(status: $status) { token, accountID in
                onSuccess(token, accountID)
            }
            .frame(minWidth: 720, minHeight: 520)

            Divider()
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
    }
}

/// Persistent cookie/session store so Google OAuth / password login can complete.
enum ChatGPTWebLoginStore {
    /// Stable ID so cookies survive between login attempts.
    private static let storeID = UUID(uuidString: "6F2C9B1A-8D4E-4F3A-9C71-2E5B8A0D4F11")!

    static var dataStore: WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: storeID)
    }

    static func clear() {
        let store = dataStore
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {}
        }
    }
}

private enum SafariUserAgent {
    /// Look like desktop Safari — Google often rejects the default WKWebView UA.
    static let value =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15"
}

private struct ChatGPTWebView: NSViewRepresentable {
    @Binding var status: String
    var onSession: (_ accessToken: String, _ accountID: String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(status: $status, onSession: onSession)
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
        webView.customUserAgent = SafariUserAgent.value
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.load(URLRequest(url: URL(string: "https://chatgpt.com/auth/login")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var status: Binding<String>
        var onSession: (_ accessToken: String, _ accountID: String?) -> Void
        weak var webView: WKWebView?
        private var didEmit = false
        private var pollTask: Task<Void, Never>?

        init(
            status: Binding<String>,
            onSession: @escaping (_ accessToken: String, _ accountID: String?) -> Void
        ) {
            self.status = status
            self.onSession = onSession
        }

        deinit {
            pollTask?.cancel()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateStatusForURL(webView.url)
            startPolling()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            updateStatusForURL(navigationAction.request.url)
            decisionHandler(.allow)
        }

        /// Google / Apple OAuth often opens a popup — keep it in this WKWebView.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
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
                self.status.wrappedValue = L10n.tr("auth.chatgpt.success")
                self.onSession(token, accountID)
            }
        }

        private func updateStatusForURL(_ url: URL?) {
            guard let host = url?.host?.lowercased() else { return }
            if host.contains("accounts.google.com") || host.contains("google.com") {
                status.wrappedValue = L10n.tr("auth.chatgpt.googleHint")
            } else if host.contains("chatgpt.com") || host.contains("openai.com") {
                status.wrappedValue = L10n.tr("auth.chatgpt.checkingSession")
            }
        }

        private func startPolling() {
            pollTask?.cancel()
            pollTask = Task { @MainActor in
                while !Task.isCancelled && !didEmit {
                    await probeSession()
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }
            }
        }

        @MainActor
        private func probeSession() async {
            guard let webView, !didEmit else { return }
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
