import Foundation

struct CursorUsageSummaryDTO: Decodable, Sendable {
    let membershipType: String?
    let billingCycleEnd: String?
    let isUnlimited: Bool?
    let individualUsage: CursorIndividualUsageDTO?
    let teamUsage: CursorTeamUsageDTO?

    enum CodingKeys: String, CodingKey {
        case membershipType, billingCycleEnd, isUnlimited, individualUsage, teamUsage
    }
}

struct CursorIndividualUsageDTO: Decodable, Sendable {
    let plan: CursorPlanUsageDTO?
    let onDemand: CursorMoneyUsageDTO?
    let overall: CursorMoneyUsageDTO?
}

struct CursorPlanUsageDTO: Decodable, Sendable {
    let enabled: Bool?
    let used: Double?
    let limit: Double?
    let remaining: Double?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
    let totalPercentUsed: Double?
}

struct CursorMoneyUsageDTO: Decodable, Sendable {
    let enabled: Bool?
    let used: Double?
    let limit: Double?
    let remaining: Double?
}

struct CursorTeamUsageDTO: Decodable, Sendable {
    let onDemand: CursorMoneyUsageDTO?
    let pooled: CursorMoneyUsageDTO?
}

struct CursorAPIClient: Sendable {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://cursor.com")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func fetchUsageSummary(credentials: CursorCredentials) async throws -> CursorUsageSummaryDTO {
        let url = baseURL.appending(path: "api/usage-summary")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("StackMeterAI/1.2", forHTTPHeaderField: "User-Agent")
        // Cursor dashboard uses WorkosCursorSessionToken cookie derived from the access JWT.
        let cookie = "WorkosCursorSessionToken=\(credentials.accessToken)"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

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
            break
        case 401, 403:
            throw ProviderError.unauthorized
        case 429:
            throw ProviderError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.badResponse("HTTP \(http.statusCode): \(body.prefix(200))")
        }

        do {
            return try JSONDecoder().decode(CursorUsageSummaryDTO.self, from: data)
        } catch {
            throw ProviderError.badResponse("Could not parse Cursor usage: \(error.localizedDescription)")
        }
    }
}
