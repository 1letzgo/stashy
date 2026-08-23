//
//  StudiosView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI
import WebKit

private struct StudiosViewContent: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var configManager = ServerConfigManager.shared
    @State private var selectedSortOption: StashDBViewModel.StudioSortOption
    @State private var isChangingSort = false
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil
    @State private var lastOpenedStudioId: String?
    var hideTitle: Bool = false
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Filter & sort sheet
    @State private var showFilterSortSheet = false
    @State private var catalogPresetRowSelection = ""
    @State private var localCatalogPresets: [StudioListLiveFilterPreset] = StudioListLiveFilterPresetStore.loadPresets()
    @State private var showSaveAsCatalogPresetAlert = false
    @State private var catalogPresetNameInput = ""
    @State private var showRenameCatalogPresetAlert = false
    @State private var renameCatalogPresetInput = ""
    @State private var showDeleteCatalogPresetAlert = false

    // Live filter (chips)
    @State private var liveFilterFavorite: Bool? = nil
    @State private var liveFilterMinRating: Int = 0
    @State private var liveFilterScenes: String? = nil // nil=any, "has"=has scenes, "none"=no scenes

    private var isLiveFilterActive: Bool {
        liveFilterFavorite != nil || liveFilterMinRating != 0 || liveFilterScenes != nil
    }

    private var activeLiveFilterDict: [String: Any] {
        var dict: [String: Any] = [:]
        if let fav = liveFilterFavorite { 
            // For Studios, the filter key appears to be "favorite"
            dict["favorite"] = fav 
        }
        if liveFilterMinRating == -1 {
            dict["rating100"] = ["modifier": "IS_NULL"]
        } else if liveFilterMinRating > 0 {
            // Exact star match (e.g. 1-star means exactly 20)
            dict["rating100"] = ["value": (liveFilterMinRating * 20), "modifier": "EQUALS"]
        }
        if liveFilterScenes == "has"  { dict["scene_count"] = ["value": 0, "modifier": "GREATER_THAN"] }
        if liveFilterScenes == "none" { dict["scene_count"] = ["value": 0, "modifier": "EQUALS"] }
        return dict
    }

    private func applyLiveFilter() {
        viewModel.currentStudioLiveFilter = activeLiveFilterDict
        viewModel.fetchStudios(sortBy: selectedSortOption, searchQuery: searchText, filter: selectedFilter, liveFilter: activeLiveFilterDict)
    }

    private var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive || !catalogPresetRowSelection.isEmpty
    }

    private var sortedServerStudioFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .studios }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var studioLiveChipRowsVisible: Bool {
        CatalogLiveChipFilterSupport.studioSavedFilterSupportsLiveEditor(selectedFilter)
    }

    private func refreshStudioLocalPresets() {
        localCatalogPresets = StudioListLiveFilterPresetStore.loadPresets()
    }

    private func clearStudioLiveChipsOnly() {
        liveFilterFavorite = nil
        liveFilterMinRating = 0
        liveFilterScenes = nil
    }

    private func mapStudioLiveFragmentToChips(_ frag: [String: Any]) {
        clearStudioLiveChipsOnly()
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
        if let sc = frag["scene_count"] as? [String: Any],
           let mod = sc["modifier"] as? String {
            if mod == "GREATER_THAN" {
                liveFilterScenes = "has"
            } else if mod == "EQUALS" {
                liveFilterScenes = "none"
            }
        }
    }

    private func applyStudioCatalogPreset(_ preset: StudioListLiveFilterPreset) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
            TabManager.shared.setSortOption(for: .studios, option: preset.sort.rawValue)
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.studioSavedFilterSupportsLiveEditor(selectedFilter) {
            mapStudioLiveFragmentToChips(preset.liveFragment)
        } else {
            clearStudioLiveChipsOnly()
        }
        performSearch()
    }

    private func applyServerStudioSavedFilter(_ f: StashDBViewModel.SavedFilter) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.studioSavedFilterSupportsLiveEditor(selectedFilter) {
                mapStudioLiveFragmentToChips(meta.liveFragment)
            } else {
                clearStudioLiveChipsOnly()
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.StudioSortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
                TabManager.shared.setSortOption(for: .studios, option: parsed.rawValue)
            }
        } else {
            selectedFilter = f
            if CatalogLiveChipFilterSupport.studioSavedFilterSupportsLiveEditor(f), let raw = f.filterDict {
                mapStudioLiveFragmentToChips(raw)
            } else {
                clearStudioLiveChipsOnly()
            }
        }
        performSearch()
    }

    private func applyCatalogPresetSelectionFromSheetIfNeeded() {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerStudioSavedFilter(f)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyStudioCatalogPreset(preset)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyStudioCatalogPreset(preset)
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

    private func saveStudioCatalogPresetOverwrite() {
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
        refreshStudioLocalPresets()
    }

    private func saveStudioCatalogPresetAs(name: String) {
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
        ) { result in
            if case .success(let saved) = result {
                catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                showSaveAsCatalogPresetAlert = false
            }
        }
    }

    private func renameStudioCatalogPreset(to newName: String) {
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
        StudioListLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshStudioLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    private func deleteStudioCatalogPreset() {
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
        StudioListLiveFilterPresetStore.remove(id: uuid)
        refreshStudioLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }

    init(viewModel: StashDBViewModel, initialSort: StashDBViewModel.StudioSortOption? = nil, hideTitle: Bool = false) {
        self.viewModel = viewModel
        let savedSort = StashDBViewModel.StudioSortOption(rawValue: TabManager.shared.getSortOption(for: .studios) ?? "")
        _selectedSortOption = State(initialValue: initialSort ?? savedSort ?? .nameAsc)
        self.hideTitle = hideTitle
    }

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.StudioSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        
        // Save to TabManager
        TabManager.shared.setSortOption(for: .studios, option: newOption.rawValue)

        // Fetch new data immediately
        viewModel.fetchStudios(sortBy: newOption, searchQuery: searchText, filter: selectedFilter, liveFilter: isLiveFilterActive ? activeLiveFilterDict : nil)
    }
    
    // Search function with debouncing
    private func performSearch() {
        viewModel.fetchStudios(sortBy: selectedSortOption, searchQuery: searchText, filter: selectedFilter, liveFilter: isLiveFilterActive ? activeLiveFilterDict : nil)
    }

    var body: some View {
        studiosCoreChrome
            .sheet(isPresented: $showFilterSortSheet, content: studiosFilterSortSheet)
            .onChange(of: catalogPresetRowSelection) { _, newId in
                handleCatalogPresetSelectionChange(newId)
            }
            .alert("Save As", isPresented: $showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $catalogPresetNameInput)
                Button("Save") { saveStudioCatalogPresetAs(name: catalogPresetNameInput) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $showRenameCatalogPresetAlert) {
                TextField("Name", text: $renameCatalogPresetInput)
                Button("Save") { renameStudioCatalogPreset(to: renameCatalogPresetInput) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { deleteStudioCatalogPreset() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteCatalogPresetConfirmationText)
            }
            .onAppear {
                onAppearAction()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
                if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.studios.rawValue {
                    if let defaultId = TabManager.shared.getDefaultFilterId(for: .studios),
                       let newFilter = viewModel.savedFilters[defaultId] {
                        selectedFilter = newFilter
                    } else {
                        selectedFilter = nil
                    }
                    performSearch()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
                if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.studios.rawValue {
                    let newSort = StashDBViewModel.StudioSortOption(rawValue: TabManager.shared.getPersistentSortOption(for: .studios) ?? "") ?? .nameAsc
                    changeSortOption(to: newSort)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
                selectedFilter = nil
                catalogPresetRowSelection = ""
                refreshStudioLocalPresets()
                performSearch()
            }
            .onChange(of: searchText) { oldValue, newValue in
                onSearchTextChange(newValue)
            }
            .onChange(of: viewModel.savedFilters) { oldValue, newValue in
                onSavedFiltersChange(newValue)
            }
            .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
                if oldValue == true && isLoading == false {
                    if viewModel.studios.isEmpty && !viewModel.isLoadingStudios && selectedFilter == nil {
                        viewModel.fetchStudios(sortBy: selectedSortOption, searchQuery: searchText, filter: nil)
                    }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { coordinator.studioToOpen != nil },
                set: { if !$0 { coordinator.studioToOpen = nil } }
            )) {
                if let studio = coordinator.studioToOpen {
                    StudioDetailView(studio: studio)
                }
            }
    }

    @ViewBuilder
    private var studiosCoreChrome: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.isLoading && viewModel.studios.isEmpty {
                StandardLoadingView(message: "Loading studios...")
            } else if viewModel.studios.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.studios.isEmpty {
                emptyStateView
            } else {
                studiosList
            }
        }
        .navigationTitle(hideTitle ? "" : "Studios")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .conditionalSearchable(isVisible: isSearchVisible, text: $searchText, prompt: "Search studios...")
        .toolbar {
            toolbarContent
        }
        .floatingActionBar(isPresented: true, catalogChrome: CatalogFloatingChromeState(hasActiveServerConfig: configManager.activeConfig != nil, primaryListIsEmpty: viewModel.studios.isEmpty, errorMessage: viewModel.errorMessage)) {
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
    private func studiosFilterSortSheet() -> some View {
        StudiosCatalogFilterSortSheet(
            serverFilters: sortedServerStudioFilters,
            localPresets: localCatalogPresets,
            selectedPresetRowId: $catalogPresetRowSelection,
            liveChipRowsVisible: studioLiveChipRowsVisible,
            sortOption: selectedSortOption,
            onSortChange: { changeSortOption(to: $0) },
            liveMinRating: $liveFilterMinRating,
            liveFavorite: $liveFilterFavorite,
            liveScenes: $liveFilterScenes,
            onApply: { applyLiveFilter() },
            onReset: {
                catalogPresetRowSelection = ""
                selectedFilter = nil
                clearStudioLiveChipsOnly()
                applyLiveFilter()
            },
            onRequestSave: { saveStudioCatalogPresetOverwrite() },
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
            refreshStudioLocalPresets()
            applyCatalogPresetSelectionFromSheetIfNeeded()
        }
    }

    private func handleCatalogPresetSelectionChange(_ newId: String) {
        guard showFilterSortSheet else { return }
        if newId.isEmpty {
            selectedFilter = nil
            clearStudioLiveChipsOnly()
            applyLiveFilter()
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerStudioSavedFilter(f)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyStudioCatalogPreset(preset)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

    private func onSearchTextChange(_ newValue: String) {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if newValue == self.searchText {
                self.performSearch()
            }
        }
    }

    private func onAppearAction() {
        var forceRefresh = false
        if let injectedSortStr = coordinator.activeSortOption,
           let injectedSort = StashDBViewModel.StudioSortOption(rawValue: injectedSortStr) {
            selectedSortOption = injectedSort
            coordinator.activeSortOption = nil
            forceRefresh = true
        }

        // Check for search text from navigation
        if !coordinator.activeSearchText.isEmpty {
            searchText = coordinator.activeSearchText
            isSearchVisible = true
            coordinator.activeSearchText = ""
            viewModel.fetchStudios(sortBy: selectedSortOption, searchQuery: searchText, filter: selectedFilter)
            viewModel.fetchSavedFilters()
            return
        }
        
        if TabManager.shared.getDefaultFilterId(for: .studios) == nil || !viewModel.savedFilters.isEmpty {
            if forceRefresh || viewModel.studios.isEmpty {
                performSearch()
            }
        }
        viewModel.fetchSavedFilters()
    }

    private func onSavedFiltersChange(_ newValue: [String: StashDBViewModel.SavedFilter]) {
        if selectedFilter == nil {
            if let defaultId = TabManager.shared.getDefaultFilterId(for: .studios),
               let filter = newValue[defaultId] {
                selectedFilter = filter
                // Only fetch if empty to avoid resetting scroll
                if viewModel.studios.isEmpty {
                    viewModel.fetchStudios(sortBy: selectedSortOption, searchQuery: searchText, filter: filter)
                }
            } else if !viewModel.isLoadingSavedFilters {
                // Default filter was set but not found, or filters finished loading and none match
                // Only fetch if empty
                if viewModel.studios.isEmpty {
                    viewModel.fetchStudios(sortBy: selectedSortOption, searchQuery: searchText, filter: nil)
                }
            }
        }
    }

    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: "building.2",
            title: "No studios found",
            buttonText: "Load Studios",
            onRetry: { performSearch() }
        )
    }

    @Environment(\.verticalSizeClass) var verticalSizeClass

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else if verticalSizeClass == .compact {
             return [
                 GridItem(.flexible(), spacing: 12),
                 GridItem(.flexible(), spacing: 12)
             ]
        } else {
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
    }

    private var studiosList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.studios) { studio in
                        NavigationLink(destination: StudioDetailView(studio: studio)) {
                            StudioCardView(studio: studio)
                        }
                        .buttonStyle(.plain)
                        .id(studio.id)
                        .simultaneousGesture(TapGesture().onEnded {
                            lastOpenedStudioId = studio.id
                        })
                    }
                }
                .padding(16)
            }
            .refreshable { performSearch() }
            .onAppear {
                if let id = lastOpenedStudioId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
        }
    }
    
}

// Studio image view with fallback URL support for SVG handling
// Studio image view with hybrid support (PNG/JPG + SVG)
struct StudioImageView: View {
    let studio: Studio
    @State private var imageLoadState: ImageLoadState = .loading

    enum ImageLoadState {
        case loading
        case success(Image)
        case successSVG(Data, String)
        case failure
    }

    private var imageURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return URL(string: "\(config.baseURL)/studio/\(studio.id)/image")
    }

    var body: some View {
        Group {
            switch imageLoadState {
            case .loading:
                Rectangle()
                    .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                    .overlay(ProgressView())

            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            case .successSVG(let svgData, let svgString):
                 ZStack {
                    SVGWebView(svgData: svgData, svgString: svgString)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Transparent overlay to catch touches if needed, or let them pass usually
                    Color.clear.contentShape(Rectangle())
                 }

            case .failure:
                placeholderView
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: "building.2")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(studio.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            )
    }

    private func loadImage() async {
        guard let url = imageURL else {
            imageLoadState = .failure
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30.0
            
            if let config = ServerConfigManager.shared.loadConfig(),
               let apiKey = config.secureApiKey, !apiKey.isEmpty {
                request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                AppLog.error("❌ Studio Image HTTP Error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                imageLoadState = .failure
                return
            }

            // 1. Try generic Image (PNG, JPG)
            if let uiImage = UIImage(data: data) {
                imageLoadState = .success(Image(uiImage: uiImage))
                return
            }

            // 2. Try SVG
            // Check header or content
            let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
            let isSVGHeader = contentType?.contains("svg") == true
            
            // Also peek at data
            let dataString = String(data: data, encoding: .utf8) ?? ""
            let isSVGContent = dataString.contains("<svg")
            
            if isSVGHeader || isSVGContent {
                if !dataString.isEmpty {
                    imageLoadState = .successSVG(data, dataString)
                    return
                }
            }

            // Fail
            AppLog.error("❌ Failed to decode studio image for \(studio.name)")
            imageLoadState = .failure
            
        } catch {
            AppLog.error("❌ Error loading studio image: \(error.localizedDescription)")
            imageLoadState = .failure
        }
    }
}

// Row-based view for list layout
struct StudioRowView: View {
    let studio: Studio
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        HStack(spacing: 16) {
            // Logo on the left (square with gray background)
            ZStack {
                Color.studioHeaderGray(for: appearance.currentTheme)
                
                StudioImageView(studio: studio)
                    .frame(width: 50, height: 50)
                    .clipped()
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Studio info
            VStack(alignment: .leading, spacing: 4) {
                Text(studio.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                HStack(spacing: 4) {
                    Image(systemName: "film")
                        .font(.caption2)
                    Text("\(studio.sceneCount) Scenes")
                        .font(.caption)
                }
                .foregroundColor(.appAccent)
            }
            
            Spacer()
            
            // Chevron removed as requested
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.secondaryAppBackground(for: appearance.currentTheme))
        .contentShape(Rectangle())
    }
}

struct StudioCardView: View {
    let studio: Studio
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo Block (Top)
            Color.studioHeaderGray(for: appearance.currentTheme)
                .aspectRatio(2.2, contentMode: .fit)
                .overlay(
                    StudioImageView(studio: studio)
                )
                .clipped()
            
            // Name & Info Area (Below)
            HStack(spacing: 8) {
                Text(studio.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Scenes
                    HStack(spacing: 3) {
                        Image(systemName: "film")
                            .font(.system(size: 10))
                        Text("\(studio.sceneCount)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    
                    // Galleries
                    if let galleryCount = studio.galleryCount, galleryCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 10))
                            Text("\(galleryCount)")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                }
                .foregroundColor(.secondary)
                .layoutPriority(1) // Ensure counts get space first
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color.secondaryAppBackground(for: appearance.currentTheme))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}

// SVG WebView for displaying SVG images
struct SVGWebView: UIViewRepresentable {
    let svgData: Data
    let svgString: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bouncesZoom = false
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.isUserInteractionEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let svgString = svgString {
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                <style>
                    * { box-sizing: border-box; margin: 0; padding: 0; }
                    html, body {
                        width: 100vw;
                        height: 100vh;
                        background: transparent;
                        overflow: hidden;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                    }
                    svg {
                        width: 100vw !important;
                        height: 100vh !important;
                        max-width: 100vw !important;
                        max-height: 100vh !important;
                        display: block;
                        object-fit: contain;
                    }
                </style>
            </head>
            <body>
                \(svgString)
                <script>
                    var svg = document.querySelector('svg');
                    if (svg) {
                        if (!svg.getAttribute('viewBox')) {
                            var w = svg.getAttribute('width') || '100';
                            var h = svg.getAttribute('height') || '100';
                            svg.setAttribute('viewBox', '0 0 ' + parseFloat(w) + ' ' + parseFloat(h));
                        }
                        svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
                        svg.removeAttribute('width');
                        svg.removeAttribute('height');
                    }
                </script>
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

struct StudiosView: View {
    @StateObject private var ownedViewModel = StashDBViewModel()
    let catalogBrowserViewModel: StashDBViewModel?
    let initialSort: StashDBViewModel.StudioSortOption?
    var hideTitle: Bool = false

    init(initialSort: StashDBViewModel.StudioSortOption? = nil, hideTitle: Bool = false, catalogBrowserViewModel: StashDBViewModel? = nil) {
        self.catalogBrowserViewModel = catalogBrowserViewModel
        self.initialSort = initialSort
        self.hideTitle = hideTitle
    }

    var body: some View {
        StudiosViewContent(
            viewModel: catalogBrowserViewModel ?? ownedViewModel,
            initialSort: initialSort,
            hideTitle: hideTitle
        )
    }
}

#Preview {
    StudiosView()
}
#endif
