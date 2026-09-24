import SwiftUI
import AppKit

/// Claude authorization without WKWebView — Claude.ai blanks out inside embedded browsers.
struct ClaudeLoginView: View {
    var onSuccess: (String) -> Void
    var onCancel: () -> Void
    var onImportDesktop: (() -> Void)?

    @State private var status = L10n.tr("auth.claude.loginHint")
    @State private var manualKey = ""
    @State private var isImporting = false

    private var hasDesktop: Bool { ClaudeAuthStore.hasLocalDesktopLogin }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.tr("auth.claude.loginTitle"))
                    .font(.headline)
                Spacer()
                Button(L10n.tr("common.cancel")) { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.tr("auth.claude.noWebViewExplain"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Group {
                        Text(L10n.tr("auth.claude.stepDesktopTitle"))
                            .font(.subheadline.weight(.semibold))
                        Text(L10n.tr("auth.claude.stepDesktopBody"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            isImporting = true
                            status = L10n.tr("auth.connecting")
                            onImportDesktop?()
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                isImporting = false
                            }
                        } label: {
                            Label(L10n.tr("auth.claude.fromDesktop"), systemImage: "laptopcomputer")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!hasDesktop || isImporting)

                        if !hasDesktop {
                            Text(L10n.tr("auth.claude.noDesktop"))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    Divider()

                    Group {
                        Text(L10n.tr("auth.claude.stepSafariTitle"))
                            .font(.subheadline.weight(.semibold))
                        Text(L10n.tr("auth.claude.stepSafariBody"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            NSWorkspace.shared.open(URL(string: "https://claude.ai/login")!)
                            status = L10n.tr("auth.claude.safariHint")
                        } label: {
                            Label(L10n.tr("auth.claude.openSafari"), systemImage: "safari")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        HStack(spacing: 8) {
                            SecureField(L10n.tr("auth.claude.pasteKey"), text: $manualKey)
                                .textFieldStyle(.roundedBorder)
                            Button(L10n.tr("auth.claude.useKey")) {
                                let key = normalizeSessionKey(manualKey)
                                guard !key.isEmpty else { return }
                                status = L10n.tr("auth.connecting")
                                onSuccess(key)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(normalizeSessionKey(manualKey).isEmpty)
                        }
                    }
                }
                .padding(16)
            }

            Divider()
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 480)
    }

    /// Accepts raw cookie value or a full `sessionKey=...` / Cookie header paste.
    private func normalizeSessionKey(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("sessionkey=") {
            value = String(value.dropFirst("sessionKey=".count))
        }
        if let range = value.range(of: "sessionKey=") {
            let rest = value[range.upperBound...]
            value = String(rest.split(separator: ";").first ?? Substring(rest))
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
