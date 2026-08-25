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
    @State private var lastOpenedTagId: String?
    @State private var isChangingSort = false
    @State private var searchText = ""
    @State private var isSearchVisible = false
    var hideTitle: Bool = false

    init(viewModel: StashDBViewModel, hideTitle: Bool = false) {
        self.viewModel = viewModel
        self.hideTitle = hideTitle
    }

    // Filter & sort sheet
    @State private var showFilterSortSheet = false
    @StateObject private var criteriaDocument = FilterCriteriaDocument(mode: .tags)

    @State private var catalogPresetRowSelection = ""
    @State private var localCatalogPresets: [TagListLiveFilterPreset] = TagListLiveFilterPresetStore.loadPresets()
    @State private var showSaveAsCatalogPresetAlert = false
    @State private var catalogPresetNameInput = ""
    @State private var showRenameCatalogPresetAlert = false
    @State private var renameCatalogPresetInput = ""
    @State private var showDeleteCatalogPresetAlert = false

    // Live filter (chips)
    @State private var liveFilterFavorite: Bool? = nil
    @State private var liveFilterHasScenes: Bool = false

    private var isLiveFilterActive: Bool {
        liveFilterFavorite != nil || liveFilterHasScenes
    }

    private var activeLiveFilterDict: [String: Any] {
        var dict: [String: Any] = [:]
        if let fav = liveFilterFavorite { dict["favorite"] = fav }
        if liveFilterHasScenes { dict["scene_count"] = ["value": 0, "modifier": "GREATER_THAN"] }
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
        viewModel.currentTagLiveFilter = effectiveLiveFilter ?? [:]
        viewModel.fetchTags(sortBy: selectedSortOption, searchQuery: searchText, filter: fetchBaseFilter, liveFilter: effectiveLiveFilter)
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
        selectedFilter != nil || isLiveFilterActive || !criteriaDocument.isEmpty || !catalogPresetRowSelection.isEmpty
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
        liveFilterHasScenes = false
    }

    private func mapTagLiveFragmentToChips(_ frag: [String: Any]) {
        clearTagLiveChipsOnly()
        if let fav = frag["favorite"] as? Bool {
            liveFilterFavorite = fav
        }
        if let sc = frag["scene_count"] as? [String: Any],
           let mod = sc["modifier"] as? String,
           mod == "GREATER_THAN" {
            liveFilterHasScenes = true
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
            return "Remove “\(f.name)” from Stash? Other devices will lose this saved filter."
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection),
           let uuid = UUID(uuidString: ls),
           let p = localCatalogPresets.first(where: { $0.id == uuid }) {
            return "Remove “\(p.name)” from this device? This cannot be undone."
        }
        return "Remove this filter? This cannot be undone."
    }

    private func saveTagCatalogPresetOverwrite() {
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
            liveFragment: activeLiveFilterDict
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
            .onChange(of: catalogPresetRowSelection) { _, newId in
                handleTagCatalogPresetSelectionChange(newId)
            }
            .alert("Save As", isPresented: $showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $catalogPresetNameInput)
                Button("Save") { saveTagCatalogPresetAs(name: catalogPresetNameInput) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $showRenameCatalogPresetAlert) {
                TextField("Name", text: $renameCatalogPresetInput)
                Button("Save") { renameTagCatalogPreset(to: renameCatalogPresetInput) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { deleteTagCatalogPreset() }
                Button("Cancel", role: .cancel) {}
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
                selectedFilter = nil
                catalogPresetRowSelection = ""
                refreshTagLocalPresets()
                performSearch()
            }
            .onChange(of: viewModel.savedFilters) { oldValue, newValue in
                if selectedFilter == nil {
                    if let defaultId = TabManager.shared.getDefaultFilterId(for: .tags),
                       let filter = newValue[defaultId] {
                        selectedFilter = filter
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
                StandardLoadingView(message: "Loading tags...")
            } else if viewModel.tags.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.tags.isEmpty {
                emptyStateView
            } else {
                tagsList
            }
        }
        .navigationTitle(hideTitle ? "" : "Tags")
        .navigationBarTitleDisplayMode(.inline)
        .conditionalSearchable(isVisible: isSearchVisible, text: $searchText, prompt: "Search tags...")
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
        .floatingActionBar(isPresented: true, catalogChrome: CatalogFloatingChromeState(hasActiveServerConfig: configManager.activeConfig != nil, primaryListIsEmpty: viewModel.tags.isEmpty, errorMessage: viewModel.errorMessage)) {
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
    private func tagsFilterSortSheet() -> some View {
        TagsCatalogFilterSortSheet(
            serverFilters: sortedServerTagFilters,
            localPresets: localCatalogPresets,
            selectedPresetRowId: $catalogPresetRowSelection,
            criteriaDocument: criteriaDocument,
            sortOption: selectedSortOption,
            onSortChange: { changeTagSortOption(to: $0) },
            liveFavorite: $liveFilterFavorite,
            liveHasScenes: $liveFilterHasScenes,
            onApply: { applyLiveFilter() },
            onReset: {
                catalogPresetRowSelection = ""
                selectedFilter = nil
                clearTagLiveChipsOnly()
                criteriaDocument.clear()
                applyLiveFilter()
            },
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
            onRequestDelete: { showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            ListLivePresetTag.migrateLegacySelection(&catalogPresetRowSelection)
            refreshTagLocalPresets()
            applyCatalogPresetSelectionFromSheetIfNeeded()
        }
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
        if TabManager.shared.getDefaultFilterId(for: .tags) == nil || !viewModel.savedFilters.isEmpty {
            if viewModel.tags.isEmpty {
                performSearch()
            }
        }
        viewModel.fetchSavedFilters()
    }

    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: "tag.fill",
            title: "No tags found",
            buttonText: "Load Tags",
            onRetry: { performSearch() }
        )
    }

    private var tagsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.tags) { tag in
                        NavigationLink(destination: TagDetailView(selectedTag: tag)) {
                            TagCardView(tag: tag)
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
                .padding(16)
            }
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

    init(hideTitle: Bool = false, catalogBrowserViewModel: StashDBViewModel? = nil) {
        self.hideTitle = hideTitle
        self.catalogBrowserViewModel = catalogBrowserViewModel
    }

    var body: some View {
        TagsViewContent(viewModel: catalogBrowserViewModel ?? ownedViewModel, hideTitle: hideTitle)
    }
}

struct TagCardView: View {
    let tag: Tag
    @ObservedObject var appearanceManager = AppearanceManager.shared

    private var hasCustomImage: Bool {
        tag.imagePath != nil && tag.imagePath?.contains("default") != true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image Block (Top)
            Color.studioHeaderGray
                .aspectRatio(2.2, contentMode: .fit)
                .overlay(
                    Group {
                        if hasCustomImage {
                            TagImageView(tag: tag)
                        } else {
                            Image(systemName: "number")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(appearanceManager.tintColor)
                        }
                    }
                )
                .clipped()

            // Name & Count Area (Below)
            HStack(spacing: 8) {
                Text(tag.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 8) {
                    if let sceneCount = tag.sceneCount, sceneCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "film")
                                .font(.system(size: 10))
                            Text("\(sceneCount)")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    if let galleryCount = tag.galleryCount, galleryCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 10))
                            Text("\(galleryCount)")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                }
                .foregroundColor(.secondary)
                .layoutPriority(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}

struct TagDetailView: View {
    @State private var selectedTag: Tag
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject var tabManager = TabManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var tagLiveFilterSheetPresented = false
    @State private var isFavorite: Bool = false
    @State private var isUpdatingFavorite: Bool = false
    @State private var isHeaderExpanded = false
    @State private var showingEditTagSheet = false
    @StateObject private var linkedStudios: DetailLinkedStudiosFilterModel
    @StateObject private var linkedGalleries: DetailLinkedGalleriesFilterModel
    @StateObject private var linkedImages: DetailLinkedImagesFilterModel
    /// Images 1/row autoplay: parent ScrollView drag/decelerate.
    @State private var imagesFeedScrolling = false

    private var chromePillHeight: CGFloat { StashyExpandingDock.activeHeight }
    private var navActionGroupSpacing: CGFloat { 7 }
    private var showsFeedsNavButton: Bool {
        tabManager.tabs.first(where: { $0.id == .reels })?.isVisible ?? true
    }
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
        case studios = "Studios"
        case groups = "Groups"
        case images = "Images"

        var icon: String {
            switch self {
            case .scenes: return "film"
            case .galleries: return "photo.stack"
            case .studios: return "building.2"
            case .groups: return "rectangle.stack.fill"
            case .images: return "photo"
            }
        }
    }
    @State private var selectedDetailTab: DetailTab
    private let preferredInitialTab: DetailTab?

    init(selectedTag: Tag, initialTab: DetailTab? = nil) {
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
        _linkedGalleries = StateObject(wrappedValue: DetailLinkedGalleriesFilterModel(scope: .tag(selectedTag.id)))
        _linkedImages = StateObject(wrappedValue: DetailLinkedImagesFilterModel(scope: .tag(selectedTag.id)))
    }

    private var columns: [GridItem] {
        if verticalSizeClass == .compact {
             return [
                 GridItem(.flexible(), spacing: 12),
                 GridItem(.flexible(), spacing: 12)
             ]
        } else if horizontalSizeClass == .regular {
            // iPad: 4 columns
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
            // iPhone: 1 column
            return [
                GridItem(.flexible(), spacing: 12)
            ]
        }
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
        if viewModel.totalDetailStudios > 0 { tabs.append(.studios) }
        if viewModel.totalDetailGroups > 0 { tabs.append(.groups) }
        if effectiveImages > 0 { tabs.append(.images) }
        return tabs
    }

    private var showTabSwitcher: Bool {
        availableTabs.count > 1
    }

    private var catalogFloatingChromeForFooter: CatalogFloatingChromeState {
        let primaryEmpty: Bool = {
            switch selectedDetailTab {
            case .scenes: return viewModel.tagScenes.isEmpty
            case .galleries: return viewModel.tagGalleries.isEmpty
            case .studios: return viewModel.detailStudios.isEmpty
            case .groups: return viewModel.detailGroups.isEmpty
            case .images: return viewModel.detailImages.isEmpty
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
            showsFloatingFilterButton: false,
            scrollHeader: AnyView(
                tagHeaderView
                    .padding(.horizontal, 16)
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Custom top chrome (Performer/Studio template): Back · section icons · Favorite · Edit.
    @ViewBuilder
    private var tagDetailNavBar: some View {
        StashySectionChromeBar {
            HStack(spacing: 8) {
                Button {
                    dismiss()
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

                if showTabSwitcher {
                    HStack(spacing: 6) {
                        ForEach(availableTabs, id: \.self) { tab in
                            let isSelected = selectedDetailTab == tab
                            Button {
                                guard !isSelected else { return }
                                HapticManager.light()
                                withAnimation(StashyExpandingDock.selectionAnimation) {
                                    selectedDetailTab = tab
                                }
                            } label: {
                                Image(systemName: tab.icon)
                                    .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                                    .foregroundColor(
                                        isSelected
                                            ? .white
                                            : .white.opacity(StashyExpandingDock.inactiveIconOpacity)
                                    )
                                    .frame(
                                        width: StashyExpandingDock.circleSize,
                                        height: StashyExpandingDock.circleSize
                                    )
                                    .background {
                                        Capsule(style: .continuous)
                                            .fill(
                                                isSelected
                                                    ? appearanceManager.tintColor
                                                    : StashyExpandingDock.inactiveBackground
                                            )
                                    }
                                    .clipShape(Capsule(style: .continuous))
                                    .contentShape(Capsule(style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tab.rawValue)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }

                if showTabSwitcher {
                    Spacer()
                        .frame(width: navActionGroupSpacing)
                }

                HStack(spacing: 6) {
                    Button {
                        toggleFavorite()
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                            .foregroundColor(
                                isFavorite
                                    ? .red
                                    : .white.opacity(StashyExpandingDock.inactiveIconOpacity)
                            )
                            .frame(
                                width: StashyExpandingDock.circleSize,
                                height: StashyExpandingDock.circleSize
                            )
                            .background(StashyExpandingDock.inactiveBackground)
                            .clipShape(Capsule(style: .continuous))
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdatingFavorite)
                    .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")

                    if appearanceManager.isEditModeEnabled {
                        Button {
                            HapticManager.light()
                            showingEditTagSheet = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                                .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                                .frame(
                                    width: StashyExpandingDock.circleSize,
                                    height: StashyExpandingDock.circleSize
                                )
                                .background(StashyExpandingDock.inactiveBackground)
                                .clipShape(Capsule(style: .continuous))
                                .contentShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit tag")
                    }
                }
            }
            .frame(minHeight: chromePillHeight)
            .padding(.horizontal, StashyExpandingDock.edgePadding)
            .padding(.vertical, 8)

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
                    ToastManager.shared.show("Failed to update favorite", icon: "exclamationmark.triangle", style: .error)
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
                            Text("Loading galleries...").font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        InlineEmptyStateView(icon: "photo.on.rectangle", title: "No galleries found")
                    }
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
            .alert("Save As", isPresented: $linkedGalleries.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $linkedGalleries.catalogPresetNameInput)
                Button("Save") { linkedGalleries.savePresetAs(name: linkedGalleries.catalogPresetNameInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $linkedGalleries.showRenameCatalogPresetAlert) {
                TextField("Name", text: $linkedGalleries.renameCatalogPresetInput)
                Button("Save") { linkedGalleries.renamePreset(to: linkedGalleries.renameCatalogPresetInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $linkedGalleries.showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { linkedGalleries.deletePreset(viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(linkedGalleries.deletePresetConfirmationText(viewModel: viewModel))
            }
            .sheet(isPresented: $linkedImages.showFilterSortSheet) {
                tagDetailImagesFilterSheet
            }
            .onChange(of: linkedImages.catalogPresetRowSelection) { _, newId in
                linkedImages.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert("Save As", isPresented: $linkedImages.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $linkedImages.catalogPresetNameInput)
                Button("Save") { linkedImages.savePresetAs(name: linkedImages.catalogPresetNameInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $linkedImages.showRenameCatalogPresetAlert) {
                TextField("Name", text: $linkedImages.renameCatalogPresetInput)
                Button("Save") { linkedImages.renamePreset(to: linkedImages.renameCatalogPresetInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $linkedImages.showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { linkedImages.deletePreset(viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
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
            .alert("Save As", isPresented: $linkedStudios.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $linkedStudios.catalogPresetNameInput)
                Button("Save") { linkedStudios.savePresetAs(name: linkedStudios.catalogPresetNameInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $linkedStudios.showRenameCatalogPresetAlert) {
                TextField("Name", text: $linkedStudios.renameCatalogPresetInput)
                Button("Save") { linkedStudios.renamePreset(to: linkedStudios.renameCatalogPresetInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $linkedStudios.showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { linkedStudios.deletePreset(viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
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
        .hideSystemNavigationBarForCustomChrome()
        .enableSwipeBackWhenNavBarHidden()
        .stashyCustomChromeInset(spacing: 0) {
            tagDetailNavBar
        }
        .sheet(isPresented: $showingEditTagSheet) {
            EditTagSheet(tag: selectedTag, viewModel: viewModel) { updated in
                selectedTag = updated
            }
        }
        .floatingActionBar(
            isPresented: selectedDetailTab != .groups,
            catalogChrome: catalogFloatingChromeForFooter
        ) {
            HStack(spacing: 0) {
                if selectedDetailTab == .scenes {
                    CatalogFilterFABButton(isActive: true) {
                        HapticManager.light()
                        tagLiveFilterSheetPresented = true
                    }
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .galleries {
                    CatalogFilterFABButton(isActive: linkedGalleries.catalogFilterSortFABActive) {
                        HapticManager.light()
                        linkedGalleries.showFilterSortSheet = true
                    }
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .studios {
                    CatalogFilterFABButton(isActive: linkedStudios.catalogFilterSortFABActive) {
                        HapticManager.light()
                        linkedStudios.showFilterSortSheet = true
                    }
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .images {
                    let cardColumns = tabManager.catalogCardColumns(for: CatalogCardColumnScope.images)
                    CatalogFABIconButton(
                        systemImage: cardColumns.toggleIcon,
                        accessibilityLabel: cardColumns.accessibilityLabel,
                        accessibilityHint: "Switches between one and two cards per row"
                    ) {
                        withAnimation(DesignTokens.Animation.quick) {
                            tabManager.toggleCatalogCardColumns(for: CatalogCardColumnScope.images)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    CatalogFilterFABButton(isActive: linkedImages.catalogFilterSortFABActive) {
                        HapticManager.light()
                        linkedImages.showFilterSortSheet = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
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
            liveMinRating: $linkedStudios.liveFilterMinRating,
            liveFavorite: $linkedStudios.liveFilterFavorite,
            liveScenes: $linkedStudios.liveFilterScenes,
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
            liveMinRating: $linkedGalleries.liveFilterMinRating,
            liveFavorite: $linkedGalleries.liveFilterFavorite,
            liveFiles: $linkedGalleries.liveFilterFiles,
            liveStudioId: $linkedGalleries.liveFilterStudioId,
            studioPickerOptions: linkedGalleries.studioPickerOptions,
            studioPickerLoading: linkedGalleries.studioPickerLoading,
            onStudioPickerSectionAppear: { linkedGalleries.loadStudioPickerOptions(viewModel: viewModel) },
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
            liveMinRating: $linkedImages.liveFilterMinRating,
            livePerformerFavorite: $linkedImages.liveFilterPerformerFavorite,
            liveOrganized: $linkedImages.liveFilterOrganized,
            liveOCounterTag: $linkedImages.liveFilterOCounterTag,
            liveStudioIds: $linkedImages.liveFilterStudioIds,
            liveTagIds: $linkedImages.liveFilterTagIds,
            liveMediaKind: $linkedImages.liveFilterMediaKind,
            studioPickerOptions: linkedImages.studioPickerOptions,
            studioPickerLoading: linkedImages.studioPickerLoading,
            onStudioPickerSectionAppear: { linkedImages.loadStudioPickerOptions(viewModel: viewModel) },
            tagPickerOptions: linkedImages.tagPickerOptions,
            tagPickerLoading: linkedImages.tagPickerLoading,
            onTagPickerSectionAppear: { linkedImages.loadTagPickerOptions(viewModel: viewModel) },
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
            showsImagesFeedAutoplaySetting: true
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
        if viewModel.detailImages.isEmpty && !viewModel.isLoadingDetailImages {
            linkedImages.refetchImages(viewModel: viewModel, initial: true)
        }
    }
    
    private var tagHeaderView: some View {
        let collapsedHeight: CGFloat = 115
        let imageWidth: CGFloat = 72
        
        return HStack(alignment: .top, spacing: 0) {
            // Thumbnail: 9:16 portrait style strip, flush to edges
            ZStack(alignment: .bottom) {
                TagImageView(tag: selectedTag)
                    .frame(width: imageWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .frame(width: imageWidth)
            .frame(minHeight: collapsedHeight)
            .frame(maxHeight: isHeaderExpanded ? .infinity : collapsedHeight)
            .background(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            
            // Details Section
            VStack(alignment: .leading, spacing: 4) {
                // Header: Name and Feeds (Edit / Favorite live in the custom navbar)
                HStack(alignment: .top, spacing: 8) {
                    Text(selectedTag.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(isHeaderExpanded ? nil : 1)
                    
                    Spacer()
                    
                    if showsFeedsNavButton {
                        Button(action: {
                            coordinator.navigateToReels(tags: [selectedTag], mode: nil)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: AppTab.reels.icon)
                                    .font(.system(size: 12, weight: .bold))
                                Text("Feeds")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(Color.pillAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(appearanceManager.tintColor.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                }
                
                // Grid for Tag Info
                let allDetails = getTagDetails(selectedTag)
                let visibleDetails = isHeaderExpanded ? allDetails : Array(allDetails.prefix(4))
                
                if !visibleDetails.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        ForEach(visibleDetails, id: \.label) { detail in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(detail.label)
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(detail.value)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                
                if let desc = selectedTag.description, !desc.isEmpty, isHeaderExpanded {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: collapsedHeight, alignment: .topLeading)
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .overlay(
            Group {
                let allDetails = getTagDetails(selectedTag)
                if allDetails.count > 4 || (selectedTag.description?.count ?? 0) > 0 {
                    Button(action: {
                        withAnimation(.spring()) {
                            isHeaderExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isHeaderExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.pillAccent)
                            .padding(6)
                            .background(appearanceManager.tintColor.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .padding(8)
                }
            },
            alignment: .bottomTrailing
        )
    }
    
    private func getTagDetails(_ t: Tag) -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        
        list.append((label: "SCENES", value: "\(effectiveScenes)"))
        if effectiveGalleries > 0 {
            list.append((label: "GALLERIES", value: "\(effectiveGalleries)"))
        }
        
        if let val = t.performerCount, val > 0 {
            list.append((label: "PERFORMERS", value: "\(val)"))
        }
        
        if let val = t.sceneMarkerCount, val > 0 {
            list.append((label: "MARKERS", value: "\(val)"))
        }
        
        if let created = t.createdAt, !created.isEmpty {
            let date = created.prefix(10)
            list.append((label: "CREATED", value: String(date)))
        }
        
        if let updated = t.updatedAt, !updated.isEmpty {
            let date = updated.prefix(10)
            list.append((label: "UPDATED", value: String(date)))
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
                    StudioCardView(studio: studio)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailStudios { ProgressView().padding() }
            else if viewModel.hasMoreDetailStudios {
                Color.clear.onAppear { linkedStudios.refetchStudios(viewModel: viewModel, initial: false) }
            }
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
    }
    
    private var imageGrid: some View {
        LinkedImagesCatalogGrid(
            images: $viewModel.detailImages,
            sortOption: linkedImages.selectedSortOption,
            isLoading: viewModel.isLoadingDetailImages,
            hasMore: viewModel.hasMoreDetailImages,
            onLoadMore: { linkedImages.refetchImages(viewModel: viewModel, initial: false) },
            multiColumnGridItems: galleryColumns,
            isFeedScrolling: imagesFeedScrolling
        )
    }
    
}

// MARK: - Edit Tag Sheet

struct EditTagSheet: View {
    let tag: Tag
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: (Tag) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section("Description") {
                    TextEditor(text: $descriptionText)
                        .frame(minHeight: 120)
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome("Edit Tag", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(
                    title: "Save",
                    enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isBusy: isSaving
                ) { save() }
            }
            .onAppear {
                name = tag.name
                descriptionText = tag.description ?? ""
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionValue: String? = trimmedDescription.isEmpty ? nil : trimmedDescription

        isSaving = true
        viewModel.updateTagDetails(
            tagId: tag.id,
            name: trimmedName,
            description: descriptionValue
        ) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    var updated = tag
                    updated.name = trimmedName
                    updated.description = descriptionValue
                    onComplete(updated)
                    ToastManager.shared.show("Tag updated", icon: "checkmark.circle", style: .success)
                    dismiss()
                } else {
                    ToastManager.shared.show("Failed to update tag", icon: "exclamationmark.triangle", style: .error)
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
        case successSVG(Data, String)
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
                    .overlay(InlineSpinner(tint: .white))
            } else if let image = loader.image {
                image
                    .resizable()
                    .scaledToFill()
            } else if let data = loader.imageData, isSVG(data) {
                let dataString = String(data: data, encoding: .utf8) ?? ""
                ZStack {
                    SVGWebView(svgData: data, svgString: dataString)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Color.clear.contentShape(Rectangle())
                }
            } else {
                Rectangle()
                    .fill(appearanceManager.tintColor)
                    .overlay(
                        Image(systemName: "number")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
        }
    }

    private func isSVG(_ data: Data) -> Bool {
        let str = String(data: data.prefix(100), encoding: .utf8) ?? ""
        return str.lowercased().contains("<svg")
    }
}

#endif

