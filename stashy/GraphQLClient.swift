//
//  GraphQLClient.swift
//  stashy
//
//  Created for architecture improvement - Phase 1
//

import Foundation
import Combine

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

// MARK: - GraphQL Client

actor GraphQLClient {
    static let shared = GraphQLClient()
    
    private var session: URLSession
    private let timeout: TimeInterval
    private var cancellables = Set<AnyCancellable>()
    
    init(session: URLSession? = nil, timeout: TimeInterval = 30.0) {
        self.timeout = timeout
        
        // Create custom URLSession configuration for better local server connectivity
        if let customSession = session {
            self.session = customSession
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeout
            config.timeoutIntervalForResource = timeout * 2
            config.waitsForConnectivity = false
            config.allowsCellularAccess = true
            config.allowsConstrainedNetworkAccess = true
            config.allowsExpensiveNetworkAccess = true
            
            // Standard TLS validation (system trust store)
            self.session = URLSession(configuration: config)
        }
    }

    /// Cancel all pending requests and reset the session.
    /// Useful when switching servers to prevent old data from being processed.
    func cancelAllRequests() {
        session.invalidateAndCancel()
        
        // Re-create the session with the same configuration and delegate
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.waitsForConnectivity = false
        config.allowsCellularAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        
        self.session = URLSession(configuration: config)
        print("📱 GraphQL: Cancelled all pending requests and reset session")
    }
    
    // MARK: - Async/Await API (Preferred)
    
    /// Execute a GraphQL query and decode the response
    func execute<T: Decodable>(
        query: String,
        variables: [String: Any]? = nil,
        retryCount: Int = 0
    ) async throws -> T {
        let request = try await buildRequest(query: query, variables: variables)
        
        let (data, response) = try await session.data(for: request)
        
        // 1. Peek for "database is locked" errors FIRST
        // This allows retry logic to trigger even if validateResponse would throw
        if isDatabaseLocked(data: data) {
            if retryCount < 3 {
                let waitTime = UInt64(500 * 1_000_000 * (retryCount + 1)) // 500ms, 1000ms, 1500ms
                print("⚠️ GraphQL: Database is locked. Retrying in \(Double(waitTime)/1_000_000_000)s... (Attempt \(retryCount + 1))")
                try await Task.sleep(nanoseconds: waitTime)
                return try await execute(query: query, variables: variables, retryCount: retryCount + 1)
            } else {
                print("❌ GraphQL: Database is locked after 3 retries.")
                throw GraphQLNetworkError.graphQLError(message: "Database is locked")
            }
        }
        
        // 2. Validate other aspects of the response
        try validateResponse(response, data: data)
        
        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            throw GraphQLNetworkError.decodingError(error)
        }
    }
    
    /// Execute a GraphQL query and return raw data
    func executeRaw(query: String, variables: [String: Any]? = nil) async throws -> Data {
        let request = try await buildRequest(query: query, variables: variables)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return data
    }
    
    // MARK: - Combine API (For backward compatibility)
    
    /// Execute a GraphQL query using Combine (for existing code compatibility)
    func execute<T: Decodable>(
        query: String,
        variables: [String: Any]? = nil
    ) -> AnyPublisher<T, GraphQLNetworkError> {
        return Future { promise in
            Task {
                do {
                    let result: T = try await self.execute(query: query, variables: variables)
                    promise(.success(result))
                } catch let error as GraphQLNetworkError {
                    promise(.failure(error))
                } catch {
                    promise(.failure(.networkError(error)))
                }
            }
        }
        .eraseToAnyPublisher()
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
        
        let request = try await buildRequest(query: bodyString, variables: nil)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        
        return try JSONDecoder().decode([String: StashJSONValue].self, from: data)
    }
    
    /// Execute a GraphQL mutation with completion handler (for gradual migration)
    nonisolated func performMutation(
        mutation: String,
        variables: [String: Any],
        completion: @escaping (Result<[String: StashJSONValue], GraphQLNetworkError>) -> Void
    ) {
        Task {
            do {
                let decoded = try await performMutation(mutation: mutation, variables: variables)
                await MainActor.run {
                    completion(.success(decoded))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error as? GraphQLNetworkError ?? .networkError(error)))
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private nonisolated func isDatabaseLocked(data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = json["errors"] as? [[String: Any]] else {
            return false
        }
        
        for error in errors {
            if let message = error["message"] as? String, message.contains("database is locked") {
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
        
        // Add API Key if available
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
            #if DEBUG
            print("📱 GraphQL: Using API key (first 8 chars): \(String(apiKey.prefix(8)))...")
            #endif
        }
        
        // Build request body
        if let variables = variables {
            let body: [String: Any] = [
                "query": query,
                "variables": variables
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else {
            // Query is already a complete JSON body string
            request.httpBody = query.data(using: .utf8)
        }
        
        #if DEBUG
        print("📱 GraphQL request to: \(urlString)")
        #endif
        
        return request
    }
    
    private nonisolated func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }
        
        #if DEBUG
        print("📱 GraphQL Status Code: \(httpResponse.statusCode)")
        if let str = String(data: data, encoding: .utf8) {
            print("📱 GraphQL Response: \(str.prefix(500))")
        }
        #endif
        
        switch httpResponse.statusCode {
        case 200...299:
            // Check for GraphQL errors in successful response
            if let responseString = String(data: data, encoding: .utf8),
               responseString.contains("\"errors\"") && responseString.contains("\"data\":null") {
                if responseString.contains("Cannot query field") {
                    throw GraphQLNetworkError.graphQLError(message: "GraphQL schema not compatible")
                }
                throw GraphQLNetworkError.graphQLError(message: "Query failed")
            }
            return
            
        case 401:
            NotificationCenter.default.post(name: NSNotification.Name("AuthError401"), object: nil)
            throw GraphQLNetworkError.unauthorized
            
        default:
            let message = String(data: data, encoding: .utf8)
            throw GraphQLNetworkError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}
