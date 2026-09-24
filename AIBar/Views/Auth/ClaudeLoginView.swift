import SwiftUI
import WebKit

/// Browser login for Claude.ai — captures the `sessionKey` cookie after sign-in.
struct ClaudeLoginView: View {
    var onSuccess: (String) -> Void
    var onCancel: () -> Void

    @State private var status = L10n.tr("auth.claude.loginHint")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("auth.claude.loginTitle"))
                    .font(.headline)
                Spacer()
                Button(L10n.tr("common.cancel")) { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)

            Divider()

            ClaudeWebView(status: $status) { sessionKey in
                onSuccess(sessionKey)
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

private struct ClaudeWebView: NSViewRepresentable {
    @Binding var status: String
    var onSessionKey: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(status: $status, onSessionKey: onSessionKey)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        var status: Binding<String>
        var onSessionKey: (String) -> Void
        weak var webView: WKWebView?
        private var didEmit = false
        private var isCancelled = false

        init(status: Binding<String>, onSessionKey: @escaping (String) -> Void) {
            self.status = status
            self.onSessionKey = onSessionKey
        }

        deinit {
            isCancelled = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            status.wrappedValue = L10n.tr("auth.claude.checkingCookies")
            pollCookies()
        }

        private func pollCookies() {
            guard let webView, !didEmit, !isCancelled else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.didEmit, !self.isCancelled else { return }
                if let session = cookies.first(where: { $0.name == "sessionKey" })?.value,
                   !session.isEmpty
                {
                    self.didEmit = true
                    DispatchQueue.main.async {
                        self.status.wrappedValue = L10n.tr("auth.claude.success")
                        self.onSessionKey(session)
                    }
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.pollCookies()
                }
            }
        }
    }
}
