//
//  MarkersView.swift
//  stashy
//

#if !os(tvOS)
import SwiftUI

private struct MarkersViewContent: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    
    @State private var selectedSortOption: StashDBViewModel.SceneMarkerSortOption = StashDBViewModel.SceneMarkerSortOption(rawValue: TabManager.shared.getSortOption(for: .markers) ?? "") ?? .createdAtDesc
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var showFilterSortSheet = false
    @State private var markerLiveChips = SceneLiveChipRowState()
    @State private var liveSheetPresetSelection = ""
    @StateObject private var criteriaDocument = FilterCriteriaDocument(mode: .sceneMarkers)
    @State private var markerLocalPresets: [MarkerLiveFilterPreset] = MarkerLiveFilterPresetStore.loadPresets()
    @State private var showSaveAsPresetAlert = false
    @State private var presetNameInput = ""
    @State private var showRenamePresetAlert = false
    @State private var showDeletePresetAlert = false
    @State private var studioPickerOptions: [Studio] = []
    @State private var studioPickerLoading = false
    @State private var tagPickerOptions: [Tag] = []
    @State private var tagPickerLoading = false
    @State private var groupPickerOptions: [StashGroup] = []
    @State private var groupPickerLoading = false
    var hideTitle: Bool = false

    init(viewModel: StashDBViewModel, hideTitle: Bool = false) {
        self.viewModel = viewModel
        self.hideTitle = hideTitle
    }
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
            return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        }
    }

    private func performSearch(isInitialLoad: Bool = true) {
        let chips = markerLiveChips.effectiveLiveFilter(for: selectedFilter)
        // The selected filter's criteria live in `criteriaDocument`, so the fetch sends those —
        // unless the editor is still empty (default filter on appear), then send the filter itself.
        let live = criteriaDocument.merged(with: chips)
        let base = criteriaDocument.isEmpty ? selectedFilter : nil
        viewModel.fetchSceneMarkers(sortBy: selectedSortOption, searchQuery: searchText, filter: base, liveFilter: live)
    }

    /// Mirrors a selected server filter into the advanced criteria editor so it stays editable.
    private func loadCriteriaDocument(from filter: StashDBViewModel.SavedFilter) {
        if let meta = filter.stashyScenePresetMetadata {
            var merged: [String: Any] = [:]
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                merged = base.criteriaObjectFilter()
            }
            for (key, value) in FilterMapper.sanitize(meta.liveFragment, isMarker: true) {
                merged[key] = value
            }
            criteriaDocument.load(merged)
        } else {
            criteriaDocument.load(filter.criteriaObjectFilter())
        }
    }

    private var sortedServerMarkerFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .sceneMarkers }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    private var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || markerLiveChips.isLiveFilterActive || !criteriaDocument.isEmpty || !liveSheetPresetSelection.isEmpty
    }

    private func loadStudiosForMarkerLivePicker() {
        guard !studioPickerLoading else { return }
        studioPickerLoading = true
        viewModel.fetchStudiosForLiveFilterPicker(mode: .scenesHasScenes) { list in
            studioPickerOptions = list
            studioPickerLoading = false
        }
    }

    private func loadTagsForMarkerLivePicker() {
        guard !tagPickerLoading else { return }
        tagPickerLoading = true
        viewModel.fetchTagsForSceneLiveFilterPicker { list in
            tagPickerOptions = list
            tagPickerLoading = false
        }
    }

    private func loadGroupsForMarkerLivePicker() {
        guard !groupPickerLoading else { return }
        groupPickerLoading = true
        viewModel.fetchGroupsForSceneLiveFilterPicker { list in
            groupPickerOptions = list
            groupPickerLoading = false
        }
    }

    private func refreshMarkerLocalPresets() {
        markerLocalPresets = MarkerLiveFilterPresetStore.loadPresets()
    }

    private func applyLiveFilterFromSheet() {
        performSearch()
    }

    private func clearMarkerLiveChipsOnly() {
        markerLiveChips.clearChipsOnly()
    }

    private func mapMarkerLiveFragmentToChips(_ frag: [String: Any]) {
        markerLiveChips.mapLiveFragmentToChips(frag)
    }

    private func applyServerMarkerSavedFilter(_ f: StashDBViewModel.SavedFilter) {
        if let meta = f.stashyScenePresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if SceneLiveChipFilterSupport.savedFilterSupportsLiveChipEditor(selectedFilter) {
                mapMarkerLiveFragmentToChips(meta.liveFragment)
            } else {
                clearMarkerLiveChipsOnly()
                applyAuxIdsFromMarkerFragment(meta.liveFragment)
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.SceneMarkerSortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
                TabManager.shared.setSortOption(for: .markers, option: parsed.rawValue)
            }
        } else {
            selectedFilter = f
            let sanitizeAsMarker = (f.mode == .sceneMarkers)
            if SceneLiveChipFilterSupport.savedFilterSupportsLiveChipEditor(f), let raw = f.filterDict {
                mapMarkerLiveFragmentToChips(raw)
            } else {
                clearMarkerLiveChipsOnly()
                let flat: [String: Any]? = {
                    if let raw = f.filterDict { return FilterMapper.sanitize(raw, isMarker: sanitizeAsMarker) }
                    if let obj = f.object_filter, let objDict = obj.value as? [String: Any] {
                        return FilterMapper.sanitize(objDict, isMarker: sanitizeAsMarker)
                    }
                    return nil
                }()
                if let flat { applyAuxIdsFromMarkerFragment(flat) }
            }
        }
        loadCriteriaDocument(from: f)
        applyLiveFilterFromSheet()
    }

    private func applyAuxIdsFromMarkerFragment(_ frag: [String: Any]) {
        let f = FilterMapper.sanitize(frag, isMarker: false)
        markerLiveChips.studioIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["studios"])
        markerLiveChips.tagIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["tags"])
        markerLiveChips.groupIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["groups"])
    }

    private func applyMarkerCatalogPreset(_ preset: MarkerLiveFilterPreset) {
        let sort = preset.sort
        if sort != selectedSortOption {
            if sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = sort
            TabManager.shared.setSortOption(for: .markers, option: sort.rawValue)
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if SceneLiveChipFilterSupport.savedFilterSupportsLiveChipEditor(selectedFilter) {
            mapMarkerLiveFragmentToChips(preset.liveFragment)
        } else {
            clearMarkerLiveChipsOnly()
            applyAuxIdsFromMarkerFragment(preset.liveFragment)
        }
        applyLiveFilterFromSheet()
    }

    private func applyMarkerPresetFromSelectionIfNeeded() {
        let newId = liveSheetPresetSelection
        guard !newId.isEmpty else { return }
        if let sid = SceneLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerMarkerSavedFilter(f)
            return
        }
        if let ls = SceneLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = markerLocalPresets.first(where: { $0.id == uuid }) {
            applyMarkerCatalogPreset(preset)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = markerLocalPresets.first(where: { $0.id == uuid }) {
            liveSheetPresetSelection = SceneLivePresetTag.localRow(uuid)
            applyMarkerCatalogPreset(preset)
        }
    }

    private var deleteMarkerPresetConfirmationText: String {
        if let sid = SceneLivePresetTag.parseServerId(liveSheetPresetSelection),
           let f = viewModel.savedFilters[sid] {
            return "Remove “\(f.name)” from Stash? Other devices will lose this saved filter."
        }
        if let ls = SceneLivePresetTag.parseLocalUUIDString(liveSheetPresetSelection),
           let uuid = UUID(uuidString: ls),
           let p = markerLocalPresets.first(where: { $0.id == uuid }) {
            return "Remove “\(p.name)” from this device? This cannot be undone."
        }
        return "Remove this filter? This cannot be undone."
    }

    private func saveMarkerPresetOverwrite() {
        let sel = liveSheetPresetSelection
        let liveDict = markerLiveChips.activeLiveFilterDict()
        if let sid = SceneLivePresetTag.parseServerId(sel) {
            let currentName = viewModel.savedFilters[sid]?.name ?? "Filter"
            viewModel.saveCatalogSavedFilter(
                mode: .sceneMarkers,
                randomSeedKind: .markers,
                existingId: sid,
                name: currentName,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: liveDict
            ) { _ in }
            return
        }
        guard let ls = SceneLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let index = markerLocalPresets.firstIndex(where: { $0.id == uuid }) else { return }
        let old = markerLocalPresets[index]
        let updated = MarkerLiveFilterPreset(
            id: old.id,
            name: old.name,
            createdAt: old.createdAt,
            sort: selectedSortOption,
            baseSavedFilterId: selectedFilter?.id,
            liveFragment: liveDict
        )
        MarkerLiveFilterPresetStore.upsert(updated)
        refreshMarkerLocalPresets()
    }

    private func saveMarkerPresetAs(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveCatalogSavedFilter(
            mode: .sceneMarkers,
            randomSeedKind: .markers,
            existingId: nil,
            name: trimmed,
            sortRaw: selectedSortOption.rawValue,
            sortField: selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            baseFilter: selectedFilter,
            liveFragment: markerLiveChips.activeLiveFilterDict()
        ) { result in
            if case .success(let saved) = result {
                liveSheetPresetSelection = SceneLivePresetTag.serverRow(saved.id)
                showSaveAsPresetAlert = false
            }
        }
    }

    private func renameMarkerPreset(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sel = liveSheetPresetSelection
        if let sid = SceneLivePresetTag.parseServerId(sel) {
            viewModel.saveCatalogSavedFilter(
                mode: .sceneMarkers,
                randomSeedKind: .markers,
                existingId: sid,
                name: trimmed,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: markerLiveChips.activeLiveFilterDict()
            ) { result in
                if case .success = result { showRenamePresetAlert = false }
            }
            return
        }
        guard let ls = SceneLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = markerLocalPresets.first(where: { $0.id == uuid }) else { return }
        MarkerLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshMarkerLocalPresets()
        showRenamePresetAlert = false
    }

    private func deleteMarkerPreset() {
        let sel = liveSheetPresetSelection
        if let sid = SceneLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { result in
                if case .success = result {
                    liveSheetPresetSelection = ""
                    selectedFilter = nil
                    clearMarkerLiveChipsOnly()
                    applyLiveFilterFromSheet()
                    showDeletePresetAlert = false
                }
            }
            return
        }
        guard let ls = SceneLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        MarkerLiveFilterPresetStore.remove(id: uuid)
        refreshMarkerLocalPresets()
        liveSheetPresetSelection = ""
        selectedFilter = nil
        clearMarkerLiveChipsOnly()
        applyLiveFilterFromSheet()
        showDeletePresetAlert = false
    }

    private func syncMarkerChipsFromSelectedFilter() {
        var m = markerLiveChips
        m.syncLiveChipsToMatchSelectedFilter(selectedFilter, savedFilters: viewModel.savedFilters)
        markerLiveChips = m
    }

    private var markerLiveMinRating: Binding<Int> {
        Binding(get: { markerLiveChips.minRating }, set: { markerLiveChips.minRating = $0 })
    }
    private var markerLiveOrganized: Binding<Bool?> {
        Binding(get: { markerLiveChips.organized }, set: { markerLiveChips.organized = $0 })
    }
    private var markerLiveInteractive: Binding<Bool?> {
        Binding(get: { markerLiveChips.interactive }, set: { markerLiveChips.interactive = $0 })
    }
    private var markerLiveOrientation: Binding<String?> {
        Binding(get: { markerLiveChips.orientation }, set: { markerLiveChips.orientation = $0 })
    }
    private var markerLivePerformerCount: Binding<Int?> {
        Binding(get: { markerLiveChips.performerCount }, set: { markerLiveChips.performerCount = $0 })
    }
    private var markerLiveResolution: Binding<String?> {
        Binding(get: { markerLiveChips.resolution }, set: { markerLiveChips.resolution = $0 })
    }
    private var markerLivePerformerFavorite: Binding<Bool?> {
        Binding(get: { markerLiveChips.performerFavorite }, set: { markerLiveChips.performerFavorite = $0 })
    }
    private var markerLiveOCounterTag: Binding<String?> {
        Binding(get: { markerLiveChips.oCounterTag }, set: { markerLiveChips.oCounterTag = $0 })
    }
    private var markerLiveStudioIds: Binding<[String]> {
        Binding(get: { markerLiveChips.studioIds }, set: { markerLiveChips.studioIds = $0 })
    }
    private var markerLiveTagIds: Binding<[String]> {
        Binding(get: { markerLiveChips.tagIds }, set: { markerLiveChips.tagIds = $0 })
    }
    private var markerLiveGroupIds: Binding<[String]> {
        Binding(get: { markerLiveChips.groupIds }, set: { markerLiveChips.groupIds = $0 })
    }

    @ViewBuilder
    private var markersFilterSortSheet: some View {
        SceneLiveFilterSheet(
            serverSceneFilters: sortedServerMarkerFilters,
            localPresets: [],
            markerLocalPresets: markerLocalPresets,
            selectedPresetId: $liveSheetPresetSelection,
            criteriaDocument: criteriaDocument,
            sortOption: .dateDesc,
            onSortChange: { _ in },
            minRating: markerLiveMinRating,
            organized: markerLiveOrganized,
            interactive: markerLiveInteractive,
            orientation: markerLiveOrientation,
            performerCount: markerLivePerformerCount,
            resolution: markerLiveResolution,
            performerFavorite: markerLivePerformerFavorite,
            oCounterTag: markerLiveOCounterTag,
            studioSelectionIds: markerLiveStudioIds,
            studioPickerOptions: studioPickerOptions,
            studioPickerLoading: studioPickerLoading,
            onStudioPickerSectionAppear: { loadStudiosForMarkerLivePicker() },
            tagSelectionIds: markerLiveTagIds,
            tagPickerOptions: tagPickerOptions,
            tagPickerLoading: tagPickerLoading,
            onTagPickerSectionAppear: { loadTagsForMarkerLivePicker() },
            groupSelectionIds: markerLiveGroupIds,
            groupPickerOptions: groupPickerOptions,
            groupPickerLoading: groupPickerLoading,
            onGroupPickerSectionAppear: { loadGroupsForMarkerLivePicker() },
            onApply: { applyLiveFilterFromSheet() },
            onReset: {
                liveSheetPresetSelection = ""
                selectedFilter = nil
                criteriaDocument.clear()
                clearMarkerLiveChipsOnly()
                applyLiveFilterFromSheet()
            },
            onRequestSave: { saveMarkerPresetOverwrite() },
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
                          let p = markerLocalPresets.first(where: { $0.id == uuid }) {
                    presetNameInput = p.name
                    showRenamePresetAlert = true
                }
            },
            onRequestDelete: { showDeletePresetAlert = true },
            showsSortControls: false,
            useMarkerSort: true,
            markerSortOption: $selectedSortOption,
            onMarkerSortChange: { changeSortOption(to: $0) }
        )
        .environmentObject(viewModel)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            SceneLivePresetTag.migrateLegacySelection(&liveSheetPresetSelection)
            refreshMarkerLocalPresets()
            applyMarkerPresetFromSelectionIfNeeded()
            viewModel.fetchSavedFilters { _ in
                applyMarkerPresetFromSelectionIfNeeded()
            }
        }
        .onChange(of: liveSheetPresetSelection) { _, newId in
            guard showFilterSortSheet else { return }
            if newId.isEmpty {
                selectedFilter = nil
                clearMarkerLiveChipsOnly()
                applyLiveFilterFromSheet()
                return
            }
            if let sid = SceneLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
                applyServerMarkerSavedFilter(f)
                return
            }
            if let ls = SceneLivePresetTag.parseLocalUUIDString(newId),
               let uuid = UUID(uuidString: ls),
               let preset = markerLocalPresets.first(where: { $0.id == uuid }) {
                applyMarkerCatalogPreset(preset)
                return
            }
            if let uuid = UUID(uuidString: newId),
               let preset = markerLocalPresets.first(where: { $0.id == uuid }) {
                liveSheetPresetSelection = SceneLivePresetTag.localRow(uuid)
                applyMarkerCatalogPreset(preset)
            }
        }
    }

    private var markersMainStack: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if (viewModel.isLoadingMarkers && viewModel.sceneMarkers.isEmpty) || (viewModel.isLoadingSavedFilters && viewModel.savedFilters.isEmpty) {
                StandardLoadingView(message: "Loading markers...")
            } else if viewModel.sceneMarkers.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.sceneMarkers.isEmpty {
                emptyStateView
            } else {
                markersList
            }
        }
        .navigationTitle(hideTitle ? "" : "Markers")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .conditionalSearchable(isVisible: isSearchVisible, text: $searchText, prompt: "Search markers...")
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
    }

    private var markersFloatingFilterBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            CatalogFilterFABButton(isActive: catalogFilterSortFABActive) {
                showFilterSortSheet = true
            }
            Spacer(minLength: 0)
        }
    }

    var body: some View {
        markersMainStack
        .floatingActionBar(isPresented: true, catalogChrome: CatalogFloatingChromeState(hasActiveServerConfig: configManager.activeConfig != nil, primaryListIsEmpty: viewModel.sceneMarkers.isEmpty, errorMessage: viewModel.errorMessage)) {
            markersFloatingFilterBar
        }
        .sheet(isPresented: $showFilterSortSheet) {
            markersFilterSortSheet
        }
        .alert("Save As", isPresented: $showSaveAsPresetAlert) {
            TextField("Name", text: $presetNameInput)
            Button("Save") { saveMarkerPresetAs(name: presetNameInput) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Creates a new saved marker filter on your Stash server (visible in Stash and other clients).")
        }
        .alert("Rename Filter", isPresented: $showRenamePresetAlert) {
            TextField("Name", text: $presetNameInput)
            Button("Rename") { renameMarkerPreset(to: presetNameInput) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Renames the selected Stash saved filter or on-device filter.")
        }
        .alert("Delete Filter", isPresented: $showDeletePresetAlert) {
            Button("Delete", role: .destructive) { deleteMarkerPreset() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(deleteMarkerPresetConfirmationText)
        }
        .onAppear {
            if !coordinator.activeSearchText.isEmpty {
                searchText = coordinator.activeSearchText
                isSearchVisible = true
                coordinator.activeSearchText = ""
                performSearch()
                viewModel.fetchSavedFilters()
                refreshMarkerLocalPresets()
                return
            }
            
            if TabManager.shared.getDefaultMarkerFilterId(for: .markers) == nil || !viewModel.savedFilters.isEmpty {
                if viewModel.sceneMarkers.isEmpty {
                    performSearch()
                }
            }
            viewModel.fetchSavedFilters()
            refreshMarkerLocalPresets()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.markers.rawValue {
                if let defaultId = TabManager.shared.getDefaultMarkerFilterId(for: .markers),
                   let newFilter = viewModel.savedFilters[defaultId] {
                    selectedFilter = newFilter
                } else {
                    selectedFilter = nil
                }
                syncMarkerChipsFromSelectedFilter()
                performSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.markers.rawValue {
                let newSort = StashDBViewModel.SceneMarkerSortOption(rawValue: TabManager.shared.getPersistentSortOption(for: .markers) ?? "") ?? .createdAtDesc
                changeSortOption(to: newSort)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            liveSheetPresetSelection = ""
            clearMarkerLiveChipsOnly()
            refreshMarkerLocalPresets()
            performSearch()
        }
        .sceneLiveUpdates(using: viewModel)
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            if selectedFilter == nil {
                if let defaultId = TabManager.shared.getDefaultMarkerFilterId(for: .markers),
                   let filter = newValue[defaultId] {
                    selectedFilter = filter
                    syncMarkerChipsFromSelectedFilter()
                    performSearch()
                } else if !viewModel.isLoadingSavedFilters {
                    performSearch()
                }
            }
        }
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
            if oldValue == true && isLoading == false {
                if viewModel.sceneMarkers.isEmpty && !viewModel.isLoadingMarkers && selectedFilter == nil {
                    performSearch()
                }
            }
        }
    }
    
    private func changeSortOption(to newOption: StashDBViewModel.SceneMarkerSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        TabManager.shared.setSortOption(for: .markers, option: newOption.rawValue)
        performSearch()
    }

    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: "bookmark.fill",
            title: "No markers found",
            buttonText: "Load Markers",
            onRetry: { performSearch() }
        )
    }

    private var markersList: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.sceneMarkers) { marker in
                    if let markerScene = marker.scene {
                        let mappedScene = markerScene.toScene().withResumeTime(marker.seconds)
                        NavigationLink(destination: SceneDetailView(scene: mappedScene, autoPlay: true)) {
                            MarkerCardView(marker: marker)
                        }
                        .buttonStyle(.plain)
                    } else {
                        MarkerCardView(marker: marker)
                    }
                }
                
                if viewModel.isLoadingMarkers {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if viewModel.hasMoreMarkers && !viewModel.sceneMarkers.isEmpty {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            viewModel.loadMoreMarkers()
                        }
                }
            }
            .padding(16)
        }
        .refreshable { performSearch() }
    }
}

struct MarkersView: View {
    @StateObject private var ownedViewModel = StashDBViewModel()
    let catalogBrowserViewModel: StashDBViewModel?
    var hideTitle: Bool = false

    init(hideTitle: Bool = false, catalogBrowserViewModel: StashDBViewModel? = nil) {
        self.hideTitle = hideTitle
        self.catalogBrowserViewModel = catalogBrowserViewModel
    }

    var body: some View {
        MarkersViewContent(viewModel: catalogBrowserViewModel ?? ownedViewModel, hideTitle: hideTitle)
    }
}

struct MarkerCardView: View {
    let marker: SceneMarker
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Background Image
                ZStack {
                    Color.studioHeaderGray
                    
                    if let thumbURL = marker.thumbnailURL {
                        CustomAsyncImage(url: thumbURL) { loader in
                            if loader.isLoading {
                                ProgressView()
                            } else if let image = loader.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "bookmark.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(appearanceManager.tintColor)
                            }
                        }
                    } else {
                        Image(systemName: "bookmark.fill")
                            .font(.largeTitle)
                            .foregroundColor(appearanceManager.tintColor)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                
                // Bottom Gradient for contrast
                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                    .frame(height: 60)
                
                // Overlay Info
                VStack {
                    HStack(alignment: .top) {
                        // Marker Name (Top Left)
                        Text(marker.title ?? "Marker")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
                            .clipShape(Capsule())
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Play count pill (Top Right)
                        if let playCount = marker.playCount, playCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 8))
                                Text("\(playCount)")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
                            .clipShape(Capsule())
                        }
                    }
                    
                    Spacer()
                    
                    // Scene Name (Bottom Left)
                    Text(marker.scene?.title ?? "Unknown Scene")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .bottomLeading)
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                }
                .padding(8)
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}
#endif
