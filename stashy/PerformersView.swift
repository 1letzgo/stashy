//
//  PerformersView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI


private struct PerformersViewContent: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var configManager = ServerConfigManager.shared
    @State private var scrollPosition: String? = nil
    @State private var shouldRestoreScroll = false
    @State private var selectedSortOption: StashDBViewModel.PerformerSortOption
    @State private var isChangingSort = false
    @State private var searchText = ""
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil
    @State private var navigationPath = [Performer]()
    @State private var isSearchVisible = false
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Filter & sort sheet (unified)
    @State private var showFilterSortSheet = false
    @StateObject private var criteriaDocument = FilterCriteriaDocument(mode: .performers)
    @State private var catalogPresetRowSelection = ""
    @State private var localCatalogPresets: [PerformerListLiveFilterPreset] = PerformerListLiveFilterPresetStore.loadPresets()
    @State private var showSaveAsCatalogPresetAlert = false
    @State private var catalogPresetNameInput = ""
    @State private var showRenameCatalogPresetAlert = false
    @State private var renameCatalogPresetInput = ""
    @State private var showDeleteCatalogPresetAlert = false

    // Live filter state (chips)
    @State private var liveFilterAgeRange: String? = nil   // "18-21" / "22-26" / "26-30" / "30+"
    @State private var liveFilterHairColor: String? = nil  // "BLONDE" / "BRUNETTE" / "RED" / "BLACK"
    @State private var liveFilterGender: String? = nil     // "FEMALE" / "MALE" / "TRANSGENDER_FEMALE" / "TRANSGENDER_MALE" / "NON_BINARY"
    @State private var liveFilterCountry: String? = nil    // "US" / "NOT_US"
    @State private var liveFilterImplants: Bool? = nil     // nil=any, true=has, false=none
    @State private var liveFilterFavorite: Bool? = nil     // nil=any, true=yes, false=no
    @State private var liveFilterMissingField: String? = nil // nil=any, "image" / "gender" / "hair_color"
    @State private var liveFilterOCounterTag: String? = nil

    private var isLiveFilterActive: Bool {
        liveFilterAgeRange != nil || liveFilterHairColor != nil || liveFilterGender != nil
        || liveFilterCountry != nil || liveFilterImplants != nil || liveFilterFavorite != nil
        || liveFilterMissingField != nil || liveFilterOCounterTag != nil
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
        // Missing-field filter uses Stash's `is_missing: "<field>"` convention.
        // If explicitly set, it wins over `has_image` to avoid contradictory filters.
        if let missingField = liveFilterMissingField, !missingField.isEmpty {
            dict.removeValue(forKey: "has_image")
            dict["is_missing"] = missingField
        }
        if let tag = liveFilterOCounterTag, let oc = sceneLiveOCounterCriterion(from: tag) {
            dict["o_counter"] = oc
        }
        return dict
    }

    /// Passed to `filter:` only while the advanced editor holds no copy of it. Once the editor has
    /// the criteria, re-sending the server filter would resurrect criteria the user edited away;
    /// while it is empty (e.g. a default filter applied on appear) the filter still has to be sent.
    private var fetchBaseFilter: StashDBViewModel.SavedFilter? {
        criteriaDocument.isEmpty ? selectedFilter : nil
    }

    /// Quick chips plus advanced criteria from the editor — what actually gets fetched.
    private var effectiveLiveFilter: [String: Any]? {
        criteriaDocument.merged(with: isLiveFilterActive ? activeLiveFilterDict : [:])
    }

    private func applyLiveFilter() {
        viewModel.currentPerformerLiveFilter = effectiveLiveFilter ?? [:]
        viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: fetchBaseFilter, liveFilter: effectiveLiveFilter)
    }

    private var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive || !criteriaDocument.isEmpty || !catalogPresetRowSelection.isEmpty
    }

    private var sortedServerPerformerFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .performers }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    private func refreshPerformerLocalPresets() {
        localCatalogPresets = PerformerListLiveFilterPresetStore.loadPresets()
    }

    private func clearPerformerLiveChipsOnly() {
        liveFilterAgeRange = nil
        liveFilterHairColor = nil
        liveFilterGender = nil
        liveFilterCountry = nil
        liveFilterImplants = nil
        liveFilterFavorite = nil
        liveFilterMissingField = nil
        liveFilterOCounterTag = nil
    }

    private func mapPerformerLiveFragmentToChips(_ frag: [String: Any]) {
        clearPerformerLiveChipsOnly()
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
    }

    private func applyPerformerCatalogPreset(_ preset: PerformerListLiveFilterPreset) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
            TabManager.shared.setSortOption(for: .performers, option: preset.sort.rawValue)
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.performerSavedFilterSupportsLiveEditor(selectedFilter) {
            mapPerformerLiveFragmentToChips(preset.liveFragment)
        } else {
            clearPerformerLiveChipsOnly()
        }
        applyLiveFilter()
    }


    /// Mirrors a selected server filter into the advanced criteria editor so its criteria stay
    /// editable in the app; fetches then pass `filter: nil` and send the document instead.
    private func loadCriteriaDocument(from filter: StashDBViewModel.SavedFilter) {
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

    private func applyServerPerformerSavedFilter(_ f: StashDBViewModel.SavedFilter) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.performerSavedFilterSupportsLiveEditor(selectedFilter) {
                mapPerformerLiveFragmentToChips(meta.liveFragment)
            } else {
                clearPerformerLiveChipsOnly()
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.PerformerSortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
                TabManager.shared.setSortOption(for: .performers, option: parsed.rawValue)
            }
        } else {
            selectedFilter = f
            if CatalogLiveChipFilterSupport.performerSavedFilterSupportsLiveEditor(f), let raw = f.filterDict {
                mapPerformerLiveFragmentToChips(raw)
            } else {
                clearPerformerLiveChipsOnly()
            }
        }
        loadCriteriaDocument(from: f)
        applyLiveFilter()
    }

    private func applyCatalogPresetSelectionFromSheetIfNeeded() {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerPerformerSavedFilter(f)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyPerformerCatalogPreset(preset)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyPerformerCatalogPreset(preset)
        }
    }

    private var deleteCatalogPresetConfirmationText: String {
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

    private func savePerformerCatalogPresetOverwrite() {
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
        refreshPerformerLocalPresets()
    }

    private func savePerformerCatalogPresetAs(name: String) {
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
        ) { result in
            if case .success(let saved) = result {
                catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                showSaveAsCatalogPresetAlert = false
            }
        }
    }

    private func renamePerformerCatalogPreset(to newName: String) {
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
            ) { result in
                if case .success = result {
                    showRenameCatalogPresetAlert = false
                }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = localCatalogPresets.first(where: { $0.id == uuid }) else { return }
        let renamed = preset.renamed(trimmed)
        PerformerListLiveFilterPresetStore.upsert(renamed)
        refreshPerformerLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    private func deletePerformerCatalogPreset() {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { result in
                if case .success = result {
                    if selectedFilter?.id == sid {
                        selectedFilter = nil
                    }
                    catalogPresetRowSelection = ""
                    showDeleteCatalogPresetAlert = false
                    performSearch()
                }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        PerformerListLiveFilterPresetStore.remove(id: uuid)
        refreshPerformerLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }

    init(viewModel: StashDBViewModel, initialSort: StashDBViewModel.PerformerSortOption? = nil) {
        self.viewModel = viewModel
        let savedSort = StashDBViewModel.PerformerSortOption(rawValue: TabManager.shared.getSortOption(for: .performers) ?? "")
        _selectedSortOption = State(initialValue: initialSort ?? savedSort ?? .sceneCountDesc)
    }
    
    @State private var gridWidth: CGFloat = 0

    /// Spalten aus der gemessenen Breite: iPhone bleibt bei 2, iPad/Querformat füllen die Fläche.
    private var columns: [GridItem] {
        DesignTokens.Grid.adaptiveColumns(
            width: gridWidth,
            ideal: DesignTokens.Grid.idealPosterCardWidth,
            minimum: 2,
            maximum: 8
        )
    }

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.PerformerSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        scrollPosition = nil
        shouldRestoreScroll = false
        
        // Save to TabManager
        TabManager.shared.setSortOption(for: .performers, option: newOption.rawValue)

        // Fetch new data immediately
        viewModel.fetchPerformers(sortBy: newOption, searchQuery: searchText, filter: fetchBaseFilter, liveFilter: effectiveLiveFilter)
    }
    
    // Search function with debouncing
    private func performSearch() {
        scrollPosition = nil
        shouldRestoreScroll = false
        viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: fetchBaseFilter, liveFilter: effectiveLiveFilter)
    }

    var body: some View {
        performersCoreChrome
            .sheet(isPresented: $showFilterSortSheet, content: performersFilterSortSheet)
            .onChange(of: catalogPresetRowSelection) { _, newId in
                handlePerformerCatalogPresetSelectionChange(newId)
            }
            .alert("Save As", isPresented: $showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $catalogPresetNameInput)
                Button("Save") { savePerformerCatalogPresetAs(name: catalogPresetNameInput) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $showRenameCatalogPresetAlert) {
                TextField("Name", text: $renameCatalogPresetInput)
                Button("Save") { renamePerformerCatalogPreset(to: renameCatalogPresetInput) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { deletePerformerCatalogPreset() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteCatalogPresetConfirmationText)
            }
            .onAppear {
                performersOnAppear()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
                selectedFilter = nil
                catalogPresetRowSelection = ""
                refreshPerformerLocalPresets()
                performSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
                if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.performers.rawValue {
                    if let defaultId = TabManager.shared.getDefaultFilterId(for: .performers),
                       let newFilter = viewModel.savedFilters[defaultId] {
                        selectedFilter = newFilter
                    } else {
                        selectedFilter = nil
                    }
                    performSearch()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
                if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.performers.rawValue {
                    let newSort = StashDBViewModel.PerformerSortOption(rawValue: TabManager.shared.getPersistentSortOption(for: .performers) ?? "") ?? .sceneCountDesc
                    changeSortOption(to: newSort)
                }
            }
            .onChange(of: viewModel.savedFilters) { oldValue, newValue in
                if selectedFilter == nil {
                    if let defaultId = TabManager.shared.getDefaultFilterId(for: .performers),
                       let filter = newValue[defaultId] {
                        selectedFilter = filter
                        if viewModel.performers.isEmpty {
                            viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: filter)
                        }
                    } else if !viewModel.isLoadingSavedFilters {
                        if viewModel.performers.isEmpty {
                            viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: nil)
                        }
                    }
                }
            }
            .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
                if oldValue == true && isLoading == false {
                    if viewModel.performers.isEmpty && !viewModel.isLoadingPerformers && selectedFilter == nil {
                        viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: nil)
                    }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { coordinator.performerToOpen != nil },
                set: { if !$0 { coordinator.performerToOpen = nil } }
            )) {
                if let performer = coordinator.performerToOpen {
                    PerformerDetailView(performer: performer)
                }
            }
    }

    @ViewBuilder
    private var performersCoreChrome: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.isLoading && viewModel.performers.isEmpty {
                StandardLoadingView(message: "Loading performers...")
            } else if viewModel.performers.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.performers.isEmpty {
                emptyStateView
            } else {
                performersGrid
            }
        }
        .navigationTitle("Performers")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .onChange(of: searchText) { oldValue, newValue in
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if newValue == self.searchText {
                    self.performSearch()
                }
            }
        }
        .toolbar {
            if !searchText.isEmpty {
                ToolbarItem(placement: .principal) {
                    Button(action: {
                        searchText = ""
                        performSearch()
                    }) {
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
        .floatingActionBar(isPresented: true, catalogChrome: CatalogFloatingChromeState(hasActiveServerConfig: configManager.activeConfig != nil, primaryListIsEmpty: viewModel.performers.isEmpty, errorMessage: viewModel.errorMessage)) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                CatalogFilterFABButton(isActive: catalogFilterSortFABActive) {
                    showFilterSortSheet = true
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func performersFilterSortSheet() -> some View {
        PerformersCatalogFilterSortSheet(
            serverFilters: sortedServerPerformerFilters,
            localPresets: localCatalogPresets,
            selectedPresetRowId: $catalogPresetRowSelection,
            criteriaDocument: criteriaDocument,
            sortOption: selectedSortOption,
            onSortChange: { changeSortOption(to: $0) },
            liveAgeRange: $liveFilterAgeRange,
            liveHairColor: $liveFilterHairColor,
            liveGender: $liveFilterGender,
            liveCountry: $liveFilterCountry,
            liveImplants: $liveFilterImplants,
            liveFavorite: $liveFilterFavorite,
            liveMissingField: $liveFilterMissingField,
            liveOCounterTag: $liveFilterOCounterTag,
            onApply: { applyLiveFilter() },
            onReset: {
                catalogPresetRowSelection = ""
                selectedFilter = nil
                clearPerformerLiveChipsOnly()
                criteriaDocument.clear()
                applyLiveFilter()
            },
            onRequestSave: { savePerformerCatalogPresetOverwrite() },
            onRequestSaveAs: {
                catalogPresetNameInput = ""
                showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = localCatalogPresets.first(where: { $0.id == uuid }) {
                    renameCatalogPresetInput = p.name
                }
                showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            ListLivePresetTag.migrateLegacySelection(&catalogPresetRowSelection)
            refreshPerformerLocalPresets()
            applyCatalogPresetSelectionFromSheetIfNeeded()
        }
    }

    private func handlePerformerCatalogPresetSelectionChange(_ newId: String) {
        guard showFilterSortSheet else { return }
        if newId.isEmpty {
            selectedFilter = nil
            clearPerformerLiveChipsOnly()
            applyLiveFilter()
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerPerformerSavedFilter(f)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyPerformerCatalogPreset(preset)
        }
    }

    private func performersOnAppear() {
        var forceRefresh = false
        if let injectedSortStr = coordinator.activeSortOption,
           let injectedSort = StashDBViewModel.PerformerSortOption(rawValue: injectedSortStr) {
            selectedSortOption = injectedSort
            coordinator.activeSortOption = nil
            forceRefresh = true
        }
        if !coordinator.activeSearchText.isEmpty {
            searchText = coordinator.activeSearchText
            isSearchVisible = true
            coordinator.activeSearchText = ""
            viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: fetchBaseFilter, liveFilter: effectiveLiveFilter)
            viewModel.fetchSavedFilters()
            return
        }
        if TabManager.shared.getDefaultFilterId(for: .performers) == nil || !viewModel.savedFilters.isEmpty {
            if forceRefresh || viewModel.performers.isEmpty {
                performSearch()
            }
        }
        viewModel.fetchSavedFilters()
    }

    private var emptyStateView: some View {
         SharedEmptyStateView(
             icon: "person.3",
             title: "No performers found",
             buttonText: "Load Performers",
             onRetry: { performSearch() }
         )
    }

    private var performersGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.performers) { performer in
                        NavigationLink(destination: PerformerDetailView(performer: performer)) {
                            PerformerCardView(
                                performer: performer,
                                badgeType: .forSort(selectedSortOption)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(performer.id)
                    }

                    // Loading indicator for pagination
                    if viewModel.isLoadingMorePerformers {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if viewModel.hasMorePerformers && !viewModel.performers.isEmpty {
                        // Invisible element to trigger loading more performers
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                // Save scroll position before loading - use element around 3/4 of current list
                                let currentCount = viewModel.performers.count
                                if currentCount > 4 {
                                    let targetIndex = currentCount * 3 / 4
                                    if targetIndex < currentCount {
                                        scrollPosition = viewModel.performers[targetIndex].id
                                        shouldRestoreScroll = true
                                    }
                                } else if let lastPerformer = viewModel.performers.last {
                                    scrollPosition = lastPerformer.id
                                    shouldRestoreScroll = true
                                }
                                viewModel.loadMorePerformers()
                            }
                            .id("pagination-trigger")
                    }
                }
                .measuresGridWidth($gridWidth)
                .padding(16)
            }
            .refreshable { performSearch() }
            .onChange(of: viewModel.isLoadingMorePerformers) { oldValue, isLoading in
                if !isLoading && shouldRestoreScroll {
                    // Loading completed, restore scroll position
                    if let scrollPosition = scrollPosition {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(scrollPosition, anchor: .top)
                            }
                            shouldRestoreScroll = false
                        }
                    }
                }
            }
        }
    }
}


struct PerformerCardView: View {
    let performer: Performer
    var badgeType: PerformerBadgeType = .sceneCount
    @ObservedObject var appearanceManager = AppearanceManager.shared

    private var ageText: String? {
        guard let b = performer.birthdate, !b.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        guard let birthDate = fmt.date(from: b) else { return nil }
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
        guard let y = years, y > 0, y < 120 else { return nil }
        return "\(y)"
    }

    private var countBadgeIcon: String {
        switch badgeType {
        case .sceneCount: return "film"
        case .imageCount: return "photo"
        case .galleryCount: return "photo.stack"
        case .oCount: return appearanceManager.oCounterIcon
        case .rating: return "star.fill"
        }
    }

    private var countBadgeText: String {
        switch badgeType {
        case .sceneCount: return "\(performer.sceneCount)"
        case .imageCount: return "\(performer.imageCount ?? 0)"
        case .galleryCount: return "\(performer.galleryCount ?? 0)"
        case .oCount: return "\(performer.oCounter ?? 0)"
        case .rating: return "\(performer.rating100 ?? 0)"
        }
    }

    var body: some View {
        // Wie `ImageThumbnailCard`: Bild in Zelle mit fester `geometry`-Fläche + `clipped()`,
        // damit `scaledToFill` den Hit-Test / Layout nicht sprengt; Root `contentShape`
        // begrenzt Touches auf die sichtbare Karte (siehe ImagesView).
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))

                        if let thumbnailURL = performer.thumbnailURL {
                            CustomAsyncImage(url: thumbnailURL) { loader in
                                if loader.isLoading {
                                    ProgressView()
                                } else if let image = loader.image {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Image(systemName: "person.fill")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: min(120, geometry.size.height * 0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)

                    VStack {
                        HStack(alignment: .top, spacing: 4) {
                            if let ageText {
                                cardPill(icon: "calendar", text: ageText)
                            }

                            Spacer(minLength: 4)

                            cardPill(icon: countBadgeIcon, text: countBadgeText)
                        }
                        .padding(8)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .bottom, spacing: 6) {
                            Text(performer.name)
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                }
            }
            .aspectRatio(9/12, contentMode: .fit)
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }

    private func cardPill(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(DesignTokens.Opacity.badge))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 2)
    }
}

// Keep old row view for compatibility
struct PerformerRowView: View {
    let performer: Performer

    var body: some View {
        PerformerCardView(performer: performer)
    }
}

struct PerformersView: View {
    @StateObject private var ownedViewModel = StashDBViewModel()
    let catalogBrowserViewModel: StashDBViewModel?
    let initialSort: StashDBViewModel.PerformerSortOption?

    init(initialSort: StashDBViewModel.PerformerSortOption? = nil, catalogBrowserViewModel: StashDBViewModel? = nil) {
        self.catalogBrowserViewModel = catalogBrowserViewModel
        self.initialSort = initialSort
    }

    var body: some View {
        PerformersViewContent(
            viewModel: catalogBrowserViewModel ?? ownedViewModel,
            initialSort: initialSort
        )
    }
}

#Preview {
    PerformersView()
}
#endif
