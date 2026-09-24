import Foundation

protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func fetch() async throws -> UsageSnapshot
}

enum ProviderError: LocalizedError, Equatable {
    case notAuthenticated(String)
    case unauthorized
    case rateLimited
    case badResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated(let message):
            return L10n.text(message) ?? message
        case .unauthorized:
            return L10n.tr("auth.expired")
        case .rateLimited:
            return L10n.tr("status.rateLimited")
        case .badResponse(let message):
            return message
        case .network(let message):
            return message
        }
    }
}
