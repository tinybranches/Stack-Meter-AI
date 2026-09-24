import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var language = LanguageStore.shared
    @State private var showUninstallConfirm = false
    @State private var uninstallError: String?

    var body: some View {
        Form {
            Section(L10n.tr("language.section")) {
                Picker(L10n.tr("language.picker"), selection: $settings.languagePreference) {
                    ForEach(LanguagePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                Text(L10n.tr("language.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L10n.tr("settings.refresh")) {
                HStack {
                    Text(L10n.tr("settings.interval"))
                    Spacer()
                    Text("\(Int(settings.pollIntervalSeconds))s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.pollIntervalSeconds, in: 30 ... 600, step: 15)
            }

            Section(L10n.tr("settings.menuBar")) {
                Toggle(L10n.tr("settings.showPercent"), isOn: $settings.showPercentInTray)
            }

            Section(L10n.tr("settings.notifications")) {
                HStack {
                    Text(L10n.tr("notify.permission.status"))
                    Spacer()
                    Text(permissionStatusText)
                        .foregroundStyle(viewModel.notifications.permission == .authorized ? .green : .orange)
                }

                if viewModel.notifications.needsEnableButton {
                    Button(L10n.tr("notify.permission.enable")) {
                        viewModel.requestNotificationPermissionFromSettings()
                    }
                    Text(permissionHintText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(L10n.tr("notify.toggle.usageThreshold"), isOn: notifyToggle($settings.notifyUsageThreshold))
                if settings.notifyUsageThreshold {
                    HStack {
                        Text(L10n.tr("settings.warning"))
                        Spacer()
                        Text("\(Int(settings.warningThreshold))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $settings.warningThreshold,
                        in: 50 ... max(50, settings.criticalThreshold),
                        step: 5
                    )
                    HStack {
                        Text(L10n.tr("settings.critical"))
                        Spacer()
                        Text("\(Int(settings.criticalThreshold))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $settings.criticalThreshold,
                        in: min(100, settings.warningThreshold) ... 100,
                        step: 5
                    )
                }

                Toggle(L10n.tr("notify.toggle.rateLimited"), isOn: notifyToggle($settings.notifyRateLimited))
                Toggle(L10n.tr("notify.toggle.limitReset"), isOn: notifyToggle($settings.notifyLimitReset))
                Toggle(L10n.tr("notify.toggle.usageJump"), isOn: notifyToggle($settings.notifyUsageJump))
                if settings.notifyUsageJump {
                    HStack {
                        Text(L10n.tr("notify.jumpThreshold"))
                        Spacer()
                        Text("\(Int(settings.usageJumpPercent))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.usageJumpPercent, in: 5 ... 50, step: 5)
                }

                Toggle(L10n.tr("notify.toggle.sessionExpired"), isOn: notifyToggle($settings.notifySessionExpired))
                Toggle(L10n.tr("notify.toggle.lowCredits"), isOn: notifyToggle($settings.notifyLowCredits))
                if settings.notifyLowCredits {
                    HStack {
                        Text(L10n.tr("notify.creditsThreshold"))
                        Spacer()
                        Text(String(format: "$%.0f", settings.lowCreditsThreshold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.lowCreditsThreshold, in: 0 ... 20, step: 1)
                }

                Text(L10n.tr("notify.togglesHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("settings.providers")) {
                ForEach(viewModel.registry.providers, id: \.id) { provider in
                    Toggle(provider.displayName, isOn: binding(for: provider.id))
                }
                Text(L10n.tr("settings.providersHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("settings.chatgptAccount")) {
                accountRow(
                    authorized: viewModel.codexAuth.isAuthorized,
                    signOut: { viewModel.signOutCodex() }
                )
                if !viewModel.codexAuth.isAuthorized {
                    Button(L10n.tr("auth.chatgpt.browserLogin")) {
                        viewModel.authorizeChatGPTBrowser()
                    }
                    if viewModel.codexAuth.hasCLILoginAvailable {
                        Button(L10n.tr("auth.chatgpt.fromCLI")) {
                            viewModel.authorizeChatGPTFromCLI()
                        }
                        .disabled(viewModel.codexAuth.isBusy)
                    }
                }
                if let error = viewModel.codexAuth.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Text(L10n.tr("auth.chatgpt.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("settings.cursorAccount")) {
                accountRow(
                    authorized: viewModel.cursorAuth.isAuthorized,
                    signOut: { viewModel.signOutCursor() }
                )
                if !viewModel.cursorAuth.isAuthorized {
                    Button(L10n.tr("auth.cursor.authorize")) {
                        viewModel.authorizeCursor()
                    }
                    .disabled(viewModel.cursorAuth.isBusy)
                }
                Text(L10n.tr("auth.cursor.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("settings.claudeAccount")) {
                accountRow(
                    authorized: viewModel.claudeAuth.isAuthorized,
                    signOut: { viewModel.signOutClaude() }
                )
                if !viewModel.claudeAuth.isAuthorized {
                    if viewModel.claudeAuth.hasLocalDesktopLogin {
                        Button(L10n.tr("auth.claude.fromDesktop")) {
                            viewModel.authorizeClaudeFromDesktop()
                        }
                        .disabled(viewModel.claudeAuth.isBusy)
                    }
                    Button(L10n.tr("auth.claude.browserLogin")) {
                        viewModel.authorizeClaudeBrowser()
                    }
                }
                Text(L10n.tr("auth.claude.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(L10n.tr("settings.uninstall"), role: .destructive) {
                    showUninstallConfirm = true
                }
                Text(L10n.tr("settings.uninstallHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let uninstallError {
                    Text(uninstallError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text(L10n.tr("settings.danger"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420, height: 720)
        .environment(\.locale, language.resolved.locale)
        .id(language.resolved)
        .onAppear {
            viewModel.refreshNotificationPermissionState()
        }
        .confirmationDialog(
            L10n.tr("settings.uninstallTitle"),
            isPresented: $showUninstallConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.tr("settings.uninstallConfirm"), role: .destructive) {
                do {
                    try UninstallService.uninstallCompletely()
                } catch {
                    uninstallError = error.localizedDescription
                }
            }
            Button(L10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(UninstallService.confirmationDetails)
        }
    }

    private var permissionStatusText: String {
        switch viewModel.notifications.permission {
        case .authorized: return L10n.tr("notify.permission.allowed")
        case .denied: return L10n.tr("notify.permission.denied")
        case .notAsked, .notDetermined, .unknown: return L10n.tr("notify.permission.off")
        }
    }

    private var permissionHintText: String {
        switch viewModel.notifications.permission {
        case .denied: return L10n.tr("notify.permission.openSystemHint")
        default: return L10n.tr("notify.permission.enableHint")
        }
    }

    private func notifyToggle(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                let wasOff = !binding.wrappedValue
                binding.wrappedValue = newValue
                if newValue, wasOff {
                    viewModel.requestNotificationPermissionFromSettings()
                }
            }
        )
    }

    private func accountRow(authorized: Bool, signOut: @escaping () -> Void) -> some View {
        Group {
            HStack {
                Text(L10n.tr("common.status"))
                Spacer()
                Text(authorized ? L10n.tr("auth.authorized") : L10n.tr("auth.notAuthorized"))
                    .foregroundStyle(authorized ? .green : .orange)
            }
            if authorized {
                Button(L10n.tr("auth.signOut"), role: .destructive, action: signOut)
            }
        }
    }

    private func binding(for providerID: String) -> Binding<Bool> {
        Binding(
            get: { settings.enabledProviderIDs.contains(providerID) },
            set: { enabled in
                var ids = settings.enabledProviderIDs
                if enabled {
                    if !ids.contains(providerID) { ids.append(providerID) }
                } else {
                    ids.removeAll { $0 == providerID }
                    if ids.isEmpty { ids = [providerID] }
                }
                settings.enabledProviderIDs = ids
                if !ids.contains(viewModel.selectedProviderID), let first = ids.first {
                    viewModel.selectProvider(first)
                }
            }
        )
    }
}
