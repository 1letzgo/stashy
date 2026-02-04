//
//  GraphQLClient.swift
//  stashy
//
//  Created for architecture improvement - Phase 1
//

import Foundation
import Combine

// MARK: - URLSession Delegate for SSL Handling

class GraphQLURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        // Allow self-signed certificates for local development
        // This is common for local Stash servers
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            let host = challenge.protectionSpace.host
            
            #if DEBUG
            print("📱 SSL Challenge for host: \(host)")
            #endif
            
            // For local/private IP addresses, accept self-signed certificates
            if isLocalOrPrivateIP(host) {
                if let serverTrust = challenge.protectionSpace.serverTrust {
                    let credential = URLCredential(trust: serverTrust)
                    completionHandler(.useCredential, credential)
                    return
                }
            }
        }
        
        // For all other cases, use default handling
        completionHandler(.performDefaultHandling, nil)
    }
    
    private func isLocalOrPrivateIP(_ host: String) -> Bool {
        // Check for localhost
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return true
        }
        
        // Check for private IP ranges
        let privateRanges = [
            "10.",           // 10.0.0.0/8
            "172.16.",       // 172.16.0.0/12
            "172.17.",
            "172.18.",
            "172.19.",
            "172.20.",
            "172.21.",
            "172.22.",
            "172.23.",
            "172.24.",
            "172.25.",
            "172.26.",
            "172.27.",
            "172.28.",
            "172.29.",
            "172.30.",
            "172.31.",
            "192.168."       // 192.168.0.0/16
        ]
        
        return privateRanges.contains { host.hasPrefix($0) }
    }
}

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

class GraphQLClient {
    static let shared = GraphQLClient()
    
    private let session: URLSession
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
            
            // Create session with custom delegate for SSL handling
            self.session = URLSession(
                configuration: config,
                delegate: GraphQLURLSessionDelegate(),
                delegateQueue: nil
            )
        }
    }
    
    // MARK: - Async/Await API (Preferred)
    
    /// Execute a GraphQL query and decode the response
    func execute<T: Decodable>(
        query: String,
        variables: [String: Any]? = nil
    ) async throws -> T {
        let request = try buildRequest(query: query, variables: variables)
        
        let (data, response) = try await session.data(for: request)
        
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
        let request = try buildRequest(query: query, variables: variables)
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
        do {
            let request = try buildRequest(query: query, variables: variables)
            
            return session.dataTaskPublisher(for: request)
                .tryMap { [weak self] data, response in
                    try self?.validateResponse(response, data: data)
                    return data
                }
                .decode(type: T.self, decoder: JSONDecoder())
                .mapError { error -> GraphQLNetworkError in
                    if let networkError = error as? GraphQLNetworkError {
                        return networkError
                    } else if error is DecodingError {
                        return .decodingError(error)
                    } else {
                        return .networkError(error)
                    }
                }
                .eraseToAnyPublisher()
        } catch {
            return Fail(error: error as? GraphQLNetworkError ?? .networkError(error))
                .eraseToAnyPublisher()
        }
    }
    
    // MARK: - Completion Handler API (For existing code)
    
    /// Execute a GraphQL query with completion handler (for gradual migration)
    func execute<T: Decodable>(
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
        
        let request = try buildRequest(query: bodyString, variables: nil)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        
        return try JSONDecoder().decode([String: StashJSONValue].self, from: data)
    }
    
    /// Execute a GraphQL mutation with completion handler (for gradual migration)
    func performMutation(
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
    
    private func buildRequest(query: String, variables: [String: Any]?) throws -> URLRequest {
        guard let config = ServerConfigManager.shared.loadConfig(),
              config.hasValidConfig else {
            throw GraphQLNetworkError.noServerConfig
        }
        
        let urlString = "\(config.baseURL)/graphql"
        
        guard let url = URL(string: urlString) else {
            throw GraphQLNetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        
        // Add API Key if available
        if let apiKey = config.secureApiKey, !apiKey.isEmpty {
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
    
    private func validateResponse(_ response: URLResponse, data: Data) throws {
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
