//
//  KeychainManager.swift
//  stashy
//
//  Secure storage for API keys using iOS Keychain
//

import Foundation
import Security
import CryptoKit

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
        return status == errSecSuccess
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
        
        if status == errSecSuccess,
           let data = result as? Data,
           let apiKey = String(data: data, encoding: .utf8) {
            return apiKey
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
    
    // MARK: - App Passcode (salted hash only — never store plaintext PIN)
    
    private let passcodeAccount = "app_passcode_v1"
    private let legacyPasscodeAccount = "app_passcode"
    
    /// Stores `v1:<salt>:<sha256hex>` in Keychain.
    @discardableResult
    func saveAppPasscodeHash(salt: String, hash: String) -> Bool {
        deleteAppPasscode()
        let payload = "v1:\(salt):\(hash)"
        guard let data = payload.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passcodeAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
    
    /// Returns stored salt+hash. Migrates legacy plaintext 4-digit PIN if found.
    func loadAppPasscodeRecord() -> (salt: String, hash: String)? {
        if let record = loadPasscodePayload(account: passcodeAccount) {
            return record
        }
        // Legacy: plaintext PIN in old account
        if let legacy = loadRawString(account: legacyPasscodeAccount),
           legacy.count == 4, legacy.allSatisfy(\.isNumber) {
            let salt = UUID().uuidString
            let hash = Self.sha256Hex(legacy + ":" + salt)
            if saveAppPasscodeHash(salt: salt, hash: hash) {
                _ = deleteRaw(account: legacyPasscodeAccount)
                print("🔄 Migrated plaintext passcode to salted hash")
                return (salt, hash)
            }
        }
        return nil
    }
    
    /// True when a passcode (hashed or legacy) is configured.
    func hasAppPasscode() -> Bool {
        loadAppPasscodeRecord() != nil
    }
    
    @discardableResult
    func deleteAppPasscode() -> Bool {
        let a = deleteRaw(account: passcodeAccount)
        let b = deleteRaw(account: legacyPasscodeAccount)
        return a || b
    }
    
    private func loadPasscodePayload(account: String) -> (salt: String, hash: String)? {
        guard let raw = loadRawString(account: account) else { return nil }
        // v1:<salt>:<hash>
        let parts = raw.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "v1", !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
        return (parts[1], parts[2])
    }
    
    private func loadRawString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }
    
    @discardableResult
    private func deleteRaw(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Migration
    
    /// Migrate API key from ServerConfig (UserDefaults) to Keychain
    func migrateAPIKeyIfNeeded(from config: ServerConfig) {
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            if loadAPIKey(forServerID: config.id) == nil {
                _ = saveAPIKey(apiKey, forServerID: config.id)
                print("🔄 Migrated API key to Keychain for server: \(config.name)")
            }
        }
    }
}
