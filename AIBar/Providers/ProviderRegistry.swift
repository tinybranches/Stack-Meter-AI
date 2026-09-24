import Foundation

@MainActor
final class ProviderRegistry: ObservableObject {
    @Published private(set) var providers: [any UsageProvider]

    init(
        providers: [any UsageProvider] = [
            CodexProvider(),
            GPTProvider(),
            CursorProvider(),
            ClaudeProvider(),
        ]
    ) {
        self.providers = providers
    }

    func provider(id: String) -> (any UsageProvider)? {
        providers.first { $0.id == id }
    }

    var enabledIDs: [String] {
        AppSettings.shared.enabledProviderIDs
    }

    var enabledProviders: [any UsageProvider] {
        let enabled = Set(enabledIDs)
        let filtered = providers.filter { enabled.contains($0.id) }
        return filtered.isEmpty ? providers : filtered
    }
}
