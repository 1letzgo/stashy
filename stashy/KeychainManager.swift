//
//  KeychainManager.swift
//  stashy
//
//  Secure storage for API keys using iOS Keychain
//

import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.letzgo.stashy"
    
    private init() {}
    
    // MARK: - API Key Management
    
    /// Save API key for a server
    func saveAPIKey(_ apiKey: String, forServerID serverID: UUID) -> Bool {
        let key = "apikey_\(serverID.uuidString)"
        
        // Delete existing first
        deleteAPIKey(forServerID: serverID)
        
        guard let data = apiKey.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("✅ API Key saved to Keychain for server: \(serverID)")
            return true
        } else {
            print("❌ Failed to save API Key to Keychain: \(status)")
            return false
        }
    }
    
    /// Load API key for a server
    func loadAPIKey(forServerID serverID: UUID) -> String? {
        let key = "apikey_\(serverID.uuidString)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    /// Delete API key for a server
    @discardableResult
    func deleteAPIKey(forServerID serverID: UUID) -> Bool {
        let key = "apikey_\(serverID.uuidString)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Migration
    
    /// Migrate API key from ServerConfig (UserDefaults) to Keychain
    func migrateAPIKeyIfNeeded(from config: ServerConfig) {
        // If there's an API key in the config and not in Keychain, migrate it
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            if loadAPIKey(forServerID: config.id) == nil {
                _ = saveAPIKey(apiKey, forServerID: config.id)
                print("🔄 Migrated API key to Keychain for server: \(config.name)")
            }
        }
    }
}
