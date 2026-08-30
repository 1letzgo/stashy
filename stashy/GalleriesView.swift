#if !os(tvOS)
//
//  GalleriesView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI
import AVKit
import AVFoundation

private struct GalleriesViewContent: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.GallerySortOption = StashDBViewModel.GallerySortOption(rawValue: TabManager.shared.getSortOption(for: .galleries) ?? "") ?? .dateDesc
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var scrollPosition: String? = nil
    @State private var shouldRestoreScroll = false
    var hideTitle: Bool = false

    @State private var showFilterSortSheet = false
    @StateObject private var criteriaDocument = FilterCriteriaDocument(mode: .galleries)
    @State private var catalogPresetRowSelection = ""
    @State private var localCatalogPresets: [GalleryListLiveFilterPreset] = GalleryListLiveFilterPresetStore.loadPresets()
    @State private var showSaveAsCatalogPresetAlert = false
    @State private var catalogPresetNameInput = ""
    @State private var showRenameCatalogPresetAlert = false
    @State private var renameCatalogPresetInput = ""
    @State private var showDeleteCatalogPresetAlert = false
    @State private var liveFilterFavorite: Bool?
    @State private var liveFilterMinRating: Int = 0
    @State private var liveFilterFiles: String?
    @State private var liveFilterStudioId: String?
    @State private var studioPickerOptions: [Studio] = []
    @State private var studioPickerLoading = false

    private var isLiveFilterActive: Bool {
        liveFilterFavorite != nil || liveFilterMinRating != 0 || liveFilterFiles != nil || liveFilterStudioId != nil
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

    private var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive || !criteriaDocument.isEmpty || !catalogPresetRowSelection.isEmpty
    }

    private var sortedServerGalleryFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .galleries }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    private func refreshGalleryLocalPresets() {
        localCatalogPresets = GalleryListLiveFilterPresetStore.loadPresets()
    }

    private func clearGalleryLiveChipsOnly() {
        liveFilterFavorite = nil
        liveFilterMinRating = 0
        liveFilterFiles = nil
        liveFilterStudioId = nil
    }

    private func loadGalleryStudioPickerOptions() {
        guard !studioPickerLoading else { return }
        studioPickerLoading = true
        viewModel.fetchStudiosForLiveFilterPicker(mode: .galleriesHasGalleries) { list in
            studioPickerOptions = list
            studioPickerLoading = false
        }
    }

    private func mapGalleryLiveFragmentToChips(_ frag: [String: Any]) {
        clearGalleryLiveChipsOnly()
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

    private func applyLiveFilter() {
        viewModel.currentGalleryLiveFilter = effectiveLiveFilter ?? [:]
        performSearch()
    }

    private func applyGalleryCatalogPreset(_ preset: GalleryListLiveFilterPreset) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
            TabManager.shared.setSortOption(for: .galleries, option: preset.sort.rawValue)
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.gallerySavedFilterSupportsLiveEditor(selectedFilter) {
            mapGalleryLiveFragmentToChips(preset.liveFragment)
        } else {
            clearGalleryLiveChipsOnly()
        }
        performSearch()
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

    private func applyServerGallerySavedFilter(_ f: StashDBViewModel.SavedFilter) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.gallerySavedFilterSupportsLiveEditor(selectedFilter) {
                mapGalleryLiveFragmentToChips(meta.liveFragment)
            } else {
                clearGalleryLiveChipsOnly()
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.GallerySortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
                TabManager.shared.setSortOption(for: .galleries, option: parsed.rawValue)
            }
        } else {
            selectedFilter = f
            if CatalogLiveChipFilterSupport.gallerySavedFilterSupportsLiveEditor(f), let raw = f.filterDict {
                mapGalleryLiveFragmentToChips(raw)
            } else {
                clearGalleryLiveChipsOnly()
            }
        }
        loadCriteriaDocument(from: f)
        performSearch()
    }

    private func applyCatalogPresetSelectionFromSheetIfNeeded() {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerGallerySavedFilter(f)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyGalleryCatalogPreset(preset)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyGalleryCatalogPreset(preset)
        }
    }

    private var deleteGalleryCatalogPresetConfirmationText: String {
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

    private func saveGalleryCatalogPresetOverwrite() {
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
        refreshGalleryLocalPresets()
    }

    private func saveGalleryCatalogPresetAs(name: String) {
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
        ) { result in
            if case .success(let saved) = result {
                catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                showSaveAsCatalogPresetAlert = false
            }
        }
    }

    private func renameGalleryCatalogPreset(to newName: String) {
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
        GalleryListLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshGalleryLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    private func deleteGalleryCatalogPreset() {
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
        GalleryListLiveFilterPresetStore.remove(id: uuid)
        refreshGalleryLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }

    private func handleGalleryCatalogPresetSelectionChange(_ newId: String) {
        // Sheet picker and floating-bar filter Menu both drive this.
        if newId.isEmpty {
            selectedFilter = nil
            clearGalleryLiveChipsOnly()
            applyLiveFilter()
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerGallerySavedFilter(f)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyGalleryCatalogPreset(preset)
        }
    }
    
    init(viewModel: StashDBViewModel, initialSort: StashDBViewModel.GallerySortOption? = nil, hideTitle: Bool = false) {
        self.viewModel = viewModel
        self.hideTitle = hideTitle
        let savedSort = StashDBViewModel.GallerySortOption(rawValue: TabManager.shared.getSortOption(for: .galleries) ?? "")
        _selectedSortOption = State(initialValue: initialSort ?? savedSort ?? .dateDesc)
    }
    
    @ObservedObject private var tabManager = TabManager.shared

    @State private var cardGridWidth: CGFloat = 0


    private var columns: [GridItem] {
        tabManager.catalogCardColumns(for: CatalogCardColumnScope.galleries).gridItems(width: cardGridWidth)
    }

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.GallerySortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        scrollPosition = nil
        shouldRestoreScroll = false
        
        // Save to TabManager
        TabManager.shared.setSortOption(for: .galleries, option: newOption.rawValue)
        
        // Fetch new data immediately
        viewModel.fetchGalleries(
            sortBy: newOption,
            searchQuery: searchText,
            isInitialLoad: true,
            filter: fetchBaseFilter,
            liveFilter: effectiveLiveFilter
        )
    }

    private func performSearch(isInitialLoad: Bool = true) {
        viewModel.fetchGalleries(
            sortBy: selectedSortOption,
            searchQuery: searchText,
            isInitialLoad: isInitialLoad,
            filter: fetchBaseFilter,
            liveFilter: effectiveLiveFilter
        )
    }

    var body: some View {
        galleriesCoreChrome
            .sheet(isPresented: $showFilterSortSheet, content: galleriesFilterSortSheet)
            .onChange(of: catalogPresetRowSelection) { _, newId in
                handleGalleryCatalogPresetSelectionChange(newId)
            }
            .alert("Save As", isPresented: $showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $catalogPresetNameInput)
                Button("Save") { saveGalleryCatalogPresetAs(name: catalogPresetNameInput) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $showRenameCatalogPresetAlert) {
                TextField("Name", text: $renameCatalogPresetInput)
                Button("Save") { renameGalleryCatalogPreset(to: renameCatalogPresetInput) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { deleteGalleryCatalogPreset() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteGalleryCatalogPresetConfirmationText)
            }
    }

    @ViewBuilder
    private var galleriesPrimaryContent: some View {
        if configManager.activeConfig == nil {
            ConnectionErrorView { performSearch() }
        } else if viewModel.isLoadingGalleries && viewModel.galleries.isEmpty {
            StandardLoadingView(message: "Loading galleries...")
        } else if viewModel.galleries.isEmpty && viewModel.errorMessage != nil {
            ConnectionErrorView { performSearch() }
        } else if viewModel.galleries.isEmpty {
            SharedEmptyStateView(
                icon: "photo.stack",
                title: "No galleries found",
                buttonText: "Reload",
                onRetry: { performSearch() }
            )
        } else {
            galleriesGridScroll
        }
    }

    private var galleriesGridScroll: some View {
        let cardColumns = tabManager.catalogCardColumns(for: CatalogCardColumnScope.galleries)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.galleries) { gallery in
                    NavigationLink(destination: ImagesView(gallery: gallery)) {
                        GalleryCardView(
                            gallery: gallery,
                            aspectRatio: cardColumns.cardAspectRatio
                        )
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.isLoadingGalleries {
                    ProgressView()
                        .padding()
                } else if viewModel.hasMoreGalleries {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            viewModel.loadMoreGalleries(searchQuery: searchText)
                        }
                }
            }
            .measuresGridWidth($cardGridWidth)
            .id(cardColumns)
            .padding(16)
        }
        .background(Color.appBackground)
        .refreshable { performSearch() }
    }

    private var galleriesFloatingBarChrome: CatalogFloatingChromeState {
        CatalogFloatingChromeState(
            hasActiveServerConfig: configManager.activeConfig != nil,
            primaryListIsEmpty: viewModel.galleries.isEmpty,
            errorMessage: viewModel.errorMessage
        )
    }

    @ViewBuilder
    private var galleriesFloatingBarContent: some View {
        let cardColumns = tabManager.catalogCardColumns(for: CatalogCardColumnScope.galleries)
        let filterMenuActive = selectedFilter != nil || !catalogPresetRowSelection.isEmpty
        HStack(spacing: 0) {
            CatalogFABIconButton(
                systemImage: cardColumns.toggleIcon,
                accessibilityLabel: cardColumns.accessibilityLabel,
                accessibilityHint: "Switches between one and two cards per row"
            ) {
                withAnimation(DesignTokens.Animation.quick) {
                    tabManager.toggleCatalogCardColumns(for: CatalogCardColumnScope.galleries)
                }
            }
            .frame(maxWidth: .infinity)

            Menu {
                Button {
                    catalogPresetRowSelection = ""
                } label: {
                    HStack {
                        Text("No Filter")
                        if catalogPresetRowSelection.isEmpty && selectedFilter == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                let serverFilters = sortedServerGalleryFilters
                if !serverFilters.isEmpty {
                    Section("Saved Filters") {
                        ForEach(serverFilters) { filter in
                            Button {
                                catalogPresetRowSelection = ListLivePresetTag.serverRow(filter.id)
                            } label: {
                                HStack {
                                    Text(filter.name)
                                    if catalogPresetRowSelection == ListLivePresetTag.serverRow(filter.id)
                                        || (catalogPresetRowSelection.isEmpty && selectedFilter?.id == filter.id) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                if !localCatalogPresets.isEmpty {
                    Section("Presets") {
                        ForEach(localCatalogPresets) { preset in
                            Button {
                                catalogPresetRowSelection = ListLivePresetTag.localRow(preset.id)
                            } label: {
                                HStack {
                                    Text(preset.name)
                                    if catalogPresetRowSelection == ListLivePresetTag.localRow(preset.id) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                CatalogQuickFilterFABLabel(isActive: filterMenuActive)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Filter")
            .accessibilityHint("Chooses a saved filter or preset")

            CatalogFilterFABButton(isActive: catalogFilterSortFABActive) {
                showFilterSortSheet = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var galleriesCoreChrome: some View {
        galleriesPrimaryContent
            .applyAppBackground()
            .modifier(GalleriesEmbeddedNavigationChrome(
                hideTitle: hideTitle,
                isSearchVisible: isSearchVisible,
                searchText: $searchText,
                onClearSearch: { performSearch() }
            ))
            .onChange(of: searchText) { _, newValue in
                NSObject.cancelPreviousPerformRequests(withTarget: self)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if newValue == self.searchText {
                        performSearch()
                    }
                }
            }
            .floatingActionBar(isPresented: true, catalogChrome: galleriesFloatingBarChrome) {
                galleriesFloatingBarContent
            }
            .onAppear(perform: handleGalleriesAppear)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
                handleGalleriesDefaultFilterChanged(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
                handleGalleriesDefaultSortChanged(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
                selectedFilter = nil
                catalogPresetRowSelection = ""
                clearGalleryLiveChipsOnly()
                refreshGalleryLocalPresets()
                performSearch()
            }
            .onChange(of: viewModel.savedFilters) { _, newValue in
                handleGalleriesSavedFiltersChanged(newValue)
            }
            .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
                if oldValue == true && isLoading == false, !viewModel.isLoadingGalleries {
                    if applyGalleriesDefaultFilterFromSettingsIfNeeded(force: false) {
                        performSearch()
                    } else if viewModel.galleries.isEmpty, selectedFilter == nil {
                        performSearch()
                    }
                }
            }
    }

    private func syncGalleryLiveChipsFromSelectedFilter() {
        guard let f = selectedFilter else {
            clearGalleryLiveChipsOnly()
            return
        }
        if let meta = f.stashyCatalogPresetMetadata {
            if CatalogLiveChipFilterSupport.gallerySavedFilterSupportsLiveEditor(
                meta.baseSavedFilterId.flatMap { viewModel.savedFilters[$0] }
            ) {
                mapGalleryLiveFragmentToChips(meta.liveFragment)
            } else {
                clearGalleryLiveChipsOnly()
            }
            return
        }
        if CatalogLiveChipFilterSupport.gallerySavedFilterSupportsLiveEditor(f), let raw = f.filterDict {
            mapGalleryLiveFragmentToChips(raw)
        } else {
            clearGalleryLiveChipsOnly()
        }
    }

    /// Applies Settings → Default Filters for Galleries. Returns `true` if selection changed.
    @discardableResult
    private func applyGalleriesDefaultFilterFromSettingsIfNeeded(force: Bool) -> Bool {
        if !force, selectedFilter != nil { return false }

        if let defaultId = TabManager.shared.getDefaultFilterId(for: .galleries),
           let filter = viewModel.savedFilters[defaultId] {
            let already =
                selectedFilter?.id == filter.id
                && catalogPresetRowSelection == ListLivePresetTag.serverRow(filter.id)
            selectedFilter = filter
            catalogPresetRowSelection = ListLivePresetTag.serverRow(filter.id)
            syncGalleryLiveChipsFromSelectedFilter()
            return force || !already
        }

        if force {
            let hadSelection = selectedFilter != nil || !catalogPresetRowSelection.isEmpty
            selectedFilter = nil
            catalogPresetRowSelection = ""
            clearGalleryLiveChipsOnly()
            return hadSelection
        }
        return false
    }

    private func handleGalleriesAppear() {
        var forceRefresh = false
        if let injectedSortStr = coordinator.activeSortOption,
           let injectedSort = StashDBViewModel.GallerySortOption(rawValue: injectedSortStr) {
            selectedSortOption = injectedSort
            viewModel.currentGallerySortOption = injectedSort
            coordinator.activeSortOption = nil
            forceRefresh = true
        } else {
            let defaultSortStr = TabManager.shared.getSortOption(for: .galleries) ?? "dateDesc"
            if let defaultSort = StashDBViewModel.GallerySortOption(rawValue: defaultSortStr) {
                selectedSortOption = defaultSort
                viewModel.currentGallerySortOption = defaultSort
            }
        }

        if !coordinator.activeSearchText.isEmpty {
            searchText = coordinator.activeSearchText
            isSearchVisible = true
            coordinator.activeSearchText = ""
            performSearch()
            viewModel.fetchSavedFilters()
            return
        }

        let appliedDefault = applyGalleriesDefaultFilterFromSettingsIfNeeded(force: false)
        let defaultPending = TabManager.shared.getDefaultFilterId(for: .galleries) != nil && viewModel.savedFilters.isEmpty
        if !defaultPending, (forceRefresh || appliedDefault || viewModel.galleries.isEmpty) {
            performSearch()
        }
        viewModel.fetchSavedFilters()
    }

    private func handleGalleriesDefaultFilterChanged(_ notification: Notification) {
        guard let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.galleries.rawValue else { return }
        _ = applyGalleriesDefaultFilterFromSettingsIfNeeded(force: true)
        performSearch()
    }

    private func handleGalleriesDefaultSortChanged(_ notification: Notification) {
        guard let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.galleries.rawValue else { return }
        let newSort = StashDBViewModel.GallerySortOption(rawValue: TabManager.shared.getPersistentSortOption(for: .galleries) ?? "") ?? .dateDesc
        changeSortOption(to: newSort)
    }

    private func handleGalleriesSavedFiltersChanged(_ newValue: [String: StashDBViewModel.SavedFilter]) {
        _ = newValue
        if applyGalleriesDefaultFilterFromSettingsIfNeeded(force: false) {
            performSearch()
        } else if !viewModel.isLoadingSavedFilters, viewModel.galleries.isEmpty, selectedFilter == nil {
            performSearch()
        }
    }

    @ViewBuilder
    private func galleriesFilterSortSheet() -> some View {
        GalleriesCatalogFilterSortSheet(
            serverFilters: sortedServerGalleryFilters,
            localPresets: localCatalogPresets,
            selectedPresetRowId: $catalogPresetRowSelection,
            criteriaDocument: criteriaDocument,
            sortOption: selectedSortOption,
            onSortChange: { changeSortOption(to: $0) },
            liveMinRating: $liveFilterMinRating,
            liveFavorite: $liveFilterFavorite,
            liveFiles: $liveFilterFiles,
            liveStudioId: $liveFilterStudioId,
            studioPickerOptions: studioPickerOptions,
            studioPickerLoading: studioPickerLoading,
            onStudioPickerSectionAppear: { loadGalleryStudioPickerOptions() },
            onApply: { applyLiveFilter() },
            onReset: {
                catalogPresetRowSelection = ""
                selectedFilter = nil
                clearGalleryLiveChipsOnly()
                criteriaDocument.clear()
                applyLiveFilter()
            },
            onRequestSave: { saveGalleryCatalogPresetOverwrite() },
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
            refreshGalleryLocalPresets()
            applyCatalogPresetSelectionFromSheetIfNeeded()
        }
    }
}

/// When embedded under custom chrome (`hideTitle`), keep the system nav bar hidden.
private struct GalleriesEmbeddedNavigationChrome: ViewModifier {
    let hideTitle: Bool
    let isSearchVisible: Bool
    @Binding var searchText: String
    var onClearSearch: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if hideTitle {
            content.hideSystemNavigationBarForCustomChrome()
        } else {
            content
                .navigationTitle("Galleries")
                .navigationBarTitleDisplayMode(.inline)
                .conditionalSearchable(isVisible: isSearchVisible, text: $searchText, prompt: "Search galleries...")
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
                                .padding(Edge.Set.horizontal, 10)
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

struct GalleriesView: View {
    @StateObject private var ownedViewModel = StashDBViewModel()
    let catalogBrowserViewModel: StashDBViewModel?
    let initialSort: StashDBViewModel.GallerySortOption?
    var hideTitle: Bool = false

    init(initialSort: StashDBViewModel.GallerySortOption? = nil, hideTitle: Bool = false, catalogBrowserViewModel: StashDBViewModel? = nil) {
        self.catalogBrowserViewModel = catalogBrowserViewModel
        self.initialSort = initialSort
        self.hideTitle = hideTitle
    }

    var body: some View {
        GalleriesViewContent(
            viewModel: catalogBrowserViewModel ?? ownedViewModel,
            initialSort: initialSort,
            hideTitle: hideTitle
        )
    }
}

struct GalleryCardView: View {
    let gallery: Gallery
    var aspectRatio: CGFloat = 1
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay(
                GeometryReader { geometry in
                    ZStack(alignment: .bottomLeading) {
                        // Image (fills the card bounds)
                        ZStack {
                            Color.gray.opacity(0.2)

                            if let url = gallery.coverURL {
                                CustomAsyncImage(url: url) { loader in
                                    if loader.isLoading {
                                        ProgressView()
                                    } else if let image = loader.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.system(size: 40))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        
                        // Gradient Overlay
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: geometry.size.height * 0.4)
                        
                        // Badges Overlay Layer — fixed fonts like SceneCardView / ImageThumbnailCard
                        VStack {
                            HStack(alignment: .top) {
                                // Studio Badge (Top Left)
                                if let studio = gallery.studio {
                                    Text(studio.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                        .clipShape(Capsule())
                                }
                                
                                Spacer()
                                
                                if let count = gallery.imageCount, count > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "photo.stack")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Text("\(count)")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(8)
                            
                            Spacer()
                            
                            HStack(alignment: .bottom) {
                                Text(gallery.displayName)
                                    .font(.headline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                        }
                    }
                }
            )
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)) // Ensure hit testing works on entire card
            .cardShadow()
            .id(aspectRatio)
    }
}

// MARK: - Gallery Item View (Feeds-style per-item view)

struct GalleryItemView: View {
    let image: StashImage
    @Binding var isMuted: Bool
    @ObservedObject var viewModel: StashDBViewModel
    @Binding var images: [StashImage]
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Binding var showUI: Bool
    @Binding var isZoomed: Bool
    /// Live binding (like Feeds `currentVisibleSceneId`) so the time-observer sees the active page.
    @Binding var currentVisibleId: String?
    let fallbackActiveId: String
    @Binding var isPlaying: Bool
    let scrubberState: ScrubberState
    var onInteraction: () -> Void
    /// Continuous play: advance to next fullscreen item (own setting, not Feeds).
    var onAdvanceToNext: () -> Void = {}

    @AppStorage("images_fullscreen_immersive") private var immersiveScaling = true
    @AppStorage("images_fullscreen_continuous") private var continuousPlay = false
    @AppStorage("images_fullscreen_continuous_duration") private var continuousDurationSeconds = 3

    // Playback State
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?
    @State private var animationAdvanceTimer: Timer?

    private var isActiveItem: Bool {
        image.id == (currentVisibleId ?? fallbackActiveId)
    }

    private var isAnimatedImage: Bool {
        let ext = image.fileExtension?.uppercased()
        return ext == "GIF" || ext == "WEBP"
    }

    private var isPortrait: Bool {
        if let file = image.visual_files?.first {
            return (file.height ?? 0) > (file.width ?? 0)
        }
        return false
    }

    /// Match Feeds: fill only when immersive is on and content orientation matches the device.
    private var shouldFill: Bool {
        guard immersiveScaling else { return false }
        let isPortraitDevice = UIScreen.main.bounds.height > UIScreen.main.bounds.width
        if isPortraitDevice {
            return isPortrait
        } else {
            return !isPortrait
        }
    }

    private var immersiveBottomInset: CGFloat {
        guard shouldFill, showUI else { return 0 }
        return ReelsImmersiveChromeLayout.videoBottomInset()
    }

    @ViewBuilder
    private var mediaLayer: some View {
        let bottomInset = immersiveBottomInset
        Group {
            if image.isAnimated {
                ZoomableScrollView(isZoomed: $isZoomed, onTap: { _ in
                    withAnimation(.easeInOut(duration: 0.4)) { showUI.toggle() }
                    if showUI { onInteraction() }
                }) {
                    GeometryReader { _ in
                        CustomAsyncImage(url: image.imageURL) { loader in
                            if let data = loader.imageData, isAnimatedData(data) {
                                AnimatedWebView(data: data, fillMode: shouldFill, bottomInset: bottomInset)
                            } else if let img = loader.image {
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: shouldFill ? .fill : .fit)
                                    .padding(.bottom, bottomInset)
                                    .clipped()
                            } else if loader.isLoading {
                                InlineSpinner(tint: .white)
                            } else {
                                Image(systemName: "exclamationmark.triangle").foregroundColor(.white)
                            }
                        }
                    }
                }
            } else if image.isVideo {
                ZoomableScrollView(isZoomed: $isZoomed, onTap: { _ in
                    withAnimation(.easeInOut(duration: 0.4)) { showUI.toggle() }
                    if showUI { onInteraction() }
                }) {
                    if let player = player {
                        FullScreenVideoPlayer(
                            player: player,
                            videoGravity: shouldFill ? .resizeAspectFill : .resizeAspect,
                            bottomContentInset: bottomInset
                        )
                    } else {
                        if let url = image.thumbnailURL {
                            CustomAsyncImage(url: url) { loader in
                                if let img = loader.image {
                                    img
                                        .resizable()
                                        .aspectRatio(contentMode: shouldFill ? .fill : .fit)
                                        .padding(.bottom, bottomInset)
                                        .clipped()
                                } else {
                                    InlineSpinner(tint: .white)
                                }
                            }
                        }
                    }
                }
            } else {
                // Static image
                ZoomableScrollView(isZoomed: $isZoomed, onTap: { _ in
                    withAnimation(.easeInOut(duration: 0.4)) { showUI.toggle() }
                    if showUI { onInteraction() }
                }) {
                    if let url = image.imageURL {
                        CustomAsyncImage(url: url) { loader in
                            if let img = loader.image {
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: shouldFill ? .fill : .fit)
                                    .padding(.bottom, bottomInset)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            } else if loader.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.largeTitle)
                                        .foregroundColor(.white)
                                    Text("Failed to load image")
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }


    var body: some View {
        ZStack {
            mediaLayer

            // Center Play Icon (only for videos, not animations)
            if !isAnimatedImage && image.isVideo && !isPlaying && showUI {
                CenterPlayButton {
                    isPlaying = true
                    player?.play()
                    onInteraction()
                }
            }
        }
        .background(Color.black)
        .onAppear {
            if image.isVideo {
                setupPlayer()
            }
            applyActivePlaybackState()
        }
        .onChange(of: image.isVideo) { _, isVideo in
            if isVideo { setupPlayer() }
            applyActivePlaybackState()
        }
        .onDisappear {
            cancelAnimationAdvanceTimer()
            player?.pause()
            if let timeObserver = timeObserver {
                player?.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
        }
        .onChange(of: isMuted) { _, newValue in
            // Persisting happens in the mute button, not here — this also fires for programmatic
            // writes, which is how AVKit's resets used to reach the stored choice.
            player?.isMuted = newValue
            if newValue {
                applyAmbientMixingAudioSession()
            } else {
                applyPlaybackAudioSession()
            }
        }
        .onChange(of: currentVisibleId) { _, _ in
            applyActivePlaybackState()
        }
        .onChange(of: isPlaying) { _, playing in
            guard isActiveItem else { return }
            if playing {
                player?.play()
            } else {
                player?.pause()
            }
        }
        .onChange(of: continuousPlay) { _, enabled in
            guard isActiveItem, !image.isVideo else { return }
            if enabled {
                startStillAdvanceTimer()
            } else {
                cancelAnimationAdvanceTimer()
            }
        }
        .onChange(of: continuousDurationSeconds) { _, _ in
            guard isActiveItem, !image.isVideo, continuousPlay else { return }
            startStillAdvanceTimer()
        }
        .onReceive(scrubberState.$seekTarget) { target in
            guard let t = target, isActiveItem, player != nil else { return }
            seek(to: t)
            DispatchQueue.main.async {
                if scrubberState.seekTarget != nil {
                    scrubberState.seekTarget = nil
                }
            }
        }
        .onReceive(scrubberState.$seeking) { seeking in
            guard isActiveItem else { return }
            if seeking {
                player?.pause()
            } else if isPlaying {
                player?.play()
                onInteraction()
            }
        }
    }

    // MARK: - Player Setup (matches ReelItemView.initPlayer)

    private func applyActivePlaybackState() {
        guard isActiveItem else {
            player?.pause()
            cancelAnimationAdvanceTimer()
            return
        }
        if image.isVideo {
            // Seed duration from metadata so the bar isn't stuck at 0/1 before the first tick.
            if let metaDuration = image.visual_files?.first?.duration, metaDuration > 0 {
                scrubberState.duration = metaDuration
            }
            if isPlaying { player?.play() }
            else { player?.pause() }
        } else {
            scrubberState.time = 0
            scrubberState.duration = 1
            scrubberState.seeking = false
            scrubberState.seekTarget = nil
            if continuousPlay {
                startStillAdvanceTimer()
            } else {
                cancelAnimationAdvanceTimer()
            }
        }
    }

    private func handlePlaybackEnded() {
        guard image.id == (currentVisibleId ?? fallbackActiveId) else { return }
        if continuousPlay {
            onAdvanceToNext()
            return
        }
        player?.seek(to: .zero)
        player?.play()
        isPlaying = true
    }

    /// Continuous: stills use the Dauer setting; animated GIFs/WebP use file duration (fallback: Dauer).
    private func startStillAdvanceTimer() {
        guard continuousPlay, !image.isVideo, isActiveItem else { return }
        cancelAnimationAdvanceTimer()
        let fallback = TimeInterval(max(1, continuousDurationSeconds))
        let duration: TimeInterval
        if isAnimatedImage {
            let meta = image.visual_files?.first?.duration ?? 0
            duration = meta > 0 ? meta : fallback
        } else {
            duration = fallback
        }
        animationAdvanceTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            handlePlaybackEnded()
        }
    }

    private func cancelAnimationAdvanceTimer() {
        animationAdvanceTimer?.invalidate()
        animationAdvanceTimer = nil
    }

    private func initPlayer(with streamURL: URL) {
        let headers = ["ApiKey": ServerConfigManager.shared.activeConfig?.secureApiKey ?? ""]
        let authenticatedURL = signedURL(streamURL) ?? streamURL
        let asset = AVURLAsset(url: authenticatedURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let newItem = AVPlayerItem(asset: asset)
        let scrubber = scrubberState
        let itemId = image.id

        if let existingPlayer = self.player {
            // Reuse existing player to prevent FullScreenVideoPlayer re-renders
            if let observer = timeObserver {
                existingPlayer.removeTimeObserver(observer)
                self.timeObserver = nil
            }
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
            existingPlayer.replaceCurrentItem(with: newItem)
        } else {
            self.player = createPlayer(for: streamURL, takesAudioSession: !isMuted, muted: isMuted)
        }

        guard let player = self.player else { return }

        player.isMuted = isMuted
        if isActiveItem, isPlaying { player.play() }

        if let metaDuration = image.visual_files?.first?.duration, metaDuration > 0, isActiveItem {
            scrubber.duration = metaDuration
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            guard itemId == (self.currentVisibleId ?? self.fallbackActiveId) else { return }
            self.handlePlaybackEnded()
        }

        // Time observer — read visible id via Binding so paging updates stay live (Feeds pattern).
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            let activeId = self.currentVisibleId ?? self.fallbackActiveId
            guard itemId == activeId else { return }
            if !scrubber.seeking {
                scrubber.time = time.seconds
            }
            if let d = player.currentItem?.duration.seconds, d > 0, !d.isNaN {
                scrubber.duration = d
            }
        }
    }

    private func setupPlayer() {
        guard let url = image.imageURL else { return }
        initPlayer(with: url)
    }

    private func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        if isActiveItem {
            scrubberState.time = time
        }
    }
}
// MARK: - Full Screen Image View (Feeds-style vertical paging)

struct FullScreenImageView: View {
    @Binding var images: [StashImage]
    let selectedImageId: String
    var onLoadMore: (() -> Void)?
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var isMediaZoomed = false
    @State private var showingDeleteConfirmation = false
    @State private var isMuted: Bool = ScenePlayerMute.initialValue()
    @State private var currentVisibleId: String?
    @State private var showUI = true
    @State private var shareItems: [Any] = []
    @State private var showingShare = false
    @State private var showingSetPerformerImagePicker = false
    @State private var performerImageTargetPerformers: [GalleryPerformer] = []
    @State private var currentItemIsPlaying = true
    @State private var scrubberState = ScrubberState()
    /// Triggers UIKit pop when `dismiss()` is a no-op under `safeAreaInset` chrome.
    @State private var navigationBackTrigger: UUID?

    init(images: Binding<[StashImage]>, selectedImageId: String, onLoadMore: (() -> Void)? = nil) {
        self._images = images
        self.selectedImageId = selectedImageId
        self.onLoadMore = onLoadMore
        self._isMuted = State(initialValue: ScenePlayerMute.initialValue())
        self._currentVisibleId = State(initialValue: selectedImageId)
    }

    private var activeImageId: String { currentVisibleId ?? selectedImageId }

    private var currentImage: StashImage? {
        images.first(where: { $0.id == activeImageId })
    }

    private var chromePillHeight: CGFloat { StashyExpandingDock.activeHeight }

    private func goBack() {
        navigationBackTrigger = UUID()
    }

    private func advanceFullscreenToNext(from id: String) {
        guard let idx = images.firstIndex(where: { $0.id == id }),
              idx + 1 < images.count else { return }
        let nextId = images[idx + 1].id
        withAnimation(.easeInOut(duration: 0.25)) {
            currentVisibleId = nextId
        }
        if idx + 2 >= images.count {
            onLoadMore?()
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                            GalleryItemView(
                                image: image,
                                isMuted: $isMuted,
                                viewModel: viewModel,
                                images: $images,
                                showUI: $showUI,
                                isZoomed: $isMediaZoomed,
                                currentVisibleId: $currentVisibleId,
                                fallbackActiveId: selectedImageId,
                                isPlaying: $currentItemIsPlaying,
                                scrubberState: scrubberState,
                                onInteraction: { },
                                onAdvanceToNext: {
                                    advanceFullscreenToNext(from: image.id)
                                }
                            )
                            .scrollDisabled(isMediaZoomed)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .background(Color.black)
                            .id(image.id)
                            .onAppear {
                                if image.id == images.last?.id {
                                    onLoadMore?()
                                }
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollDisabled(isMediaZoomed)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentVisibleId)
                .scrollContentBackground(.hidden)
                .background(Color.black)
                .ignoresSafeArea()
            }
            .background(Color.black.ignoresSafeArea())
            .ignoresSafeArea()
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .enableSwipeBackWhenNavBarHidden()
            .background {
                StashyNavigationBackTrigger(trigger: $navigationBackTrigger) {
                    dismiss()
                }
            }
            .toolbar(showUI ? .automatic : .hidden, for: .tabBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                if showUI, !StashyChromePlacement.prefersBottom {
                    fullScreenImageNavBar
                        .transition(.opacity)
                        // Keep chrome above full-bleed media hit-testing.
                        .zIndex(10)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if showUI, StashyChromePlacement.prefersBottom {
                        fullScreenImageNavBar
                            .transition(.opacity)
                    }
                    feedsStyleInfoOverlay(currentImage: currentImage)
                    feedsStyleScrubberBar(currentImage: currentImage)
                }
                .allowsHitTesting(showUI)
                .zIndex(10)
            }
            .animation(.easeInOut(duration: 0.2), value: showUI)
            .onChange(of: activeImageId) { _, _ in
                currentItemIsPlaying = true
                scrubberState.time = 0
                scrubberState.duration = 1
                scrubberState.seeking = false
                scrubberState.seekTarget = nil
            }
            .onAppear {
                if !isMuted {
                    applyPlaybackAudioSession()
                }
            }
            .onDisappear {
                showUI = true
                applyAmbientMixingAudioSession()
            }
            .task(id: selectedImageId) {
                currentVisibleId = selectedImageId
                try? await Task.sleep(for: .milliseconds(80))
                currentVisibleId = selectedImageId
                proxy.scrollTo(selectedImageId, anchor: .top)
            }
            .sheet(isPresented: $showingShare) {
                ShareSheet(items: shareItems)
            }
            .alert("Set as Performer Image?", isPresented: $showingSetPerformerImagePicker) {
                ForEach(performerImageTargetPerformers) { performer in
                    Button("Okay") {
                        setPerformerImage(performer: performer)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Update the profile picture for the selected performer.")
            }
            .alert("Really delete image?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteCurrentImage()
                }
            } message: {
                Text("This image will be permanently deleted. This action cannot be undone.")
            }
        }
    }

    /// Matches `ReelsView.reelsInfoOverlay` 1:1 (thumbnail · name - title · tags · mute/play).
    @ViewBuilder
    private func feedsStyleInfoOverlay(currentImage: StashImage?) -> some View {
        let isVideo = currentImage.map { $0.isVideo && !$0.isAnimated } ?? false
        VStack(alignment: .leading, spacing: 0) {
            if let image = currentImage {
                // Own row above the performer line — mirrors `ReelsView.reelsInfoOverlay`.
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ChromeCircleButton(
                        systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        enabled: isVideo,
                        accessibilityLabel: isMuted ? "Ton an" : "Stumm"
                    ) {
                        if isVideo {
                            isMuted.toggle()
                            ScenePlayerMute.persist(isMuted)
                        }
                    }

                    ChromeCircleButton(
                        systemImage: currentItemIsPlaying ? "pause.fill" : "play.fill",
                        enabled: isVideo,
                        accessibilityLabel: currentItemIsPlaying ? "Pause" : "Play"
                    ) {
                        if isVideo { currentItemIsPlaying.toggle() }
                    }
                }
                .padding(.horizontal, StashyExpandingDock.edgePadding)
                .padding(.bottom, 8)

                HStack(alignment: .center, spacing: 10) {
                    if let performer = image.performers?.first {
                        NavigationLink(destination: PerformerDetailView(performer: performer.toPerformer())) {
                            feedsPerformerThumbnail(performer)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let performer = image.performers?.first {
                                NavigationLink(destination: PerformerDetailView(performer: performer.toPerformer())) {
                                    Text(performer.name)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                .layoutPriority(1)
                                Text("-")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            if let title = image.title, !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(1)
                            } else if let gallery = image.galleries?.first {
                                let galleryObj = Gallery(
                                    id: gallery.id,
                                    title: gallery.title ?? "Gallery",
                                    date: nil, details: nil, imageCount: nil, organized: nil,
                                    createdAt: nil, updatedAt: nil, studio: nil, performers: nil, cover: nil
                                )
                                NavigationLink(destination: ImagesView(gallery: galleryObj)) {
                                    Text(gallery.title ?? "Unknown Gallery")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white.opacity(0.85))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        let tags = image.tags ?? []
                        Group {
                            if !tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(tags) { tag in
                                            Text("#\(tag.name)")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.8))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Color.black.opacity(0.3))
                                                .clipShape(Capsule())
                                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                                        }
                                    }
                                }
                            } else {
                                Color.clear.opacity(0)
                            }
                        }
                        .frame(height: 20)
                    }

                }
                .padding(.horizontal, StashyExpandingDock.edgePadding)
            }
        }
        .padding(.bottom, 2)
        .colorScheme(.dark)
        .opacity(showUI ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: showUI)
    }

    /// Matches `ReelsView.reelsScrubberBar` / `IsolatedScrubberBar`.
    @ViewBuilder
    private func feedsStyleScrubberBar(currentImage: StashImage?) -> some View {
        if let image = currentImage {
            // Stills and animations have nothing to scrub, but the bar still has to occupy its
            // height — dropping it shortens the bottom inset and pushes the info row down, so the
            // chrome would jump every time the feed moves between a photo and a video.
            let scrubbable = image.isVideo && !image.isAnimated
            IsolatedScrubberBar(state: scrubberState, isUIVisible: showUI)
                .opacity(scrubbable ? 1 : 0)
                .allowsHitTesting(scrubbable)
        }
    }

    @ViewBuilder
    private func feedsPerformerThumbnail(_ performer: GalleryPerformer) -> some View {
        let size: CGFloat = StashyExpandingDock.circleSize
        Circle()
            .fill(appearanceManager.tintColor.opacity(0.2))
            .frame(width: size, height: size)
            .overlay {
                if let url = performer.thumbnailURL {
                    CustomAsyncImage(url: url) { loader in
                        if let img = loader.image {
                            img.resizable()
                                .scaledToFill()
                                // Head-and-shoulders shots lose the face to a centred crop.
                                .frame(width: size, height: size, alignment: .top)
                        } else {
                            Image(systemName: "person.fill")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                } else {
                    Image(systemName: "person.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(appearanceManager.tintColor, lineWidth: 2))
    }

    @ViewBuilder
    private var fullScreenImageNavBar: some View {
        let image = currentImage
        let oCounter = image?.o_counter ?? 0
        let rating100 = image?.rating100 ?? 0
        let stars = max(0, min(5, Int(round(Double(rating100) / 20.0))))
        let performers = image?.performers ?? []

        StashySectionChromeBar {
            HStack(spacing: 8) {
                Button {
                    goBack()
                } label: {
                    HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                        Text("Back")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                    .modifier(StashyChromePillStyle(height: chromePillHeight))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    // Share / download / performer image behind one menu — as separate pills they
                    // squeezed the Back button into two lines.
                    Menu {
                        Button {
                            shareCurrentImage()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        if let image = currentImage {
                            let entryId = "image-" + image.id
                            let isDownloaded = downloadManager.isGalleryDownloaded(id: entryId)
                            let isDownloading = downloadManager.activeDownloads[entryId] != nil
                            Button {
                                downloadManager.downloadImage(image)
                            } label: {
                                Label(
                                    isDownloaded ? "Downloaded" : (isDownloading ? "Downloading…" : "Download"),
                                    systemImage: isDownloaded ? "checkmark.circle.fill" : "arrow.down.doc"
                                )
                            }
                            .disabled(isDownloaded || isDownloading)
                        }

                        if !performers.isEmpty {
                            Button {
                                performerImageTargetPerformers = performers
                                showingSetPerformerImagePicker = true
                            } label: {
                                Label("Set as performer image", systemImage: "person.crop.circle.badge.plus")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                            .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                            .modifier(StashyChromePillStyle(height: chromePillHeight, iconOnly: true))
                    }
                    .accessibilityLabel("More actions")

                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                            .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                            .modifier(StashyChromePillStyle(height: chromePillHeight, iconOnly: true))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete")

                    Menu {
                        Button {
                            updateCurrentRating(0)
                        } label: {
                            HStack {
                                Text("Clear Rating")
                                if stars == 0 { Image(systemName: "checkmark") }
                            }
                        }
                        Divider()
                        ForEach(1...5, id: \.self) { s in
                            Button {
                                updateCurrentRating(s * 20)
                            } label: {
                                HStack {
                                    Text(String(repeating: "★", count: s))
                                    if stars == s { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                            Image(systemName: "star.fill")
                                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                                .foregroundColor(.white.opacity(stars > 0 ? 1.0 : StashyExpandingDock.inactiveIconOpacity))
                            Text("\(stars)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                        }
                        .modifier(StashyChromePillStyle(height: chromePillHeight))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rating")

                    Button {
                        incrementCurrentOCounter()
                    } label: {
                        HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                            Image(systemName: oCounter > 0 ? AppearanceManager.shared.oCounterIconFilled : AppearanceManager.shared.oCounterIcon)
                                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                                .foregroundColor(oCounter > 0 ? appearanceManager.tintColor : .white.opacity(StashyExpandingDock.inactiveIconOpacity))
                            Text("\(oCounter)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                        }
                        .modifier(StashyChromePillStyle(height: chromePillHeight))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("O-Counter")
                }
                .layoutPriority(1)
            }
            .frame(height: chromePillHeight)
            .padding(.horizontal, StashyExpandingDock.edgePadding)
            .padding(.vertical, 6)
        }
    }

    private func updateCurrentRating(_ newRating: Int) {
        let targetId = currentVisibleId ?? selectedImageId
        guard let index = images.firstIndex(where: { $0.id == targetId }) else { return }
        let imageId = images[index].id
        let original = images[index].rating100
        let ratingValue: Int? = newRating > 0 ? newRating : nil
        images[index] = images[index].withRating(ratingValue)
        viewModel.updateImageRating(imageId: imageId, rating100: ratingValue) { success in
            if !success {
                DispatchQueue.main.async {
                    if let revertIndex = images.firstIndex(where: { $0.id == imageId }) {
                        images[revertIndex] = images[revertIndex].withRating(original)
                    }
                    ToastManager.shared.show("Failed to save rating", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }

    private func incrementCurrentOCounter() {
        let targetId = currentVisibleId ?? selectedImageId
        guard let index = images.firstIndex(where: { $0.id == targetId }) else { return }
        let imageId = images[index].id
        let originalCount = images[index].o_counter ?? 0
        let newCount = originalCount + 1
        images[index] = images[index].withOCounter(newCount)
        viewModel.incrementImageOCounter(imageId: imageId) { returnedCount in
            DispatchQueue.main.async {
                guard let revertIndex = images.firstIndex(where: { $0.id == imageId }) else { return }
                if let count = returnedCount {
                    images[revertIndex] = images[revertIndex].withOCounter(count)
                } else {
                    images[revertIndex] = images[revertIndex].withOCounter(originalCount)
                    ToastManager.shared.show("Failed to update O-Counter", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }

    private func shareCurrentImage() {
        let targetId = currentVisibleId ?? selectedImageId
        guard let currentImage = images.first(where: { $0.id == targetId }),
              let url = currentImage.imageURL else { return }

        Task {
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = 60
            let session = URLSession(configuration: sessionConfig)
            var request = URLRequest(url: url)
            if let apiKey = ServerConfigManager.shared.activeConfig?.secureApiKey, !apiKey.isEmpty {
                request.addValue(apiKey, forHTTPHeaderField: "ApiKey")
            }

            guard let (data, response) = try? await session.data(for: request) else { return }

            let mimeType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
            let isVideo = mimeType.contains("video") || url.absoluteString.lowercased().contains(".mp4")

            await MainActor.run {
                if isVideo {
                    // Videos: temp file URL — iOS offers "Save to Photos" and "Save to Files"
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("mp4")
                    guard (try? data.write(to: tempURL)) != nil else { return }
                    shareItems = [tempURL]
                } else {
                    // Images: UIImage — iOS offers "Save Image" to Photos
                    guard let uiImage = UIImage(data: data) else { return }
                    shareItems = [uiImage]
                }
                showingShare = true
            }
        }
    }

    private func deleteCurrentImage() {
        let targetId = currentVisibleId ?? selectedImageId
        guard let currentIndex = images.firstIndex(where: { $0.id == targetId }) else { return }
        let imageToDelete = images[currentIndex]

        viewModel.deleteImage(imageId: imageToDelete.id) { success in
            DispatchQueue.main.async {
                if success {
                    ToastManager.shared.show("Image deleted", icon: "trash", style: .success)
                    // Update the bound array so parent views (e.g. StashLine / Images grid)
                    // can immediately remove the deleted item without a full reload.
                    self.images.removeAll(where: { $0.id == imageToDelete.id })
                    self.goBack()
                } else {
                    ToastManager.shared.show("Failed to delete image", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }

    private func setPerformerImage(performer: GalleryPerformer) {
        let targetId = currentVisibleId ?? selectedImageId
        guard let currentImage = images.first(where: { $0.id == targetId }) else { return }
        
        let url: URL?
        if let ext = currentImage.fileExtension, ["JPG", "JPEG", "PNG", "WEBP"].contains(ext.uppercased()) {
            url = currentImage.imageURL
        } else {
            url = currentImage.thumbnailURL
        }
        
        guard let imageURL = url?.absoluteString else { return }

        viewModel.setPerformerImage(performerId: performer.id, imageURL: imageURL) { success in
            DispatchQueue.main.async {
                if success {
                    ToastManager.shared.show("Performer image updated", icon: "person.crop.circle.badge.checkmark", style: .success)
                    let bustedUrl = "\(imageURL)?bust=\(UUID().uuidString)"
                    // Invalidate first, then notify loaders with a busted path so they
                    // skip stale cache entries even if URL path stays the same.
                    ImageCache.shared.invalidatePerformerProfileImage(
                        performerId: performer.id,
                        newImagePath: bustedUrl
                    )
                    NotificationCenter.default.post(
                        name: NSNotification.Name("PerformerImageUpdated"),
                        object: nil,
                        userInfo: [
                            "performerId": performer.id,
                            "newImagePath": bustedUrl
                        ]
                    )
                } else {
                    ToastManager.shared.show("Failed to update performer image", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
