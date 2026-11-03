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

    /// Set while the iCloud settings sync is on (`ICloudSettingsSync`).
    static let syncEnabledKey = "icloud_settings_sync_enabled"
    private var syncsSecrets: Bool { UserDefaults.standard.bool(forKey: Self.syncEnabledKey) }
    
    private init() {}
    
    // MARK: - API Key Management

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    /// Save API key for a server (add-or-update, atomic)
    func saveAPIKey(_ apiKey: String, forServerID serverID: UUID) -> Bool {
        let key = "apikey_\(serverID.uuidString)"
        invalidateAPIKeyCache(forServerID: serverID)

        guard let data = apiKey.data(using: .utf8) else { return false }
        if syncsSecrets { saveSynced(data, account: key) }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(baseQuery(account: key) as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var addQuery = baseQuery(account: key)
        attributes.forEach { addQuery[$0.key] = $0.value }
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    /// In-memory copy of the API keys. `SecItemCopyMatching` costs around a
    /// millisecond and every signed image URL asked for it — once per card per
    /// body evaluation, which is what made the scene grid stutter.
    private var apiKeyCache: [UUID: String?] = [:]
    private let apiKeyCacheLock = NSLock()

    private func invalidateAPIKeyCache(forServerID serverID: UUID) {
        apiKeyCacheLock.lock()
        apiKeyCache[serverID] = nil
        apiKeyCacheLock.unlock()
    }

    /// Load API key for a server
    func loadAPIKey(forServerID serverID: UUID) -> String? {
        apiKeyCacheLock.lock()
        if let cached = apiKeyCache[serverID] {
            apiKeyCacheLock.unlock()
            return cached
        }
        apiKeyCacheLock.unlock()

        let loaded = loadAPIKeyFromKeychain(forServerID: serverID)
        apiKeyCacheLock.lock()
        apiKeyCache[serverID] = .some(loaded)
        apiKeyCacheLock.unlock()
        return loaded
    }

    private func loadAPIKeyFromKeychain(forServerID serverID: UUID) -> String? {
        let key = "apikey_\(serverID.uuidString)"
        if syncsSecrets, let synced = loadSynced(account: key) { return synced }

        var query = baseQuery(account: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

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
        invalidateAPIKeyCache(forServerID: serverID)
        if syncsSecrets { deleteSynced(account: key) }
        return deleteRaw(account: key)
    }
    
    // MARK: - Custom HTTP headers (per server)

    /// JSON-encoded `[ServerHTTPHeader]`. Header values are often SSO bypass tokens, so they
    /// get the same storage as the API key. Cached: every image request reads them.
    private var headersCache: [UUID: [ServerHTTPHeader]] = [:]
    private let headersCacheLock = NSLock()

    @discardableResult
    func saveCustomHeaders(_ headers: [ServerHTTPHeader], forServerID serverID: UUID) -> Bool {
        let account = "headers_\(serverID.uuidString)"
        headersCacheLock.lock(); headersCache[serverID] = nil; headersCacheLock.unlock()
        guard let data = try? JSONEncoder().encode(headers) else { return false }
        // Synced as an empty list, not deleted: other devices must see the removal.
        if syncsSecrets { saveSynced(data, account: account) }
        guard !headers.isEmpty else { return deleteRaw(account: account) }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }
        var addQuery = baseQuery(account: account)
        attributes.forEach { addQuery[$0.key] = $0.value }
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    func loadCustomHeaders(forServerID serverID: UUID) -> [ServerHTTPHeader] {
        headersCacheLock.lock()
        if let cached = headersCache[serverID] {
            headersCacheLock.unlock()
            return cached
        }
        headersCacheLock.unlock()

        var loaded: [ServerHTTPHeader] = []
        let account = "headers_\(serverID.uuidString)"
        if let raw = (syncsSecrets ? loadSynced(account: account) : nil) ?? loadRawString(account: account),
           let decoded = try? JSONDecoder().decode([ServerHTTPHeader].self, from: Data(raw.utf8)) {
            loaded = decoded
        }
        headersCacheLock.lock(); headersCache[serverID] = loaded; headersCacheLock.unlock()
        return loaded
    }

    @discardableResult
    func deleteCustomHeaders(forServerID serverID: UUID) -> Bool {
        headersCacheLock.lock(); headersCache[serverID] = nil; headersCacheLock.unlock()
        if syncsSecrets { deleteSynced(account: "headers_\(serverID.uuidString)") }
        return deleteRaw(account: "headers_\(serverID.uuidString)")
    }

    // MARK: - iCloud Keychain copies (only while the iCloud settings sync is on)

    /// The device-only items above stay in place, so turning the sync off loses nothing.
    private func syncedQuery(account: String) -> [String: Any] {
        var query = baseQuery(account: account)
        query[kSecAttrSynchronizable as String] = true
        return query
    }

    private func saveSynced(_ data: Data, account: String) {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let query = syncedQuery(account: account)
        guard SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound else { return }
        SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
    }

    private func loadSynced(account: String) -> String? {
        var query = syncedQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteSynced(account: String) {
        SecItemDelete(syncedQuery(account: account) as CFDictionary)
    }

    private func secretAccounts(forServerID id: UUID) -> [String] {
        ["apikey_\(id.uuidString)", "headers_\(id.uuidString)"]
    }

    /// Turning the sync on: copies what this device has, without replacing what iCloud has.
    func uploadSecretsToICloud(serverIDs: [UUID]) {
        for account in serverIDs.flatMap(secretAccounts) where loadSynced(account: account) == nil {
            if let local = loadRawString(account: account) {
                saveSynced(Data(local.utf8), account: account)
            }
        }
        clearSecretCaches()
    }

    /// Turning the sync off: this device keeps the newest values as its own copies.
    func adoptSyncedSecrets(serverIDs: [UUID]) {
        for id in serverIDs {
            guard syncsSecrets else { return }
            if let key = loadSynced(account: "apikey_\(id.uuidString)") {
                let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8)]
                saveLocal(attributes, account: "apikey_\(id.uuidString)")
            }
            if let headers = loadSynced(account: "headers_\(id.uuidString)") {
                let attributes: [String: Any] = [kSecValueData as String: Data(headers.utf8)]
                saveLocal(attributes, account: "headers_\(id.uuidString)")
            }
        }
    }

    private func saveLocal(_ attributes: [String: Any], account: String) {
        let query = baseQuery(account: account)
        guard SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound else { return }
        var addQuery = query.merging(attributes) { $1 }
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Removes every synced copy from iCloud Keychain; device-only items are not touched.
    func removeSyncedSecrets() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: true,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(query as CFDictionary)
    }

    func clearSecretCaches() {
        apiKeyCacheLock.lock(); apiKeyCache = [:]; apiKeyCacheLock.unlock()
        headersCacheLock.lock(); headersCache = [:]; headersCacheLock.unlock()
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
                AppLog.debug("🔄 Migrated plaintext passcode to salted hash")
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
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    @discardableResult
    private func deleteRaw(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
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
                AppLog.debug("🔄 Migrated API key to Keychain for server: \(config.name)")
            }
        }
    }
}
