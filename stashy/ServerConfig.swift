//
//  ServerConfig.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

import Foundation
import SwiftUI
import Combine

extension Notification.Name {
    /// Nach Abschluss von `StashDBViewModel.initializeServerConnection()` (Filter + Statistik). z.B. tvOS-Dashboard nach Serverwechsel neu laden; vermeidet Race mit `GraphQLClient.cancelAllRequests()`.
    static let stashServerInitializationFinished = Notification.Name("stashServerInitializationFinished")
}

enum ServerProtocol: String, Codable, CaseIterable {
    case http = "HTTP"
    case https = "HTTPS"
    
    var displayName: String {
        rawValue
    }
    
    var defaultPort: String {
        switch self {
        case .http: return "80"
        case .https: return "443"
        }
    }
}

enum AuthMethod: String, Codable, CaseIterable {
    case none = "None"
    case login = "Login"
    case apiKey = "API Key"
}

// Legacy enum for backward compatibility
enum ConnectionType: String, Codable, CaseIterable {
    case ipAddress = "IP Address"
    case domain = "Domain"

    var displayName: String {
        rawValue
    }
}

/// A user-defined HTTP header sent with every request to the Stash server — for setups behind
/// SSO or a reverse proxy that expects its own token (e.g. `X-Auth-Token`, `CF-Access-Client-Id`).
nonisolated struct ServerHTTPHeader: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var value: String

    init(id: UUID = UUID(), name: String, value: String) {
        self.id = id
        self.name = name
        self.value = value
    }

    /// Headers URLSession / the player manage themselves; setting them breaks requests.
    nonisolated static let reservedNames: Set<String> = [
        "host", "content-length", "content-type", "connection", "transfer-encoding",
        "upgrade", "range", "accept-encoding", "te", "trailer", "keep-alive", "proxy-connection"
    ]

    nonisolated var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    nonisolated var trimmedValue: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// RFC 7230 token characters only, not reserved, value present.
    nonisolated var isUsable: Bool {
        let n = trimmedName
        guard !n.isEmpty, !trimmedValue.isEmpty else { return false }
        guard !Self.reservedNames.contains(n.lowercased()) else { return false }
        let token = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return n.unicodeScalars.allSatisfy { token.contains($0) }
            && !trimmedValue.contains("\n") && !trimmedValue.contains("\r")
    }

    /// Empty rows are dropped silently; invalid names are reported by the form.
    nonisolated static func sanitized(_ headers: [ServerHTTPHeader]) -> [ServerHTTPHeader] {
        headers
            .filter { $0.isUsable }
            .map { ServerHTTPHeader(id: $0.id, name: $0.trimmedName, value: $0.trimmedValue) }
    }
}

/// Decides whether a connection test actually reached Stash. A host that merely answers — an
/// SSO login page, a reverse proxy's error page, some other service on that port — is a
/// failure, not "Connected". Only a GraphQL response carrying Stash's version counts.
enum StashConnectionProbe {
    /// The query every test sends; `evaluate` looks for its answer.
    nonisolated static let versionQueryBody = #"{"query":"{ version { version } }"}"#

    enum Outcome: Equatable {
        case stash(version: String)
        case failure(String)
    }

    nonisolated static func evaluate(data: Data?, response: URLResponse?, error: Error?) -> Outcome {
        if let error {
            let code = (error as NSError).code
            switch code {
            case NSURLErrorCannotConnectToHost: return .failure("Cannot connect — check the address and port.")
            case NSURLErrorTimedOut: return .failure("Connection timed out.")
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return .failure("Host not found.")
            case NSURLErrorServerCertificateUntrusted, NSURLErrorSecureConnectionFailed:
                return .failure("Secure connection failed — check HTTP/HTTPS.")
            default: return .failure(error.localizedDescription)
            }
        }
        guard let http = response as? HTTPURLResponse else {
            return .failure("No response from the server.")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            return .failure("Authentication failed — check the API key and custom headers.")
        }

        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if let version = ((json?["data"] as? [String: Any])?["version"] as? [String: Any])?["version"] as? String,
           !version.isEmpty {
            return .stash(version: version)
        }
        // Stash answered, but refused (e.g. "not authorized" as a GraphQL error).
        if let errors = json?["errors"] as? [[String: Any]],
           let message = errors.first?["message"] as? String, !message.isEmpty {
            return .failure("Stash rejected the request: \(message)")
        }
        guard (200...299).contains(http.statusCode) else {
            return .failure("Server error: HTTP \(http.statusCode).")
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if contentType.contains("html") {
            return .failure("The host answered with a web page, not Stash — likely a login or proxy page. Check the address and custom headers.")
        }
        return .failure("The host answered, but not as Stash. Check the address, subpath and custom headers.")
    }
}

/// Thrown by the view model's test so its message reaches `errorMessage` unchanged.
struct StashConnectionProbeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ServerConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "My Stash"
    var serverAddress: String  // Unified field for IP or domain
    var port: String?          // Optional port
    var serverProtocol: ServerProtocol
    var apiKey: String?        // Optional API Key for authentication
    var subpath: String?       // Optional subpath (e.g. "/stash")
    /// Custom headers. iOS keeps them in the Keychain (`secureCustomHeaders`) and leaves this
    /// nil; tvOS has no Keychain here and stores them in the config like the API key.
    var customHeaders: [ServerHTTPHeader]?

    var baseURL: String {
        let effectivePort = port ?? serverProtocol.defaultPort
        let scheme = serverProtocol == .https ? "https" : "http"
        
        // Only append port if it's not the default for the protocol
        let needsPort = (serverProtocol == .https && effectivePort != "443") || 
                       (serverProtocol == .http && effectivePort != "80")
        
        let url: String
        if needsPort {
            url = "\(scheme)://\(serverAddress):\(effectivePort)"
        } else {
            url = "\(scheme)://\(serverAddress)"
        }
        
        if let sub = subpath, !sub.isEmpty {
            let cleanSub = sub.hasPrefix("/") ? sub : "/\(sub)"
            let finalURL = url + cleanSub
            AppLog.debug("🌐 SERVER CONFIG: Using URL with subpath: \(finalURL)")
            return finalURL
        }
        
        AppLog.debug("🌐 SERVER CONFIG: Using URL: \(url)")
        return url
    }

    var hasValidConfig: Bool {
        return !serverAddress.isEmpty
    }
    
    /// API key from Keychain (preferred) or stored value (migration fallback)
    nonisolated var secureApiKey: String? {
        #if !os(tvOS)
        // First try Keychain
        if let keychainKey = KeychainManager.shared.loadAPIKey(forServerID: id) {
            let trimmed = keychainKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        #endif
        // Fallback to stored value (for migration)
        return apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Custom headers from the Keychain (iOS) or the stored config (tvOS / not yet migrated).
    nonisolated var secureCustomHeaders: [ServerHTTPHeader] {
        #if !os(tvOS)
        let stored = KeychainManager.shared.loadCustomHeaders(forServerID: id)
        if !stored.isEmpty { return stored }
        #endif
        return ServerHTTPHeader.sanitized(customHeaders ?? [])
    }

    /// Everything a request to `url` needs to authenticate: the Stash `ApiKey` plus the custom
    /// headers. Custom headers only go to this server's host, never to a third party (stash-box
    /// artwork, funscript hosts); `nil` means "a request to the server itself".
    nonisolated func requestHeaders(for url: URL? = nil) -> [String: String] {
        if let url, url.isFileURL { return [:] }
        var headers: [String: String] = [:]
        if let key = secureApiKey, !key.isEmpty {
            headers["ApiKey"] = key
        }
        let host = url?.host?.lowercased()
        if host == nil || host == serverAddress.lowercased() {
            for header in secureCustomHeaders {
                headers[header.name] = header.value
            }
        }
        return headers
    }

    // Modern initializer
    init(
        id: UUID = UUID(),
        name: String = "My Stash",
        serverAddress: String,
        port: String? = nil,
        serverProtocol: ServerProtocol = .https,
        apiKey: String? = nil,
        subpath: String? = nil,
        customHeaders: [ServerHTTPHeader]? = nil
    ) {
        self.id = id
        self.name = name
        self.serverAddress = serverAddress
        self.port = port
        self.serverProtocol = serverProtocol
        self.apiKey = apiKey
        self.subpath = subpath
        self.customHeaders = customHeaders
    }
    
    // Backward compatibility decoder
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "My Stash"
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        customHeaders = try container.decodeIfPresent([ServerHTTPHeader].self, forKey: .customHeaders)
        
        // Try to decode new format first
        if let serverAddress = try? container.decode(String.self, forKey: .serverAddress),
           let protocolValue = try? container.decode(ServerProtocol.self, forKey: .serverProtocol) {
            // New format
            self.serverAddress = serverAddress
            self.port = try container.decodeIfPresent(String.self, forKey: .port)
            self.serverProtocol = protocolValue
            self.subpath = try container.decodeIfPresent(String.self, forKey: .subpath)
        } else {
            // Legacy format - migrate
            let connectionType = try container.decode(ConnectionType.self, forKey: .connectionType)
            let useHTTPS = try container.decodeIfPresent(Bool.self, forKey: .useHTTPS) ?? true
            
            switch connectionType {
            case .ipAddress:
                self.serverAddress = try container.decode(String.self, forKey: .ipAddress)
                self.port = try container.decode(String.self, forKey: .port)
                self.serverProtocol = .http  // IP addresses were always HTTP in old format
            case .domain:
                self.serverAddress = try container.decode(String.self, forKey: .domain)
                self.port = nil  // Domains didn't have explicit port in old format
                self.serverProtocol = useHTTPS ? .https : .http
            }
            
            AppLog.debug("📦 Migrated legacy server config: \(name)")
        }
    }
    
    // Custom encoder to match the coding keys
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(serverAddress, forKey: .serverAddress)
        try container.encodeIfPresent(port, forKey: .port)
        try container.encode(serverProtocol, forKey: .serverProtocol)
        try container.encodeIfPresent(apiKey, forKey: .apiKey)
        try container.encodeIfPresent(subpath, forKey: .subpath)
        try container.encodeIfPresent(customHeaders, forKey: .customHeaders)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, apiKey, subpath, customHeaders
        // New format keys
        case serverAddress, port, serverProtocol
        // Legacy format keys (for backward compatibility)
        case connectionType, ipAddress, domain, useHTTPS
    }
    
    static func == (lhs: ServerConfig, rhs: ServerConfig) -> Bool {
        return lhs.id == rhs.id
    }
    
    /// Detects protocol from input string and returns it along with the cleaned address
    static func detectProtocol(from input: String) -> (protocol: ServerProtocol?, address: String) {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = cleaned.lowercased()
        
        if lowercased.hasPrefix("https://") {
            return (.https, String(cleaned.dropFirst(8)))
        } else if lowercased.hasPrefix("http://") {
            return (.http, String(cleaned.dropFirst(7)))
        }
        
        return (nil, cleaned)
    }

    /// Parses an input string (e.g. "1.2.3.4:9999/stash" or "example.com/api") into components
    static func parseAddress(_ input: String) -> (host: String, port: String?, subpath: String?) {
        // First, strip protocol if present
        let detection = detectProtocol(from: input)
        var safeInput = detection.address
        
        // Ensure we have a valid structure for URL components
        if !safeInput.contains("://") {
            safeInput = "http://\(safeInput)"
        }
        
        guard let url = URL(string: safeInput) else {
            return (detection.address, nil, nil)
        }
        
        let host = url.host ?? detection.address
        let port = url.port.map { String($0) }
        
        // Extract subpath (excluding any trailing slash)
        var path = url.path
        if path == "/" {
            path = ""
        } else if path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        
        return (host, port, path.isEmpty ? nil : path)
    }

    /// Backwards compatibility wrapper
    static func parseHostAndPort(_ input: String) -> (host: String, port: String?) {
        let result = parseAddress(input)
        return (result.host, result.port)
    }
}

class ServerConfigManager: ObservableObject {
    static let shared = ServerConfigManager()
    private let activeConfigKey = "stashy_server_config"
    private let savedServersKey = "stashy_saved_servers"

    // Publish saved servers list updates
    @Published var activeConfig: ServerConfig?
    @Published var savedServers: [ServerConfig] = []
    
    private init() {
        self.activeConfig = loadConfig()
        self.savedServers = getSavedServers() // Load initial list
    }

    // MARK: - Active Server Management
    func saveConfig(_ config: ServerConfig) {
        let oldConfig = self.activeConfig
        let encoder = JSONEncoder()
        
        if let encoded = try? encoder.encode(config) {
            UserDefaults.standard.set(encoded, forKey: activeConfigKey)
            self.activeConfig = config
            AppLog.debug("✅ Active server updated: \(config.name)")
            
            let coreSettingsChanged = oldConfig == nil ||
                oldConfig?.baseURL != config.baseURL ||
                oldConfig?.secureApiKey != config.secureApiKey ||
                oldConfig?.secureCustomHeaders != config.secureCustomHeaders ||
                oldConfig?.id != config.id

            if coreSettingsChanged {
                // Clear system URL cache to avoid using stale data/auth for the new server
                URLCache.shared.removeAllCachedResponses()
                
                // Notify all ViewModels to reset their data
                NotificationCenter.default.post(name: NSNotification.Name("ServerConfigChanged"), object: nil)
            } else {
                // Only secondary settings changed. Emit a minor notification if needed,
                // but do not nuke the URLSession.
                NotificationCenter.default.post(name: NSNotification.Name("ServerConfigPropertiesChanged"), object: nil)
            }
        }
    }

    func loadConfig() -> ServerConfig? {
        if let data = UserDefaults.standard.data(forKey: activeConfigKey) {
            let decoder = JSONDecoder()
            if let config = try? decoder.decode(ServerConfig.self, from: data) {
                #if !os(tvOS)
                // Auto-migrate API key to Keychain if needed
                KeychainManager.shared.migrateAPIKeyIfNeeded(from: config)
                #endif
                return config
            }
        }
        return nil
    }

    /// Move any leftover plaintext `apiKey` fields into Keychain and re-persist configs without secrets.
    func scrubPlaintextAPIKeysFromDisk() {
        #if !os(tvOS)
        var changed = false

        if var active = loadConfig(), let key = active.apiKey, !key.isEmpty {
            KeychainManager.shared.migrateAPIKeyIfNeeded(from: active)
            active.apiKey = nil
            if let encoded = try? JSONEncoder().encode(active) {
                UserDefaults.standard.set(encoded, forKey: activeConfigKey)
                self.activeConfig = active
                changed = true
            }
        }

        var servers = getSavedServers()
        for i in servers.indices {
            if let key = servers[i].apiKey, !key.isEmpty {
                KeychainManager.shared.migrateAPIKeyIfNeeded(from: servers[i])
                servers[i].apiKey = nil
                changed = true
            }
        }
        if changed {
            saveServersList(servers)
            AppLog.debug("🧹 Scrubbed plaintext API keys from UserDefaults")
        }
        #endif
    }
    
    // MARK: - Saved Servers Management
    // Helper to load from UserDefaults
    func getSavedServers() -> [ServerConfig] {
        if let data = UserDefaults.standard.data(forKey: savedServersKey) {
            let decoder = JSONDecoder()
            if let servers = try? decoder.decode([ServerConfig].self, from: data) {
                return servers
            }
        }
        
        // Migration: If we have an active config but no saved servers list, add the active one to the list
        if let current = loadConfig() {
            let initialList = [current]
            saveServersList(initialList) // This will update UserDefaults
            return initialList
        }
        
        return []
    }
    
    // Helper to save to UserDefaults and update published property
    func saveServersList(_ servers: [ServerConfig]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(servers) {
            UserDefaults.standard.set(encoded, forKey: savedServersKey)
            self.savedServers = servers // Update published property to trigger UI refresh
        }
    }
    
    func addOrUpdateServer(_ config: ServerConfig) {
        var servers = getSavedServers()
        
        if let index = servers.firstIndex(where: { $0.id == config.id }) {
            servers[index] = config
        } else {
            servers.append(config)
        }
        
        saveServersList(servers)
    }
    
    func deleteServer(at indexSet: IndexSet) {
        var servers = getSavedServers()
        
        // Check if active server is being deleted
        if let active = activeConfig {
            for index in indexSet {
                if index < servers.count && servers[index].id == active.id {
                    clearActiveConfig()
                }
            }
        }

        for index in indexSet where index < servers.count {
            let id = servers[index].id
            #if !os(tvOS)
            _ = KeychainManager.shared.deleteAPIKey(forServerID: id)
            KeychainManager.shared.deleteCustomHeaders(forServerID: id)
            #endif
            ImageCache.shared.clearCache(forServerID: id)
        }
        
        servers.remove(atOffsets: indexSet)
        saveServersList(servers)
    }
    
    func deleteServer(id: UUID) {
        // Check if active server is being deleted
        if let active = activeConfig, active.id == id {
            clearActiveConfig()
        }
        
        #if !os(tvOS)
        _ = KeychainManager.shared.deleteAPIKey(forServerID: id)
        KeychainManager.shared.deleteCustomHeaders(forServerID: id)
        #endif
        ImageCache.shared.clearCache(forServerID: id)
        
        var servers = getSavedServers()
        servers.removeAll { $0.id == id }
        saveServersList(servers)
    }
    
    private func clearActiveConfig() {
        UserDefaults.standard.removeObject(forKey: activeConfigKey)
        self.activeConfig = nil
        AppLog.error("⚠️ Active server deleted, config cleared.")
        
        // Notify app to reset UI state
        NotificationCenter.default.post(name: NSNotification.Name("ServerConfigChanged"), object: nil)
    }
}