//
//  ServerConfig.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

import Foundation
import SwiftUI
import Combine

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

enum StreamingQuality: String, Codable, CaseIterable {
    case original = "Original"
    case uhd = "4K (2160p)"
    case fhd = "Full HD (1080p)"
    case hd = "HD (720p)"
    case sd = "Standard (480p)"
    case low = "Low (240p)"
    
    var displayName: String { rawValue }
    
    var maxVerticalResolution: Int? {
        switch self {
        case .original: return nil
        case .uhd: return 2160
        case .fhd: return 1080
        case .hd: return 720
        case .sd: return 480
        case .low: return 240
        }
    }
}

// Legacy enum for backward compatibility
enum ConnectionType: String, Codable, CaseIterable {
    case ipAddress = "IP Address"
    case domain = "Domain"

    var displayName: String {
        rawValue
    }
}

struct ServerConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "My Stash"
    var serverAddress: String  // Unified field for IP or domain
    var port: String?          // Optional port
    var serverProtocol: ServerProtocol
    var apiKey: String?        // Optional API Key for authentication
    var subpath: String?       // Optional subpath (e.g. "/stash")
    var defaultQuality: StreamingQuality = .fhd
    var reelsQuality: StreamingQuality = .sd

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
            print("🌐 SERVER CONFIG: Using URL with subpath: \(finalURL)")
            return finalURL
        }
        
        print("🌐 SERVER CONFIG: Using URL: \(url)")
        return url
    }

    var hasValidConfig: Bool {
        return !serverAddress.isEmpty
    }
    
    /// API key from Keychain (preferred) or stored value (migration fallback)
    var secureApiKey: String? {
        #if !os(tvOS)
        // First try Keychain
        if let keychainKey = KeychainManager.shared.loadAPIKey(forServerID: id) {
            return keychainKey
        }
        #endif
        // Fallback to stored value (for migration)
        return apiKey
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
        defaultQuality: StreamingQuality = .fhd,
        reelsQuality: StreamingQuality = .sd
    ) {
        self.id = id
        self.name = name
        self.serverAddress = serverAddress
        self.port = port
        self.serverProtocol = serverProtocol
        self.apiKey = apiKey
        self.subpath = subpath
        self.defaultQuality = defaultQuality
        self.reelsQuality = reelsQuality
    }
    
    // Backward compatibility decoder
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "My Stash"
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        defaultQuality = try container.decodeIfPresent(StreamingQuality.self, forKey: .defaultQuality) ?? .fhd
        reelsQuality = try container.decodeIfPresent(StreamingQuality.self, forKey: .reelsQuality) ?? .sd
        
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
            
            print("📦 Migrated legacy server config: \(name)")
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
        try container.encode(defaultQuality, forKey: .defaultQuality)
        try container.encode(reelsQuality, forKey: .reelsQuality)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, apiKey, subpath
        // New format keys
        case serverAddress, port, serverProtocol, defaultQuality, reelsQuality
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
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(config) {
            UserDefaults.standard.set(encoded, forKey: activeConfigKey)
            self.activeConfig = config
            print("✅ Active server updated: \(config.name)")
            
            // Clear system URL cache to avoid using stale data/auth for the new server
            URLCache.shared.removeAllCachedResponses()
            
            // Notify all ViewModels to reset their data
            NotificationCenter.default.post(name: NSNotification.Name("ServerConfigChanged"), object: nil)
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
        
        servers.remove(atOffsets: indexSet)
        saveServersList(servers)
    }
    
    func deleteServer(id: UUID) {
        // Check if active server is being deleted
        if let active = activeConfig, active.id == id {
            clearActiveConfig()
        }
        
        var servers = getSavedServers()
        servers.removeAll { $0.id == id }
        saveServersList(servers)
    }
    
    private func clearActiveConfig() {
        UserDefaults.standard.removeObject(forKey: activeConfigKey)
        self.activeConfig = nil
        print("⚠️ Active server deleted, config cleared.")
        
        // Notify app to reset UI state
        NotificationCenter.default.post(name: NSNotification.Name("ServerConfigChanged"), object: nil)
    }
}