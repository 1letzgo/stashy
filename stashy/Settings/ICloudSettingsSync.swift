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

    /// iCloud key-value storage allows 1 MB and 1024 keys per app (`ICloudSettingsQuota`),
    /// whatever the user's iCloud storage, and 64 byte key names.
    private static let settingPrefix = "s."
    private static let serverPrefix = "server."
    private static let deletedServer = "deleted"
    private static let deletedSettingType = "deleted"

    private let store = NSUbiquitousKeyValueStore.default
    private var observers: [NSObjectProtocol] = []
    private var reconcileScheduled = false
    private var lastSecretRefresh = Date.distantPast
    /// iCloud reported `NSUbiquitousKeyValueStoreQuotaViolationChange`.
    private var quotaReportedByICloud = false

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
        quotaReportedByICloud = false
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
            if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
                // iCloud refused a write. The next reconcile counts again and clears this once
                // the store is back under the limit.
                sync.quotaReportedByICloud = true
            }
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
            problem = tr("hint_sign_in_to_icloud_on")
            return
        }
        let local = localEntries()
        let stored = store.dictionaryRepresentation
        var remote = stored.compactMapValues { $0 as? String }.filter { Self.isSyncKey($0.key) }
        // Apple counts every entry of the store, also ones this code does not own.
        var quota = ICloudSettingsQuota()
        for (key, value) in stored {
            switch value {
            case let s as String: quota.record(key, ICloudSettingsQuota.size(key, s))
            case let d as Data: quota.record(key, key.utf8.count + d.count)
            default: quota.record(key, key.utf8.count + 8)
            }
        }
        let oldBase = loadBase()
        var base = oldBase
        var appliedSettings = false
        var appliedServers = false
        var pushes: [(key: String, value: String)] = []
        var removals: [String] = []
        let now = Date().timeIntervalSince1970

        for key in Set(local.keys).union(remote.keys).sorted() {
            let isServer = key.hasPrefix(Self.serverPrefix)
            let setting = isServer ? nil : remote[key].flatMap(Self.decodeSetting)
            if !isServer, remote[key] != nil, setting == nil { continue }
            if let setting, !SettingsTransfer.isSyncable(setting.key) {
                // Written by an older version, or the key became device-local since: free its space.
                // This device's own value stays.
                removals.append(key)
                base[key] = nil
                continue
            }
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
                guard let value = remote[key] else { break }
                if let setting, isDeletion, local[key] == nil {
                    switch ICloudDeletionMarker.state(deletedAt: Self.deletedAt(setting), now: now) {
                    case .expired:
                        // Every device has had 90 days to apply it.
                        removals.append(key)
                        base[key] = nil
                        continue
                    case .undated:
                        if let marker = Self.deletionMarker(for: setting.key, at: now) {
                            pushes.append((key, marker))
                        }
                        continue
                    case .live:
                        break
                    }
                }
                base[key] = KeychainManager.sha256Hex(value)
            case .pushLocal:
                if let value = local[key] { pushes.append((key, value)) }
            case .pushLocalDeletion:
                if isServer {
                    pushes.append((key, Self.deletedServer))
                } else if let setting, let marker = Self.deletionMarker(for: setting.key, at: now) {
                    pushes.append((key, marker))
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

        // Space first, then the pushes that fit, servers and small values first.
        for key in removals {
            store.removeObject(forKey: key)
            remote[key] = nil
            quota.remove(key)
        }
        var keptLocal = 0
        for (key, value) in ICloudSettingsQuota.pushOrder(pushes, isServer: { $0.hasPrefix(Self.serverPrefix) }) {
            guard quota.take(key, value) else {
                keptLocal += 1
                continue
            }
            store.set(value, forKey: key)
            remote[key] = value
            base[key] = KeychainManager.sha256Hex(value)
        }
        // Hashes of entries gone from both sides only grow the file.
        base = base.filter { local[$0.key] != nil || remote[$0.key] != nil }

        if base != oldBase { saveBase(base) }
        if keptLocal == 0, quota.isWithinLimits { quotaReportedByICloud = false }
        if keptLocal > 0 {
            problem = tr("hint_icloud_sync_limit_kept_arg", keptLocal)
        } else if quotaReportedByICloud {
            problem = tr("hint_icloud_sync_limit_reached")
        } else {
            problem = nil
        }
        AppLog.debug("iCloud settings: \(quota.usedKeys) keys, \(quota.usedBytes) bytes, \(removals.count) removed, \(keptLocal) kept on device")
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

    /// A setting's deletion marker, stamped with the time so it can leave the store later.
    /// Older versions read any entry of type "deleted" as a marker, whatever its value.
    private static func deletionMarker(for name: String, at time: Double) -> String? {
        encode(SettingsTransferFile.Setting(key: name, type: deletedSettingType, value: .number(time.rounded())))
    }

    private static func deletedAt(_ marker: SettingsTransferFile.Setting) -> Double? {
        if case .number(let time) = marker.value { return time }
        return nil
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
            Label(tr("action_sync_with_icloud"), systemImage: "icloud")
        }
        .tint(appearance.tintColor)
        .stashyGroupedBlockRow(index: 0, count: sync.problem == nil ? 1 : 2)
        .alert(tr("confirm_sync_with_icloud"), isPresented: $confirmsEnable) {
            Button(tr("action_turn_on")) { sync.enable() }
            Button(tr("action_cancel"), role: .cancel) {}
        } message: {
            Text(tr("hint_settings_already_in_icloud_replace"))
        }
        .alert(tr("confirm_turn_off_icloud_sync"), isPresented: $confirmsDisable) {
            Button(tr("action_turn_off")) { sync.disable(removingCloudData: false) }
            Button(tr("hint_turn_off_and_remove_from"), role: .destructive) { sync.disable(removingCloudData: true) }
            Button(tr("action_cancel"), role: .cancel) {}
        } message: {
            Text(tr("hint_servers_api_keys_and_settings"))
        }

        if let problem = sync.problem {
            Label(problem, systemImage: "exclamationmark.icloud")
                .foregroundStyle(.secondary)
                .stashyGroupedBlockRow(index: 1, count: 2)
        }
    }
}
#endif
