import SwiftUI
import WebKit

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
        config.websiteDataStore = .nonPersistent()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.load(URLRequest(url: URL(string: "https://chatgpt.com/auth/login")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
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
            status.wrappedValue = L10n.tr("auth.chatgpt.checkingSession")
            startPolling()
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
