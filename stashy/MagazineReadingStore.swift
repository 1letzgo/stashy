//
//  MagazineReadingStore.swift
//  stashy
//
//  Last read page per gallery. Stash's gallery `custom_fields` are the shared source across
//  devices; a local per-server copy covers offline reading and servers without those fields.
//

import Foundation

@MainActor
final class MagazineReadingStore: ObservableObject {
    struct Entry: Codable, Equatable {
        /// 1-based page number; on a spread its first page.
        var page: Int
        var readAt: Date
        /// False while the server has not seen this position yet.
        var isSynced: Bool
    }

    static let shared = MagazineReadingStore()

    private static let pageField = "stashy_read_page"
    private static let readAtField = "stashy_read_at"

    @Published private(set) var entries: [String: Entry] = [:]

    private let repository = GalleryRepository()
    private var serverObserver: NSObjectProtocol?

    private static var serverSuffix: String {
        ServerConfigManager.shared.loadConfig()?.id.uuidString ?? "none"
    }

    private static var storageKey: String { "stashy.magazine.progress_\(serverSuffix)" }

    private init() {
        loadLocal()
        serverObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { MagazineReadingStore.shared.loadLocal() }
        }
    }

    /// Local only; the server gets it on `pushIfNeeded`, because every `galleryUpdate` also bumps the gallery's `updated_at`.
    func note(page: Int, galleryId: String) {
        entries[galleryId] = Entry(page: page, readAt: Date(), isSynced: false)
        saveLocal()
    }

    /// Back to the first page, here and on the server.
    func resetPosition(galleryId: String) {
        note(page: 1, galleryId: galleryId)
        Task { await pushIfNeeded(galleryId: galleryId) }
    }

    /// Merges the server's positions in; the newer `readAt` wins. Failure (offline, server without
    /// gallery custom fields) just leaves the local copy in charge.
    func sync(galleryIds: [String]) async {
        guard !galleryIds.isEmpty else { return }
        let suffix = Self.serverSuffix
        do {
            let remote = try await repository.fetchCustomFields(galleryIds: galleryIds)
            guard suffix == Self.serverSuffix else { return }
            var changed = false
            var unsyncedIds: [String] = []
            for id in galleryIds {
                let local = entries[id]
                if let fields = remote[id], let entry = Self.entry(from: fields), entry.readAt >= (local?.readAt ?? .distantPast) {
                    if local != entry {
                        entries[id] = entry
                        changed = true
                    }
                } else if local?.isSynced == false {
                    unsyncedIds.append(id)
                }
            }
            if changed { saveLocal() }
            // E.g. the app was killed while reading before it could push.
            for id in unsyncedIds { await pushIfNeeded(galleryId: id) }
        } catch {
            AppLog.debug("Magazin: reading progress not synced: \(error.localizedDescription)")
        }
    }

    func pushIfNeeded(galleryId: String) async {
        guard let entry = entries[galleryId], !entry.isSynced else { return }
        let suffix = Self.serverSuffix
        do {
            try await repository.updateCustomFields(galleryId: galleryId, partial: [
                Self.pageField: entry.page,
                Self.readAtField: ISO8601DateFormatter().string(from: entry.readAt)
            ])
            // Reading may have moved on during the request; that position still has to go out.
            guard suffix == Self.serverSuffix, entries[galleryId] == entry else { return }
            entries[galleryId]?.isSynced = true
            saveLocal()
        } catch {
            AppLog.debug("Magazin: reading progress not pushed: \(error.localizedDescription)")
        }
    }

    private static func entry(from fields: [String: StashJSONValue]) -> Entry? {
        guard let page = pageNumber(from: fields[pageField]),
              case .string(let readAtString)? = fields[readAtField],
              let readAt = ISO8601DateFormatter().date(from: readAtString) else { return nil }
        return Entry(page: page, readAt: readAt, isSynced: true)
    }

    private static func pageNumber(from value: StashJSONValue?) -> Int? {
        switch value {
        case .int(let page): return page
        case .double(let page): return Int(page)
        case .string(let page): return Int(page)
        default: return nil
        }
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            entries = [:]
            return
        }
        entries = decoded
    }

    private func saveLocal() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

/// Settings › stashy+: whether Home shows Magazin.
enum MagazineMode {
    static let enabledKey = "stashy.magazine.enabled"
}

/// Settings › stashy+: the saved gallery filter Magazin opens with, per server.
enum MagazineDefaultFilter {
    static let changeKey = "magazine"

    private static var key: String {
        "stashy.magazine.defaultFilter_\(ServerConfigManager.shared.loadConfig()?.id.uuidString ?? "none")"
    }

    static var id: String? { UserDefaults.standard.string(forKey: key) }

    static func set(_ filterId: String?) {
        UserDefaults.standard.set(filterId, forKey: key)
        NotificationCenter.default.post(
            name: NSNotification.Name("DefaultFilterChanged"),
            object: nil,
            userInfo: ["tab": changeKey]
        )
    }
}
