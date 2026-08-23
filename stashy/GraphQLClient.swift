//
//  GraphQLClient.swift
//  stashy
//

import Foundation

// MARK: - Network Errors

enum GraphQLNetworkError: LocalizedError {
    case noServerConfig
    case invalidURL
    case unauthorized
    case serverError(statusCode: Int, message: String?)
    case graphQLError(message: String)
    case decodingError(Error)
    case networkError(Error)
    case timeout

    var errorDescription: String? {
        switch self {
        case .noServerConfig:
            return "Server configuration is missing or incomplete"
        case .invalidURL:
            return "Invalid server URL"
        case .unauthorized:
            return "API key is invalid or expired"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown")"
        case .graphQLError(let message):
            return "GraphQL error: \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    return "No internet connection"
                case .cannotConnectToHost:
                    return "Server not reachable - check IP/Port/SSL"
                case .timedOut:
                    return "Connection timed out - is server running?"
                default:
                    return "Network error: \(urlError.localizedDescription)"
                }
            }
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Request timed out"
        }
    }
}

// MARK: - SSL Trust Delegate

/// Accepts self-signed certificates for local/private Stash servers and the
/// explicitly whitelisted domains. Everything else falls back to standard TLS validation.
final class StashTrustDelegate: NSObject, URLSessionDelegate {
    static let whitelistedHosts: Set<String> = ["gole.tz"]

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if Self.acceptsSelfSigned(host: challenge.protectionSpace.host) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    static func acceptsSelfSigned(host: String) -> Bool {
        let normalizedHost = host.lowercased()
        if whitelistedHosts.contains(normalizedHost) { return true }
        if normalizedHost == "localhost" || normalizedHost == "::1" || normalizedHost.hasSuffix(".local") { return true }
        if normalizedHost.hasPrefix("127.") { return true }
        if normalizedHost.hasPrefix("10.") { return true }
        if normalizedHost.hasPrefix("192.168.") { return true }
        if isPrivate172Range(normalizedHost) { return true }
        return false
    }

    private static func isPrivate172Range(_ host: String) -> Bool {
        guard host.hasPrefix("172.") else { return false }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count >= 2 else { return false }
        return octets[1] >= 16 && octets[1] <= 31
    }
}

// MARK: - Session Factory

enum StashSessionFactory {
    static func make(timeout: TimeInterval = 30.0) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.waitsForConnectivity = false
        config.allowsCellularAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        return URLSession(configuration: config, delegate: StashTrustDelegate(), delegateQueue: nil)
    }
}

// MARK: - GraphQL Client

actor GraphQLClient {
    static let shared = GraphQLClient()

    private var session: URLSession
    private let timeout: TimeInterval
    static let maxDatabaseRetries = 3

    init(session: URLSession? = nil, timeout: TimeInterval = 30.0) {
        self.timeout = timeout
        self.session = session ?? StashSessionFactory.make(timeout: timeout)
    }

    /// Cancel all pending requests and reset the session.
    /// Useful when switching servers to prevent old data from being processed.
    func cancelAllRequests() {
        session.invalidateAndCancel()
        self.session = StashSessionFactory.make(timeout: timeout)
        AppLog.debug("📱 GraphQL: Cancelled all pending requests and reset session")
    }

    // MARK: - Async/Await API

    /// Execute a GraphQL query and decode the response
    func execute<T: Decodable>(
        query: String,
        variables: [String: Any]? = nil
    ) async throws -> T {
        try await Self.withDatabaseRetry {
            let request = try await buildRequest(query: query, variables: variables)
            let data = try await performRequest(request)
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw GraphQLNetworkError.decodingError(error)
            }
        }
    }

    /// Execute a GraphQL query and return raw data
    func executeRaw(query: String, variables: [String: Any]? = nil) async throws -> Data {
        try await Self.withDatabaseRetry {
            let request = try await buildRequest(query: query, variables: variables)
            return try await performRequest(request)
        }
    }

    /// Execute a GraphQL mutation using async/await
    func performMutation(
        mutation: String,
        variables: [String: Any]
    ) async throws -> [String: StashJSONValue] {
        var body: [String: Any] = ["query": mutation]
        body["variables"] = variables

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            throw GraphQLNetworkError.decodingError(NSError(domain: "JSONEncoding", code: -1))
        }

        return try await Self.withDatabaseRetry {
            let request = try await buildRequest(query: bodyString, variables: nil)
            let data = try await performRequest(request)
            do {
                return try JSONDecoder().decode([String: StashJSONValue].self, from: data)
            } catch {
                throw GraphQLNetworkError.decodingError(error)
            }
        }
    }

    // MARK: - Completion Handler API (For existing code)

    /// Execute a GraphQL query with completion handler (for gradual migration)
    nonisolated func execute<T: Decodable>(
        query: String,
        variables: [String: Any]? = nil,
        completion: @escaping (Result<T, GraphQLNetworkError>) -> Void
    ) {
        Task {
            do {
                let result: T = try await execute(query: query, variables: variables)
                await MainActor.run {
                    completion(.success(result))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error as? GraphQLNetworkError ?? .networkError(error)))
                }
            }
        }
    }

    // MARK: - Retry

    struct DatabaseLockedError: Error {}

    /// Retries an operation only when SQLite reports a locked database
    /// (a transient condition common with Stash's storage engine).
    /// Cancellation and all other errors propagate immediately.
    static func withDatabaseRetry<T>(
        maxAttempts: Int = GraphQLClient.maxDatabaseRetries,
        _ operation: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch is DatabaseLockedError {
                attempt += 1
                guard attempt < maxAttempts else {
                    AppLog.error("GraphQL: Database is locked after \(attempt) attempts")
                    throw GraphQLNetworkError.graphQLError(message: "Database is locked")
                }
                let waitNanos = UInt64(attempt) * 500_000_000
                AppLog.debug("⚠️ GraphQL: Database is locked. Retrying in \(waitNanos / 1_000_000)ms (Attempt \(attempt))")
                try await Task.sleep(nanoseconds: waitNanos)
            }
        }
    }

    // MARK: - Private Helpers

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        if Self.isDatabaseLocked(data: data) {
            throw DatabaseLockedError()
        }

        try validateResponse(response, data: data)
        return data
    }

    private nonisolated static func isDatabaseLocked(data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = json["errors"] as? [[String: Any]] else {
            return false
        }

        for error in errors {
            if let message = error["message"] as? String,
               message.lowercased().contains("database is locked") {
                return true
            }
        }
        return false
    }

    private func buildRequest(query: String, variables: [String: Any]?) async throws -> URLRequest {
        let (urlString, apiKey) = await MainActor.run { () -> (String?, String?) in
            guard let config = ServerConfigManager.shared.loadConfig(),
                  config.hasValidConfig else {
                return (nil, nil)
            }
            return ("\(config.baseURL)/graphql", config.secureApiKey)
        }

        guard let urlString = urlString, let url = URL(string: urlString) else {
            throw GraphQLNetworkError.noServerConfig
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData

        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
            #if DEBUG
            AppLog.debug("📱 GraphQL: Using \(AppLog.redacted(apiKey, label: "ApiKey"))")
            #endif
        }

        if let variables = variables {
            let body: [String: Any] = [
                "query": query,
                "variables": variables
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else {
            request.httpBody = query.data(using: .utf8)
        }

        #if DEBUG
        AppLog.debug("📱 GraphQL request to: \(urlString)")
        #endif

        return request
    }

    private nonisolated func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        #if DEBUG
        AppLog.debug("📱 GraphQL Status Code: \(httpResponse.statusCode)")
        if let str = String(data: data, encoding: .utf8) {
            AppLog.debug("📱 GraphQL Response: \(str.prefix(500))")
        }
        #endif

        switch httpResponse.statusCode {
        case 200...299:
            try throwOnFatalGraphQLErrors(in: data)

        case 401:
            NotificationCenter.default.post(name: NSNotification.Name("AuthError401"), object: nil)
            throw GraphQLNetworkError.unauthorized

        default:
            let message = String(data: data, encoding: .utf8)
            throw GraphQLNetworkError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    /// Throws when the response carries GraphQL errors *without* usable data
    /// (i.e. `"data"` is null or absent). Partial errors alongside real data are tolerated.
    private nonisolated func throwOnFatalGraphQLErrors(in data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = object["errors"] as? [[String: Any]], !errors.isEmpty,
              object["data"] == nil else {
            return
        }

        let messages = errors.compactMap { $0["message"] as? String }
        if messages.contains(where: { $0.contains("Cannot query field") }) {
            throw GraphQLNetworkError.graphQLError(message: "GraphQL schema not compatible")
        }
        throw GraphQLNetworkError.graphQLError(message: messages.first ?? "Query failed")
    }
}
