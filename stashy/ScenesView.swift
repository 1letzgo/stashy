//
//  ScenesView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI

/// Preset picker row id: `""` | `server:<stashId>` | `local:<uuid>`.
/// Identisch zu `ListLivePresetTag` (Katalog-Filter); nur als Alias erhalten,
/// um Duplikat-Logik zu vermeiden.
typealias SceneLivePresetTag = ListLivePresetTag

/// Maps to `SceneSortOption.sortField` for the live-filter sheet (dropdown + asc/desc).
private enum SceneLiveSortFieldKind: String, CaseIterable, Identifiable {
    case date
    case created_at
    case title
    case duration
    case last_played_at
    case play_count
    case play_duration
    case o_counter
    case rating
    case random

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .date: return "Date"
        case .created_at: return "Created"
        case .title: return "Title"
        case .duration: return "Duration"
        case .last_played_at: return "Last played"
        case .play_count: return "Play count"
        case .play_duration: return "Watch time"
        case .o_counter: return "O Count"
        case .rating: return "Rating"
        case .random: return "Random"
        }
    }

    static func from(_ option: StashDBViewModel.SceneSortOption) -> SceneLiveSortFieldKind {
        SceneLiveSortFieldKind(rawValue: option.sortField) ?? .date
    }

    func sceneSortOption(ascending: Bool) -> StashDBViewModel.SceneSortOption {
        switch self {
        case .date: return ascending ? .dateAsc : .dateDesc
        case .created_at: return ascending ? .createdAtAsc : .createdAtDesc
        case .title: return ascending ? .titleAsc : .titleDesc
        case .duration: return ascending ? .durationAsc : .durationDesc
        case .last_played_at: return ascending ? .lastPlayedAtAsc : .lastPlayedAtDesc
        case .play_count: return ascending ? .playCountAsc : .playCountDesc
        case .play_duration: return ascending ? .playDurationAsc : .playDurationDesc
        case .o_counter: return ascending ? .oCounterAsc : .oCounterDesc
        case .rating: return ascending ? .ratingAsc : .ratingDesc
        case .random: return .random
        }
    }
}

/// Picker model: known fields from `SceneLiveSortFieldKind`, or **server / future** sort fields stashy does not list yet.
/// Policy: keep `SceneSortOption` as source of truth for fetches; UI shows "Other (field)" and disables Asc/Desc until the user picks a supported field.
private enum SceneLiveSortPickerValue: Hashable {
    case known(SceneLiveSortFieldKind)
    case unmapped(sortField: String)

    static func from(_ option: StashDBViewModel.SceneSortOption) -> SceneLiveSortPickerValue {
        if option.sortField == "random" { return .known(.random) }
        if let k = SceneLiveSortFieldKind(rawValue: option.sortField) { return .known(k) }
        return .unmapped(sortField: option.sortField)
    }

    var menuLabel: String {
        switch self {
        case .known(let k): return k.menuLabel
        case .unmapped(let f): return "Other (\(f))"
        }
    }

    var isRandom: Bool {
        if case .known(.random) = self { return true }
        return false
    }

    var isUnmapped: Bool {
        if case .unmapped = self { return true }
        return false
    }

    var knownKind: SceneLiveSortFieldKind? {
        if case .known(let k) = self { return k }
        return nil
    }
}

// MARK: - Marker sort (Reels „Markers“ + `SceneLiveFilterSheet`)

/// Maps to `SceneMarkerSortOption` for the live-filter sheet (dropdown + asc/desc), same layout as scene sort.
enum MarkerLiveSortFieldKind: String, CaseIterable, Identifiable {
    case created_at
    case updated_at
    case title
    case seconds
    case random

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .created_at: return "Created"
        case .updated_at: return "Updated"
        case .title: return "Title"
        case .seconds: return "Time"
        case .random: return "Random"
        }
    }

    static func from(_ option: StashDBViewModel.SceneMarkerSortOption) -> MarkerLiveSortFieldKind {
        switch option {
        case .random: return .random
        case .createdAtAsc, .createdAtDesc: return .created_at
        case .updatedAtAsc, .updatedAtDesc: return .updated_at
        case .titleAsc, .titleDesc: return .title
        case .secondsAsc, .secondsDesc: return .seconds
        }
    }

    func markerSortOption(ascending: Bool) -> StashDBViewModel.SceneMarkerSortOption {
        switch self {
        case .created_at: return ascending ? .createdAtAsc : .createdAtDesc
        case .updated_at: return ascending ? .updatedAtAsc : .updatedAtDesc
        case .title: return ascending ? .titleAsc : .titleDesc
        case .seconds: return ascending ? .secondsAsc : .secondsDesc
        case .random: return .random
        }
    }
}

enum MarkerLiveSortPickerValue: Hashable {
    case known(MarkerLiveSortFieldKind)

    static func from(_ option: StashDBViewModel.SceneMarkerSortOption) -> MarkerLiveSortPickerValue {
        .known(MarkerLiveSortFieldKind.from(option))
    }

    var isRandom: Bool {
        if case .known(.random) = self { return true }
        return false
    }

    var knownKind: MarkerLiveSortFieldKind? {
        if case .known(let k) = self { return k }
        return nil
    }
}

/// Chip rows only cover part of Stash’s `SceneFilterType`. We reject explicit non-chip / combinatorial
/// keys and ignore unknown future keys (instead of whitelisting only eight fields).
enum SceneLiveChipFilterSupport {
    /// Scene filter keys the chip UI cannot represent (see Stash `SceneFilterType`).
    private static let unsupportedSceneFilterKeys: Set<String> = [
        "AND", "OR", "NOT",
        "galleries_filter", "performers_filter", "studios_filter", "tags_filter", "movies_filter", "groups_filter", "markers_filter", "files_filter",
        "id", "title", "code", "details", "director",
        "oshash", "checksum", "phash", "phash_distance", "path", "file_count",
        "duplicated",
        "duration", "framerate", "bitrate", "video_codec", "audio_codec",
        "has_markers", "is_missing",
        "movies", "galleries", "tag_count", "performers", "performer_tags", "performer_age",
        "stash_id_endpoint", "stash_ids_endpoint", "stash_id_count",
        "url", "interactive_speed", "captions", "resume_time", "play_count", "play_duration", "last_played_at",
        "date", "created_at", "updated_at",
        "custom_fields"
    ]

    /// Some payloads nest criteria under `scene_filter`; unwrap for the support check.
    private static func flattenedForChipSupportInspection(_ dict: [String: Any]) -> [String: Any] {
        var flat = FilterMapper.sanitize(dict, isMarker: false)
        while let inner = flat["scene_filter"] as? [String: Any] {
            flat.removeValue(forKey: "scene_filter")
            let innerSan = FilterMapper.sanitize(inner, isMarker: false)
            for (k, v) in innerSan {
                flat[k] = v
            }
        }
        return flat
    }

    /// `true` when no AND/OR/NOT and no known non-chip criterion is present.
    static func filterDictSupportsLiveChipEditor(_ dict: [String: Any]?) -> Bool {
        guard let dict, !dict.isEmpty else { return true }
        let flat = flattenedForChipSupportInspection(dict)
        for key in flat.keys {
            if key == "studios" {
                if !multiIdINCLUDESCriterionIsChipRepresentable(flat["studios"]) { return false }
                continue
            }
            if key == "tags" {
                if !multiIdINCLUDESCriterionIsChipRepresentable(flat["tags"]) { return false }
                continue
            }
            if key == "groups" {
                if !multiIdINCLUDESCriterionIsChipRepresentable(flat["groups"]) { return false }
                continue
            }
            if unsupportedSceneFilterKeys.contains(key) { return false }
        }
        return true
    }

    /// Ids for `studios` / `tags` / `groups` with modifier `INCLUDES`.
    static func includesIds(fromCriterion value: Any?) -> [String] {
        guard let d = value as? [String: Any] else { return [] }
        guard (d["modifier"] as? String) == "INCLUDES" else { return [] }
        return FilterMapper.idStrings(from: d["value"])
    }

    /// First id for `studios` with modifier `INCLUDES` (Stash may send numeric ids or a single string `value`).
    static func studioIncludesFirstId(fromCriterion value: Any?) -> String? {
        includesIds(fromCriterion: value).first
    }

    /// `studios` / `tags` / `groups` with `INCLUDES` (same shape as Stash multi-id criteria).
    private static func multiIdINCLUDESCriterionIsChipRepresentable(_ value: Any?) -> Bool {
        guard let value else { return true }
        guard let d = value as? [String: Any] else { return false }
        let mod = (d["modifier"] as? String) ?? ""
        return mod == "INCLUDES"
    }

    static func savedFilterSupportsLiveChipEditor(_ filter: StashDBViewModel.SavedFilter?) -> Bool {
        filterDictSupportsLiveChipEditor(filter?.filterDict)
    }
}

/// Bridges JSON/Foundation dictionaries so GraphQL-decoded `Any` maps reliably to `[String: Any]`.
private func jsonObjectAsStringKeyedDict(_ value: Any?) -> [String: Any]? {
    guard let value else { return nil }
    if let d = value as? [String: Any] { return d }
    if let ns = value as? NSDictionary {
        var out: [String: Any] = [:]
        out.reserveCapacity(ns.count)
        for (k, v) in ns {
            guard let ks = k as? String else { continue }
            out[ks] = v
        }
        return out
    }
    return nil
}

/// Coerce JSON `Any` (e.g. `ui_options.stashy`) to a trimmed non-empty string.
private func jsonValueAsNonEmptyString(_ value: Any?) -> String? {
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
    /// Metadata written by stashy when saving a scene live preset to the server (`ui_options.stashy`).
    struct StashyScenePresetMetadata {
        var baseSavedFilterId: String?
        var liveFragment: [String: Any]
        var sortRaw: String?
    }

    var stashyScenePresetMetadata: StashyScenePresetMetadata? {
        guard let ui = jsonObjectAsStringKeyedDict(ui_options?.value),
              let stashy = jsonObjectAsStringKeyedDict(ui["stashy"]) else { return nil }
        let base = stashy["baseSavedFilterId"] as? String
        let live = jsonObjectAsStringKeyedDict(stashy["liveFragment"]) ?? [:]
        let sortRaw = jsonValueAsNonEmptyString(stashy["sortRaw"])
        return StashyScenePresetMetadata(baseSavedFilterId: base, liveFragment: live, sortRaw: sortRaw)
    }
}

/// Where `ScenesView` loads its primary scene list from (catalog vs. a hard-scoped detail entity).
enum ScenesListScope: Equatable {
    case catalog
    case performer(performerId: String)
    case studio(studioId: String)
    case tag(tagId: String)
    case group(groupId: String)
}

extension ScenesListScope {
    /// `TabManager` detail-sort key; `nil` for the catalog tab.
    fileprivate var detailSortPersistenceKey: String? {
        switch self {
        case .catalog: return nil
        case .performer: return DetailViewContext.performer.rawValue
        case .studio: return DetailViewContext.studio.rawValue
        case .tag: return DetailViewContext.tag.rawValue
        case .group: return DetailViewContext.group.rawValue
        }
    }
}

private struct ScenesViewContent: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @ObservedObject var viewModel: StashDBViewModel
    let scope: ScenesListScope
    let externalLiveFilterSheetBinding: Binding<Bool>?
    let showsFloatingFilterButton: Bool
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getSortOption(for: .scenes) ?? "") ?? .dateDesc
    @State private var isChangingSort = false
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var hasInjectedSort = false  // Flag to preserve coordinator sort
    @State private var internalLiveFilterSheetPresented = false
    @State private var liveFilterMinRating: Int = 0      // 0 = any, 1–5 stars
    @State private var liveFilterOrganized: Bool? = nil  // nil = any
    @State private var liveFilterInteractive: Bool? = nil // nil = any
    @State private var liveFilterOrientation: String? = nil // nil = any, "LANDSCAPE"/"PORTRAIT"/"SQUARE"
    @State private var liveFilterPerformerCount: Int? = nil // nil = any, 1/2/3 (3 = 3+)
    @State private var liveFilterResolution: String? = nil // nil = any, "VERY_LOW"/"LOW"/"R360P"/... (Stash enum)
    @State private var liveFilterPerformerFavorite: Bool? = nil // nil = any
    /// O-counter criterion as "MODIFIER:value" (e.g. GREATER_THAN:0); nil = any
    @State private var liveFilterOCounterTag: String? = nil
    /// Selected studio ids for live `studios` filter; empty = any studio.
    @State private var liveFilterStudioIds: [String] = []
    @State private var studioPickerOptions: [Studio] = []
    @State private var studioPickerLoading = false
    /// Live `tags` `INCLUDES`; tag picker lists only tags with scenes.
    @State private var liveFilterTagIds: [String] = []
    @State private var tagPickerOptions: [Tag] = []
    @State private var tagPickerLoading = false
    /// Live `groups` `INCLUDES`.
    @State private var liveFilterGroupIds: [String] = []
    @State private var groupPickerOptions: [StashGroup] = []
    @State private var groupPickerLoading = false
    @State private var liveFilterPresets: [SceneLiveFilterPreset] = SceneLiveFilterPresetStore.loadPresets()
    /// Selected preset UUID string in the sheet; empty = none.
    @State private var liveSheetPresetSelection: String = ""
    @StateObject private var criteriaDocument = FilterCriteriaDocument(mode: .scenes, pinsDefaults: true)
    @State private var showSaveAsPresetAlert = false
    @State private var showRenamePresetAlert = false
    @State private var showDeletePresetAlert = false
    @State private var presetNameInput = ""
    var hideTitle: Bool = false
    /// Optional content scrolled with the scene grid (e.g. performer detail header — not sticky).
    var scrollHeader: AnyView? = nil
    /// Detail (Performer/Studio/Tag/Group): nur einmal `performSearch` als „leere Liste + gespeicherte Filter fertig“-Fallback — sonst Endlosschleife, wenn `savedFilters` oft neu veröffentlicht wird.
    @State private var didRunEmptyListSavedFilterFallback = false

    private var liveFilterSheetPresented: Binding<Bool> {
        if let ext = externalLiveFilterSheetBinding {
            return ext
        }
        return $internalLiveFilterSheetPresented
    }

    private var primaryScenes: [Scene] {
        switch scope {
        case .catalog: return viewModel.scenes
        case .performer: return viewModel.performerScenes
        case .studio: return viewModel.studioScenes
        case .tag: return viewModel.tagScenes
        case .group: return viewModel.groupScenes
        }
    }

    private var primarySceneListIsEmpty: Bool {
        switch scope {
        case .catalog: return viewModel.scenes.isEmpty
        case .performer: return viewModel.performerScenes.isEmpty
        case .studio: return viewModel.studioScenes.isEmpty
        case .tag: return viewModel.tagScenes.isEmpty
        case .group: return viewModel.groupScenes.isEmpty
        }
    }

    private var isSceneListDetailScope: Bool {
        if case .catalog = scope { return false }
        return true
    }

    private var showsBlockingInitialLoad: Bool {
        switch scope {
        case .catalog:
            return viewModel.scenes.isEmpty && (viewModel.isLoading || viewModel.isLoadingScenes)
        case .performer: return viewModel.isLoadingPerformerScenes && viewModel.performerScenes.isEmpty
        case .studio: return viewModel.isLoadingStudioScenes && viewModel.studioScenes.isEmpty
        case .tag: return viewModel.isLoadingTagScenes && viewModel.tagScenes.isEmpty
        case .group: return viewModel.isLoadingGroupScenes && viewModel.groupScenes.isEmpty
        }
    }

    private var isLoadingMorePrimary: Bool {
        switch scope {
        case .catalog: return viewModel.isLoadingMoreScenes
        case .performer: return viewModel.isLoadingPerformerScenes && !viewModel.performerScenes.isEmpty
        case .studio: return viewModel.isLoadingStudioScenes && !viewModel.studioScenes.isEmpty
        case .tag: return viewModel.isLoadingTagScenes && !viewModel.tagScenes.isEmpty
        case .group: return viewModel.isLoadingGroupScenes && !viewModel.groupScenes.isEmpty
        }
    }

    private var hasMorePrimary: Bool {
        switch scope {
        case .catalog: return viewModel.hasMoreScenes
        case .performer: return viewModel.hasMorePerformerScenes
        case .studio: return viewModel.hasMoreStudioScenes
        case .tag: return viewModel.hasMoreTagScenes
        case .group: return viewModel.hasMoreGroupScenes
        }
    }

    private func loadMorePrimary() {
        switch scope {
        case .catalog:
            viewModel.loadMoreScenes()
        case .performer(let performerId):
            viewModel.loadMorePerformerScenes(performerId: performerId)
        case .studio(let studioId):
            viewModel.loadMoreStudioScenes(studioId: studioId)
        case .tag(let tagId):
            viewModel.loadMoreTagScenes(tagId: tagId)
        case .group(let groupId):
            viewModel.loadMoreGroupScenes(groupId: groupId)
        }
    }

    private func persistSceneSort(_ option: StashDBViewModel.SceneSortOption) {
        switch scope {
        case .catalog:
            TabManager.shared.setSortOption(for: .scenes, option: option.rawValue)
        case .group:
            TabManager.shared.setPersistentDetailSortOption(for: DetailViewContext.group.rawValue, option: option.rawValue)
        case .performer, .studio, .tag:
            if let key = scope.detailSortPersistenceKey {
                TabManager.shared.setDetailSortOption(for: key, option: option.rawValue)
            }
        }
    }

    private func refreshLivePresets() {
        liveFilterPresets = SceneLiveFilterPresetStore.loadPresets()
    }

    private var isLiveFilterActive: Bool { false }

    /// Chips, saved scene filter, or a preset row in the sheet — drives FAB tint/dot now that toolbar filter/sort are gone.
    private var liveFilterFABHasSomethingSet: Bool {
        selectedFilter != nil || !liveSheetPresetSelection.isEmpty
    }

    /// Same resolution as Settings › Default Sorting for Scenes, then session sort, when a filter has no valid embedded sort.
    private var scenesTabDefaultSortOption: StashDBViewModel.SceneSortOption {
        switch scope {
        case .catalog:
            return TabManager.shared.resolvedScenesSortFallbackFromTabConfig()
        case .performer, .studio, .tag, .group:
            guard let key = scope.detailSortPersistenceKey else { return .dateDesc }
            return TabManager.shared.resolvedDetailSceneSortFallback(for: key)
        }
    }

    private var activeLiveFilterDict: [String: Any] { [:] }
    
    /// Passed to `filter:` only while the advanced editor holds no copy of it (see below).
    private var fetchBaseFilter: StashDBViewModel.SavedFilter? {
        criteriaDocument.isEmpty ? selectedFilter : nil
    }

    /// Quick chips merged with the advanced criteria editor; advanced criteria win per key.
    ///
    /// A selected saved filter is loaded into `criteriaDocument`, so fetches pass `filter: nil` —
    /// otherwise the server filter would re-apply criteria the user just edited away.
    private var effectiveSceneLiveFilterForFetch: [String: Any] {
        var dict = criteriaDocument.sanitizedObjectFilter
        for (key, value) in activeLiveFilterDict {
            dict[key] = value
        }
        if !liveFilterStudioIds.isEmpty {
            dict["studios"] = ["modifier": "INCLUDES", "value": liveFilterStudioIds, "depth": 0]
        }
        if !liveFilterTagIds.isEmpty {
            dict["tags"] = ["modifier": "INCLUDES", "value": liveFilterTagIds, "depth": 0]
        }
        if !liveFilterGroupIds.isEmpty {
            dict["groups"] = ["modifier": "INCLUDES", "value": liveFilterGroupIds, "depth": 0]
        }
        if liveFilterMinRating == -1 {
            dict["rating100"] = ["modifier": "IS_NULL"]
        } else if liveFilterMinRating > 0, dict["rating100"] == nil {
            dict["rating100"] = ["value": (liveFilterMinRating * 20), "modifier": "EQUALS"]
        }
        return dict
    }

    /// Reads `INCLUDES` ids each for `studios`, `tags`, `groups` (after clearing other live chips).
    private func applyLiveAuxIdsFromFragment(_ frag: [String: Any]) {
        let f = FilterMapper.sanitize(frag, isMarker: false)
        liveFilterStudioIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["studios"])
        liveFilterTagIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["tags"])
        liveFilterGroupIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["groups"])
    }

    /// Does not change sort: syncs chip state to `selectedFilter` / stashy metadata (e.g. deep link).
    private func syncLiveChipsToMatchSelectedFilter() {
        guard let f = selectedFilter else { return }
        if let meta = f.stashyScenePresetMetadata {
            let base: StashDBViewModel.SavedFilter?
            if let bid = meta.baseSavedFilterId, let b = viewModel.savedFilters[bid] {
                base = b
            } else {
                base = nil
            }
            if SceneLiveChipFilterSupport.savedFilterSupportsLiveChipEditor(base) {
                mapLiveFragmentToChips(meta.liveFragment)
            } else {
                clearLiveFilterChipsOnly()
                applyLiveAuxIdsFromFragment(meta.liveFragment)
            }
        } else if SceneLiveChipFilterSupport.savedFilterSupportsLiveChipEditor(f) {
            if let raw = f.filterDict {
                mapLiveFragmentToChips(raw)
                } else {
                clearLiveFilterChipsOnly()
            }
                } else {
            clearLiveFilterChipsOnly()
            let flat: [String: Any]? = {
                if let raw = f.filterDict { return FilterMapper.sanitize(raw, isMarker: false) }
                if let obj = f.object_filter, let objDict = obj.value as? [String: Any] {
                    return FilterMapper.sanitize(objDict, isMarker: false)
                }
                return nil
            }()
            if let flat {
                applyLiveAuxIdsFromFragment(flat)
            }
        }
    }

    private func mapLiveFragmentToChips(_ frag: [String: Any]) {}

    private func boolFromLiveJSON(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let d = value as? [String: Any], let inner = d["value"] { return boolFromLiveJSON(inner) }
        if let s = value as? String {
            let lower = s.lowercased()
            if ["true", "1", "yes"].contains(lower) { return true }
            if ["false", "0", "no"].contains(lower) { return false }
        }
        return nil
    }

    private func intFromLiveJSON(_ value: Any) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private func applyLiveFilterPreset(_ preset: SceneLiveFilterPreset) {
        let sort = StashDBViewModel.SceneSortOption(rawValue: preset.sortRaw) ?? scenesTabDefaultSortOption
        if sort != selectedSortOption {
            selectedSortOption = sort
            persistSceneSort(sort)
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
            var merged = f.criteriaObjectFilter()
            for (k, v) in FilterMapper.sanitize(preset.liveFragment, isMarker: false) {
                merged[k] = v
            }
            criteriaDocument.load(merged)
        } else {
            selectedFilter = nil
            criteriaDocument.load(preset.liveFragment)
        }
        mapLiveFragmentToChips(preset.liveFragment)
        applyLiveFilter()
    }

    private func clearLiveFilterChipsOnly() {
        liveFilterMinRating = 0
        liveFilterOrganized = nil
        liveFilterInteractive = nil
        liveFilterOrientation = nil
        liveFilterPerformerCount = nil
        liveFilterResolution = nil
        liveFilterPerformerFavorite = nil
        liveFilterOCounterTag = nil
        liveFilterStudioIds = []
        liveFilterTagIds = []
        liveFilterGroupIds = []
    }

    private func loadStudiosForSceneLivePicker() {
        guard !studioPickerLoading else { return }
        studioPickerLoading = true
        viewModel.fetchStudiosForLiveFilterPicker(mode: .scenesHasScenes) { list in
            studioPickerOptions = list
            studioPickerLoading = false
        }
    }

    private func loadTagsForSceneLivePicker() {
        guard !tagPickerLoading else { return }
        tagPickerLoading = true
        viewModel.fetchTagsForSceneLiveFilterPicker { list in
            tagPickerOptions = list
            tagPickerLoading = false
        }
    }

    private func loadGroupsForSceneLivePicker() {
        guard !groupPickerLoading else { return }
        groupPickerLoading = true
        viewModel.fetchGroupsForSceneLiveFilterPicker { list in
            groupPickerOptions = list
            groupPickerLoading = false
        }
    }

    private func applyServerSceneSavedFilter(_ f: StashDBViewModel.SavedFilter) {
        selectedFilter = f
        if let meta = f.stashyScenePresetMetadata {
            var merged: [String: Any]
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                merged = base.criteriaObjectFilter()
                for (k, v) in FilterMapper.sanitize(meta.liveFragment, isMarker: false) {
                    merged[k] = v
                }
            } else if !meta.liveFragment.isEmpty {
                merged = FilterMapper.sanitize(meta.liveFragment, isMarker: false)
            } else {
                merged = f.criteriaObjectFilter()
            }
            criteriaDocument.load(merged)
            mapLiveFragmentToChips(meta.liveFragment)
            let resolvedSort: StashDBViewModel.SceneSortOption
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.SceneSortOption(rawValue: sr) {
                resolvedSort = parsed
            } else {
                resolvedSort = scenesTabDefaultSortOption
            }
            if resolvedSort != selectedSortOption {
                selectedSortOption = resolvedSort
                persistSceneSort(resolvedSort)
            }
        } else {
            criteriaDocument.load(f.criteriaObjectFilter())
            if let raw = f.filterDict {
                mapLiveFragmentToChips(raw)
            } else {
                clearLiveFilterChipsOnly()
            }
        }
        applyLiveFilter()
    }

    /// Re-applies the current preset row selection to chip state (and fetch). Used when the sheet opens so `onChange` is not skipped for an unchanged selection.
    private func applyLiveFilterPresetFromSelectionIfNeeded() {
        let newId = liveSheetPresetSelection
        guard !newId.isEmpty else { return }
        if let sid = SceneLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSceneSavedFilter(f)
            return
        }
        if let ls = SceneLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = liveFilterPresets.first(where: { $0.id == uuid }) {
            applyLiveFilterPreset(preset)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = liveFilterPresets.first(where: { $0.id == uuid }) {
            liveSheetPresetSelection = SceneLivePresetTag.localRow(uuid)
            applyLiveFilterPreset(preset)
        }
    }

    private var sortedServerSceneFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .scenes }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var deletePresetConfirmationText: String {
        if let sid = SceneLivePresetTag.parseServerId(liveSheetPresetSelection),
           let f = viewModel.savedFilters[sid] {
            return "Remove “\(f.name)” from Stash? Other devices will lose this saved filter."
        }
        if let ls = SceneLivePresetTag.parseLocalUUIDString(liveSheetPresetSelection),
           let uuid = UUID(uuidString: ls),
           let p = liveFilterPresets.first(where: { $0.id == uuid }) {
            return "Remove “\(p.name)” from this device? This cannot be undone."
        }
        return "Remove this filter? This cannot be undone."
    }

    private func saveLivePresetOverwrite() {
        let sel = liveSheetPresetSelection
        if let sid = SceneLivePresetTag.parseServerId(sel) {
            let currentName = viewModel.savedFilters[sid]?.name ?? "Filter"
            viewModel.saveFullObjectFilter(
                mode: .scenes,
                existingId: sid,
                name: currentName,
                sortField: selectedSortOption.sortField == "random" ? "random" : selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                sortRaw: selectedSortOption.rawValue,
                objectFilter: criteriaDocument.sanitizedObjectFilter,
                randomSeedKind: .scenes
            ) { _ in }
            return
        }
        guard let ls = SceneLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let index = liveFilterPresets.firstIndex(where: { $0.id == uuid }) else { return }
        let old = liveFilterPresets[index]
        let updated = SceneLiveFilterPreset(
            id: old.id,
            name: old.name,
            createdAt: old.createdAt,
            sort: selectedSortOption,
            baseSavedFilterId: selectedFilter?.id,
            liveFragment: criteriaDocument.sanitizedObjectFilter
        )
        SceneLiveFilterPresetStore.upsert(updated)
        refreshLivePresets()
    }

    private func saveLivePresetAs(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveFullObjectFilter(
            mode: .scenes,
            existingId: nil,
            name: trimmed,
            sortField: selectedSortOption.sortField == "random" ? "random" : selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            sortRaw: selectedSortOption.rawValue,
            objectFilter: criteriaDocument.sanitizedObjectFilter,
            randomSeedKind: .scenes
        ) { result in
            if case .success(let saved) = result {
                liveSheetPresetSelection = SceneLivePresetTag.serverRow(saved.id)
                selectedFilter = saved
                showSaveAsPresetAlert = false
            }
        }
    }

    private func renameLivePreset(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sel = liveSheetPresetSelection
        if let sid = SceneLivePresetTag.parseServerId(sel) {
            viewModel.saveFullObjectFilter(
                mode: .scenes,
                existingId: sid,
                name: trimmed,
                sortField: selectedSortOption.sortField == "random" ? "random" : selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                sortRaw: selectedSortOption.rawValue,
                objectFilter: criteriaDocument.sanitizedObjectFilter,
                randomSeedKind: .scenes
            ) { result in
                if case .success = result {
                    showRenamePresetAlert = false
                }
            }
            return
        }
        guard let ls = SceneLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = liveFilterPresets.first(where: { $0.id == uuid }) else { return }
        let renamed = preset.renamed(trimmed)
        SceneLiveFilterPresetStore.upsert(renamed)
        refreshLivePresets()
        showRenamePresetAlert = false
    }

    private func deleteLivePreset() {
        let sel = liveSheetPresetSelection
        if let sid = SceneLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { result in
                if case .success = result {
                    if selectedFilter?.id == sid {
                        selectedFilter = nil
                    }
                    liveSheetPresetSelection = ""
                    showDeletePresetAlert = false
                    applyLiveFilter()
                }
            }
            return
        }
        guard let ls = SceneLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        SceneLiveFilterPresetStore.remove(id: uuid)
        refreshLivePresets()
        liveSheetPresetSelection = ""
        showDeletePresetAlert = false
    }
    
    init(
        viewModel: StashDBViewModel,
        sort: StashDBViewModel.SceneSortOption? = nil,
        filter: StashDBViewModel.SavedFilter? = nil,
        hideTitle: Bool = false,
        scope: ScenesListScope = .catalog,
        externalLiveFilterSheetBinding: Binding<Bool>? = nil,
        showsFloatingFilterButton: Bool = true,
        scrollHeader: AnyView? = nil
    ) {
        self.viewModel = viewModel
        self.scope = scope
        self.externalLiveFilterSheetBinding = externalLiveFilterSheetBinding
        self.showsFloatingFilterButton = showsFloatingFilterButton
        self.hideTitle = hideTitle
        self.scrollHeader = scrollHeader
        let defaultSort: StashDBViewModel.SceneSortOption = {
            if let sort { return sort }
            switch scope {
            case .catalog:
                return StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getSortOption(for: .scenes) ?? "") ?? .dateDesc
            case .performer, .studio, .tag, .group:
                guard let key = scope.detailSortPersistenceKey else { return .dateDesc }
                return StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getDetailSortOption(for: key) ?? "")
                    ?? TabManager.shared.resolvedDetailSceneSortFallback(for: key)
            }
        }()
        _selectedSortOption = State(initialValue: sort ?? defaultSort)
        _selectedFilter = State(initialValue: filter)
        _hasInjectedSort = State(initialValue: sort != nil)
    }


    @ObservedObject private var tabManager = TabManager.shared

    @State private var cardGridWidth: CGFloat = 0


    private var columns: [GridItem] {
        tabManager.catalogCardColumns(for: CatalogCardColumnScope.scenes).gridItems(width: cardGridWidth)
    }

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.SceneSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        persistSceneSort(newOption)

        switch scope {
        case .catalog:
            viewModel.fetchScenes(sortBy: newOption, searchQuery: searchText, filter: fetchBaseFilter, liveFilter: effectiveSceneLiveFilterForFetch)
        case .performer(let performerId):
            viewModel.fetchPerformerScenes(
                performerId: performerId,
                sortBy: newOption,
                isInitialLoad: true,
                filter: fetchBaseFilter,
                liveFilter: effectiveSceneLiveFilterForFetch,
                searchQuery: searchText
            )
        case .studio(let studioId):
            viewModel.fetchStudioScenes(
                studioId: studioId,
                sortBy: newOption,
                isInitialLoad: true,
                filter: fetchBaseFilter,
                liveFilter: effectiveSceneLiveFilterForFetch,
                searchQuery: searchText
            )
        case .tag(let tagId):
            viewModel.fetchTagScenes(
                tagId: tagId,
                sortBy: newOption,
                isInitialLoad: true,
                filter: fetchBaseFilter,
                liveFilter: effectiveSceneLiveFilterForFetch,
                searchQuery: searchText
            )
        case .group(let groupId):
            viewModel.fetchGroupScenes(
                groupId: groupId,
                sortBy: newOption,
                isInitialLoad: true,
                filter: fetchBaseFilter,
                liveFilter: effectiveSceneLiveFilterForFetch,
                searchQuery: searchText
            )
        }
    }
    
    // Search function with debouncing
    private func performSearch() {
        switch scope {
        case .catalog:
            viewModel.fetchScenes(sortBy: selectedSortOption, searchQuery: searchText, filter: fetchBaseFilter, liveFilter: effectiveSceneLiveFilterForFetch)
        case .performer(let performerId):
            viewModel.fetchPerformerScenes(
                performerId: performerId,
                sortBy: selectedSortOption,
                isInitialLoad: true,
                filter: fetchBaseFilter,
                liveFilter: effectiveSceneLiveFilterForFetch,
                searchQuery: searchText
            )
        case .studio(let studioId):
            viewModel.fetchStudioScenes(
                studioId: studioId,
                sortBy: selectedSortOption,
                isInitialLoad: true,
                filter: fetchBaseFilter,
                liveFilter: effectiveSceneLiveFilterForFetch,
                searchQuery: searchText
            )
        case .tag(let tagId):
            viewModel.fetchTagScenes(
                tagId: tagId,
                sortBy: selectedSortOption,
                isInitialLoad: true,
                filter: fetchBaseFilter,
                liveFilter: effectiveSceneLiveFilterForFetch,
                searchQuery: searchText
            )
        case .group(let groupId):
            viewModel.fetchGroupScenes(
                groupId: groupId,
                sortBy: selectedSortOption,
                isInitialLoad: true,
                filter: fetchBaseFilter,
                liveFilter: effectiveSceneLiveFilterForFetch,
                searchQuery: searchText
            )
        }
    }

    private func applyLiveFilter() {
        persistSceneSort(selectedSortOption)
        // Full criteria live in `criteriaDocument` — do not also pass `selectedFilter` or base criteria double-apply.
        switch scope {
        case .catalog:
            viewModel.currentSceneLiveFilter = effectiveSceneLiveFilterForFetch
            viewModel.fetchScenes(sortBy: selectedSortOption, searchQuery: searchText, filter: fetchBaseFilter, liveFilter: effectiveSceneLiveFilterForFetch)
        case .performer(let performerId):
            viewModel.fetchPerformerScenes(
                performerId: performerId,
                sortBy: selectedSortOption,
                isInitialLoad: true,
                filter: fetchBaseFilter,
                liveFilter: effectiveSceneLiveFilterForFetch,
                searchQuery: searchText
            )
        case .studio(let studioId):
            viewModel.fetchStudioScenes(
                studioId: studioId,
                sortBy: selectedSortOption,
                isInitialLoad: true,
                filter: fetchBaseFilter,
                liveFilter: effectiveSceneLiveFilterForFetch,
                searchQuery: searchText
            )
        case .tag(let tagId):
            viewModel.fetchTagScenes(
                tagId: tagId,
                sortBy: selectedSortOption,
                isInitialLoad: true,
                filter: fetchBaseFilter,
                liveFilter: effectiveSceneLiveFilterForFetch,
                searchQuery: searchText
            )
        case .group(let groupId):
            viewModel.fetchGroupScenes(
                groupId: groupId,
                sortBy: selectedSortOption,
                isInitialLoad: true,
                filter: fetchBaseFilter,
                liveFilter: effectiveSceneLiveFilterForFetch,
                searchQuery: searchText
            )
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Content
            Group {
                if configManager.activeConfig == nil {
                    ConnectionErrorView { performSearch() }
                } else if showsBlockingInitialLoad {
                    StandardLoadingView(message: "Loading scenes...")
                } else if primarySceneListIsEmpty && viewModel.errorMessage != nil {
                    ConnectionErrorView(title: viewModel.errorMessage ?? "Server not reachable") { performSearch() }
                } else if primarySceneListIsEmpty {
                    scenesEmptyContent
                } else {
                    scenesGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        .applyAppBackground()
        .modifier(ScenesEmbeddedNavigationChrome(hideTitle: hideTitle, searchText: $searchText, onClearSearch: performSearch))
        .onChange(of: searchText) { oldValue, newValue in
            // Debounce: Nur suchen wenn Nutzer aufhört zu tippen (0.5s Delay)
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if newValue == self.searchText {
                    self.performSearch()
                }
            }
        }
        .floatingActionBar(
            isPresented: showsFloatingFilterButton,
            catalogChrome: CatalogFloatingChromeState(hasActiveServerConfig: configManager.activeConfig != nil, primaryListIsEmpty: primarySceneListIsEmpty, errorMessage: viewModel.errorMessage)
        ) {
            HStack(spacing: 0) {
                let cardColumns = tabManager.catalogCardColumns(for: CatalogCardColumnScope.scenes)
                CatalogFABIconButton(
                    systemImage: cardColumns.toggleIcon,
                    accessibilityLabel: cardColumns.accessibilityLabel,
                    accessibilityHint: "Switches between one and two cards per row"
                ) {
                    withAnimation(DesignTokens.Animation.quick) {
                        tabManager.toggleCatalogCardColumns(for: CatalogCardColumnScope.scenes)
                    }
                }
                .frame(maxWidth: .infinity)

                CatalogFilterFABButton(isActive: liveFilterFABHasSomethingSet) {
                    liveFilterSheetPresented.wrappedValue = true
                }
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: liveFilterSheetPresented) {
            SceneLiveFilterSheet(
                serverSceneFilters: sortedServerSceneFilters,
                localPresets: liveFilterPresets,
                selectedPresetId: $liveSheetPresetSelection,
                criteriaDocument: criteriaDocument,
                sortOption: selectedSortOption,
                onSortChange: { changeSortOption(to: $0) },
                onApply: { applyLiveFilter() },
                onReset: {
                    criteriaDocument.clear()
                    liveFilterMinRating = 0
                    liveFilterOrganized = nil
                    liveFilterInteractive = nil
                    liveFilterOrientation = nil
                    liveFilterPerformerCount = nil
                    liveFilterResolution = nil
                    liveFilterPerformerFavorite = nil
                    liveFilterOCounterTag = nil
                    liveFilterStudioIds = []
                    liveFilterTagIds = []
                    liveFilterGroupIds = []
                    liveSheetPresetSelection = ""
                    selectedFilter = nil
                    applyLiveFilter()
                },
                onRequestSave: { saveLivePresetOverwrite() },
                onRequestSaveAs: {
                    presetNameInput = ""
                    showSaveAsPresetAlert = true
                },
                onRequestRename: {
                    if let sid = SceneLivePresetTag.parseServerId(liveSheetPresetSelection),
                       let f = viewModel.savedFilters[sid] {
                        presetNameInput = f.name
                        showRenamePresetAlert = true
                    } else if let ls = SceneLivePresetTag.parseLocalUUIDString(liveSheetPresetSelection),
                              let uuid = UUID(uuidString: ls),
                              let p = liveFilterPresets.first(where: { $0.id == uuid }) {
                        presetNameInput = p.name
                        showRenamePresetAlert = true
                    }
                },
                onRequestDelete: { showDeletePresetAlert = true },
                useMarkerSort: false,
                markerSortOption: .constant(StashDBViewModel.SceneMarkerSortOption.createdAtDesc),
                onMarkerSortChange: { _ in }
            )
            .environmentObject(viewModel)
            .onAppear {
                SceneLivePresetTag.migrateLegacySelection(&liveSheetPresetSelection)
                refreshLivePresets()
                applyLiveFilterPresetFromSelectionIfNeeded()
                viewModel.fetchSavedFilters { _ in
                    applyLiveFilterPresetFromSelectionIfNeeded()
                }
            }
            .onChange(of: liveSheetPresetSelection) { _, newId in
                guard liveFilterSheetPresented.wrappedValue else { return }
                if newId.isEmpty {
                    selectedFilter = nil
                    clearLiveFilterChipsOnly()
                    applyLiveFilter()
                    return
                }
                if let sid = SceneLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
                    applyServerSceneSavedFilter(f)
                    return
                }
                if let ls = SceneLivePresetTag.parseLocalUUIDString(newId),
                   let uuid = UUID(uuidString: ls),
                   let preset = liveFilterPresets.first(where: { $0.id == uuid }) {
                    applyLiveFilterPreset(preset)
                    return
                }
                if let uuid = UUID(uuidString: newId),
                   let preset = liveFilterPresets.first(where: { $0.id == uuid }) {
                    liveSheetPresetSelection = SceneLivePresetTag.localRow(uuid)
                    applyLiveFilterPreset(preset)
                }
            }
        }
        .alert("Save As", isPresented: $showSaveAsPresetAlert) {
            TextField("Name", text: $presetNameInput)
            Button("Save") { saveLivePresetAs(name: presetNameInput) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Creates a new saved scene filter on your Stash server (visible in Stash and other clients).")
        }
        .alert("Rename Filter", isPresented: $showRenamePresetAlert) {
            TextField("Name", text: $presetNameInput)
            Button("Rename") { renameLivePreset(to: presetNameInput) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Renames the selected Stash saved filter or on-device filter.")
        }
        .alert("Delete Filter", isPresented: $showDeletePresetAlert) {
            Button("Delete", role: .destructive) { deleteLivePreset() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(deletePresetConfirmationText)
        }
        .onAppear {
            // Check for injected sort from coordinator FIRST (before filters load)
            if let injectedSortStr = coordinator.activeSortOption,
               let injectedSort = StashDBViewModel.SceneSortOption(rawValue: injectedSortStr) {
                selectedSortOption = injectedSort
                coordinator.activeSortOption = nil
                hasInjectedSort = true  // Mark that we have an injected sort
            }
            
            if let injectedFilter = coordinator.activeFilter {
                selectedFilter = injectedFilter
                coordinator.activeFilter = nil
                syncLiveChipsToMatchSelectedFilter()
            }
            
            if !coordinator.activeSearchText.isEmpty {
                searchText = coordinator.activeSearchText
                isSearchVisible = true
                coordinator.activeSearchText = ""
            }
            
            // Fetch filters - onChange will handle loading scenes with correct sort
            viewModel.fetchSavedFilters()
            refreshLivePresets()
            
            // If no default filter is set, fetch immediately ONLY if we don't have scenes yet.
            // Detail scopes never take the Settings default, so they must not wait for it either.
            if isSceneListDetailScope || TabManager.shared.getDefaultFilterId(for: .scenes) == nil {
                if primarySceneListIsEmpty {
                    performSearch()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            liveSheetPresetSelection = ""
            refreshLivePresets()
            performSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            // Catalog only: on a performer / studio / tag / group page the list is already scoped,
            // and layering the Settings default on top silently hides scenes (e.g. `organized`).
            if scope == .catalog,
               let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.scenes.rawValue {
                // Determine new filter
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .scenes),
                   let newFilter = viewModel.savedFilters[defaultId] {
                    selectedFilter = newFilter
                    syncLiveChipsToMatchSelectedFilter()
                } else {
                    selectedFilter = nil
                }
                performSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
            if scope == .catalog,
               let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.scenes.rawValue {
                let newSort = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getPersistentSortOption(for: .scenes) ?? "") ?? .dateDesc
                changeSortOption(to: newSort)
            }
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // CRITICAL: Check coordinator FIRST - filters may load before onAppear runs!
            if let injectedSortStr = coordinator.activeSortOption,
               let injectedSort = StashDBViewModel.SceneSortOption(rawValue: injectedSortStr) {
                selectedSortOption = injectedSort
                coordinator.activeSortOption = nil
                hasInjectedSort = true
            }
            
            // Check if we should skip default filter (e.g., from universal search)
            if coordinator.noDefaultFilter {
                coordinator.noDefaultFilter = false
                performSearch()
                return
            }
            
            // Apply default filter if set and none selected yet
            // Uses selectedSortOption which may have just been set from coordinator above
            if selectedFilter == nil {
                // `scope == .catalog` mirrors `ImagesView`'s `guard gallery == nil`: the Settings
                // default filter belongs to the catalog list, not to a scoped detail list.
                if scope == .catalog,
                   let defaultId = TabManager.shared.getDefaultFilterId(for: .scenes),
                   let filter = newValue[defaultId] {
                    selectedFilter = filter
                    syncLiveChipsToMatchSelectedFilter()
                    // Only fetch if we don't have scenes yet (e.g., initial app load)
                    if primarySceneListIsEmpty {
                        performSearch()
                    }
                    // Reset flag after using injected sort with default filter
                    if hasInjectedSort {
                        hasInjectedSort = false
                    }
                } else if !viewModel.isLoadingSavedFilters {
                    // Default filter was set but NO filters were found on server, or filters finished loading and defaultId is missing
                    // Trigger fetch without filter to avoid being stuck in loading state (only if empty)
                    if primarySceneListIsEmpty {
                        if isSceneListDetailScope {
                            if !didRunEmptyListSavedFilterFallback {
                                didRunEmptyListSavedFilterFallback = true
                                performSearch()
                            }
                        } else {
                            performSearch()
                        }
                    }
                }
            }
        }

        .sceneLiveUpdates(using: viewModel)
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
            // Fallback: If filters finished loading, we have no active filter, and no scenes yet, trigger fetch
            if oldValue == true && isLoading == false {
                let loadingPrimary: Bool
                switch scope {
                case .catalog: loadingPrimary = viewModel.isLoadingScenes
                case .performer: loadingPrimary = viewModel.isLoadingPerformerScenes
                case .studio: loadingPrimary = viewModel.isLoadingStudioScenes
                case .tag: loadingPrimary = viewModel.isLoadingTagScenes
                case .group: loadingPrimary = viewModel.isLoadingGroupScenes
                }
                if primarySceneListIsEmpty && !loadingPrimary && selectedFilter == nil {
                    if isSceneListDetailScope {
                        guard !didRunEmptyListSavedFilterFallback else { return }
                        didRunEmptyListSavedFilterFallback = true
                    }
                    AppLog.debug("🔄 Fallback: Filters loaded (empty), triggering initial scene fetch")
                    performSearch()
                }
            }
        }
        .onChange(of: scope) { _, _ in
            didRunEmptyListSavedFilterFallback = false
        }
    }

    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: "film",
            title: "No scenes found",
            buttonText: "Load Scenes",
            onRetry: { performSearch() }
        )
    }

    @ViewBuilder
    private var scenesEmptyContent: some View {
        if let scrollHeader {
            ScrollView {
                VStack(spacing: 12) {
                    scrollHeader
                    emptyStateView
                }
                // Match PerformerDetail non-scene tabs (`.padding(16)`).
                .padding(.top, 16)
            }
            .background(Color.appBackground)
            .refreshable { performSearch() }
        } else {
            emptyStateView
        }
    }

    private var scenesGrid: some View {
            ScrollView {
                let cardColumns = tabManager.catalogCardColumns(for: CatalogCardColumnScope.scenes)
                VStack(spacing: 12) {
                    if let scrollHeader {
                        scrollHeader
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(primaryScenes) { scene in
                            NavigationLink(destination: SceneDetailView(scene: scene)) {
                                SceneCardView(
                                    scene: scene,
                                    aspectRatio: cardColumns.cardAspectRatio
                                )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(scene.id)
                        }

                        // Loading indicator for pagination
                    if isLoadingMorePrimary {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                    } else if hasMorePrimary && !primaryScenes.isEmpty {
                            // Invisible element to trigger loading more scenes
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                loadMorePrimary()
                            }
                        }
                    }
                    .measuresGridWidth($cardGridWidth)
                    // Force cell rebuild — LazyVGrid otherwise keeps stale square/16:9 sizes.
                    .id(cardColumns)
                    .padding(.horizontal, 16)
                    .padding(.top, scrollHeader == nil ? 16 : 0)
                }
                // Match PerformerDetail non-scene tabs (`.padding(16)`).
                .padding(.top, scrollHeader != nil ? 16 : 0)
            }
            .background(Color.appBackground)
            .refreshable { performSearch() }
    }
}

/// Scene list with shared filter/sort UI. On detail screens pass ``sharedViewModel`` and a scoped case (``ScenesListScope/performer(performerId:)``, ``ScenesListScope/studio(studioId:)``, etc.) so list state stays on the parent `StashDBViewModel`.
struct ScenesView: View {
    @StateObject private var ownedViewModel = StashDBViewModel()
    var sharedViewModel: StashDBViewModel?
    let sort: StashDBViewModel.SceneSortOption?
    let filter: StashDBViewModel.SavedFilter?
    let hideTitle: Bool
    let scope: ScenesListScope
    let externalLiveFilterSheetBinding: Binding<Bool>?
    let showsFloatingFilterButton: Bool
    let scrollHeader: AnyView?

    init(
        sort: StashDBViewModel.SceneSortOption? = nil,
        filter: StashDBViewModel.SavedFilter? = nil,
        hideTitle: Bool = false,
        scope: ScenesListScope = .catalog,
        sharedViewModel: StashDBViewModel? = nil,
        externalLiveFilterSheetBinding: Binding<Bool>? = nil,
        showsFloatingFilterButton: Bool? = nil,
        scrollHeader: AnyView? = nil
    ) {
        self.sort = sort
        self.filter = filter
        self.hideTitle = hideTitle
        self.scope = scope
        self.sharedViewModel = sharedViewModel
        self.externalLiveFilterSheetBinding = externalLiveFilterSheetBinding
        self.showsFloatingFilterButton = showsFloatingFilterButton ?? (externalLiveFilterSheetBinding == nil)
        self.scrollHeader = scrollHeader
    }

    var body: some View {
        ScenesViewContent(
            viewModel: effectiveViewModel,
            sort: sort,
            filter: filter,
            hideTitle: hideTitle,
            scope: scope,
            externalLiveFilterSheetBinding: externalLiveFilterSheetBinding,
            showsFloatingFilterButton: showsFloatingFilterButton,
            scrollHeader: scrollHeader
        )
    }

    private var effectiveViewModel: StashDBViewModel {
        sharedViewModel ?? ownedViewModel
    }

    /// Katalog-Tab unter ``CatalogsView``: ein über Tab-Wechsel hinweg bleibendes ViewModel.
    static func catalogTab(viewModel: StashDBViewModel) -> some View {
        ScenesViewContent(
            viewModel: viewModel,
            sort: nil,
            filter: nil,
            hideTitle: false,
            scope: .catalog,
            externalLiveFilterSheetBinding: nil,
            showsFloatingFilterButton: true
        )
    }
}

/// When embedded in Performer/Studio/Tag/Group detail (`hideTitle`), do not re-enable the system
/// nav bar — child `.toolbar` / `.navigationTitle` would otherwise override the parent's custom chrome
/// (especially when pushed from Search).
private struct ScenesEmbeddedNavigationChrome: ViewModifier {
    let hideTitle: Bool
    @Binding var searchText: String
    var onClearSearch: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if hideTitle {
            content.hideSystemNavigationBarForCustomChrome()
        } else {
            content
                .navigationTitle("Scenes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !searchText.isEmpty {
                        ToolbarItem(placement: .principal) {
                            Button {
                                searchText = ""
                                onClearSearch()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                    Text(searchText)
                                        .font(.system(size: 12, weight: .bold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
        }
    }
}

// Card-based view for grid layout
#Preview {
    ScenesView()
}

// MARK: - Scene live filter presets (local)

struct SceneLiveFilterPreset: Codable, Identifiable, Equatable {
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
        sort: StashDBViewModel.SceneSortOption,
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

    var sort: StashDBViewModel.SceneSortOption {
        if let o = StashDBViewModel.SceneSortOption(rawValue: sortRaw) {
            return o
        }
        return TabManager.shared.resolvedScenesSortFallbackFromTabConfig()
    }

    var liveFragment: [String: Any] {
        guard let data = liveFragmentJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func renamed(_ newName: String) -> SceneLiveFilterPreset {
        SceneLiveFilterPreset(
            id: id,
            name: newName,
            createdAt: createdAt,
            sort: sort,
            baseSavedFilterId: baseSavedFilterId,
            liveFragment: liveFragment
        )
    }
}

enum SceneLiveFilterPresetStore {
    private static func storageKey(serverId: UUID) -> String {
        "stashy_scene_live_filter_presets_\(serverId.uuidString)"
    }

    static func loadPresets() -> [SceneLiveFilterPreset] {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return [] }
        let key = storageKey(serverId: serverId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SceneLiveFilterPreset].self, from: data)) ?? []
    }

    private static func saveAll(_ presets: [SceneLiveFilterPreset]) {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return }
        let key = storageKey(serverId: serverId)
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(_ preset: SceneLiveFilterPreset) {
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

// MARK: - Settings sheet (filter / sort)

struct SceneLiveFilterSheet: View {
    /// Same width as `filterRow` labels so sort chips line up with filter chips.
    private static let labelColumnWidth: CGFloat = 80

    var serverSceneFilters: [StashDBViewModel.SavedFilter]
    var localPresets: [SceneLiveFilterPreset]
    /// When ``useMarkerSort`` is true, local on-device presets come from the markers store instead of ``localPresets``.
    var markerLocalPresets: [MarkerLiveFilterPreset] = []
    @Binding var selectedPresetId: String
    @ObservedObject var criteriaDocument: FilterCriteriaDocument
    var sortOption: StashDBViewModel.SceneSortOption
    var onSortChange: (StashDBViewModel.SceneSortOption) -> Void
    var onApply: () -> Void
    var onReset: () -> Void
    var onRequestSave: () -> Void
    var onRequestSaveAs: () -> Void
    var onRequestRename: () -> Void
    var onRequestDelete: () -> Void
    /// When `true`, shows Immersive Scaling / Continuous Play (Feeds only).
    var showsFeedsPlaybackSettings: Bool = false
    /// When `false`, hides the scene sort card (e.g. when ``useMarkerSort`` shows marker sort instead).
    var showsSortControls: Bool = true
    /// When `true`, shows marker sort (Asc/Desc + field); scene sort bindings are ignored for the sort card.
    var useMarkerSort: Bool = false
    @Binding var markerSortOption: StashDBViewModel.SceneMarkerSortOption
    var onMarkerSortChange: (StashDBViewModel.SceneMarkerSortOption) -> Void

    @ObservedObject private var appearance = AppearanceManager.shared
    @Environment(\.dismiss) private var dismiss

    private var hasSelectedPreset: Bool { !selectedPresetId.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Filter")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: Self.labelColumnWidth, alignment: .leading)
                        Picker("Filter", selection: $selectedPresetId) {
                            Text("None").tag("")
                            if !serverSceneFilters.isEmpty {
                                Section {
                                    ForEach(serverSceneFilters) { f in
                                        Text(f.name).tag(SceneLivePresetTag.serverRow(f.id))
                                    }
                                }
                            }
                            if useMarkerSort {
                                if !markerLocalPresets.isEmpty {
                                    Section {
                                        ForEach(markerLocalPresets) { preset in
                                            Text(preset.name).tag(SceneLivePresetTag.localRow(preset.id))
                                        }
                                    }
                                }
                            } else if !localPresets.isEmpty {
                                Section {
                                    ForEach(localPresets) { preset in
                                        Text(preset.name).tag(SceneLivePresetTag.localRow(preset.id))
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityLabel("Filter")
                        .tint(appearance.tintColor)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .catalogFilterSortControlCardChrome()

                    if useMarkerSort {
                        markerSortControlsCard
                    } else if showsSortControls {
                        sortControlsCard
                    }

                    if showsFeedsPlaybackSettings {
                        FeedsPlaybackSettingsCard()
                    }


                    FilterCriteriaEditorView(document: criteriaDocument, onChange: onApply)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .catalogSettingsSheetChrome(
                hasSelectedPreset: hasSelectedPreset,
                onReset: onReset,
                onRequestSave: onRequestSave,
                onRequestSaveAs: onRequestSaveAs,
                onRequestRename: onRequestRename,
                onRequestDelete: onRequestDelete
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // iOS 26 insets/floats partial-height sheets; `.large` stays edge-attached like Tools feels.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
    }

    private var markerSortControlsCard: some View {
        let pickerValue = MarkerLiveSortPickerValue.from(markerSortOption)
        let ascending = markerSortOption.direction == "ASC"
        let randomMode = pickerValue.isRandom
        let orderControlsDisabled = randomMode

        return HStack(alignment: .center, spacing: 12) {
            Text("Sort")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: Self.labelColumnWidth, alignment: .leading)

            HStack(spacing: 6) {
                filterChip("Asc", isActive: ascending && !orderControlsDisabled) {
                    guard let k = pickerValue.knownKind, !orderControlsDisabled else { return }
                    onMarkerSortChange(k.markerSortOption(ascending: true))
                }
                .accessibilityLabel("Ascending")

                filterChip("Desc", isActive: !ascending && !orderControlsDisabled) {
                    guard let k = pickerValue.knownKind, !orderControlsDisabled else { return }
                    onMarkerSortChange(k.markerSortOption(ascending: false))
                }
                .accessibilityLabel("Descending")
            }
            .fixedSize(horizontal: true, vertical: false)
            .opacity(orderControlsDisabled ? 0.4 : 1)
            .allowsHitTesting(!orderControlsDisabled)

            Spacer(minLength: 8)

            Picker("Sort type", selection: Binding(
                get: { MarkerLiveSortPickerValue.from(markerSortOption) },
                set: { newVal in
                    guard case .known(let newKind) = newVal else { return }
                    if newKind == .random {
                        onMarkerSortChange(.random)
                    } else if MarkerLiveSortPickerValue.from(markerSortOption).isRandom {
                        onMarkerSortChange(newKind.markerSortOption(ascending: false))
                    } else {
                        onMarkerSortChange(newKind.markerSortOption(ascending: markerSortOption.direction == "ASC"))
                    }
                }
            )) {
                ForEach(MarkerLiveSortFieldKind.allCases) { k in
                    Text(k.menuLabel).tag(MarkerLiveSortPickerValue.known(k))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel("Sort field")
            .tint(appearance.tintColor)
        }
        .catalogFilterSortControlCardChrome()
    }

    private var sortControlsCard: some View {
        let pickerValue = SceneLiveSortPickerValue.from(sortOption)
        let ascending = sortOption.direction == "ASC"
        let randomMode = pickerValue.isRandom
        let unmappedMode = pickerValue.isUnmapped
        let orderControlsDisabled = randomMode || unmappedMode

        return HStack(alignment: .center, spacing: 12) {
            Text("Sort")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: Self.labelColumnWidth, alignment: .leading)

            HStack(spacing: 6) {
                filterChip("Asc", isActive: ascending && !orderControlsDisabled) {
                    guard let k = pickerValue.knownKind, !orderControlsDisabled else { return }
                    onSortChange(k.sceneSortOption(ascending: true))
                }
                .accessibilityLabel("Ascending")

                filterChip("Desc", isActive: !ascending && !orderControlsDisabled) {
                    guard let k = pickerValue.knownKind, !orderControlsDisabled else { return }
                    onSortChange(k.sceneSortOption(ascending: false))
                }
                .accessibilityLabel("Descending")
            }
            .fixedSize(horizontal: true, vertical: false)
            .opacity(orderControlsDisabled ? 0.4 : 1)
            .allowsHitTesting(!orderControlsDisabled)

            Spacer(minLength: 8)

            Picker("Sort type", selection: Binding(
                get: { SceneLiveSortPickerValue.from(sortOption) },
                set: { newVal in
                    switch newVal {
                    case .known(let newKind):
                        if newKind == .random {
                            onSortChange(.random)
                        } else if SceneLiveSortPickerValue.from(sortOption).isRandom {
                            onSortChange(newKind.sceneSortOption(ascending: false))
                        } else {
                            onSortChange(newKind.sceneSortOption(ascending: sortOption.direction == "ASC"))
                        }
                    case .unmapped:
                        break
                    }
                }
            )) {
                if case .unmapped(let f) = pickerValue {
                    Text("Other (\(f))").tag(SceneLiveSortPickerValue.unmapped(sortField: f))
                }
                ForEach(SceneLiveSortFieldKind.allCases) { k in
                    Text(k.menuLabel).tag(SceneLiveSortPickerValue.known(k))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel("Sort field")
            .tint(appearance.tintColor)
        }
        .catalogFilterSortControlCardChrome()
    }

    @ViewBuilder
    private func filterRow<Chips: View>(label: String, @ViewBuilder chips: () -> Chips) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: Self.labelColumnWidth, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chips()
                }
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func filterChip(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? appearance.tintColor : Color.secondaryAppBackground)
                .foregroundColor(isActive ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
#endif
