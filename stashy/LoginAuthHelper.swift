//
//  LoginAuthHelper.swift
//  stashy
//
//  Created for login-based API key retrieval
//

import Foundation

class LoginAuthHelper {
    static let shared = LoginAuthHelper()
    
    private init() {}
    
    enum LoginError: LocalizedError {
        case invalidURL
        case loginFailed(String)
        case noData
        case apiKeyNotFound
        case connectionError(Error)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL"
            case .loginFailed(let msg): return "Login failed: \(msg)"
            case .noData: return "No data received from server"
            case .apiKeyNotFound: return "API Key not found in server configuration"
            case .connectionError(let error): return error.localizedDescription
            }
        }
    }
    
    /// Authenticates with username/password and retrieves the API Key via GraphQL
    func fetchAPIKey(baseURL: String, username: String, password: String) async throws -> String {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpCookieAcceptPolicy = .always
        sessionConfig.httpShouldSetCookies = true
        
        // Use the same delegate as GraphQLClient for SSL/Self-signed cert support
        let session = URLSession(configuration: sessionConfig, delegate: GraphQLURLSessionDelegate(), delegateQueue: nil)
        
        // 1. Perform Login
        guard var loginURL = URL(string: baseURL) else {
            throw LoginError.invalidURL
        }
        loginURL.appendPathComponent("login")
        
        var loginRequest = URLRequest(url: loginURL)
        loginRequest.httpMethod = "POST"
        loginRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let loginBody = "username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&password=\(password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        loginRequest.httpBody = loginBody.data(using: .utf8)
        
        let (_, loginResponse) = try await session.data(for: loginRequest)
        
        guard let httpLoginResponse = loginResponse as? HTTPURLResponse else {
            throw LoginError.noData
        }
        
        if httpLoginResponse.statusCode != 200 {
            throw LoginError.loginFailed("Server returned status code \(httpLoginResponse.statusCode)")
        }
        
        // 2. Fetch API Key via GraphQL
        guard var gqlURL = URL(string: baseURL) else {
            throw LoginError.invalidURL
        }
        gqlURL.appendPathComponent("graphql")
        
        var gqlRequest = URLRequest(url: gqlURL)
        gqlRequest.httpMethod = "POST"
        gqlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let query = """
        {"query": "{ configuration { general { apiKey } } }"}
        """
        gqlRequest.httpBody = query.data(using: .utf8)
        
        let (gqlData, gqlResponse) = try await session.data(for: gqlRequest)
        
        guard let httpGqlResponse = gqlResponse as? HTTPURLResponse else {
            throw LoginError.noData
        }
        
        if httpGqlResponse.statusCode != 200 {
            throw LoginError.loginFailed("GraphQL request failed: \(httpGqlResponse.statusCode)")
        }
        
        // Parse the response
        do {
            if let json = try JSONSerialization.jsonObject(with: gqlData) as? [String: Any],
               let data = json["data"] as? [String: Any],
               let configuration = data["configuration"] as? [String: Any],
               let general = configuration["general"] as? [String: Any],
               let apiKey = general["apiKey"] as? String {
                
                if apiKey.isEmpty {
                    throw LoginError.apiKeyNotFound
                }
                return apiKey
            } else {
                throw LoginError.apiKeyNotFound
            }
        } catch {
            throw LoginError.connectionError(error)
        }
    }
}
