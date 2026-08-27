//
//  DetailLinkedCatalogControllers.swift
//  stashy
//
//  Reusable filter/sort + preset state for performer/tag/studio lists embedded in detail screens
//  (studio → performers/tags/sub-studios, performer → studios/tags, group → …, tag → studios).
//

#if !os(tvOS)
import Combine
import SwiftUI

// MARK: - Performers (scoped to studio / tag / group)

enum DetailLinkedPerformersScope: Equatable {
    case studio(String)
    case tag(String)
    case group(String)
}

@MainActor
final class DetailLinkedPerformersFilterModel: ObservableObject {
    let scope: DetailLinkedPerformersScope

    @Published var showFilterSortSheet = false
    @Published var catalogPresetRowSelection = ""
    @Published var localCatalogPresets: [PerformerListLiveFilterPreset] = PerformerListLiveFilterPresetStore.loadPresets()
    @Published var showSaveAsCatalogPresetAlert = false
    @Published var catalogPresetNameInput = ""
    @Published var showRenameCatalogPresetAlert = false
    @Published var renameCatalogPresetInput = ""
    @Published var showDeleteCatalogPresetAlert = false

    @Published var selectedSortOption: StashDBViewModel.PerformerSortOption
    @Published var selectedFilter: StashDBViewModel.SavedFilter?

    @Published var liveFilterAgeRange: String?
    @Published var liveFilterHairColor: String?
    @Published var liveFilterGender: String?
    @Published var liveFilterCountry: String?
    @Published var liveFilterImplants: Bool?
    @Published var liveFilterFavorite: Bool?
    @Published var liveFilterMissingField: String?
    @Published var liveFilterOCounterTag: String?

    /// Advanced Stash criteria from the full editor; merged over the quick chips on every fetch.
    let criteriaDocument = FilterCriteriaDocument(mode: .performers)
    private var criteriaObserver: AnyCancellable?

    init(scope: DetailLinkedPerformersScope, initialSort: StashDBViewModel.PerformerSortOption = .nameAsc) {
        self.scope = scope
        self.selectedSortOption = initialSort
        self.selectedFilter = nil
        // Nested ObservableObject: forward its changes so FAB state / sheets refresh.
        criteriaObserver = criteriaDocument.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private var isLiveFilterActive: Bool {
        liveFilterAgeRange != nil || liveFilterHairColor != nil || liveFilterGender != nil
            || liveFilterCountry != nil || liveFilterImplants != nil || liveFilterFavorite != nil
            || liveFilterMissingField != nil || liveFilterOCounterTag != nil
    }

    var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive || !criteriaDocument.isEmpty || !catalogPresetRowSelection.isEmpty
    }

    func sortedServerPerformerFilters(viewModel: StashDBViewModel) -> [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .performers }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    private var activeLiveFilterDict: [String: Any] {
        var dict: [String: Any] = [:]
        if let age = liveFilterAgeRange {
            let cal = Calendar.current
            let now = Date()
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            switch age {
            case "18-21":
                let lo = fmt.string(from: cal.date(byAdding: .year, value: -21, to: now)!)
                let hi = fmt.string(from: cal.date(byAdding: .year, value: -18, to: now)!)
                dict["birthdate"] = ["value": lo, "value2": hi, "modifier": "BETWEEN"]
            case "22-26":
                let lo = fmt.string(from: cal.date(byAdding: .year, value: -26, to: now)!)
                let hi = fmt.string(from: cal.date(byAdding: .year, value: -22, to: now)!)
                dict["birthdate"] = ["value": lo, "value2": hi, "modifier": "BETWEEN"]
            case "26-30":
                let lo = fmt.string(from: cal.date(byAdding: .year, value: -30, to: now)!)
                let hi = fmt.string(from: cal.date(byAdding: .year, value: -26, to: now)!)
                dict["birthdate"] = ["value": lo, "value2": hi, "modifier": "BETWEEN"]
            case "30+":
                let lo = fmt.string(from: cal.date(byAdding: .year, value: -30, to: now)!)
                dict["birthdate"] = ["value": lo, "modifier": "LESS_THAN"]
            default: break
            }
        }
        if let hair = liveFilterHairColor {
            dict["hair_color"] = ["value": hair, "modifier": "EQUALS"]
        }
        if let gender = liveFilterGender {
            dict["gender"] = ["value": gender, "modifier": "EQUALS"]
        }
        if let country = liveFilterCountry {
            if country == "NOT_US" {
                dict["country"] = ["value": "US", "modifier": "NOT_EQUALS"]
            } else {
                dict["country"] = ["value": country, "modifier": "EQUALS"]
            }
        }
        if let implants = liveFilterImplants {
            dict["fake_tits"] = ["value": implants ? "FAKE" : "NATURAL", "modifier": "EQUALS"]
        }
        if let favorite = liveFilterFavorite {
            dict["filter_favorites"] = favorite
        }
        if let missingField = liveFilterMissingField, !missingField.isEmpty {
            dict.removeValue(forKey: "has_image")
            dict["is_missing"] = missingField
        }
        if let tag = liveFilterOCounterTag, let oc = sceneLiveOCounterCriterion(from: tag) {
            dict["o_counter"] = oc
        }
        return dict
    }

    /// Passed to `filter:` only while the advanced editor holds no copy of it — otherwise the
    /// server filter would resurrect criteria the user edited away.
    var fetchBaseFilter: StashDBViewModel.SavedFilter? {
        criteriaDocument.isEmpty ? selectedFilter : nil
    }

    /// Quick chips merged with the advanced criteria editor — advanced criteria win per key.
    var effectiveLiveFilter: [String: Any]? {
        criteriaDocument.merged(with: isLiveFilterActive ? activeLiveFilterDict : [:])
    }

    func refetchPerformers(viewModel: StashDBViewModel, initial: Bool) {
        let live = effectiveLiveFilter
        switch scope {
        case .studio(let id):
            viewModel.fetchDetailPerformers(studioId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .tag(let id):
            viewModel.fetchDetailPerformers(tagId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .group(let id):
            viewModel.fetchDetailPerformers(groupId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        }
    }

    func applyLiveFilter(viewModel: StashDBViewModel) {
        refetchPerformers(viewModel: viewModel, initial: true)
    }

    func refreshLocalPresets() {
        localCatalogPresets = PerformerListLiveFilterPresetStore.loadPresets()
    }

    func clearLiveChipsOnly() {
        liveFilterAgeRange = nil
        liveFilterHairColor = nil
        liveFilterGender = nil
        liveFilterCountry = nil
        liveFilterImplants = nil
        liveFilterFavorite = nil
        liveFilterMissingField = nil
        liveFilterOCounterTag = nil
    }

    func mapLiveFragmentToChips(_ frag: [String: Any]) {
        clearLiveChipsOnly()
        if let fav = frag["filter_favorites"] as? Bool {
            liveFilterFavorite = fav
        }
        if let hair = frag["hair_color"] as? [String: Any], let v = hair["value"] as? String {
            liveFilterHairColor = v
        }
        if let g = frag["gender"] as? [String: Any], let v = g["value"] as? String {
            liveFilterGender = v
        }
        if let c = frag["country"] as? [String: Any] {
            let mod = (c["modifier"] as? String) ?? ""
            if mod == "NOT_EQUALS", (c["value"] as? String) == "US" {
                liveFilterCountry = "NOT_US"
            } else if let v = c["value"] as? String {
                liveFilterCountry = v
            }
        }
        if let ft = frag["fake_tits"] as? [String: Any], let v = ft["value"] as? String {
            liveFilterImplants = (v == "FAKE")
        }
        if let m = frag["is_missing"] as? String {
            liveFilterMissingField = m
        }
        if let oc = frag["o_counter"] as? [String: Any],
           let mod = oc["modifier"] as? String,
           let raw = oc["value"],
           let v = Self.intFromLiveFragmentJSON(raw) {
            liveFilterOCounterTag = "\(mod):\(v)"
        }
    }

    func changeSortOption(to newOption: StashDBViewModel.PerformerSortOption, viewModel: StashDBViewModel) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        refetchPerformers(viewModel: viewModel, initial: true)
    }

    private static func intFromLiveFragmentJSON(_ raw: Any) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double { return Int(d) }
        if let n = raw as? NSNumber { return n.intValue }
        return nil
    }

    func applyCatalogPreset(_ preset: PerformerListLiveFilterPreset, viewModel: StashDBViewModel) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.performerSavedFilterSupportsLiveEditor(selectedFilter) {
            mapLiveFragmentToChips(preset.liveFragment)
        } else {
            clearLiveChipsOnly()
        }
        applyLiveFilter(viewModel: viewModel)
    }


    /// Mirrors a selected server filter into the advanced criteria editor so its criteria stay
    /// editable; fetches then pass `filter: nil` and send the document instead.
    private func loadCriteriaDocument(from filter: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = filter.stashyCatalogPresetMetadata {
            var merged: [String: Any] = [:]
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                merged = base.criteriaObjectFilter()
            }
            for (key, value) in FilterMapper.sanitize(meta.liveFragment, isMarker: false) {
                merged[key] = value
            }
            criteriaDocument.load(merged)
        } else {
            criteriaDocument.load(filter.criteriaObjectFilter())
        }
    }

    func applyServerSavedFilter(_ f: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.performerSavedFilterSupportsLiveEditor(selectedFilter) {
                mapLiveFragmentToChips(meta.liveFragment)
            } else {
                clearLiveChipsOnly()
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.PerformerSortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
            }
        } else {
            selectedFilter = f
            let raw = CatalogLiveChipFilterSupport.criteriaForLiveChipUI(from: f)
            if CatalogLiveChipFilterSupport.performerSavedFilterSupportsLiveEditor(f), !raw.isEmpty {
                mapLiveFragmentToChips(raw)
            } else {
                clearLiveChipsOnly()
            }
        }
        loadCriteriaDocument(from: f, viewModel: viewModel)
        applyLiveFilter(viewModel: viewModel)
    }

    func handlePresetSelection(_ newId: String, viewModel: StashDBViewModel) {
        guard showFilterSortSheet else { return }
        if newId.isEmpty {
            selectedFilter = nil
            clearLiveChipsOnly()
            criteriaDocument.clear()
            applyLiveFilter(viewModel: viewModel)
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: StashDBViewModel) {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func deletePresetConfirmationText(viewModel: StashDBViewModel) -> String {
        if let sid = ListLivePresetTag.parseServerId(catalogPresetRowSelection),
           let f = viewModel.savedFilters[sid] {
            return "Remove “\(f.name)” from Stash? Other devices will lose this saved filter."
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection),
           let uuid = UUID(uuidString: ls),
           let p = localCatalogPresets.first(where: { $0.id == uuid }) {
            return "Remove “\(p.name)” from this device? This cannot be undone."
        }
        return "Remove this filter? This cannot be undone."
    }

    func savePresetOverwrite(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            let name = viewModel.savedFilters[sid]?.name ?? "Filter"
            viewModel.saveCatalogSavedFilter(
                mode: .performers,
                randomSeedKind: .performers,
                existingId: sid,
                name: name,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { _ in }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let index = localCatalogPresets.firstIndex(where: { $0.id == uuid }) else { return }
        let old = localCatalogPresets[index]
        let updated = PerformerListLiveFilterPreset(
            id: old.id,
            name: old.name,
            createdAt: old.createdAt,
            sort: selectedSortOption,
            baseSavedFilterId: selectedFilter?.id,
            liveFragment: activeLiveFilterDict
        )
        PerformerListLiveFilterPresetStore.upsert(updated)
        refreshLocalPresets()
    }

    func savePresetAs(name: String, viewModel: StashDBViewModel) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveCatalogSavedFilter(
            mode: .performers,
            randomSeedKind: .performers,
            existingId: nil,
            name: trimmed,
            sortRaw: selectedSortOption.rawValue,
            sortField: selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            baseFilter: selectedFilter,
            liveFragment: activeLiveFilterDict
        ) { [weak self] result in
            guard let self else { return }
            if case .success(let saved) = result {
                self.catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                self.showSaveAsCatalogPresetAlert = false
            }
        }
    }

    func renamePreset(to newName: String, viewModel: StashDBViewModel) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.saveCatalogSavedFilter(
                mode: .performers,
                randomSeedKind: .performers,
                existingId: sid,
                name: trimmed,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { [weak self] result in
                if case .success = result { self?.showRenameCatalogPresetAlert = false }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = localCatalogPresets.first(where: { $0.id == uuid }) else { return }
        PerformerListLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    func deletePreset(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { [weak self] result in
                guard let self else { return }
                if case .success = result {
                    if self.selectedFilter?.id == sid { self.selectedFilter = nil }
                    self.catalogPresetRowSelection = ""
                    self.showDeleteCatalogPresetAlert = false
                    self.refetchPerformers(viewModel: viewModel, initial: true)
                }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        PerformerListLiveFilterPresetStore.remove(id: uuid)
        refreshLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }
}

// MARK: - Tags (scoped to performer / studio / group)

enum DetailLinkedTagsScope: Equatable {
    case performer(String)
    case studio(String)
    case group(String)
}

@MainActor
final class DetailLinkedTagsFilterModel: ObservableObject {
    let scope: DetailLinkedTagsScope

    @Published var showFilterSortSheet = false
    @Published var catalogPresetRowSelection = ""
    @Published var localCatalogPresets: [TagListLiveFilterPreset] = TagListLiveFilterPresetStore.loadPresets()
    @Published var showSaveAsCatalogPresetAlert = false
    @Published var catalogPresetNameInput = ""
    @Published var showRenameCatalogPresetAlert = false
    @Published var renameCatalogPresetInput = ""
    @Published var showDeleteCatalogPresetAlert = false

    @Published var selectedSortOption: StashDBViewModel.TagSortOption
    @Published var selectedFilter: StashDBViewModel.SavedFilter?
    @Published var liveFilterFavorite: Bool?
    @Published var liveFilterHasScenes: Bool = false

    /// Advanced Stash criteria from the full editor; merged over the quick chips on every fetch.
    let criteriaDocument = FilterCriteriaDocument(mode: .tags)
    private var criteriaObserver: AnyCancellable?

    init(scope: DetailLinkedTagsScope, initialSort: StashDBViewModel.TagSortOption = .sceneCountDesc) {
        self.scope = scope
        self.selectedSortOption = initialSort
        self.selectedFilter = nil
        // Nested ObservableObject: forward its changes so FAB state / sheets refresh.
        criteriaObserver = criteriaDocument.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private var isLiveFilterActive: Bool {
        liveFilterFavorite != nil || liveFilterHasScenes
    }

    var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive || !criteriaDocument.isEmpty || !catalogPresetRowSelection.isEmpty
    }

    func sortedServerTagFilters(viewModel: StashDBViewModel) -> [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .tags }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    private var activeLiveFilterDict: [String: Any] {
        var dict: [String: Any] = [:]
        if let fav = liveFilterFavorite { dict["favorite"] = fav }
        if liveFilterHasScenes { dict["scene_count"] = ["value": 0, "modifier": "GREATER_THAN"] }
        return dict
    }

    /// Passed to `filter:` only while the advanced editor holds no copy of it — otherwise the
    /// server filter would resurrect criteria the user edited away.
    var fetchBaseFilter: StashDBViewModel.SavedFilter? {
        criteriaDocument.isEmpty ? selectedFilter : nil
    }

    /// Quick chips merged with the advanced criteria editor — advanced criteria win per key.
    var effectiveLiveFilter: [String: Any]? {
        criteriaDocument.merged(with: isLiveFilterActive ? activeLiveFilterDict : [:])
    }

    func refetchTags(viewModel: StashDBViewModel, initial: Bool) {
        let live = effectiveLiveFilter
        switch scope {
        case .performer(let id):
            viewModel.fetchDetailTags(performerId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .studio(let id):
            viewModel.fetchDetailTags(studioId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .group(let id):
            viewModel.fetchDetailTags(groupId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        }
    }

    func applyLiveFilter(viewModel: StashDBViewModel) {
        refetchTags(viewModel: viewModel, initial: true)
    }

    func refreshLocalPresets() {
        localCatalogPresets = TagListLiveFilterPresetStore.loadPresets()
    }

    func clearLiveChipsOnly() {
        liveFilterFavorite = nil
        liveFilterHasScenes = false
    }

    func mapLiveFragmentToChips(_ frag: [String: Any]) {
        clearLiveChipsOnly()
        if let fav = frag["favorite"] as? Bool {
            liveFilterFavorite = fav
        }
        if let sc = frag["scene_count"] as? [String: Any], let mod = sc["modifier"] as? String, mod == "GREATER_THAN" {
            liveFilterHasScenes = true
        }
    }

    func changeSortOption(to newOption: StashDBViewModel.TagSortOption, viewModel: StashDBViewModel) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        refetchTags(viewModel: viewModel, initial: true)
    }

    func applyCatalogPreset(_ preset: TagListLiveFilterPreset, viewModel: StashDBViewModel) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.tagSavedFilterSupportsLiveEditor(selectedFilter) {
            mapLiveFragmentToChips(preset.liveFragment)
        } else {
            clearLiveChipsOnly()
        }
        applyLiveFilter(viewModel: viewModel)
    }


    /// Mirrors a selected server filter into the advanced criteria editor so its criteria stay
    /// editable; fetches then pass `filter: nil` and send the document instead.
    private func loadCriteriaDocument(from filter: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = filter.stashyCatalogPresetMetadata {
            var merged: [String: Any] = [:]
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                merged = base.criteriaObjectFilter()
            }
            for (key, value) in FilterMapper.sanitize(meta.liveFragment, isMarker: false) {
                merged[key] = value
            }
            criteriaDocument.load(merged)
        } else {
            criteriaDocument.load(filter.criteriaObjectFilter())
        }
    }

    func applyServerSavedFilter(_ f: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.tagSavedFilterSupportsLiveEditor(selectedFilter) {
                mapLiveFragmentToChips(meta.liveFragment)
            } else {
                clearLiveChipsOnly()
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.TagSortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
            }
        } else {
            selectedFilter = f
            let raw = CatalogLiveChipFilterSupport.criteriaForLiveChipUI(from: f)
            if CatalogLiveChipFilterSupport.tagSavedFilterSupportsLiveEditor(f), !raw.isEmpty {
                mapLiveFragmentToChips(raw)
            } else {
                clearLiveChipsOnly()
            }
        }
        loadCriteriaDocument(from: f, viewModel: viewModel)
        applyLiveFilter(viewModel: viewModel)
    }

    func handlePresetSelection(_ newId: String, viewModel: StashDBViewModel) {
        guard showFilterSortSheet else { return }
        if newId.isEmpty {
            selectedFilter = nil
            clearLiveChipsOnly()
            criteriaDocument.clear()
            applyLiveFilter(viewModel: viewModel)
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: StashDBViewModel) {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func deletePresetConfirmationText(viewModel: StashDBViewModel) -> String {
        if let sid = ListLivePresetTag.parseServerId(catalogPresetRowSelection),
           let f = viewModel.savedFilters[sid] {
            return "Remove “\(f.name)” from Stash? Other devices will lose this saved filter."
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection),
           let uuid = UUID(uuidString: ls),
           let p = localCatalogPresets.first(where: { $0.id == uuid }) {
            return "Remove “\(p.name)” from this device? This cannot be undone."
        }
        return "Remove this filter? This cannot be undone."
    }

    func savePresetOverwrite(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            let name = viewModel.savedFilters[sid]?.name ?? "Filter"
            viewModel.saveCatalogSavedFilter(
                mode: .tags,
                randomSeedKind: .tags,
                existingId: sid,
                name: name,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { _ in }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let index = localCatalogPresets.firstIndex(where: { $0.id == uuid }) else { return }
        let old = localCatalogPresets[index]
        let updated = TagListLiveFilterPreset(
            id: old.id,
            name: old.name,
            createdAt: old.createdAt,
            sort: selectedSortOption,
            baseSavedFilterId: selectedFilter?.id,
            liveFragment: activeLiveFilterDict
        )
        TagListLiveFilterPresetStore.upsert(updated)
        refreshLocalPresets()
    }

    func savePresetAs(name: String, viewModel: StashDBViewModel) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveCatalogSavedFilter(
            mode: .tags,
            randomSeedKind: .tags,
            existingId: nil,
            name: trimmed,
            sortRaw: selectedSortOption.rawValue,
            sortField: selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            baseFilter: selectedFilter,
            liveFragment: activeLiveFilterDict
        ) { [weak self] result in
            guard let self else { return }
            if case .success(let saved) = result {
                self.catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                self.showSaveAsCatalogPresetAlert = false
            }
        }
    }

    func renamePreset(to newName: String, viewModel: StashDBViewModel) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.saveCatalogSavedFilter(
                mode: .tags,
                randomSeedKind: .tags,
                existingId: sid,
                name: trimmed,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { [weak self] result in
                if case .success = result { self?.showRenameCatalogPresetAlert = false }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = localCatalogPresets.first(where: { $0.id == uuid }) else { return }
        TagListLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    func deletePreset(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { [weak self] result in
                guard let self else { return }
                if case .success = result {
                    if self.selectedFilter?.id == sid { self.selectedFilter = nil }
                    self.catalogPresetRowSelection = ""
                    self.showDeleteCatalogPresetAlert = false
                    self.refetchTags(viewModel: viewModel, initial: true)
                }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        TagListLiveFilterPresetStore.remove(id: uuid)
        refreshLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }
}

// MARK: - Studios (scoped to performer / tag / parent studio / group)

enum DetailLinkedStudiosScope: Equatable {
    case performer(String)
    case tag(String)
    case parentStudio(String)
    case group(String)
}

@MainActor
final class DetailLinkedStudiosFilterModel: ObservableObject {
    let scope: DetailLinkedStudiosScope

    @Published var showFilterSortSheet = false
    @Published var catalogPresetRowSelection = ""
    @Published var localCatalogPresets: [StudioListLiveFilterPreset] = StudioListLiveFilterPresetStore.loadPresets()
    @Published var showSaveAsCatalogPresetAlert = false
    @Published var catalogPresetNameInput = ""
    @Published var showRenameCatalogPresetAlert = false
    @Published var renameCatalogPresetInput = ""
    @Published var showDeleteCatalogPresetAlert = false

    @Published var selectedSortOption: StashDBViewModel.StudioSortOption
    @Published var selectedFilter: StashDBViewModel.SavedFilter?
    @Published var liveFilterFavorite: Bool?
    @Published var liveFilterMinRating: Int = 0
    @Published var liveFilterScenes: String?

    /// Advanced Stash criteria from the full editor; merged over the quick chips on every fetch.
    let criteriaDocument = FilterCriteriaDocument(mode: .studios)
    private var criteriaObserver: AnyCancellable?

    init(scope: DetailLinkedStudiosScope, initialSort: StashDBViewModel.StudioSortOption = .nameAsc) {
        self.scope = scope
        self.selectedSortOption = initialSort
        self.selectedFilter = nil
        // Nested ObservableObject: forward its changes so FAB state / sheets refresh.
        criteriaObserver = criteriaDocument.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private var isLiveFilterActive: Bool {
        liveFilterFavorite != nil || liveFilterMinRating != 0 || liveFilterScenes != nil
    }

    var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive || !criteriaDocument.isEmpty || !catalogPresetRowSelection.isEmpty
    }

    func sortedServerStudioFilters(viewModel: StashDBViewModel) -> [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .studios }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    private var activeLiveFilterDict: [String: Any] {
        var dict: [String: Any] = [:]
        if let fav = liveFilterFavorite { dict["favorite"] = fav }
        if liveFilterMinRating == -1 {
            dict["rating100"] = ["modifier": "IS_NULL"]
        } else if liveFilterMinRating > 0 {
            dict["rating100"] = ["value": (liveFilterMinRating * 20), "modifier": "EQUALS"]
        }
        if liveFilterScenes == "has" { dict["scene_count"] = ["value": 0, "modifier": "GREATER_THAN"] }
        if liveFilterScenes == "none" { dict["scene_count"] = ["value": 0, "modifier": "EQUALS"] }
        return dict
    }

    /// Passed to `filter:` only while the advanced editor holds no copy of it — otherwise the
    /// server filter would resurrect criteria the user edited away.
    var fetchBaseFilter: StashDBViewModel.SavedFilter? {
        criteriaDocument.isEmpty ? selectedFilter : nil
    }

    /// Quick chips merged with the advanced criteria editor — advanced criteria win per key.
    var effectiveLiveFilter: [String: Any]? {
        criteriaDocument.merged(with: isLiveFilterActive ? activeLiveFilterDict : [:])
    }

    func refetchStudios(viewModel: StashDBViewModel, initial: Bool) {
        let live = effectiveLiveFilter
        switch scope {
        case .performer(let id):
            viewModel.fetchDetailStudios(performerId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .tag(let id):
            viewModel.fetchDetailStudios(tagId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .parentStudio(let id):
            viewModel.fetchDetailStudios(parentStudioId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .group(let id):
            viewModel.fetchDetailStudios(groupId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        }
    }

    func applyLiveFilter(viewModel: StashDBViewModel) {
        refetchStudios(viewModel: viewModel, initial: true)
    }

    func refreshLocalPresets() {
        localCatalogPresets = StudioListLiveFilterPresetStore.loadPresets()
    }

    func clearLiveChipsOnly() {
        liveFilterFavorite = nil
        liveFilterMinRating = 0
        liveFilterScenes = nil
    }

    func mapLiveFragmentToChips(_ frag: [String: Any]) {
        clearLiveChipsOnly()
        if let fav = frag["favorite"] as? Bool {
            liveFilterFavorite = fav
        }
        if let r = frag["rating100"] as? [String: Any] {
            let mod = (r["modifier"] as? String) ?? ""
            if mod == "IS_NULL" {
                liveFilterMinRating = -1
            } else if let raw = r["value"] {
                let v: Int? = {
                    if let i = raw as? Int { return i }
                    if let d = raw as? Double { return Int(d) }
                    if let n = raw as? NSNumber { return n.intValue }
                    return nil
                }()
                if let v {
                    liveFilterMinRating = max(0, min(5, v / 20))
                }
            }
        }
        if let sc = frag["scene_count"] as? [String: Any], let mod = sc["modifier"] as? String {
            if mod == "GREATER_THAN" {
                liveFilterScenes = "has"
            } else if mod == "EQUALS" {
                liveFilterScenes = "none"
            }
        }
    }

    func changeSortOption(to newOption: StashDBViewModel.StudioSortOption, viewModel: StashDBViewModel) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        refetchStudios(viewModel: viewModel, initial: true)
    }

    func applyCatalogPreset(_ preset: StudioListLiveFilterPreset, viewModel: StashDBViewModel) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.studioSavedFilterSupportsLiveEditor(selectedFilter) {
            mapLiveFragmentToChips(preset.liveFragment)
        } else {
            clearLiveChipsOnly()
        }
        applyLiveFilter(viewModel: viewModel)
    }


    /// Mirrors a selected server filter into the advanced criteria editor so its criteria stay
    /// editable; fetches then pass `filter: nil` and send the document instead.
    private func loadCriteriaDocument(from filter: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = filter.stashyCatalogPresetMetadata {
            var merged: [String: Any] = [:]
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                merged = base.criteriaObjectFilter()
            }
            for (key, value) in FilterMapper.sanitize(meta.liveFragment, isMarker: false) {
                merged[key] = value
            }
            criteriaDocument.load(merged)
        } else {
            criteriaDocument.load(filter.criteriaObjectFilter())
        }
    }

    func applyServerSavedFilter(_ f: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.studioSavedFilterSupportsLiveEditor(selectedFilter) {
                mapLiveFragmentToChips(meta.liveFragment)
            } else {
                clearLiveChipsOnly()
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.StudioSortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
            }
        } else {
            selectedFilter = f
            let raw = CatalogLiveChipFilterSupport.criteriaForLiveChipUI(from: f)
            if CatalogLiveChipFilterSupport.studioSavedFilterSupportsLiveEditor(f), !raw.isEmpty {
                mapLiveFragmentToChips(raw)
            } else {
                clearLiveChipsOnly()
            }
        }
        loadCriteriaDocument(from: f, viewModel: viewModel)
        applyLiveFilter(viewModel: viewModel)
    }

    func handlePresetSelection(_ newId: String, viewModel: StashDBViewModel) {
        guard showFilterSortSheet else { return }
        if newId.isEmpty {
            selectedFilter = nil
            clearLiveChipsOnly()
            criteriaDocument.clear()
            applyLiveFilter(viewModel: viewModel)
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: StashDBViewModel) {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func deletePresetConfirmationText(viewModel: StashDBViewModel) -> String {
        if let sid = ListLivePresetTag.parseServerId(catalogPresetRowSelection),
           let f = viewModel.savedFilters[sid] {
            return "Remove “\(f.name)” from Stash? Other devices will lose this saved filter."
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection),
           let uuid = UUID(uuidString: ls),
           let p = localCatalogPresets.first(where: { $0.id == uuid }) {
            return "Remove “\(p.name)” from this device? This cannot be undone."
        }
        return "Remove this filter? This cannot be undone."
    }

    func savePresetOverwrite(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            let name = viewModel.savedFilters[sid]?.name ?? "Filter"
            viewModel.saveCatalogSavedFilter(
                mode: .studios,
                randomSeedKind: .studios,
                existingId: sid,
                name: name,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { _ in }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let index = localCatalogPresets.firstIndex(where: { $0.id == uuid }) else { return }
        let old = localCatalogPresets[index]
        let updated = StudioListLiveFilterPreset(
            id: old.id,
            name: old.name,
            createdAt: old.createdAt,
            sort: selectedSortOption,
            baseSavedFilterId: selectedFilter?.id,
            liveFragment: activeLiveFilterDict
        )
        StudioListLiveFilterPresetStore.upsert(updated)
        refreshLocalPresets()
    }

    func savePresetAs(name: String, viewModel: StashDBViewModel) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveCatalogSavedFilter(
            mode: .studios,
            randomSeedKind: .studios,
            existingId: nil,
            name: trimmed,
            sortRaw: selectedSortOption.rawValue,
            sortField: selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            baseFilter: selectedFilter,
            liveFragment: activeLiveFilterDict
        ) { [weak self] result in
            guard let self else { return }
            if case .success(let saved) = result {
                self.catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                self.showSaveAsCatalogPresetAlert = false
            }
        }
    }

    func renamePreset(to newName: String, viewModel: StashDBViewModel) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.saveCatalogSavedFilter(
                mode: .studios,
                randomSeedKind: .studios,
                existingId: sid,
                name: trimmed,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { [weak self] result in
                if case .success = result { self?.showRenameCatalogPresetAlert = false }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = localCatalogPresets.first(where: { $0.id == uuid }) else { return }
        StudioListLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    func deletePreset(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { [weak self] result in
                guard let self else { return }
                if case .success = result {
                    if self.selectedFilter?.id == sid { self.selectedFilter = nil }
                    self.catalogPresetRowSelection = ""
                    self.showDeleteCatalogPresetAlert = false
                    self.refetchStudios(viewModel: viewModel, initial: true)
                }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        StudioListLiveFilterPresetStore.remove(id: uuid)
        refreshLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }
}

// MARK: - Galleries (scoped to performer / studio / tag / group)

enum DetailLinkedGalleriesScope: Equatable {
    case performer(String)
    case studio(String)
    case tag(String)
    case group(String)
}

@MainActor
final class DetailLinkedGalleriesFilterModel: ObservableObject {
    let scope: DetailLinkedGalleriesScope

    @Published var showFilterSortSheet = false
    @Published var catalogPresetRowSelection = ""
    @Published var localCatalogPresets: [GalleryListLiveFilterPreset] = GalleryListLiveFilterPresetStore.loadPresets()
    @Published var showSaveAsCatalogPresetAlert = false
    @Published var catalogPresetNameInput = ""
    @Published var showRenameCatalogPresetAlert = false
    @Published var renameCatalogPresetInput = ""
    @Published var showDeleteCatalogPresetAlert = false

    @Published var selectedSortOption: StashDBViewModel.GallerySortOption
    @Published var selectedFilter: StashDBViewModel.SavedFilter?
    @Published var liveFilterFavorite: Bool?
    @Published var liveFilterMinRating: Int = 0
    @Published var liveFilterFiles: String?
    @Published var liveFilterStudioId: String?
    @Published var studioPickerOptions: [Studio] = []
    @Published var studioPickerLoading = false

    /// Advanced Stash criteria from the full editor; merged over the quick chips on every fetch.
    let criteriaDocument = FilterCriteriaDocument(mode: .galleries)
    private var criteriaObserver: AnyCancellable?

    init(scope: DetailLinkedGalleriesScope, initialSort: StashDBViewModel.GallerySortOption = .dateDesc) {
        self.scope = scope
        self.selectedSortOption = initialSort
        self.selectedFilter = nil
        // Nested ObservableObject: forward its changes so FAB state / sheets refresh.
        criteriaObserver = criteriaDocument.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private var isLiveFilterActive: Bool {
        liveFilterFavorite != nil || liveFilterMinRating != 0 || liveFilterFiles != nil || liveFilterStudioId != nil
    }

    var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive || !criteriaDocument.isEmpty || !catalogPresetRowSelection.isEmpty
    }

    func loadStudioPickerOptions(viewModel: StashDBViewModel) {
        guard !studioPickerLoading else { return }
        studioPickerLoading = true
        viewModel.fetchStudiosForLiveFilterPicker(mode: .galleriesHasGalleries) { [weak self] list in
            guard let self else { return }
            self.studioPickerOptions = list
            self.studioPickerLoading = false
        }
    }

    func sortedServerGalleryFilters(viewModel: StashDBViewModel) -> [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .galleries }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    private var activeLiveFilterDict: [String: Any] {
        var dict: [String: Any] = [:]
        if let fav = liveFilterFavorite { dict["favorite"] = fav }
        if liveFilterMinRating == -1 {
            dict["rating100"] = ["modifier": "IS_NULL"]
        } else if liveFilterMinRating > 0 {
            dict["rating100"] = ["value": (liveFilterMinRating * 20), "modifier": "EQUALS"]
        }
        if liveFilterFiles == "has" { dict["file_count"] = ["value": 0, "modifier": "GREATER_THAN"] }
        if liveFilterFiles == "none" { dict["file_count"] = ["value": 0, "modifier": "EQUALS"] }
        if let sid = liveFilterStudioId {
            dict["studios"] = ["modifier": "INCLUDES", "value": [sid]]
        }
        return dict
    }

    /// Passed to `filter:` only while the advanced editor holds no copy of it — otherwise the
    /// server filter would resurrect criteria the user edited away.
    var fetchBaseFilter: StashDBViewModel.SavedFilter? {
        criteriaDocument.isEmpty ? selectedFilter : nil
    }

    /// Quick chips merged with the advanced criteria editor — advanced criteria win per key.
    var effectiveLiveFilter: [String: Any]? {
        criteriaDocument.merged(with: isLiveFilterActive ? activeLiveFilterDict : [:])
    }

    func refetchGalleries(viewModel: StashDBViewModel, initial: Bool) {
        let live = effectiveLiveFilter
        switch scope {
        case .performer(let id):
            viewModel.fetchPerformerGalleries(performerId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .studio(let id):
            viewModel.fetchStudioGalleries(studioId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .tag(let id):
            viewModel.fetchTagGalleries(tagId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .group(let id):
            viewModel.fetchGroupGalleries(groupId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        }
    }

    func applyLiveFilter(viewModel: StashDBViewModel) {
        refetchGalleries(viewModel: viewModel, initial: true)
    }

    func refreshLocalPresets() {
        localCatalogPresets = GalleryListLiveFilterPresetStore.loadPresets()
    }

    func clearLiveChipsOnly() {
        liveFilterFavorite = nil
        liveFilterMinRating = 0
        liveFilterFiles = nil
        liveFilterStudioId = nil
    }

    func mapLiveFragmentToChips(_ frag: [String: Any]) {
        clearLiveChipsOnly()
        if let fav = frag["favorite"] as? Bool {
            liveFilterFavorite = fav
        }
        if let r = frag["rating100"] as? [String: Any] {
            let mod = (r["modifier"] as? String) ?? ""
            if mod == "IS_NULL" {
                liveFilterMinRating = -1
            } else if let raw = r["value"] {
                let v: Int? = {
                    if let i = raw as? Int { return i }
                    if let d = raw as? Double { return Int(d) }
                    if let n = raw as? NSNumber { return n.intValue }
                    return nil
                }()
                if let v {
                    liveFilterMinRating = max(0, min(5, v / 20))
                }
            }
        }
        if let fc = frag["file_count"] as? [String: Any], let mod = fc["modifier"] as? String {
            if mod == "GREATER_THAN" {
                liveFilterFiles = "has"
            } else if mod == "EQUALS" {
                liveFilterFiles = "none"
            }
        }
        if let st = frag["studios"] as? [String: Any],
           (st["modifier"] as? String) == "INCLUDES",
           let vals = st["value"] as? [Any] {
            let ids = vals.compactMap { $0 as? String }
            liveFilterStudioId = ids.first
        }
    }

    func changeSortOption(to newOption: StashDBViewModel.GallerySortOption, viewModel: StashDBViewModel) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        refetchGalleries(viewModel: viewModel, initial: true)
    }

    func applyCatalogPreset(_ preset: GalleryListLiveFilterPreset, viewModel: StashDBViewModel) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.gallerySavedFilterSupportsLiveEditor(selectedFilter) {
            mapLiveFragmentToChips(preset.liveFragment)
        } else {
            clearLiveChipsOnly()
        }
        applyLiveFilter(viewModel: viewModel)
    }


    /// Mirrors a selected server filter into the advanced criteria editor so its criteria stay
    /// editable; fetches then pass `filter: nil` and send the document instead.
    private func loadCriteriaDocument(from filter: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = filter.stashyCatalogPresetMetadata {
            var merged: [String: Any] = [:]
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                merged = base.criteriaObjectFilter()
            }
            for (key, value) in FilterMapper.sanitize(meta.liveFragment, isMarker: false) {
                merged[key] = value
            }
            criteriaDocument.load(merged)
        } else {
            criteriaDocument.load(filter.criteriaObjectFilter())
        }
    }

    func applyServerSavedFilter(_ f: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.gallerySavedFilterSupportsLiveEditor(selectedFilter) {
                mapLiveFragmentToChips(meta.liveFragment)
            } else {
                clearLiveChipsOnly()
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.GallerySortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
            }
        } else {
            selectedFilter = f
            let raw = CatalogLiveChipFilterSupport.criteriaForLiveChipUI(from: f)
            if CatalogLiveChipFilterSupport.gallerySavedFilterSupportsLiveEditor(f), !raw.isEmpty {
                mapLiveFragmentToChips(raw)
            } else {
                clearLiveChipsOnly()
            }
        }
        loadCriteriaDocument(from: f, viewModel: viewModel)
        applyLiveFilter(viewModel: viewModel)
    }

    func handlePresetSelection(_ newId: String, viewModel: StashDBViewModel) {
        guard showFilterSortSheet else { return }
        if newId.isEmpty {
            selectedFilter = nil
            clearLiveChipsOnly()
            criteriaDocument.clear()
            applyLiveFilter(viewModel: viewModel)
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: StashDBViewModel) {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func deletePresetConfirmationText(viewModel: StashDBViewModel) -> String {
        if let sid = ListLivePresetTag.parseServerId(catalogPresetRowSelection),
           let f = viewModel.savedFilters[sid] {
            return "Remove “\(f.name)” from Stash? Other devices will lose this saved filter."
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection),
           let uuid = UUID(uuidString: ls),
           let p = localCatalogPresets.first(where: { $0.id == uuid }) {
            return "Remove “\(p.name)” from this device? This cannot be undone."
        }
        return "Remove this filter? This cannot be undone."
    }

    func savePresetOverwrite(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            let name = viewModel.savedFilters[sid]?.name ?? "Filter"
            viewModel.saveCatalogSavedFilter(
                mode: .galleries,
                randomSeedKind: .galleries,
                existingId: sid,
                name: name,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { _ in }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let index = localCatalogPresets.firstIndex(where: { $0.id == uuid }) else { return }
        let old = localCatalogPresets[index]
        let updated = GalleryListLiveFilterPreset(
            id: old.id,
            name: old.name,
            createdAt: old.createdAt,
            sort: selectedSortOption,
            baseSavedFilterId: selectedFilter?.id,
            liveFragment: activeLiveFilterDict
        )
        GalleryListLiveFilterPresetStore.upsert(updated)
        refreshLocalPresets()
    }

    func savePresetAs(name: String, viewModel: StashDBViewModel) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveCatalogSavedFilter(
            mode: .galleries,
            randomSeedKind: .galleries,
            existingId: nil,
            name: trimmed,
            sortRaw: selectedSortOption.rawValue,
            sortField: selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            baseFilter: selectedFilter,
            liveFragment: activeLiveFilterDict
        ) { [weak self] result in
            guard let self else { return }
            if case .success(let saved) = result {
                self.catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                self.showSaveAsCatalogPresetAlert = false
            }
        }
    }

    func renamePreset(to newName: String, viewModel: StashDBViewModel) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.saveCatalogSavedFilter(
                mode: .galleries,
                randomSeedKind: .galleries,
                existingId: sid,
                name: trimmed,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { [weak self] result in
                if case .success = result { self?.showRenameCatalogPresetAlert = false }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = localCatalogPresets.first(where: { $0.id == uuid }) else { return }
        GalleryListLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    func deletePreset(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { [weak self] result in
                guard let self else { return }
                if case .success = result {
                    if self.selectedFilter?.id == sid { self.selectedFilter = nil }
                    self.catalogPresetRowSelection = ""
                    self.showDeleteCatalogPresetAlert = false
                    self.refetchGalleries(viewModel: viewModel, initial: true)
                }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        GalleryListLiveFilterPresetStore.remove(id: uuid)
        refreshLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }
}

// MARK: - Images (detail lists + single gallery)

enum DetailLinkedImagesScope: Equatable {
    case catalogRoot
    case performer(String)
    case studio(String)
    case tag(String)
    case group(String)
    case gallery(String)
    /// Reels „Clips“: `refetchImages` delegates to `fetchClips` (or `externalRefetchClips` when set).
    case reelsClips
    /// Embedded StashLine in Reels „Pics“: still images only, optional performer id.
    case reelsStashLine
}

@MainActor
final class DetailLinkedImagesFilterModel: ObservableObject {
    let scope: DetailLinkedImagesScope

    /// Reels clips: parent supplies merged performer/tag filter; when set, replaces default `refetchImages` tail for `.reelsClips`.
    var externalRefetchClips: ((StashDBViewModel) -> Void)?
    /// Performer id for `.reelsStashLine` (Reels Pics embedded StashLine).
    @Published var reelsStashLinePerformerId: String?

    @Published var showFilterSortSheet = false
    @Published var catalogPresetRowSelection = ""
    @Published var localCatalogPresets: [ImageListLiveFilterPreset] = ImageListLiveFilterPresetStore.loadPresets()
    @Published var showSaveAsCatalogPresetAlert = false
    @Published var catalogPresetNameInput = ""
    @Published var showRenameCatalogPresetAlert = false
    @Published var renameCatalogPresetInput = ""
    @Published var showDeleteCatalogPresetAlert = false

    @Published var selectedSortOption: StashDBViewModel.ImageSortOption
    @Published var selectedFilter: StashDBViewModel.SavedFilter?
    /// Live chip maps to Stash `ImageFilterType.performer_favorite` (there is no image-level `favorite` in the API).
    @Published var liveFilterPerformerFavorite: Bool?
    @Published var liveFilterMinRating: Int = 0
    @Published var liveFilterOrganized: String?
    @Published var liveFilterOCounterTag: String?
    @Published var liveFilterStudioIds: [String] = []
    @Published var studioPickerOptions: [Studio] = []
    @Published var studioPickerLoading = false
    @Published var liveFilterTagIds: [String] = []
    @Published var tagPickerOptions: [Tag] = []
    @Published var tagPickerLoading = false
    @Published var liveFilterMediaKind: ImageListMediaKind = .all

    /// Catalog root: skip re-applying Settings defaults / initial fetch after the first bootstrap
    /// (e.g. returning from FullScreenImageView must not wipe an active filter).
    var hasCompletedInitialBootstrap = false
    /// Feeds deep-link (performer/tag → Pics): keep Filter = None; do not inject Settings default.
    var suppressSettingsDefaultFilter = false
    /// Scroll restore target after popping fullscreen (survives ImagesView remounts when model is hoisted).
    var sessionLastOpenedImageId: String?
    /// When true, `handlePresetSelection` ignores the next `catalogPresetRowSelection` change
    /// (sheet-open picker sync must not refetch the list).
    private var ignoreNextPresetSelectionChange = false

    /// Advanced Stash criteria from the full editor; merged over the quick chips on every fetch.
    let criteriaDocument = FilterCriteriaDocument(mode: .images)
    private var criteriaObserver: AnyCancellable?

    init(scope: DetailLinkedImagesScope, initialSort: StashDBViewModel.ImageSortOption = .dateDesc) {
        self.scope = scope
        self.selectedSortOption = initialSort
        self.selectedFilter = nil
        // Nested ObservableObject: forward its changes so FAB state / sheets refresh.
        criteriaObserver = criteriaDocument.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// After an ImagesView remount, restore chip/filter UI from the shared catalog VM session.
    func rehydrateFromViewModelSessionIfNeeded(_ viewModel: StashDBViewModel) {
        guard case .catalogRoot = scope else { return }
        let hasLocalFilter =
            selectedFilter != nil
            || !catalogPresetRowSelection.isEmpty
            || isLiveFilterActive
        guard !hasLocalFilter else { return }

        if let f = viewModel.currentImageFilter {
            selectedFilter = f
            catalogPresetRowSelection = ListLivePresetTag.serverRow(f.id)
            if viewModel.currentImageLiveFilter.isEmpty {
                syncLiveChipsFromSelectedFilter(viewModel: viewModel)
            } else {
                mapLiveFragmentToChips(viewModel.currentImageLiveFilter)
            }
        } else if !viewModel.currentImageLiveFilter.isEmpty {
            mapLiveFragmentToChips(viewModel.currentImageLiveFilter)
        }

        selectedSortOption = viewModel.currentImageSortOption
    }

    private var isLiveFilterActive: Bool {
        let mediaKindActive: Bool = {
            if case .reelsStashLine = scope { return false }
            return liveFilterMediaKind != .all
        }()
        return liveFilterPerformerFavorite != nil || liveFilterMinRating != 0 || liveFilterOrganized != nil
            || liveFilterOCounterTag != nil || !liveFilterStudioIds.isEmpty || !liveFilterTagIds.isEmpty
            || mediaKindActive
    }

    var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive || !criteriaDocument.isEmpty || !catalogPresetRowSelection.isEmpty
    }

    /// Clips use a fixed video-style `path` regex in `fetchClips` and ignore live `path`.
    /// StashLine (Reels „Pics“) lists images only — Bilder/Videos-Zeile ausblenden.
    var showImageMediaTypeFilter: Bool {
        switch scope {
        case .reelsClips, .reelsStashLine: return false
        default: return true
        }
    }

    func sortedServerImageFilters(viewModel: StashDBViewModel) -> [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .images }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Picker-Zeile (`server:` / `local:`) so wählen, dass sie **immer** zu Einträgen im Filter-Sheet passt.
    /// Sonst zeigt SwiftUI bei `.menu` einen **leeren** Titel, obwohl `selectedFilter` noch gesetzt ist (z. B. Basis-Filter vs. Stashy-Wrapper, oder veraltete ID nach `savedFilters`-Reload).
    func resolvedCatalogPresetPickerRowId(viewModel: StashDBViewModel) -> String {
        let serverRows = sortedServerImageFilters(viewModel: viewModel)
        let serverById = Dictionary(uniqueKeysWithValues: serverRows.map { ($0.id, $0) })

        func localTagExists(_ tagged: String) -> Bool {
            guard let ls = ListLivePresetTag.parseLocalUUIDString(tagged),
                  let uuid = UUID(uuidString: ls) else { return false }
            return localCatalogPresets.contains(where: { $0.id == uuid })
        }

        func serverTagExists(_ tagged: String) -> Bool {
            guard let sid = ListLivePresetTag.parseServerId(tagged) else { return false }
            return serverById[sid] != nil
        }

        let trimmed = catalogPresetRowSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, serverTagExists(trimmed) || localTagExists(trimmed) {
            return trimmed
        }

        guard let base = selectedFilter else { return "" }

        if serverById[base.id] != nil {
            return ListLivePresetTag.serverRow(base.id)
        }

        let wrappers = serverRows
            .filter { $0.stashyCatalogPresetMetadata?.baseSavedFilterId == base.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if let w = wrappers.first {
            return ListLivePresetTag.serverRow(w.id)
        }
        return ""
    }

    /// Nach Server-Reload: gleiche Filter-ID, aktuelle Server-Struktur (verhindert hängende UI-Zustände).
    func rehydrateSelectedFilter(from viewModel: StashDBViewModel) {
        guard let f = selectedFilter else { return }
        if let fresh = viewModel.savedFilters[f.id] {
            selectedFilter = fresh
        }
    }

    func applyResolvedCatalogPresetPickerRowIfNeeded(viewModel: StashDBViewModel) {
        rehydrateSelectedFilter(from: viewModel)
        let next = resolvedCatalogPresetPickerRowId(viewModel: viewModel)
        if catalogPresetRowSelection != next {
            catalogPresetRowSelection = next
        }
    }

    /// Sheet open: migrate legacy IDs + sync Menu title row. Does **not** re-apply filters / refetch.
    func prepareCatalogFilterSortSheetUI(viewModel: StashDBViewModel) {
        var sel = catalogPresetRowSelection
        ListLivePresetTag.migrateLegacySelection(&sel)
        ignoreNextPresetSelectionChange = true
        if catalogPresetRowSelection != sel {
            catalogPresetRowSelection = sel
        }
        refreshLocalPresets()
        rehydrateSelectedFilter(from: viewModel)
        let next = resolvedCatalogPresetPickerRowId(viewModel: viewModel)
        if catalogPresetRowSelection != next {
            ignoreNextPresetSelectionChange = true
            catalogPresetRowSelection = next
        }
        DispatchQueue.main.async { [weak self] in
            self?.ignoreNextPresetSelectionChange = false
        }
    }


    private var activeLiveFilterDict: [String: Any] {
        var dict: [String: Any] = [:]
        if let fav = liveFilterPerformerFavorite { dict["performer_favorite"] = fav }
        if liveFilterMinRating == -1 {
            dict["rating100"] = ["modifier": "IS_NULL"]
        } else if liveFilterMinRating > 0 {
            dict["rating100"] = ["value": (liveFilterMinRating * 20), "modifier": "EQUALS"]
        }
        if liveFilterOrganized == "true" { dict["organized"] = true }
        if liveFilterOrganized == "false" { dict["organized"] = false }
        if let tag = liveFilterOCounterTag, let oc = sceneLiveOCounterCriterion(from: tag) {
            dict["o_counter"] = oc
        }
        if !liveFilterStudioIds.isEmpty {
            dict["studios"] = ["modifier": "INCLUDES", "value": liveFilterStudioIds, "depth": 0]
        }
        if !liveFilterTagIds.isEmpty {
            dict["tags"] = ["modifier": "INCLUDES", "value": liveFilterTagIds, "depth": 0]
        }
        if let pathCrit = liveFilterMediaKind.pathCriterion {
            if case .reelsStashLine = scope { /* images-only feed; ignore preset path */ } else {
                dict["path"] = pathCrit
            }
        }
        return dict
    }

    /// Passed to `filter:` only while the advanced editor holds no copy of it — otherwise the
    /// server filter would resurrect criteria the user edited away.
    var fetchBaseFilter: StashDBViewModel.SavedFilter? {
        criteriaDocument.isEmpty ? selectedFilter : nil
    }

    /// Quick chips merged with the advanced criteria editor — advanced criteria win per key.
    var effectiveLiveFilter: [String: Any]? {
        criteriaDocument.merged(with: isLiveFilterActive ? activeLiveFilterDict : [:])
    }

    func loadStudioPickerOptions(viewModel: StashDBViewModel) {
        guard !studioPickerLoading else { return }
        studioPickerLoading = true
        viewModel.fetchStudiosForLiveFilterPicker(mode: .imagesHasImages) { [weak self] list in
            guard let self else { return }
            self.studioPickerOptions = list
            self.studioPickerLoading = false
        }
    }

    func loadTagPickerOptions(viewModel: StashDBViewModel) {
        guard !tagPickerLoading else { return }
        tagPickerLoading = true
        viewModel.fetchTagsForImageLiveFilterPicker { [weak self] list in
            guard let self else { return }
            self.tagPickerOptions = list
            self.tagPickerLoading = false
        }
    }

    /// Non-nil when any live chip is set; merge into `fetchImages` / `fetchClips`.
    func imageLiveFragmentForFetch() -> [String: Any]? {
        effectiveLiveFilter
    }

    func refetchImages(viewModel: StashDBViewModel, initial: Bool) {
        let live = effectiveLiveFilter
        switch scope {
        case .catalogRoot:
            viewModel.fetchImages(
                sortBy: selectedSortOption,
                isInitialLoad: initial,
                filter: fetchBaseFilter,
                staticPathFilter: viewModel.imageStaticPathFilter,
                performerId: viewModel.imagePerformerIdFilter,
                liveFilter: live
            )
        case .performer(let id):
            viewModel.fetchDetailImages(performerId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .studio(let id):
            viewModel.fetchDetailImages(studioId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .tag(let id):
            viewModel.fetchDetailImages(tagId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .group(let id):
            viewModel.fetchDetailImages(groupId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .gallery(let id):
            viewModel.fetchGalleryImages(galleryId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: fetchBaseFilter, liveFilter: live)
        case .reelsStashLine:
            viewModel.fetchImages(
                sortBy: selectedSortOption,
                isInitialLoad: initial,
                filter: selectedFilter,
                staticPathFilter: true,
                performerId: reelsStashLinePerformerId,
                liveFilter: live
            )
        case .reelsClips:
            if let ext = externalRefetchClips {
                ext(viewModel)
            } else {
                viewModel.fetchClips(sortBy: selectedSortOption, filter: selectedFilter, isInitialLoad: initial, liveFilter: live)
            }
        }
    }

    func applyLiveFilter(viewModel: StashDBViewModel) {
        refetchImages(viewModel: viewModel, initial: true)
    }

    func refreshLocalPresets() {
        localCatalogPresets = ImageListLiveFilterPresetStore.loadPresets()
    }

    func clearLiveChipsOnly() {
        liveFilterPerformerFavorite = nil
        liveFilterMinRating = 0
        liveFilterOrganized = nil
        liveFilterOCounterTag = nil
        liveFilterStudioIds = []
        liveFilterTagIds = []
        liveFilterMediaKind = .all
    }

    func mapLiveFragmentToChips(_ frag: [String: Any]) {
        clearLiveChipsOnly()
        if let media = ImageListMediaKind.fromPathFragment(frag["path"]) {
            liveFilterMediaKind = media
        }
        if let fav = frag["performer_favorite"] as? Bool {
            liveFilterPerformerFavorite = fav
        }
        if let r = frag["rating100"] as? [String: Any] {
            let mod = (r["modifier"] as? String) ?? ""
            if mod == "IS_NULL" {
                liveFilterMinRating = -1
            } else if let raw = r["value"] {
                let v: Int? = {
                    if let i = raw as? Int { return i }
                    if let d = raw as? Double { return Int(d) }
                    if let n = raw as? NSNumber { return n.intValue }
                    return nil
                }()
                if let v {
                    liveFilterMinRating = max(0, min(5, v / 20))
                }
            }
        }
        if let o = frag["organized"] as? Bool {
            liveFilterOrganized = o ? "true" : "false"
        }
        if let oc = frag["o_counter"] as? [String: Any],
           let mod = oc["modifier"] as? String,
           let raw = oc["value"] {
            let v: Int? = {
                if let i = raw as? Int { return i }
                if let d = raw as? Double { return Int(d) }
                if let n = raw as? NSNumber { return n.intValue }
                return nil
            }()
            if let v {
                liveFilterOCounterTag = "\(mod):\(v)"
            }
        }
        liveFilterStudioIds = CatalogLiveChipFilterSupport.includesIds(fromCriterion: frag["studios"])
        liveFilterTagIds = CatalogLiveChipFilterSupport.includesIds(fromCriterion: frag["tags"])
    }

    /// Applies chip state from a normal Stash saved image filter (`filter_dict` and/or `object_filter`).
    func applyPlainImageSavedFilterToLiveChips(_ f: StashDBViewModel.SavedFilter) {
        let criteria = CatalogLiveChipFilterSupport.imageFilterCriteriaForLiveChipUI(from: f)
        guard !criteria.isEmpty else {
            clearLiveChipsOnly()
            return
        }
        if CatalogLiveChipFilterSupport.imageSavedFilterSupportsLiveEditor(f) {
            mapLiveFragmentToChips(criteria)
        } else {
            clearLiveChipsOnly()
            liveFilterStudioIds = CatalogLiveChipFilterSupport.includesIds(fromCriterion: criteria["studios"])
            liveFilterTagIds = CatalogLiveChipFilterSupport.includesIds(fromCriterion: criteria["tags"])
        }
    }

    /// Syncs live chip bindings from ``selectedFilter`` (e.g. default filter on catalog load).
    func syncLiveChipsFromSelectedFilter(viewModel: StashDBViewModel) {
        guard let f = selectedFilter else {
            clearLiveChipsOnly()
            return
        }
        if let meta = f.stashyCatalogPresetMetadata, !meta.liveFragment.isEmpty {
            let base: StashDBViewModel.SavedFilter?
            if let bid = meta.baseSavedFilterId, let b = viewModel.savedFilters[bid] {
                base = b
            } else {
                base = nil
            }
            if CatalogLiveChipFilterSupport.imageSavedFilterSupportsLiveEditor(base) {
                mapLiveFragmentToChips(meta.liveFragment)
            } else {
                clearLiveChipsOnly()
                liveFilterStudioIds = CatalogLiveChipFilterSupport.includesIds(fromCriterion: meta.liveFragment["studios"])
                liveFilterTagIds = CatalogLiveChipFilterSupport.includesIds(fromCriterion: meta.liveFragment["tags"])
            }
            return
        }
        // Empty (or missing) chip fragment: read the chips off the filter's own criteria. Without
        // this a filter whose tags live only in `object_filter` shows blank chips — and saving
        // from that state wrote the blank back over the tags.
        applyPlainImageSavedFilterToLiveChips(f)
    }

    func changeSortOption(to newOption: StashDBViewModel.ImageSortOption, viewModel: StashDBViewModel) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        if case .reelsStashLine = scope {
            TabManager.shared.setSortOption(for: .stashline, option: newOption.rawValue)
        }
        refetchImages(viewModel: viewModel, initial: true)
    }

    func applyCatalogPreset(_ preset: ImageListLiveFilterPreset, viewModel: StashDBViewModel) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.imageSavedFilterSupportsLiveEditor(selectedFilter) {
            mapLiveFragmentToChips(preset.liveFragment)
        } else {
            clearLiveChipsOnly()
            liveFilterStudioIds = CatalogLiveChipFilterSupport.includesIds(fromCriterion: preset.liveFragment["studios"])
            liveFilterTagIds = CatalogLiveChipFilterSupport.includesIds(fromCriterion: preset.liveFragment["tags"])
        }
        applyLiveFilter(viewModel: viewModel)
    }


    /// Mirrors a selected server filter into the advanced criteria editor so its criteria stay
    /// editable; fetches then pass `filter: nil` and send the document instead.
    private func loadCriteriaDocument(from filter: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = filter.stashyCatalogPresetMetadata {
            var merged: [String: Any] = [:]
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                merged = base.criteriaObjectFilter()
            }
            for (key, value) in FilterMapper.sanitize(meta.liveFragment, isMarker: false) {
                merged[key] = value
            }
            criteriaDocument.load(merged)
        } else {
            criteriaDocument.load(filter.criteriaObjectFilter())
        }
    }

    func applyServerSavedFilter(_ f: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.imageSavedFilterSupportsLiveEditor(selectedFilter) {
                mapLiveFragmentToChips(meta.liveFragment)
            } else {
                clearLiveChipsOnly()
                liveFilterStudioIds = CatalogLiveChipFilterSupport.includesIds(fromCriterion: meta.liveFragment["studios"])
                liveFilterTagIds = CatalogLiveChipFilterSupport.includesIds(fromCriterion: meta.liveFragment["tags"])
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.ImageSortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
            }
        } else {
            selectedFilter = f
            applyPlainImageSavedFilterToLiveChips(f)
        }
        loadCriteriaDocument(from: f, viewModel: viewModel)
        applyLiveFilter(viewModel: viewModel)
    }

    func handlePresetSelection(_ newId: String, viewModel: StashDBViewModel) {
        // Sheet picker and floating-bar filter Menu both drive this.
        // Cleared asynchronously after `prepareCatalogFilterSortSheetUI` so multi-step sync is covered.
        guard !ignoreNextPresetSelectionChange else { return }
        if newId.isEmpty {
            selectedFilter = nil
            clearLiveChipsOnly()
            criteriaDocument.clear()
            applyLiveFilter(viewModel: viewModel)
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: StashDBViewModel) {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func deletePresetConfirmationText(viewModel: StashDBViewModel) -> String {
        if let sid = ListLivePresetTag.parseServerId(catalogPresetRowSelection),
           let f = viewModel.savedFilters[sid] {
            return "Remove “\(f.name)” from Stash? Other devices will lose this saved filter."
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection),
           let uuid = UUID(uuidString: ls),
           let p = localCatalogPresets.first(where: { $0.id == uuid }) {
            return "Remove “\(p.name)” from this device? This cannot be undone."
        }
        return "Remove this filter? This cannot be undone."
    }

    func savePresetOverwrite(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            let name = viewModel.savedFilters[sid]?.name ?? "Filter"
            viewModel.saveCatalogSavedFilter(
                mode: .images,
                randomSeedKind: .images,
                existingId: sid,
                name: name,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { _ in }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let index = localCatalogPresets.firstIndex(where: { $0.id == uuid }) else { return }
        let old = localCatalogPresets[index]
        let updated = ImageListLiveFilterPreset(
            id: old.id,
            name: old.name,
            createdAt: old.createdAt,
            sort: selectedSortOption,
            baseSavedFilterId: selectedFilter?.id,
            liveFragment: activeLiveFilterDict
        )
        ImageListLiveFilterPresetStore.upsert(updated)
        refreshLocalPresets()
    }

    func savePresetAs(name: String, viewModel: StashDBViewModel) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveCatalogSavedFilter(
            mode: .images,
            randomSeedKind: .images,
            existingId: nil,
            name: trimmed,
            sortRaw: selectedSortOption.rawValue,
            sortField: selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            baseFilter: selectedFilter,
            liveFragment: activeLiveFilterDict
        ) { [weak self] result in
            guard let self else { return }
            if case .success(let saved) = result {
                self.catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                self.showSaveAsCatalogPresetAlert = false
            }
        }
    }

    func renamePreset(to newName: String, viewModel: StashDBViewModel) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.saveCatalogSavedFilter(
                mode: .images,
                randomSeedKind: .images,
                existingId: sid,
                name: trimmed,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { [weak self] result in
                if case .success = result { self?.showRenameCatalogPresetAlert = false }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = localCatalogPresets.first(where: { $0.id == uuid }) else { return }
        ImageListLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    func deletePreset(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { [weak self] result in
                guard let self else { return }
                if case .success = result {
                    if self.selectedFilter?.id == sid { self.selectedFilter = nil }
                    self.catalogPresetRowSelection = ""
                    self.showDeleteCatalogPresetAlert = false
                    self.refetchImages(viewModel: viewModel, initial: true)
                }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        ImageListLiveFilterPresetStore.remove(id: uuid)
        refreshLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }
}

#endif
