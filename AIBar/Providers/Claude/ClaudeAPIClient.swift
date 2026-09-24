import Foundation

struct ClaudeOrganizationDTO: Decodable, Sendable {
    let uuid: String?
    let name: String?
    let capabilities: [String]?
}

struct ClaudeOrganizationsResponse: Decodable, Sendable {
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

    let fiveHour: ClaudeUsageWindowDTO?
    let sevenDay: ClaudeUsageWindowDTO?

    var fiveHourWindow: ClaudeUsageWindowDTO? { five_hour ?? fiveHour }
    var sevenDayWindow: ClaudeUsageWindowDTO? { seven_day ?? sevenDay }
}

struct ClaudeAPIClient: Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let browserUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15"

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://claude.ai")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    /// Prefer the claude.ai chat org (capabilities include "chat"), not the API console org.
    static func resolveOrganizationID(
        in orgs: [ClaudeOrganizationDTO],
        preferredID: String? = nil
    ) -> String? {
        if let chatOrg = orgs.first(where: { ($0.capabilities ?? []).contains("chat") }),
           let chatID = chatOrg.uuid, !chatID.isEmpty
        {
            return chatID
        }
        if let preferredID, !preferredID.isEmpty,
           orgs.contains(where: { $0.uuid == preferredID })
        {
            return preferredID
        }
        return orgs.first?.uuid
    }

    func fetchOrganizations(sessionKey: String) async throws -> [ClaudeOrganizationDTO] {
        let url = baseURL.appending(path: "api/organizations")
        let data = try await get(url: url, sessionKey: sessionKey, organizationID: nil)
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
        let data = try await get(url: url, sessionKey: sessionKey, organizationID: organizationID)
        do {
            return try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        } catch {
            throw ProviderError.badResponse("Could not parse Claude usage: \(error.localizedDescription)")
        }
    }

    /// Resolve chat org and fetch usage, retrying other orgs on permission_error.
    func fetchUsageResolvingOrg(
        sessionKey: String,
        preferredOrganizationID: String?
    ) async throws -> (usage: ClaudeUsageResponse, organizationID: String) {
        let orgs = try await fetchOrganizations(sessionKey: sessionKey)
        guard !orgs.isEmpty else {
            throw ProviderError.notAuthenticated("auth.claude.noOrg")
        }

        var candidates: [String] = []
        if let resolved = Self.resolveOrganizationID(in: orgs, preferredID: preferredOrganizationID) {
            candidates.append(resolved)
        }
        for org in orgs {
            if let id = org.uuid, !id.isEmpty, !candidates.contains(id) {
                candidates.append(id)
            }
        }

        var lastError: Error = ProviderError.notAuthenticated("auth.claude.noOrg")
        for orgID in candidates {
            do {
                let usage = try await fetchUsage(sessionKey: sessionKey, organizationID: orgID)
                return (usage, orgID)
            } catch ProviderError.wrongOrganization {
                lastError = ProviderError.wrongOrganization
                continue
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func get(url: URL, sessionKey: String, organizationID: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")

        var cookie = "sessionKey=\(sessionKey)"
        if let organizationID, !organizationID.isEmpty {
            cookie += "; lastActiveOrg=\(organizationID)"
        }
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

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
        case 401:
            throw ProviderError.unauthorized
        case 403:
            if isPermissionError(data) {
                throw ProviderError.wrongOrganization
            }
            throw ProviderError.unauthorized
        case 429:
            throw ProviderError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.badResponse("HTTP \(http.statusCode): \(body.prefix(200))")
        }
    }

    private func isPermissionError(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let error = json["error"] as? [String: Any],
           let type = error["type"] as? String,
           type == "permission_error"
        {
            return true
        }
        let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? ""
        return message.localizedCaseInsensitiveContains("Invalid authorization for organization")
    }
}
