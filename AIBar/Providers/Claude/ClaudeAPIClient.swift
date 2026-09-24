import Foundation

struct ClaudeOrganizationDTO: Decodable, Sendable {
    let uuid: String?
    let name: String?
}

struct ClaudeOrganizationsResponse: Decodable, Sendable {
    // API may return a bare array or wrapped object.
    let organizations: [ClaudeOrganizationDTO]?

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([ClaudeOrganizationDTO].self) {
            organizations = array
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let orgs = try container.decodeIfPresent([ClaudeOrganizationDTO].self, forKey: .organizations) {
            organizations = orgs
        } else {
            organizations = try container.decodeIfPresent([ClaudeOrganizationDTO].self, forKey: .data)
        }
    }

    enum CodingKeys: String, CodingKey {
        case organizations, data
    }
}

struct ClaudeUsageWindowDTO: Decodable, Sendable {
    let utilization: Double?
    let resets_at: String?
    let resetsAt: String?

    var resetsISO: String? { resetsAt ?? resets_at }
}

struct ClaudeUsageResponse: Decodable, Sendable {
    let five_hour: ClaudeUsageWindowDTO?
    let seven_day: ClaudeUsageWindowDTO?
    let seven_day_sonnet: ClaudeUsageWindowDTO?
    let seven_day_opus: ClaudeUsageWindowDTO?

    // Also accept camelCase variants if present.
    let fiveHour: ClaudeUsageWindowDTO?
    let sevenDay: ClaudeUsageWindowDTO?

    var fiveHourWindow: ClaudeUsageWindowDTO? { five_hour ?? fiveHour }
    var sevenDayWindow: ClaudeUsageWindowDTO? { seven_day ?? sevenDay }
}

struct ClaudeAPIClient: Sendable {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://claude.ai")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func fetchOrganizations(sessionKey: String) async throws -> [ClaudeOrganizationDTO] {
        let url = baseURL.appending(path: "api/organizations")
        let data = try await get(url: url, sessionKey: sessionKey)
        // Try array first, then wrapped.
        if let orgs = try? JSONDecoder().decode([ClaudeOrganizationDTO].self, from: data) {
            return orgs
        }
        let wrapped = try JSONDecoder().decode(ClaudeOrganizationsResponse.self, from: data)
        return wrapped.organizations ?? []
    }

    func fetchUsage(sessionKey: String, organizationID: String) async throws -> ClaudeUsageResponse {
        let url = baseURL
            .appending(path: "api/organizations")
            .appending(path: organizationID)
            .appending(path: "usage")
        let data = try await get(url: url, sessionKey: sessionKey)
        do {
            return try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        } catch {
            throw ProviderError.badResponse("Could not parse Claude usage: \(error.localizedDescription)")
        }
    }

    private func get(url: URL, sessionKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("StackMeterAI/1.2", forHTTPHeaderField: "User-Agent")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.badResponse("Invalid HTTP response.")
        }

        switch http.statusCode {
        case 200 ... 299:
            return data
        case 401, 403:
            throw ProviderError.unauthorized
        case 429:
            throw ProviderError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.badResponse("HTTP \(http.statusCode): \(body.prefix(200))")
        }
    }
}
