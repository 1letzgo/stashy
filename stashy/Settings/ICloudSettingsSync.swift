//
//  ICloudSettingsSync.swift
//  stashy
//
//  Optional sync of servers and settings between iPhone, iPad and Mac. Servers and settings go
//  through iCloud key-value storage, API keys and custom headers through iCloud Keychain
//  (`KeychainManager`), never through the key-value store.
//

#if !os(tvOS)
import SwiftUI

@MainActor
final class ICloudSettingsSync: ObservableObject {
    static let shared = ICloudSettingsSync()

    @Published private(set) var isEnabled = UserDefaults.standard.bool(forKey: KeychainManager.syncEnabledKey)
    @Published private(set) var problem: String?

    /// iCloud key-value storage allows 1 MB, 1024 keys and 64 byte key names.
    private static let maxTotalBytes = 900_000
    private static let maxKeyCount = 1000
    private static let maxEntryBytes = 64_000
    private static let settingPrefix = "s."
    private static let serverPrefix = "server."
    private static let deletedServer = "deleted"
    private static let deletedSettingType = "deleted"

    private let store = NSUbiquitousKeyValueStore.default
    private var observers: [NSObjectProtocol] = []
    private var reconcileScheduled = false
    private var lastSecretRefresh = Date.distantPast

    private init() {}

    // MARK: Lifecycle

    /// Called at launch; does nothing until the user turned the sync on.
    func start() {
        guard isEnabled else { return }
        observe()
        store.synchronize()
        reconcile()
    }

    func enable() {
        guard !isEnabled else { return }
        UserDefaults.standard.set(true, forKey: KeychainManager.syncEnabledKey)
        isEnabled = true
        KeychainManager.shared.uploadSecretsToICloud(serverIDs: ServerConfigManager.shared.getSavedServers().map(\.id))
        start()
    }

    /// Stops syncing on this device. Every API key stays here; other devices keep syncing.
    /// `removingCloudData` also clears the API keys and settings stored in iCloud.
    func disable(removingCloudData: Bool) {
        guard isEnabled else { return }
        let keychain = KeychainManager.shared
        keychain.adoptSyncedSecrets(serverIDs: ServerConfigManager.shared.getSavedServers().map(\.id))
        if removingCloudData {
            keychain.removeSyncedSecrets()
            for key in store.dictionaryRepresentation.keys where Self.isSyncKey(key) {
                store.removeObject(forKey: key)
            }
            store.synchronize()
        }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        UserDefaults.standard.set(false, forKey: KeychainManager.syncEnabledKey)
        isEnabled = false
        problem = nil
        keychain.clearSecretCaches()
        saveBase([:])
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        func on(_ name: Notification.Name, object: Any? = nil, _ action: @escaping @MainActor (ICloudSettingsSync, Notification) -> Void) {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    action(self, note)
                }
            })
        }
        on(NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store) { sync, note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            sync.problem = reason == NSUbiquitousKeyValueStoreQuotaViolationChange
                ? "iCloud storage for settings is full. Some settings are not synced." : nil
            sync.reconcile()
            sync.refreshSecrets()
        }
        // Throttled, not debounced: frequent writes (feed positions) would starve a debounce.
        on(UserDefaults.didChangeNotification) { sync, _ in sync.scheduleReconcile() }
        on(NSNotification.Name("AuthError401")) { sync, _ in sync.refreshSecrets() }
        #if os(macOS)
        let becameActive = NSApplication.didBecomeActiveNotification
        #else
        let becameActive = UIApplication.didBecomeActiveNotification
        #endif
        on(becameActive) { sync, _ in
            sync.store.synchronize()
            sync.reconcile()
            sync.refreshSecrets()
        }
    }

    private func scheduleReconcile() {
        guard !reconcileScheduled else { return }
        reconcileScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            MainActor.assumeIsolated {
                self?.reconcileScheduled = false
                self?.reconcile()
            }
        }
    }

    /// iCloud Keychain sends no change notice, so a new key is only found by looking again.
    private func refreshSecrets() {
        guard Date().timeIntervalSince(lastSecretRefresh) > 10 else { return }
        lastSecretRefresh = Date()
        let active = ServerConfigManager.shared.activeConfig
        let before = active?.secureApiKey
        let headersBefore = active?.secureCustomHeaders
        KeychainManager.shared.clearSecretCaches()
        guard active?.secureApiKey != before || active?.secureCustomHeaders != headersBefore else { return }
        NotificationCenter.default.post(name: NSNotification.Name("ServerConfigChanged"), object: nil)
    }

    // MARK: Reconcile

    private func reconcile() {
        guard isEnabled else { return }
        if FileManager.default.ubiquityIdentityToken == nil {
            problem = "Sign in to iCloud on this device to sync."
            return
        }
        let local = localEntries()
        let remote = store.dictionaryRepresentation.compactMapValues { $0 as? String }.filter { Self.isSyncKey($0.key) }
        let oldBase = loadBase()
        var base = oldBase
        var appliedSettings = false
        var appliedServers = false
        var skippedForSpace = false
        var usedBytes = remote.reduce(0) { $0 + $1.value.utf8.count }
        var usedKeys = remote.count

        func push(_ key: String, _ value: String) {
            let size = value.utf8.count
            let previous = remote[key]?.utf8.count
            guard size <= Self.maxEntryBytes,
                  usedBytes - (previous ?? 0) + size <= Self.maxTotalBytes,
                  previous != nil || usedKeys < Self.maxKeyCount else {
                skippedForSpace = true
                return
            }
            usedBytes += size - (previous ?? 0)
            if previous == nil { usedKeys += 1 }
            store.set(value, forKey: key)
            base[key] = KeychainManager.sha256Hex(value)
        }

        for key in Set(local.keys).union(remote.keys).sorted() {
            let isServer = key.hasPrefix(Self.serverPrefix)
            let setting = isServer ? nil : remote[key].flatMap(Self.decodeSetting)
            if !isServer, remote[key] != nil, setting == nil { continue }
            if let setting, !SettingsTransfer.isSyncable(setting.key) { continue }
            let isDeletion = isServer ? remote[key] == Self.deletedServer : setting?.type == Self.deletedSettingType

            // `base` holds hashes, so compare the hashes throughout.
            let action = ICloudSettingsMerge.action(
                local: local[key].map(KeychainManager.sha256Hex),
                remote: remote[key].map(KeychainManager.sha256Hex),
                remoteIsDeletion: isDeletion,
                base: base[key]
            )
            switch action {
            case .none:
                if let value = remote[key] { base[key] = KeychainManager.sha256Hex(value) }
            case .pushLocal:
                if let value = local[key] { push(key, value) }
            case .pushLocalDeletion:
                if isServer {
                    push(key, Self.deletedServer)
                } else if let setting, let marker = Self.encode(SettingsTransferFile.Setting(key: setting.key, type: Self.deletedSettingType, value: .null)) {
                    push(key, marker)
                }
            case .applyRemote:
                guard let value = remote[key] else { break }
                if isServer {
                    if applyServer(value) {
                        appliedServers = true
                        base[key] = KeychainManager.sha256Hex(value)
                    }
                } else if let setting, SettingsTransfer.apply(setting, to: .standard) {
                    appliedSettings = true
                    base[key] = KeychainManager.sha256Hex(value)
                }
            case .applyRemoteDeletion:
                guard let value = remote[key] else { break }
                if isServer {
                    if let id = UUID(uuidString: String(key.dropFirst(Self.serverPrefix.count))) {
                        ServerConfigManager.shared.deleteServer(id: id)
                        appliedServers = true
                    }
                } else if let setting {
                    UserDefaults.standard.removeObject(forKey: setting.key)
                    appliedSettings = true
                }
                base[key] = KeychainManager.sha256Hex(value)
            }
        }

        if base != oldBase { saveBase(base) }
        if skippedForSpace {
            problem = "iCloud storage for settings is full. Some settings are not synced."
        }
        if appliedSettings {
            AppearanceManager.shared.reload()
            TabManager.shared.reloadSettings()
        }
        if appliedServers {
            finishServerChanges()
        }
    }

    private func finishServerChanges() {
        let manager = ServerConfigManager.shared
        // The active server stays a per-device choice; a device without one takes the first.
        if manager.activeConfig == nil, let first = manager.getSavedServers().first {
            manager.saveConfig(first)
        }
    }

    private func applyServer(_ value: String) -> Bool {
        guard let server = try? JSONDecoder().decode(SettingsTransferFile.Server.self, from: Data(value.utf8)),
              let config = SettingsTransfer.config(from: server) else { return false }
        let manager = ServerConfigManager.shared
        manager.addOrUpdateServer(config)
        if manager.activeConfig?.id == config.id {
            manager.saveConfig(config)
        }
        return true
    }

    // MARK: Entries

    private func localEntries() -> [String: String] {
        var entries: [String: String] = [:]
        for config in ServerConfigManager.shared.getSavedServers() {
            if let value = Self.encode(SettingsTransfer.serverEntry(for: config, includeSecrets: false)) {
                entries[Self.serverPrefix + config.id.uuidString] = value
            }
        }
        for setting in SettingsTransfer.settingEntries(where: SettingsTransfer.isSyncable) {
            if let value = Self.encode(setting) {
                entries[Self.settingKey(setting.key)] = value
            }
        }
        return entries
    }

    private static func settingKey(_ name: String) -> String {
        settingPrefix + KeychainManager.sha256Hex(name).prefix(40)
    }

    private static func isSyncKey(_ key: String) -> Bool {
        key.hasPrefix(settingPrefix) || key.hasPrefix(serverPrefix)
    }

    private static func decodeSetting(_ value: String) -> SettingsTransferFile.Setting? {
        try? JSONDecoder().decode(SettingsTransferFile.Setting.self, from: Data(value.utf8))
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    // MARK: Agreed state

    /// Hashes of what both sides last agreed on. A file, not UserDefaults: writing it must not
    /// look like a settings change.
    private var baseURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("icloud-settings-sync.json")
    }

    private func loadBase() -> [String: String] {
        guard let baseURL, let data = try? Data(contentsOf: baseURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func saveBase(_ base: [String: String]) {
        guard let baseURL, let data = try? JSONEncoder().encode(base) else { return }
        try? data.write(to: baseURL, options: .atomic)
    }
}

/// Settings row: the toggle, plus the choice of what happens to the iCloud copy when turning off.
struct ICloudSettingsSyncRow: View {
    @ObservedObject private var sync = ICloudSettingsSync.shared
    @ObservedObject private var appearance = AppearanceManager.shared
    @State private var confirmsEnable = false
    @State private var confirmsDisable = false

    var body: some View {
        Toggle(isOn: Binding(
            get: { sync.isEnabled },
            set: { on in
                if on { confirmsEnable = true } else { confirmsDisable = true }
            }
        )) {
            Label("Sync with iCloud", systemImage: "icloud")
        }
        .tint(appearance.tintColor)
        .stashyGroupedBlockRow(index: 0, count: sync.problem == nil ? 1 : 2)
        .alert("Sync with iCloud?", isPresented: $confirmsEnable) {
            Button("Turn On") { sync.enable() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Settings already in iCloud replace the ones on this device. API keys are end-to-end encrypted through iCloud Keychain, which must be on for them to sync.")
        }
        .alert("Turn off iCloud sync?", isPresented: $confirmsDisable) {
            Button("Turn Off") { sync.disable(removingCloudData: false) }
            Button("Turn Off and Remove from iCloud", role: .destructive) { sync.disable(removingCloudData: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Servers, API keys and settings stay on this device either way.")
        }

        if let problem = sync.problem {
            Label(problem, systemImage: "exclamationmark.icloud")
                .foregroundStyle(.secondary)
                .stashyGroupedBlockRow(index: 1, count: 2)
        }
    }
}
#endif
