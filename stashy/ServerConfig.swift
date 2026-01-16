//
//  ServerConfig.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

import Foundation

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
    var connectionType: ConnectionType
    var ipAddress: String
    var port: String
    var domain: String
    var apiKey: String?  // Optional API Key for authentication
    var useHTTPS: Bool  // HTTP or HTTPS for Domain

    var baseURL: String {
        let url: String
        switch connectionType {
        case .ipAddress:
            url = "http://\(ipAddress):\(port)"
        case .domain:
            let scheme = useHTTPS ? "https" : "http"
            url = "\(scheme)://\(domain)"
        }
        print("🌐 SERVER CONFIG: Verwende URL: \(url)")
        return url
    }

    var hasValidConfig: Bool {
        switch connectionType {
        case .ipAddress:
            return !ipAddress.isEmpty && !port.isEmpty
        case .domain:
            return !domain.isEmpty
        }
    }
    
    /// API key from Keychain (preferred) or stored value (migration fallback)
    var secureApiKey: String? {
        // First try Keychain
        if let keychainKey = KeychainManager.shared.loadAPIKey(forServerID: id) {
            return keychainKey
        }
        // Fallback to stored value (for migration)
        return apiKey
    }

    // Backward compatibility initializer
    init(ipAddress: String, port: String) {
        self.connectionType = .ipAddress
        self.ipAddress = ipAddress
        self.port = port
        self.domain = ""
        self.apiKey = nil
        self.useHTTPS = true
    }

    init(id: UUID = UUID(), name: String = "My Stash", connectionType: ConnectionType, ipAddress: String, port: String, domain: String, apiKey: String? = nil, useHTTPS: Bool = true) {
        self.id = id
        self.name = name
        self.connectionType = connectionType
        self.ipAddress = ipAddress
        self.port = port
        self.domain = domain
        self.apiKey = apiKey
        self.useHTTPS = useHTTPS
    }
    
    // Decoder für Backward Compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "My Stash"
        connectionType = try container.decode(ConnectionType.self, forKey: .connectionType)
        ipAddress = try container.decode(String.self, forKey: .ipAddress)
        port = try container.decode(String.self, forKey: .port)
        domain = try container.decode(String.self, forKey: .domain)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        useHTTPS = try container.decodeIfPresent(Bool.self, forKey: .useHTTPS) ?? true
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, connectionType, ipAddress, port, domain, apiKey, useHTTPS
    }
    
    static func == (lhs: ServerConfig, rhs: ServerConfig) -> Bool {
        return lhs.id == rhs.id
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
            
            // Notify all ViewModels to reset their data
            NotificationCenter.default.post(name: NSNotification.Name("ServerConfigChanged"), object: nil)
        }
    }

    func loadConfig() -> ServerConfig? {
        if let data = UserDefaults.standard.data(forKey: activeConfigKey) {
            let decoder = JSONDecoder()
            if let config = try? decoder.decode(ServerConfig.self, from: data) {
                // Auto-migrate API key to Keychain if needed
                KeychainManager.shared.migrateAPIKeyIfNeeded(from: config)
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