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
    @ObservedObject private var appearance = AppearanceManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.GallerySortOption = StashDBViewModel.GallerySortOption(rawValue: TabManager.shared.getSortOption(for: .galleries) ?? "") ?? .dateDesc
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var scrollPosition: String? = nil
    @State private var shouldRestoreScroll = false
    var hideTitle: Bool = false

    @State private var showFilterSortSheet = false
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

    private var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive || !catalogPresetRowSelection.isEmpty
    }

    private var sortedServerGalleryFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .galleries }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var galleryLiveChipRowsVisible: Bool {
        CatalogLiveChipFilterSupport.gallerySavedFilterSupportsLiveEditor(selectedFilter)
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
        viewModel.currentGalleryLiveFilter = activeLiveFilterDict
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
        guard showFilterSortSheet else { return }
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
    
    // Grid Setup
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // Dynamische Spalten
    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            // iPad: 4 columns
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
            // iPhone: 2 columns
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
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
            filter: selectedFilter,
            liveFilter: isLiveFilterActive ? activeLiveFilterDict : nil
        )
    }

    private func performSearch(isInitialLoad: Bool = true) {
        viewModel.fetchGalleries(
            sortBy: selectedSortOption,
            searchQuery: searchText,
            isInitialLoad: isInitialLoad,
            filter: selectedFilter,
            liveFilter: isLiveFilterActive ? activeLiveFilterDict : nil
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
    private var galleriesCoreChrome: some View {
        Group {
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
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.galleries) { gallery in
                            NavigationLink(destination: ImagesView(gallery: gallery)) {
                                GalleryCardView(gallery: gallery)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Loading Indicator / Infinite Scroll
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
                    .padding(16)
                }
                .background(Color.appBackground)
                .refreshable { performSearch() }
            }
        }
        .navigationTitle(hideTitle ? "" : "Galleries")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .conditionalSearchable(isVisible: isSearchVisible, text: $searchText, prompt: "Search galleries...")
        .onChange(of: searchText) { oldValue, newValue in
            // Debounce
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if newValue == self.searchText {
                    performSearch()
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
                        .padding(Edge.Set.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                    }
                }
            }
            
        }
        .floatingActionBar(isPresented: true, catalogChrome: CatalogFloatingChromeState(hasActiveServerConfig: configManager.activeConfig != nil, primaryListIsEmpty: viewModel.galleries.isEmpty, errorMessage: viewModel.errorMessage)) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button {
                    showFilterSortSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(catalogFilterSortFABActive ? appearance.tintColor : .primary)
                        .overlay(alignment: .topTrailing) {
                            if catalogFilterSortFABActive {
                                Circle()
                                    .fill(appearance.tintColor)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 3, y: -3)
                            }
                        }
                }
                .accessibilityLabel("Filter and sort")
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            // Apply default sort option
            let defaultSortStr = TabManager.shared.getSortOption(for: .galleries) ?? "dateDesc"
            if let defaultSort = StashDBViewModel.GallerySortOption(rawValue: defaultSortStr) {
                 selectedSortOption = defaultSort
                 viewModel.currentGallerySortOption = defaultSort
            }
            
            // Check for search text from navigation
            if !coordinator.activeSearchText.isEmpty {
                searchText = coordinator.activeSearchText
                isSearchVisible = true
                coordinator.activeSearchText = ""
                performSearch()
                viewModel.fetchSavedFilters()
                return
            }
            
            if TabManager.shared.getDefaultFilterId(for: .galleries) == nil || !viewModel.savedFilters.isEmpty {
                if viewModel.galleries.isEmpty {
                    performSearch()
                }
            }
            viewModel.fetchSavedFilters()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.galleries.rawValue {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .galleries),
                   let newFilter = viewModel.savedFilters[defaultId] {
                    selectedFilter = newFilter
                } else {
                    selectedFilter = nil
                }
                performSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.galleries.rawValue {
                let newSort = StashDBViewModel.GallerySortOption(rawValue: TabManager.shared.getPersistentSortOption(for: .galleries) ?? "") ?? .dateDesc
                changeSortOption(to: newSort)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            catalogPresetRowSelection = ""
            clearGalleryLiveChipsOnly()
            refreshGalleryLocalPresets()
            performSearch()
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // Apply default filter if set and none selected yet
            if selectedFilter == nil {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .galleries),
                   let filter = newValue[defaultId] {
                    selectedFilter = filter
                    // Only fetch if empty to avoid resetting scroll
                    if viewModel.galleries.isEmpty {
                        performSearch()
                    }
                } else if !viewModel.isLoadingSavedFilters {
                    // Default filter was set but not found, or filters finished loading and none match
                    // Only fetch if empty
                    if viewModel.galleries.isEmpty {
                        performSearch()
                    }
                }
            }
        }
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
            if oldValue == true && isLoading == false {
                if viewModel.galleries.isEmpty && !viewModel.isLoadingGalleries && selectedFilter == nil {
                    performSearch()
                }
            }
        }
    }

    @ViewBuilder
    private func galleriesFilterSortSheet() -> some View {
        GalleriesCatalogFilterSortSheet(
            serverFilters: sortedServerGalleryFilters,
            localPresets: localCatalogPresets,
            selectedPresetRowId: $catalogPresetRowSelection,
            liveChipRowsVisible: galleryLiveChipRowsVisible,
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
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                GeometryReader { geometry in
                    ZStack(alignment: .bottomLeading) {
                        // Image (Strictly filling the square)
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
                        
                        // Badges Overlay Layer
                        VStack {
                            HStack(alignment: .top) {
                                // Studio Badge (Top Left)
                                if let studio = gallery.studio {
                                    Text(studio.name)
                                        .font(.system(size: 9, weight: .bold))
                                        .lineLimit(1)
                                        .foregroundColor(.white)
                                        .padding(Edge.Set.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                        .clipShape(Capsule())
                                }
                                
                                Spacer()
                                
                                if let count = gallery.imageCount, count > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "photo.stack")
                                            .font(.system(size: 8, weight: .bold))
                                        Text("\(count)")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(6)
                            
                            Spacer()
                            
                            HStack(alignment: .bottom) {
                                // Info Section (Bottom Left Title)
                                Text(gallery.displayName)
                                   .font(.system(size: geometry.size.width * 0.08, weight: .bold))
                                   .foregroundColor(.white)
                                   .lineLimit(1)
                                   .shadow(radius: 2)
                                
                                Spacer()
                            }
                            .padding(8)
                        }
                    }
                }
            )
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)) // Ensure hit testing works on entire card
            .cardShadow()
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
    var onInteraction: () -> Void

    // Playback State
    @State private var player: AVPlayer?
    @State private var isPlaying = true
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 1.0
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    @State private var showRatingOverlay = false
    @State private var showTagsOverlay = false

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

    @ViewBuilder
    private var mediaLayer: some View {
        Group {
            if image.isAnimated {
                ZoomableScrollView(isZoomed: $isZoomed, onTap: { _ in
                    withAnimation(.easeInOut(duration: 0.4)) { showUI.toggle() }
                    if showUI { onInteraction() }
                }) {
                    GeometryReader { _ in
                        CustomAsyncImage(url: image.imageURL) { loader in
                            if let data = loader.imageData, isAnimatedData(data) {
                                AnimatedWebView(data: data, fillMode: false)
                            } else if let img = loader.image {
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else if loader.isLoading {
                                ProgressView().tint(.white)
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
                        FullScreenVideoPlayer(player: player, videoGravity: .resizeAspect)
                    } else {
                        if let url = image.thumbnailURL {
                            CustomAsyncImage(url: url) { loader in
                                if let img = loader.image {
                                    img
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    ProgressView().tint(.white)
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
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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


    @ViewBuilder
    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            // Tags overlay (toggled by button)
            if showTagsOverlay {
                if let tags = image.tags, !tags.isEmpty {
                    ScrollView(Axis.Set.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tags) { tag in
                                Text("#\(tag.name)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(Edge.Set.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                            }
                        }
                        .padding(Edge.Set.horizontal, 16)
                    }
                    .padding(Edge.Set.bottom, 5)
                    .transition(AnyTransition.move(edge: Edge.bottom).combined(with: .opacity))
                }
            }
            
            // Rating overlay (expands upward)
            if showRatingOverlay {
                let rating = image.rating100 ?? 0
                HStack {
                    StarRatingView(
                        rating100: rating,
                        isInteractive: true,
                        size: 28,
                        spacing: 10,
                        isVertical: false
                    ) { newRating in
                        if let index = images.firstIndex(where: { $0.id == image.id }) {
                            images[index] = images[index].withRating(newRating)
                            viewModel.updateImageRating(imageId: image.id, rating100: newRating) { _ in }
                        }
                        onInteraction()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showRatingOverlay = false
                            }
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(Edge.Set.horizontal, 16)
                .background(Color.black.opacity(DesignTokens.Opacity.badge))
                .clipShape(Capsule())
                .padding(Edge.Set.bottom, 8)
                .transition(AnyTransition.move(edge: Edge.bottom).combined(with: .opacity))
            }
            

                // Performer and Title labels
            VStack(alignment: .leading, spacing: 4) {
                performerLabel
                titleLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Edge.Set.horizontal, 16)
            .padding(Edge.Set.bottom, 8)

            // Full-width progress bar
            if image.isVideo {
                CustomVideoScrubber(
                    value: Binding(get: { currentTime }, set: { val in
                        currentTime = val
                        seek(to: val)
                    }),
                    total: duration,
                    onEditingChanged: { editing in
                        isSeeking = editing
                        if editing {
                            player?.pause()
                        } else {
                            if isPlaying { player?.play() }
                            onInteraction()
                        }
                    }
                )
                .padding(Edge.Set.horizontal, 0)
                .padding(Edge.Set.bottom, 15)
            }
            
            // Bottom row: Action buttons
            HStack(alignment: .center, spacing: 0) {
                Spacer()
                
                // Tags button
                if let tags = image.tags, !tags.isEmpty {
                    BottomBarButton(icon: "tag.fill", count: tags.count) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showTagsOverlay.toggle()
                            showRatingOverlay = false
                        }
                        onInteraction()
                    }
                    Spacer()
                }
                
                // Rating
                let rating = image.rating100 ?? 0
                BottomBarButton(icon: "star", count: rating > 0 ? (rating / 20) : 0) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showRatingOverlay.toggle()
                        showTagsOverlay = false
                    }
                    onInteraction()
                }
                
                Spacer()
                
                // O-Counter
                BottomBarButton(icon: AppearanceManager.shared.oCounterIcon, count: image.o_counter ?? 0) {
                    if let index = images.firstIndex(where: { $0.id == image.id }) {
                        viewModel.incrementImageOCounter(imageId: image.id) { returnedCount in
                            if let count = returnedCount {
                                images[index] = images[index].withOCounter(count)
                            }
                        }
                    }
                    onInteraction()
                }
                
                Spacer()
                
                // Video Controls (Mute & Play/Pause - only for videos)
                if image.isVideo {
                    // Mute
                    BottomBarButton(
                        icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        count: 0,
                        hideCount: true
                    ) {
                        isMuted.toggle()
                        onInteraction()
                    }
                    
                    Spacer()
                    
                    // Play/Pause
                    BottomBarButton(
                        icon: isPlaying ? "pause.fill" : "play.fill",
                        count: 0,
                        hideCount: true
                    ) {
                        isPlaying.toggle()
                        if isPlaying { player?.play() }
                        else { player?.pause() }
                        onInteraction()
                    }
                    Spacer()
                }
            }
            .padding(Edge.Set.horizontal, 16)
            .frame(height: 50)
        }
        .padding(.bottom, 30)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mediaLayer
            
            // Center Play Icon (only for videos, not animations)
            if !isAnimatedImage && image.isVideo && !isPlaying && showUI {
                CenterPlayButton {
                    isPlaying = true
                    player?.play()
                    onInteraction()
                }
            }
            
            if showUI {
                bottomOverlay
                    .transition(AnyTransition.move(edge: Edge.bottom).combined(with: .opacity))
            }
        }
        .background(Color.black)
        .onAppear {
            if image.isVideo {
                setupPlayer()
            }
        }
        .onDisappear {
            player?.pause()
            if let timeObserver = timeObserver {
                player?.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
        }
        .onChange(of: isMuted) { _, newValue in
            player?.isMuted = newValue
        }
    }

    @ViewBuilder
    private var performerLabel: some View {
        if let performers = image.performers, let firstPerf = performers.first {
            let performerObj = Performer(
                id: firstPerf.id, name: firstPerf.name, disambiguation: nil, birthdate: nil, country: nil, imagePath: nil, sceneCount: 0, galleryCount: nil, gender: nil, ethnicity: nil, height: nil, weight: nil, measurements: nil, fakeTits: nil, penis_length: nil, careerLength: nil, tattoos: nil, piercings: nil, aliasList: nil, favorite: nil, rating100: nil, createdAt: nil, updatedAt: nil, oCounter: nil
            )
            NavigationLink(destination: PerformerDetailView(performer: performerObj)) {
                Text(firstPerf.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var titleLabel: some View {
        HStack(spacing: 6) {
            if let title = image.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            } else if let galleries = image.galleries, let gallery = galleries.first {
                let galleryObj = Gallery(id: gallery.id, title: gallery.title ?? "Gallery", date: nil, details: nil, imageCount: nil, organized: nil, createdAt: nil, updatedAt: nil, studio: nil, performers: nil, cover: nil)

                NavigationLink(destination: ImagesView(gallery: galleryObj)) {
                    Text(gallery.title ?? "Unknown Gallery")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Player Setup (matches ReelItemView.initPlayer)

    private func initPlayer(with streamURL: URL) {
        let headers = ["ApiKey": ServerConfigManager.shared.activeConfig?.secureApiKey ?? ""]
        let authenticatedURL = signedURL(streamURL) ?? streamURL
        let asset = AVURLAsset(url: authenticatedURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let newItem = AVPlayerItem(asset: asset)

        if let existingPlayer = self.player {
            // Reuse existing player to prevent FullScreenVideoPlayer re-renders
            if let observer = timeObserver {
                existingPlayer.removeTimeObserver(observer)
                self.timeObserver = nil
            }
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: existingPlayer.currentItem)
            existingPlayer.replaceCurrentItem(with: newItem)
        } else {
            self.player = createPlayer(for: streamURL)
        }

        guard let player = self.player else { return }

        player.isMuted = isMuted
        if isPlaying { player.play() }

        // Loop on end
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            player.seek(to: .zero)
            player.play()
        }

        // Time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            if !self.isSeeking {
                self.currentTime = time.seconds
            }
            if let d = player.currentItem?.duration.seconds, d > 0, !d.isNaN {
                self.duration = d
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
    }
}
// MARK: - Full Screen Image View (Feeds-style vertical paging)

struct FullScreenImageView: View {
    @Binding var images: [StashImage]
    @State var selectedImageId: String
    var onLoadMore: (() -> Void)?
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var isMediaZoomed = false
    @State private var showingDeleteConfirmation = false
    @State private var isMuted: Bool = !isHeadphonesConnected()
    @State private var currentVisibleId: String?
    @State private var showUI = true
    @State private var shareItems: [Any] = []
    @State private var showingShare = false
    @State private var showingSetPerformerImagePicker = false
    @State private var performerImageTargetPerformers: [GalleryPerformer] = []

    var body: some View {
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
                            onInteraction: { }
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
            .onScrollPhaseChange { oldPhase, newPhase in
                // Scrolling no longer affects UI visibility
            }
            .onChange(of: showUI) { _, newValue in
                // UI state changes are now purely manual
            }
            .ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea()
        .onDisappear {
            showUI = true
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(showUI ? .visible : .hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        shareCurrentImage()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(appearanceManager.tintColor)
                    }
                    let targetId = currentVisibleId ?? selectedImageId
                    if let currentImage = images.first(where: { $0.id == targetId }),
                       let performers = currentImage.performers, !performers.isEmpty {
                        Button {
                            performerImageTargetPerformers = performers
                            showingSetPerformerImagePicker = true
                        } label: {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .foregroundColor(appearanceManager.tintColor)
                        }
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(appearanceManager.tintColor)
                    }
                }
            }
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
        .onAppear {
            currentVisibleId = selectedImageId
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
                    dismiss()
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
