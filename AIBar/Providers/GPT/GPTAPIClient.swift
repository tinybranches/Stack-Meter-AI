import Foundation

/// ChatGPT plan / chat usage via ChatGPT backend.
///
/// Historical `conversation/limits` often returns 404 now. Current plans expose
/// the same rate-limit windows through `/wham/usage` (shared ChatGPT/Codex allowance
/// on many Plus/Pro plans — see OpenAI usage docs).
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
        // Prefer chat-specific endpoints when they still exist; fall back to wham/usage.
        let paths = [
            "conversation/limits",
            "f/conversation/limits",
            "wham/usage",
            "codex/usage",
        ]
        var lastError: Error = ProviderError.badResponse("No ChatGPT usage endpoint responded.")
        var sawUnauthorized = false

        for path in paths {
            do {
                let data = try await getData(path: path, credentials: credentials)
                if let limits = try? JSONDecoder().decode(GPTLimitsResponse.self, from: data),
                   limits.hasUsablePayload
                {
                    return limits
                }
                // wham/usage shape (CodexUsageResponse) — map into GPTLimitsResponse.
                if let usage = try? JSONDecoder().decode(CodexUsageResponse.self, from: data) {
                    return GPTLimitsResponse(from: usage)
                }
                lastError = ProviderError.badResponse("Unrecognized ChatGPT usage payload from \(path).")
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

    private func getData(path: String, credentials: CodexCredentials) async throws -> Data {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
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

    let rateLimit: CodexRateLimit?
    let credits: CodexCredits?

    /// True when we can render at least one meter or spend figure.
    var hasUsablePayload: Bool {
        rateLimit?.primaryWindow != nil
            || rateLimit?.secondaryWindow != nil
            || usedPercent != nil
            || remainingPercent != nil
            || messageCap != nil
            || credits?.balance?.value != nil
            || planType != nil
            || planName != nil
    }

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

    init(
        rateLimitReached: Bool? = nil,
        messageCap: Double? = nil,
        messageCapWindow: Double? = nil,
        resetTime: Double? = nil,
        limitReached: Bool? = nil,
        usedPercent: Double? = nil,
        remainingPercent: Double? = nil,
        planType: String? = nil,
        planName: String? = nil,
        rateLimit: CodexRateLimit? = nil,
        credits: CodexCredits? = nil
    ) {
        self.rateLimitReached = rateLimitReached
        self.messageCap = messageCap
        self.messageCapWindow = messageCapWindow
        self.resetTime = resetTime
        self.limitReached = limitReached
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.planType = planType
        self.planName = planName
        self.rateLimit = rateLimit
        self.credits = credits
    }

    init(from usage: CodexUsageResponse) {
        self.init(
            rateLimitReached: usage.rateLimit?.limitReached,
            limitReached: usage.rateLimit?.limitReached,
            planType: usage.planType,
            planName: usage.planName,
            rateLimit: usage.rateLimit,
            credits: usage.credits
        )
    }
}
