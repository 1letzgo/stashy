//
//  TagsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

#if !os(tvOS)
import SwiftUI

private struct TagsViewContent: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.TagSortOption = StashDBViewModel.TagSortOption(rawValue: TabManager.shared.getSortOption(for: .tags) ?? "") ?? .sceneCountDesc
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil
    /// Settings default filter applies once per view lifetime; `selectedFilter == nil` alone
    /// also means "user reset to Any", and every `savedFilters` refresh re-applied it.
    @State private var didApplyDefaultFilter = false
    @State private var lastOpenedTagId: String?
    @State private var isChangingSort = false
    @State private var searchText = ""
    @State private var isSearchVisible = false
    var hideTitle: Bool = false

    init(viewModel: StashDBViewModel, hideTitle: Bool = false, filterMemory: CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.TagSortOption>>? = nil) {
        self.viewModel = viewModel
        self.hideTitle = hideTitle
        self.filterMemory = filterMemory
        if let filterMemory {
            _criteriaDocument = StateObject(wrappedValue: filterMemory.criteriaDocument)
            // Remount (Home sub-tab switch): restore what the list was fetched with.
            if let snap = filterMemory.snapshot {
                _selectedSortOption = State(initialValue: snap.sortOption)
                _selectedFilter = State(initialValue: snap.selectedFilter)
                _catalogPresetRowSelection = State(initialValue: snap.presetSelection)
                _searchText = State(initialValue: snap.searchText)
                _isSearchVisible = State(initialValue: snap.isSearchVisible)
                _didApplyDefaultFilter = State(initialValue: snap.didApplyDefaultFilter)
            }
        }
    }

    /// Host-owned filter state (Home sub-tab, see `CatalogRootFilterMemories`); `nil` = the
    /// state lives and dies with this view.
    private let filterMemory: CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.TagSortOption>>?

    private var filterMemorySnapshot: CatalogListFilterSnapshot<StashDBViewModel.TagSortOption> {
        CatalogListFilterSnapshot(
            sortOption: selectedSortOption,
            selectedFilter: selectedFilter,
            presetSelection: catalogPresetRowSelection,
            searchText: searchText,
            isSearchVisible: isSearchVisible,
            didApplyDefaultFilter: didApplyDefaultFilter
        )
    }

    // Filter & sort sheet
    @State private var showFilterSortSheet = false
    @AppStorage(TagHierarchy.hideSubTagsKey) private var hidesSubTags = false
    @AppStorage(TagHierarchy.includeSubTagContentKey) private var includesSubTagContent = false
    @StateObject private var criteriaDocument = FilterCriteriaDocument(mode: .tags, pinsDefaults: true)

    @State private var catalogPresetRowSelection = ""
    @State private var localCatalogPresets: [TagListLiveFilterPreset] = TagListLiveFilterPresetStore.loadPresets()
    @State private var showSaveAsCatalogPresetAlert = false
    @State private var catalogPresetNameInput = ""
    @State private var showRenameCatalogPresetAlert = false
    @State private var renameCatalogPresetInput = ""
    @State private var showDeleteCatalogPresetAlert = false

    // Live filter (chips)
    @State private var liveFilterFavorite: Bool? = nil
    /// "has" / "none"; nil = any.
    @State private var liveFilterScenes: String?

    private var isLiveFilterActive: Bool { false }

    private var activeLiveFilterDict: [String: Any] { [:] }

    /// Passed to `filter:` only while the advanced editor holds no copy of it. Once the editor has
    /// the criteria, re-sending the server filter would resurrect criteria the user edited away;
    /// while it is empty (e.g. a default filter applied on appear) the filter still has to be sent.
    private var fetchBaseFilter: StashDBViewModel.SavedFilter? {
        criteriaDocument.isEmpty ? selectedFilter : nil
    }

    /// Quick chips plus advanced criteria from the editor — what actually gets fetched.
    private var effectiveLiveFilter: [String: Any]? {
        var merged = criteriaDocument.merged(with: isLiveFilterActive ? activeLiveFilterDict : [:]) ?? [:]
        // "Hide sub-tags": top-level tags only. A search still finds every tag, and a parent
        // criterion of the user's own wins.
        if hidesSubTags, searchText.isEmpty, merged["parents"] == nil, merged["parent_count"] == nil {
            merged["parent_count"] = ["value": 0, "modifier": "EQUALS"]
        }
        return merged.isEmpty ? nil : merged
    }

    private func applyLiveFilter() {
        viewModel.currentTagLiveFilter = effectiveLiveFilter ?? [:]
        viewModel.fetchTags(sortBy: selectedSortOption, searchQuery: searchText, filter: fetchBaseFilter, liveFilter: effectiveLiveFilter)
    }

    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var gridWidth: CGFloat = 0

    private var columns: [GridItem] {
        DesignTokens.Grid.adaptiveColumns(
            width: gridWidth,
            ideal: DesignTokens.Grid.idealPosterCardWidth,
            minimum: 2,
            maximum: 8
        )
    }

    // Search function
    private func performSearch(isInitialLoad: Bool = true) {
        viewModel.fetchTags(sortBy: selectedSortOption, searchQuery: searchText, isInitialLoad: isInitialLoad, filter: fetchBaseFilter, liveFilter: effectiveLiveFilter)
    }

    private func changeTagSortOption(to newOption: StashDBViewModel.TagSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        TabManager.shared.setSortOption(for: .tags, option: newOption.rawValue)
        performSearch()
    }

    private var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || !criteriaDocument.isEmpty || !catalogPresetRowSelection.isEmpty
    }

    private var sortedServerTagFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .tags }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    private func refreshTagLocalPresets() {
        localCatalogPresets = TagListLiveFilterPresetStore.loadPresets()
    }

    private func clearTagLiveChipsOnly() {
        liveFilterFavorite = nil
        liveFilterScenes = nil
    }

    private func mapTagLiveFragmentToChips(_ frag: [String: Any]) {
        clearTagLiveChipsOnly()
        if let fav = frag["favorite"] as? Bool {
            liveFilterFavorite = fav
        }
        if let sc = frag["scene_count"] as? [String: Any],
           let mod = sc["modifier"] as? String {
            if mod == "GREATER_THAN" { liveFilterScenes = "has" }
            if mod == "EQUALS", (sc["value"] as? Int) == 0 { liveFilterScenes = "none" }
        }
    }

    private func applyTagCatalogPreset(_ preset: TagListLiveFilterPreset) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
            TabManager.shared.setSortOption(for: .tags, option: preset.sort.rawValue)
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.tagSavedFilterSupportsLiveEditor(selectedFilter) {
            mapTagLiveFragmentToChips(preset.liveFragment)
        } else {
            clearTagLiveChipsOnly()
        }
        // Ein lokales Preset speichert seine Kriterien im `liveFragment` — die legt der Editor
        // über die Kriterien des Basisfilters, damit die Sheet zeigt, was wirklich gefiltert wird.
        var mergedPresetCriteria: [String: Any] = selectedFilter?.criteriaObjectFilter() ?? [:]
        for (key, value) in preset.liveFragment { mergedPresetCriteria[key] = value }
        criteriaDocument.load(mergedPresetCriteria)
        performSearch()
    }


    /// Mirrors a selected server filter into the advanced criteria editor so its criteria stay
    /// editable in the app; fetches then pass `filter: nil` and send the document instead.
    private func loadCriteriaDocument(from filter: StashDBViewModel.SavedFilter) {
        // `object_filter` holds every criterion in the web UI's format (base filter and chips
        // merged when it was saved); the old `ui_options.stashy` copy would override edits
        // made in Stash itself.
        criteriaDocument.load(filter.criteriaObjectFilter())
    }

    private func applyServerTagSavedFilter(_ f: StashDBViewModel.SavedFilter) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.tagSavedFilterSupportsLiveEditor(selectedFilter) {
                mapTagLiveFragmentToChips(meta.liveFragment)
            } else {
                clearTagLiveChipsOnly()
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.TagSortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
                TabManager.shared.setSortOption(for: .tags, option: parsed.rawValue)
            }
        } else {
            selectedFilter = f
            if CatalogLiveChipFilterSupport.tagSavedFilterSupportsLiveEditor(f), let raw = f.filterDict {
                mapTagLiveFragmentToChips(raw)
            } else {
                clearTagLiveChipsOnly()
            }
        }
        loadCriteriaDocument(from: f)
        performSearch()
    }

    private func applyCatalogPresetSelectionFromSheetIfNeeded() {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerTagSavedFilter(f)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyTagCatalogPreset(preset)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyTagCatalogPreset(preset)
        }
    }

    private var deleteCatalogPresetConfirmationText: String {
        if let sid = ListLivePresetTag.parseServerId(catalogPresetRowSelection),
           let f = viewModel.savedFilters[sid] {
            return tr("hint_remove_arg_from_stash_other", f.name)
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection),
           let uuid = UUID(uuidString: ls),
           let p = localCatalogPresets.first(where: { $0.id == uuid }) {
            return tr("hint_remove_arg_from_this_device", p.name)
        }
        return tr("hint_remove_this_filter_this_cannot")
    }

    private func saveTagCatalogPresetOverwrite() {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            let name = viewModel.savedFilters[sid]?.name ?? tr("filter")
            viewModel.saveCatalogSavedFilter(
                mode: .tags,
                randomSeedKind: .tags,
                existingId: sid,
                name: name,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: criteriaDocument.merged(with: activeLiveFilterDict) ?? [:]
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
            liveFragment: criteriaDocument.merged(with: activeLiveFilterDict) ?? [:]
        )
        TagListLiveFilterPresetStore.upsert(updated)
        refreshTagLocalPresets()
    }

    private func saveTagCatalogPresetAs(name: String) {
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
            liveFragment: criteriaDocument.merged(with: activeLiveFilterDict) ?? [:]
        ) { result in
            if case .success(let saved) = result {
                catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                showSaveAsCatalogPresetAlert = false
            }
        }
    }

    private func renameTagCatalogPreset(to newName: String) {
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
                liveFragment: criteriaDocument.merged(with: activeLiveFilterDict) ?? [:]
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
        TagListLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshTagLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    private func deleteTagCatalogPreset() {
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
        TagListLiveFilterPresetStore.remove(id: uuid)
        refreshTagLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }

    var body: some View {
        tagsCoreChrome
            .sheet(isPresented: $showFilterSortSheet, content: tagsFilterSortSheet)
            .onChange(of: hidesSubTags) { _, _ in applyLiveFilter() }
            // The cards count sub-tags in while the content switch is on.
            .onChange(of: includesSubTagContent) { _, _ in applyLiveFilter() }
            // A tag got or lost a parent: it joins or leaves the top level.
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TagParentsChanged"))) { _ in
                applyLiveFilter()
            }
            .onChange(of: catalogPresetRowSelection) { _, newId in
                handleTagCatalogPresetSelectionChange(newId)
            }
            .alert(tr("action_save_as_new"), isPresented: $showSaveAsCatalogPresetAlert) {
                TextField(tr("name"), text: $catalogPresetNameInput)
                Button(tr("action_save")) { saveTagCatalogPresetAs(name: catalogPresetNameInput) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_save_current_sort_filter_and"))
            }
            .alert(tr("action_rename"), isPresented: $showRenameCatalogPresetAlert) {
                TextField(tr("name"), text: $renameCatalogPresetInput)
                Button(tr("action_save")) { renameTagCatalogPreset(to: renameCatalogPresetInput) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_rename_this_preset_or_saved"))
            }
            .alert(tr("confirm_delete_filter"), isPresented: $showDeleteCatalogPresetAlert) {
                Button(tr("action_delete"), role: .destructive) { deleteTagCatalogPreset() }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(deleteCatalogPresetConfirmationText)
            }
            .onAppear {
                tagsOnAppear()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
                if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.tags.rawValue {
                    if let defaultId = TabManager.shared.getDefaultFilterId(for: .tags),
                       let newFilter = viewModel.savedFilters[defaultId] {
                        selectedFilter = newFilter
                        didApplyDefaultFilter = true
                    } else {
                        selectedFilter = nil
                    }
                    performSearch()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
                if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.tags.rawValue {
                    let newSort = StashDBViewModel.TagSortOption(rawValue: TabManager.shared.getPersistentSortOption(for: .tags) ?? "") ?? .sceneCountDesc
                    changeTagSortOption(to: newSort)
                }
            }
            .onDisappear {
                filterMemory?.snapshot = filterMemorySnapshot
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
                selectedFilter = nil
                didApplyDefaultFilter = false
                catalogPresetRowSelection = ""
                criteriaDocument.clear()
                refreshTagLocalPresets()
                performSearch()
            }
            .onChange(of: viewModel.savedFilters) { _, _ in
                if selectedFilter == nil {
                    if applySettingsDefaultFilterIfNeeded() {
                        performSearch()
                    } else if !viewModel.isLoadingSavedFilters {
                        performSearch()
                    }
                }
            }
            .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
                if oldValue == true && isLoading == false {
                    if viewModel.tags.isEmpty && !viewModel.isLoading && selectedFilter == nil {
                        performSearch()
                    }
                }
            }
    }

    @ViewBuilder
    private var tagsCoreChrome: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if (viewModel.isLoading && viewModel.tags.isEmpty) || (viewModel.isLoadingSavedFilters && viewModel.savedFilters.isEmpty) {
                // Keep the bar while a sort/filter change refetches, so it does not jump away.
                VStack(spacing: 0) {
                    quickBar
                    StandardLoadingView(message: tr("loading_tags"))
                }
            } else if viewModel.tags.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.tags.isEmpty {
                VStack(spacing: 0) {
                    if !criteriaDocument.isEmpty || activePresetName != nil { quickBar }
                    emptyStateView
                }
            } else {
                // Pinned above the list so it always shows, also after coming back from a detail page.
                tagsList
                    .catalogPinnedQuickBar { quickBar }
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if newValue == self.searchText {
                    self.performSearch()
                }
            }
        }
        .stashyCatalogChrome(catalogChromeConfig)
        .homeBreadcrumbChrome(homeMenu) { quickBar(part: .sortMenu) }
    }

    private var catalogChromeConfig: CatalogChromeConfig {
        CatalogChromeConfig(
            title: tr("tags"),
            ownsNavigationBar: !hideTitle,
            visibility: CatalogFloatingChromeState(
                hasActiveServerConfig: configManager.activeConfig != nil,
                primaryListIsEmpty: viewModel.tags.isEmpty,
                errorMessage: viewModel.errorMessage
            ),
            isPresented: true,
            search: CatalogSearchChrome(
                text: $searchText,
                isVisible: $isSearchVisible,
                prompt: tr("placeholder_search_tags"),
                onClear: { performSearch() }
            )
        )
    }

    @ViewBuilder
    private func tagsFilterSortSheet() -> some View {
        TagsCatalogFilterSortSheet(
            serverFilters: sortedServerTagFilters,
            localPresets: localCatalogPresets,
            selectedPresetRowId: $catalogPresetRowSelection,
            criteriaDocument: criteriaDocument,
            sortOption: selectedSortOption,
            onSortChange: { changeTagSortOption(to: $0) },
            onApply: { applyLiveFilter() },
            onReset: { resetAllCatalogFilters() },
            onRequestSave: { saveTagCatalogPresetOverwrite() },
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
            onRequestDelete: { showDeleteCatalogPresetAlert = true },
            showsSubTagOptions: true
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            ListLivePresetTag.migrateLegacySelection(&catalogPresetRowSelection)
            refreshTagLocalPresets()
            applyCatalogPresetSelectionFromSheetIfNeeded()
        }
    }

    /// Sets the Settings-configured default filter for this tab, if one is configured and no
    /// filter is active yet. Mirrors the state assignments of `applyServerTagSavedFilter`
    /// (minus the fetch) so the preset row and chips stay in sync. Returns whether it applied one.
    @discardableResult
    private func applySettingsDefaultFilterIfNeeded() -> Bool {
        guard !didApplyDefaultFilter, selectedFilter == nil else { return false }
        guard let defaultId = TabManager.shared.getDefaultFilterId(for: .tags),
              let filter = viewModel.savedFilters[defaultId] else { return false }

        selectedFilter = filter

        didApplyDefaultFilter = true
        catalogPresetRowSelection = ListLivePresetTag.serverRow(filter.id)
        if CatalogLiveChipFilterSupport.tagSavedFilterSupportsLiveEditor(filter), let raw = filter.filterDict {
            mapTagLiveFragmentToChips(raw)
        } else {
            clearTagLiveChipsOnly()
        }
        loadCriteriaDocument(from: filter)
        return true
    }

    private func handleTagCatalogPresetSelectionChange(_ newId: String) {
        guard showFilterSortSheet else { return }
        if newId.isEmpty {
            selectedFilter = nil
            clearTagLiveChipsOnly()
            applyLiveFilter()
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerTagSavedFilter(f)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyTagCatalogPreset(preset)
        }
    }

    private func tagsOnAppear() {
        if !coordinator.activeSearchText.isEmpty {
            searchText = coordinator.activeSearchText
            isSearchVisible = true
            coordinator.activeSearchText = ""
            performSearch()
            viewModel.fetchSavedFilters()
            return
        }
        // Were saved filters already loaded (warm view model from another catalog sub-tab),
        // `onChange(of: savedFilters)` below never fires - apply the default here instead.
        if applySettingsDefaultFilterIfNeeded() {
            performSearch()
        } else if TabManager.shared.getDefaultFilterId(for: .tags) == nil || !viewModel.savedFilters.isEmpty {
            if viewModel.tags.isEmpty {
                performSearch()
            }
        }
        viewModel.fetchSavedFilters()
    }

    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: "tag.fill",
            title: tr("empty_tags_found"),
            buttonText: tr("action_load_tags"),
            onRetry: { performSearch() }
        )
    }

    /// Sheet "Reset" and the saved-filter chip's ✕: drops the preset and every criterion.
    private func resetAllCatalogFilters() {
        catalogPresetRowSelection = ""
        selectedFilter = nil
        clearTagLiveChipsOnly()
        criteriaDocument.clear()
        applyLiveFilter()
    }

    /// Name of the active saved filter / local preset for the removable chip above the list.
    private var activePresetName: String? {
        if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection), let uuid = UUID(uuidString: ls) {
            return localCatalogPresets.first { $0.id == uuid }?.name
        }
        if let sid = ListLivePresetTag.parseServerId(catalogPresetRowSelection) {
            return viewModel.savedFilters[sid]?.name ?? selectedFilter?.name
        }
        return selectedFilter?.name
    }

    @Environment(\.homeBreadcrumbMenu) private var homeMenu

    /// Above the list: the whole quick bar, or on Home (breadcrumb chrome) only the filter chips.
    private var quickBar: some View {
        quickBar(part: homeMenu == nil ? .all : .chipsOnly)
    }

    private func quickBar(part: CatalogQuickBarPart) -> some View {
        CatalogListQuickBar(
            mode: .tags,
            sort: selectedSortOption,
            onSort: { changeTagSortOption(to: $0) },
            document: criteriaDocument,
            presetName: activePresetName,
            onClearPreset: { resetAllCatalogFilters() },
            onFiltersChanged: { applyLiveFilter() },
            onOpenFilters: { showFilterSortSheet = true },
            collapsesOnScroll: !hideTitle,
            part: part
        )
    }

    private var tagsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.tags) { tag in
                        NavigationLink(destination: TagDetailView(selectedTag: tag)) {
                            TagCardView(tag: tag, badge: CatalogCardBadge(sortField: selectedSortOption.sortField))
                        }
                        .buttonStyle(.plain)
                        .id(tag.id)
                        .simultaneousGesture(TapGesture().onEnded {
                            lastOpenedTagId = tag.id
                        })
                    }
                
                    // Loading indicator for pagination
                    if viewModel.isLoadingMoreTags {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if viewModel.hasMoreTags && !viewModel.tags.isEmpty {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                viewModel.loadMoreTags()
                            }
                    }
                }
                .measuresGridWidth($gridWidth)
                .padding([.horizontal, .bottom], 16)
                }
            }
            .collapsesCatalogChrome(enabled: !hideTitle)
            .refreshable { performSearch() }
            .onAppear {
                if let id = lastOpenedTagId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
        }
    }
}

struct TagsView: View {
    @StateObject private var ownedViewModel = StashDBViewModel()
    let catalogBrowserViewModel: StashDBViewModel?
    var hideTitle: Bool = false
    let filterMemory: CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.TagSortOption>>?

    init(hideTitle: Bool = false, catalogBrowserViewModel: StashDBViewModel? = nil, filterMemory: CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.TagSortOption>>? = nil) {
        self.hideTitle = hideTitle
        self.catalogBrowserViewModel = catalogBrowserViewModel
        self.filterMemory = filterMemory
    }

    var body: some View {
        var content = TagsViewContent(viewModel: catalogBrowserViewModel ?? ownedViewModel, hideTitle: hideTitle, filterMemory: filterMemory)
        return content
    }
}

struct TagCardView: View {
    let tag: Tag
    /// What the list is sorted by; scenes for every sort that is not a count.
    var badge: CatalogCardBadge = .scenes
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @AppStorage(TagHierarchy.includeSubTagContentKey) private var includesSubTagContent = false

    /// The badge's count, or the scene count when the tag does not carry that count. With
    /// "Include sub-tag content" the counts over all sub-tags, where the tag came with them.
    private var shownCount: (badge: CatalogCardBadge, count: Int) {
        let all = includesSubTagContent
        let value: Int?
        switch badge {
        case .scenes: value = (all ? tag.sceneCountAll : nil) ?? tag.sceneCount
        case .images: value = (all ? tag.imageCountAll : nil) ?? tag.imageCount
        case .galleries: value = (all ? tag.galleryCountAll : nil) ?? tag.galleryCount
        case .performers, .performersAll: value = (all ? tag.performerCountAll : nil) ?? tag.performerCount
        case .markers: value = (all ? tag.sceneMarkerCountAll : nil) ?? tag.sceneMarkerCount
        case .oCount, .oCountAll, .rating: value = nil
        }
        if let value { return (badge, value) }
        return (.scenes, (all ? tag.sceneCountAll : nil) ?? tag.sceneCount ?? 0)
    }

    private var hasCustomImage: Bool {
        tag.imagePath != nil && tag.imagePath?.contains("default") != true
    }

    /// Same build as the gallery and performer cards: the image fills the card, counts sit as
    /// glass pills at the top, the name over a dark gradient at the bottom. A tag without its
    /// own image gets the studio grey with a number sign in the accent colour.
    var body: some View {
        Color.clear
            // 16:9 like the scene cards.
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(
                Group {
                    if hasCustomImage {
                        TagImageView(tag: tag)
                    } else {
                        Rectangle()
                            .fill(Color.studioHeaderGray(for: appearanceManager.currentTheme))
                            .overlay(
                                Image(systemName: "number")
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundColor(appearanceManager.tintColor)
                                    // Clear of the name, and of "Part of …" below it.
                                    .padding(.bottom, tag.partOfText == nil ? 16 : 34)
                                    .accessibilityHidden(true)
                            )
                    }
                }
            )
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 72)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                let shown = shownCount
                CatalogCardCountPill(icon: shown.badge.icon(oCounterIcon: appearanceManager.oCounterIcon),
                                     count: shown.count, spokenLabel: shown.badge.spokenCount(shown.count))
                    .padding(8)
            }
            .overlay(alignment: .topLeading) {
                // Where the tag stands: the number of its direct sub-tags.
                if let subTags = tag.childCount, subTags > 0 {
                    CatalogCardCountPill(icon: "tag.fill", count: subTags,
                                         spokenLabel: tr(subTags == 1 ? "arg_count_sub_tag" : "arg_count_sub_tags", subTags))
                        .padding(8)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tag.name)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    // "Part of …" for a sub-tag.
                    if let partOf = tag.partOfText {
                        Text(partOf)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .cardShadow()
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

struct TagDetailView: View {
    @State private var selectedTag: Tag
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject var tabManager = TabManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.stashyDismiss) private var dismiss
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var tagLiveFilterSheetPresented = false
    @State private var tagSceneFilterActive = false
    @State private var isFavorite: Bool = false
    @State private var isUpdatingFavorite: Bool = false
    @State private var isHeaderExpanded = false
    @State private var showingEditTagSheet = false
    @State private var showingTagImageFullscreen = false
    @AppStorage(TagHierarchy.includeSubTagContentKey) private var includesSubTagContent = false
    @StateObject private var linkedStudios: DetailLinkedStudiosFilterModel
    @StateObject private var linkedGalleries: DetailLinkedGalleriesFilterModel
    /// Scenes tab filter / sort, kept here so it survives the tab remounting `ScenesView`.
    @StateObject private var scenesFilterMemory: ScenesListFilterMemory
    @StateObject private var linkedImages: DetailLinkedImagesFilterModel
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var showingTagDownloadOptions = false
    @State private var showingSceneDownloadOptions = false
    /// Images 1/row autoplay: parent ScrollView drag/decelerate.
    @State private var imagesFeedScrolling = false

    private var showsFeedsNavButton: Bool {
        tabManager.tabs.first(where: { $0.id == .reels })?.isVisible ?? true
    }
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
        case studios = "Studios"
        case groups = "Groups"
        case images = "Images"
        /// The tag's direct sub-tags.
        case tags = "Tags"

        /// The name on screen; the raw value is data.
        var title: String {
            switch self {
            case .scenes: return tr("scenes")
            case .galleries: return tr("galleries")
            case .tags: return tr("sub_tags")
            case .studios: return tr("studios")
            case .groups: return tr("groups")
            case .images: return tr("images")
            }
        }

        var icon: String {
            switch self {
            case .scenes: return "film"
            case .galleries: return "photo.stack"
            case .studios: return "building.2"
            case .groups: return "rectangle.stack.fill"
            case .images: return "photo"
            case .tags: return "tag"
            }
        }
    }
    @State private var selectedDetailTab: DetailTab
    private let preferredInitialTab: DetailTab?

    /// `filterPerformerId`: opened from that performer's page — its scenes, galleries and images
    /// start filtered on the performer.
    init(selectedTag: Tag, initialTab: DetailTab? = nil, filterPerformerId: String? = nil) {
        _selectedTag = State(initialValue: selectedTag)
        preferredInitialTab = initialTab
        let sc = selectedTag.sceneCount ?? 0
        let gal = selectedTag.galleryCount ?? 0
        let img = selectedTag.imageCount ?? 0
        let resolvedTab: DetailTab
        if let initialTab {
            resolvedTab = initialTab
        } else if sc > 0 {
            resolvedTab = .scenes
        } else if gal > 0 {
            resolvedTab = .galleries
        } else if img > 0 {
            resolvedTab = .images
        } else {
            resolvedTab = .scenes
        }
        _selectedDetailTab = State(initialValue: resolvedTab)
        _linkedStudios = StateObject(wrappedValue: DetailLinkedStudiosFilterModel(scope: .tag(selectedTag.id)))
        let galleries = DetailLinkedGalleriesFilterModel(scope: .tag(selectedTag.id))
        let images = DetailLinkedImagesFilterModel(scope: .tag(selectedTag.id))
        if let filterPerformerId {
            galleries.criteriaDocument.load(PerformerScopedDetail.criteria(performerId: filterPerformerId))
            images.criteriaDocument.load(PerformerScopedDetail.criteria(performerId: filterPerformerId))
        }
        _linkedGalleries = StateObject(wrappedValue: galleries)
        _linkedImages = StateObject(wrappedValue: images)
        _scenesFilterMemory = StateObject(wrappedValue: PerformerScopedDetail.scenesMemory(performerId: filterPerformerId))
    }

    @State private var gridWidth: CGFloat = 0

    /// Breite Karten: eine pro Zeile auf dem iPhone, mehr sobald Platz da ist.
    private var columns: [GridItem] {
        DesignTokens.Grid.adaptiveColumns(
            width: gridWidth,
            ideal: 420,
            minimum: 1,
            maximum: 4
        )
    }

    private var galleryColumns: [GridItem] {
        if horizontalSizeClass == .regular {
             return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
             return [
                 GridItem(.flexible(), spacing: 12),
                 GridItem(.flexible(), spacing: 12)
             ]
        }
    }
    
    private var effectiveScenes: Int {
        max(viewModel.totalTagScenes, selectedTag.sceneCount ?? 0)
    }
    
    private var effectiveGalleries: Int {
        max(viewModel.totalTagGalleries, selectedTag.galleryCount ?? 0)
    }

    private var effectiveImages: Int {
        max(viewModel.totalDetailImages, selectedTag.imageCount ?? 0)
    }

    private var availableTabs: [DetailTab] {
        var tabs: [DetailTab] = []
        if effectiveScenes > 0 { tabs.append(.scenes) }
        if effectiveGalleries > 0 { tabs.append(.galleries) }
        if viewModel.totalDetailTags > 0 { tabs.append(.tags) }
        if viewModel.totalDetailStudios > 0 { tabs.append(.studios) }
        if viewModel.totalDetailGroups > 0 { tabs.append(.groups) }
        if effectiveImages > 0 { tabs.append(.images) }
        return tabs
    }

    private var catalogFloatingChromeForFooter: CatalogFloatingChromeState {
        let primaryEmpty: Bool = {
            switch selectedDetailTab {
            case .scenes: return viewModel.tagScenes.isEmpty
            case .galleries: return viewModel.tagGalleries.isEmpty
            case .studios: return viewModel.detailStudios.isEmpty
            case .groups: return viewModel.detailGroups.isEmpty
            case .images: return viewModel.detailImages.isEmpty
            case .tags: return viewModel.detailTags.isEmpty
            }
        }()
        return CatalogFloatingChromeState(
            hasActiveServerConfig: configManager.activeConfig != nil,
            primaryListIsEmpty: primaryEmpty,
            errorMessage: viewModel.errorMessage,
            imageFindListError: viewModel.imageFindListError
        )
    }

    /// Auto-switch to galleries only for a genuinely empty scene list, not for an empty filtered result.
    private var shouldAutoSwitchToTagGalleriesForEmptyScenes: Bool {
        viewModel.totalTagScenes == 0
            && !viewModel.isLoadingTagScenes
            && viewModel.totalTagGalleries > 0
            && effectiveScenes == 0
            && !viewModel.isTagDetailSceneListConstrained
    }

    private var shouldAutoSwitchToTagImagesForEmptyScenes: Bool {
        viewModel.totalTagScenes == 0
            && !viewModel.isLoadingTagScenes
            && effectiveImages > 0
            && effectiveGalleries == 0
            && effectiveScenes == 0
            && !viewModel.isTagDetailSceneListConstrained
    }

    private func autoSwitchAwayFromEmptyTagScenes() {
        if shouldAutoSwitchToTagGalleriesForEmptyScenes {
            withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
        } else if shouldAutoSwitchToTagImagesForEmptyScenes {
            withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .images }
        } else if selectedDetailTab == .scenes, effectiveScenes == 0, let first = availableTabs.first {
            withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = first }
        }
    }

    @ViewBuilder
    private var tagScenesStack: some View {
        ScenesView(
            hideTitle: true,
            scope: .tag(tagId: selectedTag.id),
            sharedViewModel: viewModel,
            externalLiveFilterSheetBinding: $tagLiveFilterSheetPresented,
            externalLiveFilterActiveBinding: $tagSceneFilterActive,
            showsFloatingFilterButton: false,
            scrollHeader: AnyView(
                tagHeaderView
                    .padding(.horizontal, 16)
            ),
            filterMemory: scenesFilterMemory
        )
        .environment(\.detailBreadcrumb, detailCrumb)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Back · section dropdown, like the overviews' breadcrumb (PerformerDetail template).
    private var detailCrumb: DetailBreadcrumb {
        DetailBreadcrumb(
            sections: availableTabs.map { .init(id: $0.rawValue, title: $0.title, systemImage: $0.icon) },
            selectionID: selectedDetailTab.rawValue,
            onSelect: { id in
                if let tab = DetailTab(rawValue: id) { selectedDetailTab = tab }
            },
            onBack: { dismiss() }
        )
    }

    /// Top chrome. The Scenes list draws this row itself (`detailBreadcrumbChrome`); every
    /// other section gets it here with its sort menu and settings.
    @ViewBuilder
    private var tagDetailNavBar: some View {
        if selectedDetailTab != .scenes {
            StashySectionChromeBar {
                DetailBreadcrumbRow(crumb: detailCrumb) { sectionControls }
                    .padding(.horizontal, StashyExpandingDock.edgePadding)
                    .padding(.vertical, 6)
            }
        }
    }

    /// Sort menu and filter / sort settings of the shown section.
    @ViewBuilder
    private var sectionControls: some View {
        HStack(spacing: 6) {
            switch selectedDetailTab {
            case .galleries:
                CatalogQuickSortMenu(mode: .galleries, sort: linkedGalleries.selectedSortOption) {
                    linkedGalleries.changeSortOption(to: $0, viewModel: viewModel)
                }
            case .images:
                CatalogQuickSortMenu(mode: .images, sort: linkedImages.selectedSortOption) {
                    linkedImages.changeSortOption(to: $0, viewModel: viewModel)
                }
            case .studios:
                CatalogQuickSortMenu(mode: .studios, sort: linkedStudios.selectedSortOption) {
                    linkedStudios.changeSortOption(to: $0, viewModel: viewModel)
                }
            case .scenes, .groups, .tags:
                EmptyView()
            }
            if let filter = sectionFilterSlot {
                DetailTopBarSlotButton(slot: filter)
            }
        }
    }

    /// The shown section's filter and sort sheet (Groups has none yet).
    private var sectionFilterSlot: CatalogChromeSlot? {
        func slot(active: Bool, open: @escaping () -> Void) -> CatalogChromeSlot {
            CatalogChromeSlot(systemImage: "slider.horizontal.3", isActive: active, accessibilityLabel: tr("action_filter_and_sort_2")) {
                HapticManager.light()
                open()
            }
        }
        switch selectedDetailTab {
        case .scenes: return slot(active: tagSceneFilterActive) { tagLiveFilterSheetPresented = true }
        case .galleries: return slot(active: linkedGalleries.catalogFilterSortFABActive) { linkedGalleries.showFilterSortSheet = true }
        case .studios: return slot(active: linkedStudios.catalogFilterSortFABActive) { linkedStudios.showFilterSortSheet = true }
        case .images: return slot(active: linkedImages.catalogFilterSortFABActive) { linkedImages.showFilterSortSheet = true }
        case .groups, .tags: return nil
        }
    }

    private func toggleFavorite() {
        guard !isUpdatingFavorite else { return }
        HapticManager.light()
        isUpdatingFavorite = true
        let newState = !isFavorite
        withAnimation(DesignTokens.Animation.quick) { isFavorite = newState }

        viewModel.toggleTagFavorite(tagId: selectedTag.id, favorite: newState) { success in
            DispatchQueue.main.async {
                if !success {
                    isFavorite = !newState
                    ToastManager.shared.show(tr("error_update_favorite"), icon: "exclamationmark.triangle", style: .error)
                } else {
                    selectedTag.favorite = newState
                }
                isUpdatingFavorite = false
            }
        }
    }

    @ViewBuilder
    private var nonScenesTagScroll: some View {
        ScrollView {
            VStack(spacing: 12) {
                tagHeaderView

                if selectedDetailTab == .galleries {
                    if !viewModel.tagGalleries.isEmpty {
                        galleryGrid
                    } else if viewModel.isLoadingTagGalleries {
                        VStack {
                            InlineSpinner()
                            Text(tr("loading_galleries")).font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        InlineEmptyStateView(icon: "photo.on.rectangle", title: tr("empty_galleries_found"))
                    }
                } else if selectedDetailTab == .tags {
                    subTagGrid
                } else if selectedDetailTab == .studios {
                    studioGrid
                } else if selectedDetailTab == .groups {
                    groupGrid
                } else if selectedDetailTab == .images {
                    imageGrid
                }
            }
            .padding(16)
        }
        .onScrollPhaseChange { _, newPhase in
            guard selectedDetailTab == .images else {
                if imagesFeedScrolling { imagesFeedScrolling = false }
                return
            }
            imagesFeedScrolling = newPhase != .idle
        }
    }

    var body: some View {
        tagDetailWithLinkedGalleriesAndImagesSheets
    }

    private var tagDetailWithLinkedGalleriesAndImagesSheets: some View {
        tagDetailWithLinkedStudiosSheets
            .sheet(isPresented: $linkedGalleries.showFilterSortSheet) {
                tagDetailGalleriesFilterSheet
            }
            .onChange(of: linkedGalleries.catalogPresetRowSelection) { _, newId in
                linkedGalleries.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert(tr("action_save_as_new"), isPresented: $linkedGalleries.showSaveAsCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedGalleries.catalogPresetNameInput)
                Button(tr("action_save")) { linkedGalleries.savePresetAs(name: linkedGalleries.catalogPresetNameInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_save_current_sort_filter_and"))
            }
            .alert(tr("action_rename"), isPresented: $linkedGalleries.showRenameCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedGalleries.renameCatalogPresetInput)
                Button(tr("action_save")) { linkedGalleries.renamePreset(to: linkedGalleries.renameCatalogPresetInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_rename_this_preset_or_saved"))
            }
            .alert(tr("confirm_delete_filter"), isPresented: $linkedGalleries.showDeleteCatalogPresetAlert) {
                Button(tr("action_delete"), role: .destructive) { linkedGalleries.deletePreset(viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(linkedGalleries.deletePresetConfirmationText(viewModel: viewModel))
            }
            .sheet(isPresented: $linkedImages.showFilterSortSheet) {
                tagDetailImagesFilterSheet
            }
            .onChange(of: linkedImages.catalogPresetRowSelection) { _, newId in
                linkedImages.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert(tr("action_save_as_new"), isPresented: $linkedImages.showSaveAsCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedImages.catalogPresetNameInput)
                Button(tr("action_save")) { linkedImages.savePresetAs(name: linkedImages.catalogPresetNameInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_save_current_sort_filter_and"))
            }
            .alert(tr("action_rename"), isPresented: $linkedImages.showRenameCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedImages.renameCatalogPresetInput)
                Button(tr("action_save")) { linkedImages.renamePreset(to: linkedImages.renameCatalogPresetInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_rename_this_preset_or_saved"))
            }
            .alert(tr("confirm_delete_filter"), isPresented: $linkedImages.showDeleteCatalogPresetAlert) {
                Button(tr("action_delete"), role: .destructive) { linkedImages.deletePreset(viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(linkedImages.deletePresetConfirmationText(viewModel: viewModel))
            }
    }

    private var tagDetailWithLinkedStudiosSheets: some View {
        tagDetailCoreChrome
            .sheet(isPresented: $linkedStudios.showFilterSortSheet) {
                tagDetailStudiosFilterSheet
            }
            .onChange(of: linkedStudios.catalogPresetRowSelection) { _, newId in
                linkedStudios.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert(tr("action_save_as_new"), isPresented: $linkedStudios.showSaveAsCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedStudios.catalogPresetNameInput)
                Button(tr("action_save")) { linkedStudios.savePresetAs(name: linkedStudios.catalogPresetNameInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_save_current_sort_filter_and"))
            }
            .alert(tr("action_rename"), isPresented: $linkedStudios.showRenameCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedStudios.renameCatalogPresetInput)
                Button(tr("action_save")) { linkedStudios.renamePreset(to: linkedStudios.renameCatalogPresetInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_rename_this_preset_or_saved"))
            }
            .alert(tr("confirm_delete_filter"), isPresented: $linkedStudios.showDeleteCatalogPresetAlert) {
                Button(tr("action_delete"), role: .destructive) { linkedStudios.deletePreset(viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(linkedStudios.deletePresetConfirmationText(viewModel: viewModel))
            }
    }

    private var tagDetailCoreChrome: some View {
        Group {
            if selectedDetailTab == .scenes {
                tagScenesStack
            } else {
                nonScenesTagScroll
            }
        }
        .applyAppBackground()
        .fullScreenCover(isPresented: $showingTagImageFullscreen) {
            tagImageFullscreen
        }
        .onAppear {
            loadDetailData()
            isFavorite = selectedTag.favorite ?? false
        }
        .onChange(of: viewModel.totalTagGalleries) { oldValue, newValue in
            guard preferredInitialTab == nil else { return }
            if newValue > 0 && shouldAutoSwitchToTagGalleriesForEmptyScenes {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
        }
        .onChange(of: viewModel.totalDetailImages) { _, newValue in
            guard preferredInitialTab == nil else { return }
            if newValue > 0 && shouldAutoSwitchToTagImagesForEmptyScenes {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .images }
            }
        }
        .onChange(of: viewModel.totalTagScenes) { oldValue, newValue in
            guard preferredInitialTab == nil else { return }
            if newValue > 0 {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .scenes }
            } else {
                autoSwitchAwayFromEmptyTagScenes()
            }
        }
        .onChange(of: viewModel.isLoadingTagScenes) { _, loading in
            guard preferredInitialTab == nil else { return }
            if !loading { autoSwitchAwayFromEmptyTagScenes() }
        }
        .sceneLiveUpdates(using: viewModel)
        // A tag that holds only sub-tags: go to the first section that has something.
        .onChange(of: availableTabs) { _, tabs in
            guard preferredInitialTab == nil, !tabs.contains(selectedDetailTab), let first = tabs.first else { return }
            withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = first }
        }
        // Every filter sheet of this page offers "Include sub-tag content"; the Scenes list
        // reloads itself, the other sections here.
        .environment(\.showsSubTagContentOption, true)
        .onChange(of: includesSubTagContent) { _, _ in
            linkedGalleries.refetchGalleries(viewModel: viewModel, initial: true)
            linkedStudios.refetchStudios(viewModel: viewModel, initial: true)
            viewModel.fetchDetailGroups(tagId: selectedTag.id)
            viewModel.fetchDetailTags(parentTagId: selectedTag.id)
            linkedImages.refetchImages(viewModel: viewModel, initial: true)
        }
        // A tag moved in the hierarchy: this page's sub-tags (and what they hold) changed.
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TagParentsChanged"))) { note in
            guard (note.userInfo?["tagId"] as? String) != selectedTag.id else { return }
            viewModel.fetchDetailTags(parentTagId: selectedTag.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TagImageUpdated"))) { notification in
            guard let tagId = notification.userInfo?["tagId"] as? String,
                  tagId == selectedTag.id else { return }
            if let newPath = notification.userInfo?["newImagePath"] as? String {
                selectedTag.imagePath = newPath
            }
            if let updatedAt = notification.userInfo?["updatedAt"] as? String {
                selectedTag.updatedAt = updatedAt
            }
        }
        .sceneBulkDownloadDialog(
            isPresented: $showingSceneDownloadOptions,
            scope: .tag(id: selectedTag.id),
            scopeName: selectedTag.name,
            sceneCount: selectedTag.sceneCount,
        )
        .stashyDetailChrome(tagDetailChromeConfig) {
            tagDetailNavBar
        }
        .sheet(isPresented: $showingEditTagSheet) {
            EditTagSheet(tag: selectedTag, viewModel: viewModel, onDeleted: { dismiss() }) { updated in
                selectedTag = updated
            }
        }
        .alert(tr("tag_images"), isPresented: $showingTagDownloadOptions) {
            let entryId = "tag-" + selectedTag.id
            let batch = DownloadManager.galleryNewestBatchSize
            // `image_count` is depth 0, like the download's tag criterion.
            if let stored = downloadManager.downloadedGallery(id: entryId) {
                Button(tr("action_sync_newest")) {
                    downloadManager.syncTagImages(entryId: entryId)
                }
                if DownloadManager.showsSyncNewestBatch(count: selectedTag.imageCount ?? stored.serverImageCount, batch: batch) {
                    Button(tr("action_sync_newest_arg", batch)) {
                        downloadManager.syncTagImages(entryId: entryId, limit: batch)
                    }
                }
                Button(tr("action_remove_download"), role: .destructive) {
                    downloadManager.deleteGalleryDownload(id: entryId)
                }
            } else {
                DownloadBatchOptions.buttons(count: selectedTag.imageCount, batch: batch, singular: "image", plural: "images") { limit in
                    downloadManager.downloadTagImages(tagId: selectedTag.id, tagName: selectedTag.name, limit: limit)
                }
            }
            Button(tr("action_cancel"), role: .cancel) {}
        }
    }

    // MARK: - Shared detail chrome

    /// Favorite and Edit sit in the floating bar with the list's actions, not in the top chrome.
    private var entityActionSlots: [CatalogChromeSlot] {
        var actions = [CatalogChromeSlot(
            systemImage: isFavorite ? "heart.fill" : "heart",
            accessibilityLabel: isFavorite ? tr("action_remove_favorite") : tr("action_add_favorite"),
            tint: isFavorite ? .red : nil
        ) {
            guard !isUpdatingFavorite else { return }
            toggleFavorite()
        }]
        if appearanceManager.isEditModeEnabled {
            actions.append(CatalogChromeSlot(systemImage: "pencil", accessibilityLabel: tr("action_edit_tag")) {
                HapticManager.light()
                showingEditTagSheet = true
            })
        }
        return actions
    }

    /// Per-tab slots for the embedded list, mirroring the previous floating action bar content.
    private var tagDetailListSlots: CatalogSlotSet {
        var slots = CatalogSlotSet(
            visibility: catalogFloatingChromeForFooter,
            isPresented: true
        )
        slots.entityActions = entityActionSlots
        // Filter & sort live in the top bar now (breadcrumb row); the bar keeps the actions.
        switch selectedDetailTab {
        case .scenes:
            slots.contextual = SceneBulkDownloadChrome.slot {
                showingSceneDownloadOptions = true
            }
        case .images:
            slots.contextual = tagImagesDownloadSlot
        default:
            break
        }
        return slots
    }

    /// Downloads the tag's images for offline use. Mirrors the gallery control: pick a batch size
    /// first, then sync or remove once something is stored.
    private var tagImagesDownloadSlot: CatalogChromeSlot {
        let entryId = "tag-" + selectedTag.id
        let isDownloading = downloadManager.activeDownloads[entryId] != nil
        let stored = downloadManager.downloadedGallery(id: entryId)

        if isDownloading {
            return CatalogChromeSlot(
                systemImage: "stop.circle",
                isActive: true,
                accessibilityLabel: tr("action_cancel_download")
            ) {
                HapticManager.light()
                downloadManager.cancelGalleryDownload(id: entryId)
            }
        } else if stored != nil {
            return CatalogChromeSlot(
                systemImage: "checkmark.circle.fill",
                isActive: true,
                accessibilityLabel: tr("downloaded")
            ) {
                HapticManager.light()
                showingTagDownloadOptions = true
            }
        } else {
            return CatalogChromeSlot(
                systemImage: "arrow.down.doc",
                accessibilityLabel: tr("action_download_images")
            ) {
                HapticManager.light()
                showingTagDownloadOptions = true
            }
        }
    }

    private var tagDetailChromeConfig: StashyDetailChromeConfig {
        StashyDetailChromeConfig(listSlots: tagDetailListSlots, insetSpacing: 0)
    }

    @ViewBuilder
    private var tagDetailStudiosFilterSheet: some View {
        StudiosCatalogFilterSortSheet(
            serverFilters: linkedStudios.sortedServerStudioFilters(viewModel: viewModel),
            localPresets: linkedStudios.localCatalogPresets,
            selectedPresetRowId: $linkedStudios.catalogPresetRowSelection,
           criteriaDocument: linkedStudios.criteriaDocument,
            sortOption: linkedStudios.selectedSortOption,
            onSortChange: { linkedStudios.changeSortOption(to: $0, viewModel: viewModel) },
            onApply: { linkedStudios.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedStudios.catalogPresetRowSelection = ""
                linkedStudios.selectedFilter = nil
                linkedStudios.clearLiveChipsOnly()
                linkedStudios.criteriaDocument.clear()
                linkedStudios.applyLiveFilter(viewModel: viewModel)
            },
            onRequestSave: { linkedStudios.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                linkedStudios.catalogPresetNameInput = ""
                linkedStudios.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(linkedStudios.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    linkedStudios.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(linkedStudios.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = linkedStudios.localCatalogPresets.first(where: { $0.id == uuid }) {
                    linkedStudios.renameCatalogPresetInput = p.name
                }
                linkedStudios.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { linkedStudios.showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            ListLivePresetTag.migrateLegacySelection(&linkedStudios.catalogPresetRowSelection)
            linkedStudios.refreshLocalPresets()
            linkedStudios.applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var tagDetailGalleriesFilterSheet: some View {
        GalleriesCatalogFilterSortSheet(
            serverFilters: linkedGalleries.sortedServerGalleryFilters(viewModel: viewModel),
            localPresets: linkedGalleries.localCatalogPresets,
            selectedPresetRowId: $linkedGalleries.catalogPresetRowSelection,
           criteriaDocument: linkedGalleries.criteriaDocument,
            sortOption: linkedGalleries.selectedSortOption,
            onSortChange: { linkedGalleries.changeSortOption(to: $0, viewModel: viewModel) },
            onApply: { linkedGalleries.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedGalleries.catalogPresetRowSelection = ""
                linkedGalleries.selectedFilter = nil
                linkedGalleries.clearLiveChipsOnly()
                linkedGalleries.criteriaDocument.clear()
                linkedGalleries.applyLiveFilter(viewModel: viewModel)
            },
            onRequestSave: { linkedGalleries.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                linkedGalleries.catalogPresetNameInput = ""
                linkedGalleries.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(linkedGalleries.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    linkedGalleries.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(linkedGalleries.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = linkedGalleries.localCatalogPresets.first(where: { $0.id == uuid }) {
                    linkedGalleries.renameCatalogPresetInput = p.name
                }
                linkedGalleries.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { linkedGalleries.showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            var sel = linkedGalleries.catalogPresetRowSelection
            ListLivePresetTag.migrateLegacySelection(&sel)
            linkedGalleries.catalogPresetRowSelection = sel
            linkedGalleries.refreshLocalPresets()
            linkedGalleries.applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var tagDetailImagesFilterSheet: some View {
        ImagesCatalogFilterSortSheet(
            serverFilters: linkedImages.sortedServerImageFilters(viewModel: viewModel),
            localPresets: linkedImages.localCatalogPresets,
            selectedPresetRowId: $linkedImages.catalogPresetRowSelection,
           criteriaDocument: linkedImages.criteriaDocument,
            filterMenuTitleFallback: linkedImages.selectedFilter?.name,
            showMediaTypeFilter: linkedImages.showImageMediaTypeFilter,
            sortOption: linkedImages.selectedSortOption,
            onSortChange: { linkedImages.changeSortOption(to: $0, viewModel: viewModel) },
            liveMediaKind: $linkedImages.liveFilterMediaKind,
            onApply: { linkedImages.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedImages.catalogPresetRowSelection = ""
                linkedImages.selectedFilter = nil
                linkedImages.clearLiveChipsOnly()
                linkedImages.criteriaDocument.clear()
                linkedImages.refetchImages(viewModel: viewModel, initial: true)
            },
            onRequestSave: { linkedImages.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                linkedImages.catalogPresetNameInput = ""
                linkedImages.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(linkedImages.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    linkedImages.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(linkedImages.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = linkedImages.localCatalogPresets.first(where: { $0.id == uuid }) {
                    linkedImages.renameCatalogPresetInput = p.name
                }
                linkedImages.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { linkedImages.showDeleteCatalogPresetAlert = true },
            showsImagesFeedAutoplaySetting: true,
            cardColumnScope: CatalogCardColumnScope.images
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            linkedImages.prepareCatalogFilterSortSheetUI(viewModel: viewModel)
        }
    }
    
    // MARK: - Subviews & Logic
    
    private func loadDetailData() {
        if viewModel.tagGalleries.isEmpty && !viewModel.isLoadingTagGalleries {
            linkedGalleries.refetchGalleries(viewModel: viewModel, initial: true)
        }
        
        // Refresh tag metadata / favorite from server
        viewModel.fetchTag(tagId: selectedTag.id) { updatedTag in
            if let tag = updatedTag {
                self.selectedTag = tag
                self.isFavorite = tag.favorite ?? false
            }
        }
        
        // Fetch extended content
        viewModel.fetchSavedFilters()
        linkedStudios.refetchStudios(viewModel: viewModel, initial: true)
        viewModel.fetchDetailGroups(tagId: selectedTag.id)
        viewModel.fetchDetailTags(parentTagId: selectedTag.id)
        if viewModel.detailImages.isEmpty && !viewModel.isLoadingDetailImages {
            linkedImages.refetchImages(viewModel: viewModel, initial: true)
        }
    }

    /// Stash serves a generic placeholder (`…&default=true`) for tags without their own
    /// image; those (and not-yet-hydrated tags) get the plain card instead of a hero.
    private var tagHasCustomImage: Bool {
        guard let path = selectedTag.imagePath, !path.isEmpty else { return false }
        return !path.contains("default=true")
    }

    /// Header card (`DetailHeroCard`): the tag image blurred as the compact band backdrop,
    /// the image centre-cropped in the circle straddling the band edge, name, Feeds pill,
    /// counts and description in the solid section.
    /// Tap opens the image fullscreen. Edit / Favorite live in the nav bar.
    private var tagHeaderView: some View {
        DetailHeroCard(
            title: selectedTag.name,
            items: getTagDetails(selectedTag).map { DetailHeroItem(label: $0.label, value: $0.value) },
            description: selectedTag.description,
            showsHero: tagHasCustomImage,
            heroAccessibilityLabel: tr("action_open_tag_image"),
            onHeroTap: { showingTagImageFullscreen = true },
            isExpanded: $isHeaderExpanded,
            placeholderSystemImage: AppTab.tags.icon,
            backdrop: {
                TagImageView(tag: selectedTag)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
            },
            avatar: {
                TagImageView(tag: selectedTag)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
            },
            accessory: { onImage in
                if showsFeedsNavButton {
                    DetailHeroFeedsButton(onImage: onImage) {
                        coordinator.navigateToReels(tags: [selectedTag], mode: nil)
                    }
                }
            },
            footer: { parentTagLinks }
        )
    }

    /// Fullscreen tag image (aspect-fit; SVG tags go through the shared rasterizer).
    private var tagImageFullscreen: some View {
        DetailHeroFullscreenViewer {
            CustomAsyncImage(url: selectedTag.thumbnailURL) { loader in
                if let image = loader.image {
                    image.resizable().scaledToFit()
                } else if let data = loader.imageData,
                          (String(data: data.prefix(100), encoding: .utf8) ?? "").lowercased().contains("<svg") {
                    RasterizedSVGImage(data: data, height: 600)
                } else if loader.isLoading {
                    InlineSpinner(tint: .white)
                } else {
                    Image(systemName: "number")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }

    private func getTagDetails(_ t: Tag) -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        
        list.append((label: tr("scenes").uppercased(), value: "\(effectiveScenes)"))
        if effectiveGalleries > 0 {
            list.append((label: tr("galleries").uppercased(), value: "\(effectiveGalleries)"))
        }
        
        if let val = t.performerCount, val > 0 {
            list.append((label: tr("performers").uppercased(), value: "\(val)"))
        }
        
        if let val = t.sceneMarkerCount, val > 0 {
            list.append((label: tr("markers").uppercased(), value: "\(val)"))
        }

        if let aliases = t.aliases, !aliases.isEmpty {
            list.append((label: tr("aliases").uppercased(), value: aliases.joined(separator: ", ")))
        }
        
        if let created = t.createdAt, !created.isEmpty {
            let date = created.prefix(10)
            list.append((label: tr("created").uppercased(), value: String(date)))
        }
        
        if let updated = t.updatedAt, !updated.isEmpty {
            let date = updated.prefix(10)
            list.append((label: tr("updated").uppercased(), value: String(date)))
        }
        
        return list
    }
    
    private var galleryGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.tagGalleries) { gallery in
                NavigationLink(destination: ImagesView(gallery: gallery)) {
                    GalleryCardView(gallery: gallery)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            if viewModel.isLoadingMoreTagGalleries {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.hasMoreTagGalleries {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        viewModel.loadMoreTagGalleries(tagId: selectedTag.id)
                    }
            }
        }
    }
    
    private var studioGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.detailStudios) { studio in
                NavigationLink(destination: StudioDetailView(studio: studio)) {
                    StudioCardView(studio: studio, badge: CatalogCardBadge(sortField: linkedStudios.selectedSortOption.sortField))
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailStudios { ProgressView().padding() }
            else if viewModel.hasMoreDetailStudios {
                Color.clear.onAppear { linkedStudios.refetchStudios(viewModel: viewModel, initial: false) }
            }
        }
        .measuresGridWidth($gridWidth)
    }
    
    /// The tag's direct sub-tags, by name.
    private var subTagGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailTags) { tag in
                NavigationLink(destination: TagDetailView(selectedTag: tag)) {
                    TagCardView(tag: tag)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailTags { ProgressView().padding() }
            else if viewModel.hasMoreDetailTags {
                Color.clear.onAppear { viewModel.fetchDetailTags(parentTagId: selectedTag.id, isInitialLoad: false) }
            }
        }
    }

    /// "Part of <parent>" links under the header, one per tag this one belongs to.
    @ViewBuilder
    private var parentTagLinks: some View {
        if let parents = selectedTag.parents, !parents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(parents) { parent in
                    NavigationLink(destination: TagDetailView(selectedTag: Tag(id: parent.id, name: parent.name ?? ""))) {
                        HStack(spacing: 4) {
                            Image(systemName: "tag")
                            Text(tr("arg_part_of", parent.name ?? "")).lineLimit(1)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(appearanceManager.tintColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .padding(.trailing, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var groupGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.detailGroups) { group in
                NavigationLink(destination: GroupDetailView(selectedGroup: group)) {
                    GroupCardView(group: group)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailGroups { ProgressView().padding() }
            else if viewModel.hasMoreDetailGroups {
                Color.clear.onAppear { viewModel.fetchDetailGroups(tagId: selectedTag.id, isInitialLoad: false) }
            }
        }
        .measuresGridWidth($gridWidth)
    }
    
    private var imageGrid: some View {
        LinkedImagesCatalogGrid(
            images: $viewModel.detailImages,
            sortOption: linkedImages.selectedSortOption,
            isLoading: viewModel.isLoadingDetailImages,
            hasMore: viewModel.hasMoreDetailImages,
            onLoadMore: { linkedImages.refetchImages(viewModel: viewModel, initial: false) },
            multiColumnGridItems: galleryColumns,
            isFeedScrolling: imagesFeedScrolling,
            viewModel: viewModel
        )
    }
    
}

// MARK: - Edit Tag Sheet

struct EditTagSheet: View {
    let tag: Tag
    @ObservedObject var viewModel: StashDBViewModel
    var onDeleted: (() -> Void)? = nil
    var onComplete: (Tag) -> Void

    @Environment(\.stashyDismiss) private var dismiss
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var aliases: [String] = []
    @State private var newAlias: String = ""
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showingDeleteConfirmation = false
    /// The tags this one belongs to. Written as soon as they are picked, like a scene's tags.
    @State private var parents: [Tag.TagRef] = []
    @State private var showingParentPicker = false

    var body: some View {
        NavigationView {
            Form {
                Section(tr("identity")) {
                    TextField(tr("name"), text: $name)
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section(tr("parent_tags")) {
                    Button {
                        showingParentPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "tag")
                                .foregroundColor(appearanceManager.tintColor)
                            Text(parents.isEmpty ? tr("none") : parents.map { $0.name ?? "" }.joined(separator: ", "))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section(tr("description")) {
                    TextEditor(text: $descriptionText)
                        .frame(minHeight: 120)
                }
                .listRowBackground(Color.secondaryAppBackground)

                // Only once the tag came with its aliases: saving an empty list over unloaded
                // ones would delete them.
                if tag.aliases != nil {
                    Section {
                        ForEach(aliases, id: \.self) { alias in
                            Text(alias)
                        }
                        .onDelete { aliases.remove(atOffsets: $0) }
                        HStack {
                            TextField(tr("action_add_alias"), text: $newAlias)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit(addAlias)
                            Button(action: addAlias) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(appearanceManager.tintColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(newAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel(tr("action_add_alias"))
                        }
                    } header: {
                        Text(tr("aliases"))
                    } footer: {
                        Text(tr("hint_other_names_for_this_tag"))
                    }
                    .listRowBackground(Color.secondaryAppBackground)
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            if isDeleting {
                                InlineSpinner(tint: .red)
                            } else {
                                Label(tr("action_delete_tag"), systemImage: "trash")
                                    .foregroundStyle(.red)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isSaving || isDeleting)
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome(tr("action_edit_tag"), onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(
                    title: tr("action_save"),
                    enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isBusy: isSaving
                ) { save() }
            }
            .onAppear {
                name = tag.name
                descriptionText = tag.description ?? ""
                aliases = tag.aliases ?? []
                parents = tag.parents ?? []
            }
            .sheet(isPresented: $showingParentPicker) {
                ParentTagsPickerSheet(tagId: tag.id, current: parents, viewModel: viewModel) { picked in
                    parents = picked
                    var updated = tag
                    updated.parents = picked
                    onComplete(updated)
                }
            }
            .alert(tr("action_delete_tag"), isPresented: $showingDeleteConfirmation) {
                Button(tr("action_cancel"), role: .cancel) { }
                Button(tr("action_delete"), role: .destructive) { performDelete() }
            } message: {
                Text(tr("hint_delete_arg_this_cannot_be", tag.name))
            }
        }
    }

    private func performDelete() {
        isDeleting = true
        viewModel.deleteTag(tagId: tag.id) { result in
            DispatchQueue.main.async {
                isDeleting = false
                switch result {
                case .success:
                    ToastManager.shared.show(tr("tag_deleted"), icon: "trash", style: .success)
                    dismiss()
                    // Pop the detail only once the sheet is gone — both in one runloop
                    // leaves the navigation stack inconsistent.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onDeleted?() }
                case .failure(let error):
                    ToastManager.shared.show(error.localizedDescription, icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }

    private func addAlias() {
        let alias = newAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else { return }
        // Stash rejects duplicates and an alias equal to the name.
        let existing = Set((aliases + [name]).map { $0.lowercased() })
        if !existing.contains(alias.lowercased()) { aliases.append(alias) }
        newAlias = ""
    }

    private func save() {
        // A typed but not yet added alias counts too.
        if !newAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addAlias() }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionValue: String? = trimmedDescription.isEmpty ? nil : trimmedDescription

        isSaving = true
        let aliasesValue: [String]? = tag.aliases == nil ? nil : aliases
        viewModel.updateTagDetails(
            tagId: tag.id,
            name: trimmedName,
            description: descriptionValue,
            aliases: aliasesValue
        ) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    var updated = tag
                    updated.name = trimmedName
                    updated.description = descriptionValue
                    if let aliasesValue { updated.aliases = aliasesValue }
                    updated.parents = parents
                    onComplete(updated)
                    ToastManager.shared.show(tr("tag_updated"), icon: "checkmark.circle", style: .success)
                    dismiss()
                } else {
                    ToastManager.shared.show(tr("error_update_tag"), icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}

struct TagImageView: View {
    let tag: Tag
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var imageLoadState: ImageLoadState = .loading

    enum ImageLoadState {
        case loading
        case success(Image)
        case failure
    }

    private var imageURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return URL(string: "\(config.baseURL)/tag/\(tag.id)/image")
    }

    var body: some View {
        CustomAsyncImage(url: tag.thumbnailURL) { loader in
            if loader.isLoading {
                Rectangle()
                    .fill(appearanceManager.tintColor)
                    .overlay(InlineSpinner(tint: Color.onAppTint))
            } else if let image = loader.image {
                image
                    .resizable()
                    .scaledToFill()
            } else if let data = loader.imageData, isSVG(data) {
                RasterizedSVGImage(data: data)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle()
                    .fill(appearanceManager.tintColor)
                    .overlay(
                        Image(systemName: "number")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color.onAppTint)
                    )
            }
        }
    }

    private func isSVG(_ data: Data) -> Bool {
        let str = String(data: data.prefix(100), encoding: .utf8) ?? ""
        return str.lowercased().contains("<svg")
    }
}


/// Picks the tags a tag belongs to: every tag by name, the tag itself left out, each with its
/// number of sub-tags. Saves on its own, like the scene's tag picker.
struct ParentTagsPickerSheet: View {
    let tagId: String
    let current: [Tag.TagRef]
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: ([Tag.TagRef]) -> Void

    @Environment(\.stashyDismiss) private var dismiss
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @State private var allTags: [Tag] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []
    @State private var isSaving = false

    private var filtered: [Tag] {
        let offered = allTags.filter { $0.id != tagId }
        if searchText.isEmpty { return offered }
        return offered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(tr("search_tags"))) {
                    TextField(tr("placeholder_search"), text: $searchText)
                    if isLoading {
                        HStack { Spacer(); ProgressView(tr("loading")); Spacer() }.padding()
                    } else {
                        ForEach(filtered) { tag in
                            HStack {
                                Text(tag.name)
                                Spacer()
                                if let subTags = tag.childCount, subTags > 0 {
                                    Text(tr(subTags == 1 ? "arg_count_sub_tag" : "arg_count_sub_tags", subTags))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                if selectedIds.contains(tag.id) {
                                    Image(systemName: "checkmark").foregroundColor(appearanceManager.tintColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedIds.contains(tag.id) { selectedIds.remove(tag.id) } else { selectedIds.insert(tag.id) }
                            }
                        }
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome(tr("parent_tags"), onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(title: tr("action_save"), enabled: !isSaving && !isLoading, isBusy: isSaving) { save() }
            }
            .onAppear {
                selectedIds = Set(current.map(\.id))
                viewModel.fetchAllTagsByName { fetched in
                    allTags = fetched
                    isLoading = false
                }
            }
        }
    }

    private func save() {
        isSaving = true
        // In the list's name order, so the row reads the same every time.
        let picked = allTags.filter { selectedIds.contains($0.id) }.map { Tag.TagRef(id: $0.id, name: $0.name) }
        viewModel.updateTagParents(tagId: tagId, parentIds: picked.map(\.id)) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    onComplete(picked)
                    dismiss()
                } else {
                    ToastManager.shared.show(tr("error_update_tags"), icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}

#endif
