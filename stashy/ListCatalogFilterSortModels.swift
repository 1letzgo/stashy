//
//  ListCatalogFilterSortModels.swift
//  stashy
//
//  Shared preset picker tags, local presets, and SavedFilter metadata for
//  Performers / Tags / Studios catalog "Filter & Sort" sheets.
//

#if !os(tvOS)
import Foundation

// MARK: - O Count live chip (`o_counter` / `IntCriterionInput`)

/// Tag encoding for live-filter `o_counter`, used by scene / image / performer chip rows and presets.
enum SceneLiveOCounterChip {
    static let equalZero = "EQUALS:0"
    static let greaterThan0 = "GREATER_THAN:0"
    static let greaterThan4 = "GREATER_THAN:4"
    static let greaterThan9 = "GREATER_THAN:9"
}

func sceneLiveOCounterCriterion(from tag: String) -> [String: Any]? {
    let parts = tag.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2, let v = Int(parts[1]) else { return nil }
    return ["value": v, "modifier": parts[0]]
}

// MARK: - Image list media type (live `image_filter.path` regex)

/// Live chip for Stash `findImages` via `path` / `MATCHES_REGEX`.
enum ImageListMediaKind: String, CaseIterable, Identifiable, Equatable {
    case all
    case stillImage
    case video

    var id: String { rawValue }

    /// Regex value for `ImageFilterType.path` with modifier `MATCHES_REGEX`.
    static let stillImagePathRegex = "(?i)\\.(jpe?g|png|webp|gif)$"
    static let videoPathRegex = "(?i)\\.(mp4|mov|m4v|webm|mkv)$"

    var pathCriterion: [String: Any]? {
        switch self {
        case .all:
            return nil
        case .stillImage:
            return ["value": Self.stillImagePathRegex, "modifier": "MATCHES_REGEX"]
        case .video:
            return ["value": Self.videoPathRegex, "modifier": "MATCHES_REGEX"]
        }
    }

    /// Restores chip state from a saved `liveFragment` `path` criterion (ignores unknown regexes).
    static func fromPathFragment(_ path: Any?) -> ImageListMediaKind? {
        guard let path = path as? [String: Any],
              (path["modifier"] as? String) == "MATCHES_REGEX",
              let value = path["value"] as? String else { return nil }
        if value == stillImagePathRegex { return .stillImage }
        if value == videoPathRegex { return .video }
        return nil
    }
}

// MARK: - Preset picker row ids (`""` | `server:<stashId>` | `local:<uuid>`)

enum ListLivePresetTag {
    static let serverPrefix = "server:"
    static let localPrefix = "local:"

    static func serverRow(_ id: String) -> String { serverPrefix + id }
    static func localRow(_ uuid: UUID) -> String { localPrefix + uuid.uuidString }

    static func parseServerId(_ tagged: String) -> String? {
        guard tagged.hasPrefix(serverPrefix) else { return nil }
        return String(tagged.dropFirst(serverPrefix.count))
    }

    static func parseLocalUUIDString(_ tagged: String) -> String? {
        guard tagged.hasPrefix(localPrefix) else { return nil }
        return String(tagged.dropFirst(localPrefix.count))
    }

    static func migrateLegacySelection(_ selection: inout String) {
        let s = selection
        guard !s.isEmpty, !s.contains(":"), UUID(uuidString: s) != nil else { return }
        selection = localPrefix + s
    }
}

// MARK: - JSON helpers (SavedFilter ui_options)

private func catalogJsonObjectAsStringKeyedDict(_ value: Any?) -> [String: Any]? {
    guard let value else { return nil }
    if let d = value as? [String: Any] { return d }
    if let ns = value as? NSDictionary {
        var out: [String: Any] = [:]
        for (k, v) in ns {
            guard let ks = k as? String else { continue }
            out[ks] = v
        }
        return out
    }
    return nil
}

private func catalogJsonValueAsNonEmptyString(_ value: Any?) -> String? {
    if let s = value as? String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    if let s = value as? NSString {
        let t = (s as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    return nil
}

extension StashDBViewModel.SavedFilter {
    /// Metadata written by stashy when saving a catalog list preset to the server (`ui_options.stashy`).
    struct StashyCatalogPresetMetadata {
        var baseSavedFilterId: String?
        var liveFragment: [String: Any]
        var sortRaw: String?
    }

    var stashyCatalogPresetMetadata: StashyCatalogPresetMetadata? {
        guard let ui = catalogJsonObjectAsStringKeyedDict(ui_options?.value),
              let stashy = catalogJsonObjectAsStringKeyedDict(ui["stashy"]) else { return nil }
        let base = stashy["baseSavedFilterId"] as? String
        let live = catalogJsonObjectAsStringKeyedDict(stashy["liveFragment"]) ?? [:]
        let sortRaw = catalogJsonValueAsNonEmptyString(stashy["sortRaw"])
        return StashyCatalogPresetMetadata(baseSavedFilterId: base, liveFragment: live, sortRaw: sortRaw)
    }
}

// MARK: - Performer local presets

struct PerformerListLiveFilterPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var sortRaw: String
    var baseSavedFilterId: String?
    var liveFragmentJSON: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sort: StashDBViewModel.PerformerSortOption,
        baseSavedFilterId: String?,
        liveFragment: [String: Any]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortRaw = sort.rawValue
        self.baseSavedFilterId = baseSavedFilterId
        if JSONSerialization.isValidJSONObject(liveFragment),
           let data = try? JSONSerialization.data(withJSONObject: liveFragment, options: []),
           let json = String(data: data, encoding: .utf8) {
            self.liveFragmentJSON = json
        } else {
            self.liveFragmentJSON = "{}"
        }
    }

    var sort: StashDBViewModel.PerformerSortOption {
        StashDBViewModel.PerformerSortOption(rawValue: sortRaw) ?? .sceneCountDesc
    }

    var liveFragment: [String: Any] {
        guard let data = liveFragmentJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func renamed(_ newName: String) -> PerformerListLiveFilterPreset {
        PerformerListLiveFilterPreset(
            id: id,
            name: newName,
            createdAt: createdAt,
            sort: sort,
            baseSavedFilterId: baseSavedFilterId,
            liveFragment: liveFragment
        )
    }
}

enum PerformerListLiveFilterPresetStore {
    private static func storageKey(serverId: UUID) -> String {
        "stashy_performer_catalog_live_filter_presets_\(serverId.uuidString)"
    }

    static func loadPresets() -> [PerformerListLiveFilterPreset] {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return [] }
        let key = storageKey(serverId: serverId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PerformerListLiveFilterPreset].self, from: data)) ?? []
    }

    private static func saveAll(_ presets: [PerformerListLiveFilterPreset]) {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return }
        let key = storageKey(serverId: serverId)
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(_ preset: PerformerListLiveFilterPreset) {
        var all = loadPresets()
        if let idx = all.firstIndex(where: { $0.id == preset.id }) {
            all[idx] = preset
        } else {
            all.append(preset)
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveAll(all)
    }

    static func remove(id: UUID) {
        var all = loadPresets()
        all.removeAll { $0.id == id }
        saveAll(all)
    }
}

// MARK: - Tag local presets

struct TagListLiveFilterPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var sortRaw: String
    var baseSavedFilterId: String?
    var liveFragmentJSON: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sort: StashDBViewModel.TagSortOption,
        baseSavedFilterId: String?,
        liveFragment: [String: Any]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortRaw = sort.rawValue
        self.baseSavedFilterId = baseSavedFilterId
        if JSONSerialization.isValidJSONObject(liveFragment),
           let data = try? JSONSerialization.data(withJSONObject: liveFragment, options: []),
           let json = String(data: data, encoding: .utf8) {
            self.liveFragmentJSON = json
        } else {
            self.liveFragmentJSON = "{}"
        }
    }

    var sort: StashDBViewModel.TagSortOption {
        StashDBViewModel.TagSortOption(rawValue: sortRaw) ?? .sceneCountDesc
    }

    var liveFragment: [String: Any] {
        guard let data = liveFragmentJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func renamed(_ newName: String) -> TagListLiveFilterPreset {
        TagListLiveFilterPreset(
            id: id,
            name: newName,
            createdAt: createdAt,
            sort: sort,
            baseSavedFilterId: baseSavedFilterId,
            liveFragment: liveFragment
        )
    }
}

enum TagListLiveFilterPresetStore {
    private static func storageKey(serverId: UUID) -> String {
        "stashy_tag_catalog_live_filter_presets_\(serverId.uuidString)"
    }

    static func loadPresets() -> [TagListLiveFilterPreset] {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return [] }
        let key = storageKey(serverId: serverId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([TagListLiveFilterPreset].self, from: data)) ?? []
    }

    private static func saveAll(_ presets: [TagListLiveFilterPreset]) {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return }
        let key = storageKey(serverId: serverId)
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(_ preset: TagListLiveFilterPreset) {
        var all = loadPresets()
        if let idx = all.firstIndex(where: { $0.id == preset.id }) {
            all[idx] = preset
        } else {
            all.append(preset)
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveAll(all)
    }

    static func remove(id: UUID) {
        var all = loadPresets()
        all.removeAll { $0.id == id }
        saveAll(all)
    }
}

// MARK: - Studio local presets

struct StudioListLiveFilterPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var sortRaw: String
    var baseSavedFilterId: String?
    var liveFragmentJSON: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sort: StashDBViewModel.StudioSortOption,
        baseSavedFilterId: String?,
        liveFragment: [String: Any]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortRaw = sort.rawValue
        self.baseSavedFilterId = baseSavedFilterId
        if JSONSerialization.isValidJSONObject(liveFragment),
           let data = try? JSONSerialization.data(withJSONObject: liveFragment, options: []),
           let json = String(data: data, encoding: .utf8) {
            self.liveFragmentJSON = json
        } else {
            self.liveFragmentJSON = "{}"
        }
    }

    var sort: StashDBViewModel.StudioSortOption {
        StashDBViewModel.StudioSortOption(rawValue: sortRaw) ?? .nameAsc
    }

    var liveFragment: [String: Any] {
        guard let data = liveFragmentJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func renamed(_ newName: String) -> StudioListLiveFilterPreset {
        StudioListLiveFilterPreset(
            id: id,
            name: newName,
            createdAt: createdAt,
            sort: sort,
            baseSavedFilterId: baseSavedFilterId,
            liveFragment: liveFragment
        )
    }
}

enum StudioListLiveFilterPresetStore {
    private static func storageKey(serverId: UUID) -> String {
        "stashy_studio_catalog_live_filter_presets_\(serverId.uuidString)"
    }

    static func loadPresets() -> [StudioListLiveFilterPreset] {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return [] }
        let key = storageKey(serverId: serverId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([StudioListLiveFilterPreset].self, from: data)) ?? []
    }

    private static func saveAll(_ presets: [StudioListLiveFilterPreset]) {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return }
        let key = storageKey(serverId: serverId)
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(_ preset: StudioListLiveFilterPreset) {
        var all = loadPresets()
        if let idx = all.firstIndex(where: { $0.id == preset.id }) {
            all[idx] = preset
        } else {
            all.append(preset)
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveAll(all)
    }

    static func remove(id: UUID) {
        var all = loadPresets()
        all.removeAll { $0.id == id }
        saveAll(all)
    }
}

// MARK: - When to show live chip rows vs. server-only notice

enum CatalogLiveChipFilterSupport {
    // MARK: Studio criterion parsing (saved filters / JSON may use Int ids or a single string `value`)

    /// Ids for `studios` / `tags` with modifier `INCLUDES` (catalog live filters).
    static func includesIds(fromCriterion value: Any?) -> [String] {
        guard let d = value as? [String: Any] else { return [] }
        guard (d["modifier"] as? String) == "INCLUDES" else { return [] }
        return FilterMapper.idStrings(from: d["value"])
    }

    /// First id for `studios` with modifier `INCLUDES` (catalog live filters).
    static func studioIncludesFirstId(fromCriterion value: Any?) -> String? {
        includesIds(fromCriterion: value).first
    }

    /// Criteria dict for image live chips: prefers `filter_dict`, else `object_filter`, unwraps nested `image_filter`.
    static func imageFilterCriteriaForLiveChipUI(from filter: StashDBViewModel.SavedFilter?) -> [String: Any] {
        guard let filter else { return [:] }
        let raw: [String: Any]?
        if let d = filter.filterDict, !d.isEmpty {
            raw = d
        } else if let obj = filter.object_filter, let od = obj.value as? [String: Any], !od.isEmpty {
            raw = od
        } else {
            return [:]
        }
        var flat = FilterMapper.sanitize(raw!, isMarker: false)
        while let inner = flat["image_filter"] as? [String: Any] {
            flat.removeValue(forKey: "image_filter")
            let innerSan = FilterMapper.sanitize(inner, isMarker: false)
            for (k, v) in innerSan {
                flat[k] = v
            }
        }
        return flat
    }

    static func performerSavedFilterSupportsLiveEditor(_ filter: StashDBViewModel.SavedFilter?) -> Bool {
        guard let dict = filter?.filterDict, !dict.isEmpty else { return true }
        if dict.keys.contains(where: { $0 == "AND" || $0 == "OR" || $0 == "NOT" }) { return false }
        let allowed: Set<String> = [
            "birthdate", "hair_color", "gender", "country", "fake_tits", "filter_favorites",
            "is_missing", "has_image", "rating100", "scene_count", "tag_count", "stash_ids", "o_counter"
        ]
        return dict.keys.allSatisfy { allowed.contains($0) }
    }

    static func tagSavedFilterSupportsLiveEditor(_ filter: StashDBViewModel.SavedFilter?) -> Bool {
        guard let dict = filter?.filterDict, !dict.isEmpty else { return true }
        if dict.keys.contains(where: { $0 == "AND" || $0 == "OR" || $0 == "NOT" }) { return false }
        let allowed: Set<String> = ["favorite", "scene_count", "performer_count", "marker_count", "stash_ids"]
        return dict.keys.allSatisfy { allowed.contains($0) }
    }

    static func studioSavedFilterSupportsLiveEditor(_ filter: StashDBViewModel.SavedFilter?) -> Bool {
        guard let dict = filter?.filterDict, !dict.isEmpty else { return true }
        if dict.keys.contains(where: { $0 == "AND" || $0 == "OR" || $0 == "NOT" }) { return false }
        let allowed: Set<String> = ["favorite", "rating100", "scene_count", "details", "stash_ids"]
        return dict.keys.allSatisfy { allowed.contains($0) }
    }

    static func gallerySavedFilterSupportsLiveEditor(_ filter: StashDBViewModel.SavedFilter?) -> Bool {
        guard let dict = filter?.filterDict, !dict.isEmpty else { return true }
        if dict.keys.contains(where: { $0 == "AND" || $0 == "OR" || $0 == "NOT" }) { return false }
        let allowed: Set<String> = ["favorite", "rating100", "file_count", "path", "details", "stash_ids", "studios"]
        return dict.keys.allSatisfy { allowed.contains($0) }
    }

    static func imageSavedFilterSupportsLiveEditor(_ filter: StashDBViewModel.SavedFilter?) -> Bool {
        let flat = imageFilterCriteriaForLiveChipUI(from: filter)
        guard !flat.isEmpty else { return true }
        if flat.keys.contains(where: { $0 == "AND" || $0 == "OR" || $0 == "NOT" }) { return false }
        let allowed: Set<String> = ["performer_favorite", "rating100", "organized", "is_missing", "path", "stash_ids", "o_counter", "studios", "tags"]
        if flat["studios"] != nil, includesIds(fromCriterion: flat["studios"]).isEmpty {
            return false
        }
        if flat["tags"] != nil, includesIds(fromCriterion: flat["tags"]).isEmpty {
            return false
        }
        return flat.keys.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - Gallery local presets

struct GalleryListLiveFilterPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var sortRaw: String
    var baseSavedFilterId: String?
    var liveFragmentJSON: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sort: StashDBViewModel.GallerySortOption,
        baseSavedFilterId: String?,
        liveFragment: [String: Any]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortRaw = sort.rawValue
        self.baseSavedFilterId = baseSavedFilterId
        if JSONSerialization.isValidJSONObject(liveFragment),
           let data = try? JSONSerialization.data(withJSONObject: liveFragment, options: []),
           let json = String(data: data, encoding: .utf8) {
            self.liveFragmentJSON = json
        } else {
            self.liveFragmentJSON = "{}"
        }
    }

    var sort: StashDBViewModel.GallerySortOption {
        StashDBViewModel.GallerySortOption(rawValue: sortRaw) ?? .dateDesc
    }

    var liveFragment: [String: Any] {
        guard let data = liveFragmentJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func renamed(_ newName: String) -> GalleryListLiveFilterPreset {
        GalleryListLiveFilterPreset(
            id: id,
            name: newName,
            createdAt: createdAt,
            sort: sort,
            baseSavedFilterId: baseSavedFilterId,
            liveFragment: liveFragment
        )
    }
}

enum GalleryListLiveFilterPresetStore {
    private static func storageKey(serverId: UUID) -> String {
        "stashy_gallery_catalog_live_filter_presets_\(serverId.uuidString)"
    }

    static func loadPresets() -> [GalleryListLiveFilterPreset] {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return [] }
        let key = storageKey(serverId: serverId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([GalleryListLiveFilterPreset].self, from: data)) ?? []
    }

    private static func saveAll(_ presets: [GalleryListLiveFilterPreset]) {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return }
        let key = storageKey(serverId: serverId)
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(_ preset: GalleryListLiveFilterPreset) {
        var all = loadPresets()
        if let idx = all.firstIndex(where: { $0.id == preset.id }) {
            all[idx] = preset
        } else {
            all.append(preset)
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveAll(all)
    }

    static func remove(id: UUID) {
        var all = loadPresets()
        all.removeAll { $0.id == id }
        saveAll(all)
    }
}

// MARK: - Image local presets

struct ImageListLiveFilterPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var sortRaw: String
    var baseSavedFilterId: String?
    var liveFragmentJSON: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sort: StashDBViewModel.ImageSortOption,
        baseSavedFilterId: String?,
        liveFragment: [String: Any]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortRaw = sort.rawValue
        self.baseSavedFilterId = baseSavedFilterId
        if JSONSerialization.isValidJSONObject(liveFragment),
           let data = try? JSONSerialization.data(withJSONObject: liveFragment, options: []),
           let json = String(data: data, encoding: .utf8) {
            self.liveFragmentJSON = json
        } else {
            self.liveFragmentJSON = "{}"
        }
    }

    var sort: StashDBViewModel.ImageSortOption {
        StashDBViewModel.ImageSortOption(rawValue: sortRaw) ?? .dateDesc
    }

    var liveFragment: [String: Any] {
        guard let data = liveFragmentJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func renamed(_ newName: String) -> ImageListLiveFilterPreset {
        ImageListLiveFilterPreset(
            id: id,
            name: newName,
            createdAt: createdAt,
            sort: sort,
            baseSavedFilterId: baseSavedFilterId,
            liveFragment: liveFragment
        )
    }
}

enum ImageListLiveFilterPresetStore {
    private static func storageKey(serverId: UUID) -> String {
        "stashy_image_catalog_live_filter_presets_\(serverId.uuidString)"
    }

    static func loadPresets() -> [ImageListLiveFilterPreset] {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return [] }
        let key = storageKey(serverId: serverId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ImageListLiveFilterPreset].self, from: data)) ?? []
    }

    private static func saveAll(_ presets: [ImageListLiveFilterPreset]) {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return }
        let key = storageKey(serverId: serverId)
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(_ preset: ImageListLiveFilterPreset) {
        var all = loadPresets()
        if let idx = all.firstIndex(where: { $0.id == preset.id }) {
            all[idx] = preset
        } else {
            all.append(preset)
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveAll(all)
    }

    static func remove(id: UUID) {
        var all = loadPresets()
        all.removeAll { $0.id == id }
        saveAll(all)
    }
}

// MARK: - Marker catalog local presets (scene-style live chips + `SceneMarkerSortOption`)

struct MarkerLiveFilterPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var sortRaw: String
    var baseSavedFilterId: String?
    var liveFragmentJSON: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sort: StashDBViewModel.SceneMarkerSortOption,
        baseSavedFilterId: String?,
        liveFragment: [String: Any]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortRaw = sort.rawValue
        self.baseSavedFilterId = baseSavedFilterId
        if JSONSerialization.isValidJSONObject(liveFragment),
           let data = try? JSONSerialization.data(withJSONObject: liveFragment, options: []),
           let json = String(data: data, encoding: .utf8) {
            self.liveFragmentJSON = json
        } else {
            self.liveFragmentJSON = "{}"
        }
    }

    var sort: StashDBViewModel.SceneMarkerSortOption {
        StashDBViewModel.SceneMarkerSortOption(rawValue: sortRaw)
            ?? StashDBViewModel.SceneMarkerSortOption(rawValue: TabManager.shared.getSortOption(for: .markers) ?? "") ?? .createdAtDesc
    }

    var liveFragment: [String: Any] {
        guard let data = liveFragmentJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func renamed(_ newName: String) -> MarkerLiveFilterPreset {
        MarkerLiveFilterPreset(
            id: id,
            name: newName,
            createdAt: createdAt,
            sort: sort,
            baseSavedFilterId: baseSavedFilterId,
            liveFragment: liveFragment
        )
    }
}

enum MarkerLiveFilterPresetStore {
    private static func storageKey(serverId: UUID) -> String {
        "stashy_marker_catalog_live_filter_presets_\(serverId.uuidString)"
    }

    static func loadPresets() -> [MarkerLiveFilterPreset] {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return [] }
        let key = storageKey(serverId: serverId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MarkerLiveFilterPreset].self, from: data)) ?? []
    }

    private static func saveAll(_ presets: [MarkerLiveFilterPreset]) {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return }
        let key = storageKey(serverId: serverId)
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(_ preset: MarkerLiveFilterPreset) {
        var all = loadPresets()
        if let idx = all.firstIndex(where: { $0.id == preset.id }) {
            all[idx] = preset
        } else {
            all.append(preset)
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveAll(all)
    }

    static func remove(id: UUID) {
        var all = loadPresets()
        all.removeAll { $0.id == id }
        saveAll(all)
    }
}
#endif
