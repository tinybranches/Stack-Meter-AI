import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var language = LanguageStore.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()

            if let snapshot = viewModel.selectedSnapshot {
                content(for: snapshot)
            } else {
                Text(L10n.tr("popover.noProvider"))
                    .foregroundStyle(.secondary)
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
        .environment(\.locale, language.resolved.locale)
        .id(language.resolved)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stack Meter AI")
                .font(.headline)

            if viewModel.registry.enabledProviders.count > 1 {
                providerTabs
            } else {
                HStack(spacing: 6) {
                    StatusDot(
                        status: viewModel.selectedSnapshot?.status ?? .loading,
                        isLimited: viewModel.selectedSnapshot?.isLimited == true
                    )
                    Text(viewModel.selectedSnapshot?.providerName ?? "Codex")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var providerTabs: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.registry.enabledProviders, id: \.id) { provider in
                let selected = viewModel.selectedProviderID == provider.id
                let snapshot = viewModel.snapshots[provider.id]
                let status = snapshot?.status ?? .loading
                Button {
                    viewModel.selectProvider(provider.id)
                } label: {
                    HStack(spacing: 5) {
                        StatusDot(status: status, isLimited: snapshot?.isLimited == true)
                        Text(provider.displayName)
                            .font(.caption.weight(selected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06),
                        in: Capsule()
                    )
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func content(for snapshot: UsageSnapshot) -> some View {
        switch snapshot.status {
        case .authNeeded:
            AuthNeededView(viewModel: viewModel)
        case .loading:
            HStack {
                ProgressView()
                Text(L10n.tr("popover.fetching"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            metrics(for: snapshot)
        }
    }

    @ViewBuilder
    private func metrics(for snapshot: UsageSnapshot) -> some View {
        if let plan = snapshot.planName {
            Text(plan)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if snapshot.windows.isEmpty {
            Text(L10n.text(snapshot.message) ?? L10n.tr("popover.noWindows"))
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(snapshot.windows) { window in
                    RateWindowRow(window: window)
                }
            }
            if let message = L10n.text(snapshot.message),
               snapshot.status != .unavailable
            {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if snapshot.spend.hasAnyValue || snapshot.tokens.hasAnyValue {
            Divider()
            HStack(alignment: .top, spacing: 16) {
                if snapshot.spend.hasAnyValue {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("popover.spend"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let credits = snapshot.spend.creditsBalance {
                            Text(L10n.tr("popover.credits", credits))
                                .font(.callout.monospacedDigit())
                        }
                        if let spend = snapshot.spend.spendUSD {
                            Text(L10n.tr("popover.usedUSD", spend))
                                .font(.callout.monospacedDigit())
                        }
                    }
                }

                if snapshot.tokens.hasAnyValue {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("popover.tokens"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(L10n.tr("popover.tokensToday", formatTokens(snapshot.tokens.today)))
                            .font(.callout.monospacedDigit())
                        Text(L10n.tr("popover.tokensMonth", formatTokens(snapshot.tokens.month)))
                            .font(.callout.monospacedDigit())
                    }
                }
            }
        }

        if let message = L10n.text(snapshot.message),
           snapshot.status == .unavailable,
           !snapshot.windows.isEmpty
        {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        let updated = snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)
        Text(L10n.tr("popover.updated", updated))
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.refreshNow()
            } label: {
                Label(
                    viewModel.isRefreshing ? L10n.tr("common.refreshing") : L10n.tr("common.refresh"),
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(viewModel.isRefreshing)

            Button(L10n.tr("common.settings")) {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }

            Spacer()

            Button(L10n.tr("common.quit")) {
                viewModel.quit()
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
    }

    private func formatTokens(_ value: Int?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.notation(.compactName).locale(LanguageRuntime.current.locale))
    }
}

private struct AuthNeededView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.callout.weight(.semibold))

            Text(L10n.text(viewModel.selectedSnapshot?.message) ?? defaultMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch viewModel.selectedProviderID {
            case "codex":
                Button {
                    viewModel.authorizeChatGPTBrowser()
                } label: {
                    Label(L10n.tr("auth.chatgpt.browserLogin"), systemImage: "globe")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if viewModel.codexAuth.hasCLILoginAvailable {
                    Button {
                        viewModel.authorizeChatGPTFromCLI()
                    } label: {
                        Label(L10n.tr("auth.chatgpt.fromCLI"), systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.codexAuth.isBusy)
                }

                if let error = viewModel.codexAuth.errorMessage {
                    Text(error).font(.caption2).foregroundStyle(.red)
                }
                if let status = viewModel.codexAuth.statusMessage {
                    Text(status).font(.caption2).foregroundStyle(.secondary)
                }

            case "cursor":
                Button {
                    viewModel.authorizeCursor()
                } label: {
                    Label(L10n.tr("auth.cursor.authorize"), systemImage: "laptopcomputer")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.cursorAuth.isBusy)

                if let error = viewModel.cursorAuth.errorMessage {
                    Text(error).font(.caption2).foregroundStyle(.red)
                }
                if let status = viewModel.cursorAuth.statusMessage {
                    Text(status).font(.caption2).foregroundStyle(.secondary)
                }

            case "claude":
                Button {
                    viewModel.authorizeClaudeBrowser()
                } label: {
                    Label(L10n.tr("auth.claude.browserLogin"), systemImage: "globe")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if let error = viewModel.claudeAuth.errorMessage {
                    Text(error).font(.caption2).foregroundStyle(.red)
                }
                if let status = viewModel.claudeAuth.statusMessage {
                    Text(status).font(.caption2).foregroundStyle(.secondary)
                }

            default:
                EmptyView()
            }
        }
    }

    private var title: String {
        switch viewModel.selectedProviderID {
        case "cursor": return L10n.tr("auth.cursor.title")
        case "claude": return L10n.tr("auth.claude.title")
        default: return L10n.tr("auth.title")
        }
    }

    private var defaultMessage: String {
        switch viewModel.selectedProviderID {
        case "codex": return L10n.tr("auth.chatgpt.needed")
        case "cursor": return L10n.tr("auth.cursor.needed")
        case "claude": return L10n.tr("auth.claude.needed")
        default: return L10n.tr("auth.needed")
        }
    }
}

private struct RateWindowRow: View {
    let window: RateWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.text(window.name) ?? window.name)
                    .font(.callout.weight(.medium))
                Spacer()
                Text(L10n.tr("popover.usedPercent", Int(window.usedPercent.rounded())))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(barColor)
            }
            ProgressView(value: min(1, window.usedPercent / 100))
                .tint(barColor)
            HStack {
                Text(L10n.tr("popover.leftPercent", Int(window.remainingPercent.rounded())))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let resetAt = window.resetAt {
                    let formatted = resetAt.formatted(date: .abbreviated, time: .shortened)
                    Text(L10n.tr("popover.resets", formatted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var barColor: Color {
        if window.limitReached || window.usedPercent >= 95 { return .red }
        if window.usedPercent >= 80 { return .orange }
        return .green
    }
}
