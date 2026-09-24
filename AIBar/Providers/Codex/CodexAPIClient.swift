import Foundation

struct CodexAPIClient: Sendable {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://chatgpt.com/backend-api")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func fetchUsage(credentials: CodexCredentials) async throws -> CodexUsageResponse {
        let paths = ["wham/usage", "codex/usage"]
        var lastError: Error = ProviderError.badResponse("No usage endpoint responded.")
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

    private func get(path: String, credentials: CodexCredentials) async throws -> CodexUsageResponse {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("StackMeterAI/1.2", forHTTPHeaderField: "User-Agent")
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
            return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        } catch {
            throw ProviderError.badResponse("Could not parse usage response: \(error.localizedDescription)")
        }
    }
}
