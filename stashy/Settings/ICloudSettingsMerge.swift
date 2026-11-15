//
//  ICloudSettingsMerge.swift
//  stashy
//
//  The three-way rule behind the iCloud settings sync: what this device has, what iCloud has
//  and what both last agreed on decide which side moves. No Foundation state, so it stays testable.
//

enum ICloudSettingsMerge {
    enum Action: Equatable {
        /// Both sides already agree, or there is nothing on either side.
        case none
        case applyRemote
        case applyRemoteDeletion
        case pushLocal
        case pushLocalDeletion
    }

    /// - Parameters:
    ///   - local: this device's value, `nil` when it has none
    ///   - remote: iCloud's value, `nil` when iCloud has none; a deletion is `remoteIsDeletion`
    ///   - base: the value both sides last agreed on, `nil` when this device never synced it
    ///
    /// iCloud having *nothing* never deletes anything here: an empty store also means another
    /// account or a wiped store. Only an explicit deletion marker does.
    static func action(local: String?, remote: String?, remoteIsDeletion: Bool, base: String?) -> Action {
        guard let remote else {
            return local == nil ? .none : .pushLocal
        }
        if remoteIsDeletion {
            guard let local else { return .none }
            // Deleted elsewhere: only an untouched copy goes. Never-synced or edited ones survive.
            return local == base ? .applyRemoteDeletion : .pushLocal
        }
        guard let local else {
            return remote == base ? .pushLocalDeletion : .applyRemote
        }
        if local == remote { return .none }
        if remote == base { return .pushLocal }
        // A device joining, or both sides changed: iCloud wins.
        return .applyRemote
    }
}

/// What iCloud key-value storage allows this app, counted the way Apple counts it: key names and
/// values together. Apple's limits are 1 MB and 1024 keys per app, independent of the user's
/// iCloud storage; the defaults keep 10 % headroom. No Foundation state, so it stays testable.
struct ICloudSettingsQuota: Equatable {
    static let defaultMaxTotalBytes = 900_000
    static let defaultMaxKeyCount = 1000
    /// One setting larger than this is no setting: it stays on the device.
    static let defaultMaxEntryBytes = 64_000

    var maxTotalBytes = defaultMaxTotalBytes
    var maxKeyCount = defaultMaxKeyCount
    var maxEntryBytes = defaultMaxEntryBytes

    private(set) var usedBytes = 0
    private(set) var entrySizes: [String: Int] = [:]

    var usedKeys: Int { entrySizes.count }
    var isWithinLimits: Bool { usedBytes <= maxTotalBytes && usedKeys <= maxKeyCount }

    init(entries: [String: String] = [:]) {
        for (key, value) in entries { record(key, Self.size(key, value)) }
    }

    static func size(_ key: String, _ value: String) -> Int { key.utf8.count + value.utf8.count }

    /// Records an entry already in the store (also one this app does not own).
    mutating func record(_ key: String, _ size: Int) {
        usedBytes += size - (entrySizes[key] ?? 0)
        entrySizes[key] = size
    }

    func fits(_ key: String, _ value: String) -> Bool {
        let size = Self.size(key, value)
        guard size <= maxEntryBytes else { return false }
        let previous = entrySizes[key]
        if previous == nil, usedKeys >= maxKeyCount { return false }
        return usedBytes - (previous ?? 0) + size <= maxTotalBytes
    }

    /// Takes the entry into the count when it fits; `false` leaves the count untouched.
    mutating func take(_ key: String, _ value: String) -> Bool {
        guard fits(key, value) else { return false }
        record(key, Self.size(key, value))
        return true
    }

    mutating func remove(_ key: String) {
        guard let size = entrySizes.removeValue(forKey: key) else { return }
        usedBytes -= size
    }

    /// Pushes ordered so the most entries fit: servers first, then the smallest values.
    static func pushOrder(_ pushes: [(key: String, value: String)], isServer: (String) -> Bool) -> [(key: String, value: String)] {
        pushes.sorted { a, b in
            let sa = isServer(a.key), sb = isServer(b.key)
            if sa != sb { return sa }
            let la = a.value.utf8.count, lb = b.value.utf8.count
            return la != lb ? la < lb : a.key < b.key
        }
    }
}

/// Deletion markers of settings carry the time they were written (seconds since 1970) and leave
/// the store after `lifetime`. Markers from versions before that carry none: they get one stamped
/// on first sight, so they expire too.
enum ICloudDeletionMarker {
    static let lifetime: Double = 90 * 86_400

    enum State: Equatable {
        case live
        case expired
        case undated
    }

    static func state(deletedAt: Double?, now: Double, lifetime: Double = lifetime) -> State {
        guard let deletedAt, deletedAt > 0 else { return .undated }
        return now - deletedAt > lifetime ? .expired : .live
    }
}
