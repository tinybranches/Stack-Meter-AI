import Foundation

/// ChatGPT (GPT) conversation / plan limits via undocumented backend endpoints.
struct GPTAPIClient: Sendable {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://chatgpt.com/backend-api")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func fetchLimits(credentials: CodexCredentials) async throws -> GPTLimitsResponse {
        let paths = ["conversation/limits", "f/conversation/limits"]
        var lastError: Error = ProviderError.badResponse("No ChatGPT limits endpoint responded.")
        var sawUnauthorized = false

        for path in paths {
            do {
                return try await get(path: path, credentials: credentials)
            } catch let error as ProviderError {
                if case .unauthorized = error {
                    sawUnauthorized = true
                    continue
                }
                if case .rateLimited = error { throw error }
                lastError = error
            } catch {
                lastError = error
            }
        }

        if sawUnauthorized { throw ProviderError.unauthorized }
        throw lastError
    }

    private func get(path: String, credentials: CodexCredentials) async throws -> GPTLimitsResponse {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("StackMeterAI/1.4", forHTTPHeaderField: "User-Agent")
        request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

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
            return try JSONDecoder().decode(GPTLimitsResponse.self, from: data)
        } catch {
            throw ProviderError.badResponse("Could not parse ChatGPT limits: \(error.localizedDescription)")
        }
    }
}

struct GPTLimitsResponse: Decodable, Sendable {
    let rateLimitReached: Bool?
    let messageCap: Double?
    let messageCapWindow: Double?
    let resetTime: Double?
    let limitReached: Bool?
    let usedPercent: Double?
    let remainingPercent: Double?
    let planType: String?
    let planName: String?

    // Nested / alternate shapes
    let rateLimit: CodexRateLimit?
    let credits: CodexCredits?

    enum CodingKeys: String, CodingKey {
        case rateLimitReached = "rate_limit_reached"
        case messageCap = "message_cap"
        case messageCapWindow = "message_cap_window"
        case resetTime = "reset_time"
        case limitReached = "limit_reached"
        case usedPercent = "used_percent"
        case remainingPercent = "remaining_percent"
        case planType = "plan_type"
        case planName = "plan_name"
        case rateLimit = "rate_limit"
        case credits
    }
}
