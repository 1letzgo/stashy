//
//  CatalogsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

#if !os(tvOS)
import SwiftUI

struct CatalogsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    /// Ein ViewModel für alle Katalog-Listen-Tabs (Scenes, Images, …): Daten bleiben beim Unter-Tab-Wechsel warm, ein Verbindungstest.
    @StateObject private var catalogBrowserViewModel = StashDBViewModel()
    /// Images filter/sort session — lives on CatalogsView so it survives ImagesView remounts
    /// when pushing FullScreenImageView (especially 1/row video).
    @StateObject private var catalogImagesFilters = DetailLinkedImagesFilterModel(scope: .catalogRoot)
    
    enum CatalogsTab: String, CaseIterable {
        case dashboard = "Dashboard"
        case scenes = "Scenes"
        case images = "Images"
        case galleries = "Galleries"
        case performers = "Performers"
        case studios = "Studios"
        case tags = "Tags"
        case groups = "Groups"
        case markers = "Markers"
        
        var icon: String {
            switch self {
            case .dashboard: return "house.fill"
            case .scenes: return "film"
            case .images: return "photo"
            case .galleries: return "photo.stack"
            case .performers: return "person.fill"
            case .studios: return "building.2"
            case .tags: return "tag"
            case .groups: return "rectangle.stack.fill"
            case .markers: return "bookmark.fill"
            }
        }

        static func from(appTab: AppTab) -> CatalogsTab? {
            switch appTab {
            case .dashboard: return .dashboard
            case .scenes: return .scenes
            case .galleries: return .galleries
            case .images: return .images
            case .performers: return .performers
            case .studios: return .studios
            case .tags: return .tags
            case .groups: return .groups
            case .markers: return .markers
            default: return nil
            }
        }
    }
    
    private var sortedVisibleTabs: [CatalogsTab] {
        var tabs = tabManager.tabs
            .filter { ($0.id == .dashboard || $0.id == .performers || $0.id == .studios || $0.id == .tags || $0.id == .scenes || $0.id == .galleries || $0.id == .images || $0.id == .groups || $0.id == .markers) && $0.isVisible }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { (config: TabConfig) -> CatalogsTab? in
                switch config.id {
                case .dashboard: return .dashboard
                case .scenes: return .scenes
                case .galleries: return .galleries
                case .images: return .images
                case .performers: return .performers
                case .studios: return .studios
                case .tags: return .tags
                case .groups: return .groups
                case .markers: return .markers
                default: return nil
                }
            }
        // Search → Show All / stats deep links can target a hidden catalog tab.
        if let current = CatalogsTab(rawValue: coordinator.catalogueSubTab), !tabs.contains(current) {
            tabs.append(current)
        }
        return tabs
    }
    
    private var selectedTabBinding: Binding<CatalogsTab> {
        Binding(
            get: { effectiveTab ?? .studios },
            set: { coordinator.catalogueSubTab = $0.rawValue }
        )
    }

    private var showTabSwitcher: Bool {
        sortedVisibleTabs.count > 1
    }

    private var effectiveTab: CatalogsTab? {
        let visible = sortedVisibleTabs
        
        // If current sub-tab is in visible list, use it
        if let current = CatalogsTab(rawValue: coordinator.catalogueSubTab), visible.contains(current) {
            return current
        }
        
        // Otherwise fallback to the first visible one (respecting sortOrder)
        return visible.first
    }

    @ViewBuilder
    private func catalogRoot(for tab: CatalogsTab) -> some View {
        switch tab {
        case .dashboard:
            HomeView(catalogBrowserViewModel: catalogBrowserViewModel)
        case .scenes:
            ScenesView.catalogTab(viewModel: catalogBrowserViewModel)
        case .images:
            ImagesView(
                catalogBrowserViewModel: catalogBrowserViewModel,
                sharedImageListFilters: catalogImagesFilters,
                initialSearch: coordinator.activeSearchText
            )
        case .galleries:
            GalleriesView(catalogBrowserViewModel: catalogBrowserViewModel)
        case .performers:
            PerformersView(catalogBrowserViewModel: catalogBrowserViewModel)
        case .studios:
            StudiosView(hideTitle: false, catalogBrowserViewModel: catalogBrowserViewModel)
        case .tags:
            TagsView(hideTitle: false, catalogBrowserViewModel: catalogBrowserViewModel)
        case .groups:
            GroupsView(hideTitle: false, catalogBrowserViewModel: catalogBrowserViewModel)
        case .markers:
            MarkersView(hideTitle: false, catalogBrowserViewModel: catalogBrowserViewModel)
        }
    }
    
    var body: some View {
        Group {
            if let tab = effectiveTab {
                catalogRoot(for: tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.identity)
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Please enable Dashboard, Performers, Studios, Tags, Groups or Markers in Settings")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.identity)
            }
        }
        .transaction(value: coordinator.catalogueSubTab) { $0.animation = nil }
        .animation(nil, value: coordinator.catalogueSubTab)
        .navigationBarHidden(true)
        // Swipe-back can desync UIKit/SwiftUI stacks; menu switches must always clear details.
        .popNavigationToRootOnChange("\(coordinator.catalogueSubTab)|\(coordinator.cataloguePopToken.uuidString)")
        .stashyCustomChromeInset(spacing: DesignTokens.Chrome.contentTopGap) {
            if showTabSwitcher {
                StashySectionChromeBar {
                    CatalogCategoryRow(tabs: sortedVisibleTabs, selection: selectedTabBinding)
                        .padding(.horizontal, StashyExpandingDock.edgePadding)
                        .padding(.vertical, 6)
                }
            }
        }
    }
}
#endif

// MARK: - Groups Support Views

#if !os(tvOS)
struct GroupsView: View {
    @StateObject private var ownedViewModel = StashDBViewModel()
    let catalogBrowserViewModel: StashDBViewModel?
    var hideTitle: Bool = false

    init(hideTitle: Bool = false, catalogBrowserViewModel: StashDBViewModel? = nil) {
        self.hideTitle = hideTitle
        self.catalogBrowserViewModel = catalogBrowserViewModel
    }

    var body: some View {
        GroupsViewContent(viewModel: catalogBrowserViewModel ?? ownedViewModel, hideTitle: hideTitle)
    }
}

private struct GroupsViewContent: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.GroupSortOption = StashDBViewModel.GroupSortOption(rawValue: TabManager.shared.getSortOption(for: .groups) ?? "") ?? .nameAsc
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var showGroupsFilterSheet = false
    @State private var groupsPresetRowSelection = ""
    @StateObject private var groupsCriteriaDocument = FilterCriteriaDocument(mode: .groups)
    @State private var showGroupsSaveAsAlert = false
    @State private var showGroupsRenameAlert = false
    @State private var showGroupsDeleteAlert = false
    @State private var groupsFilterNameInput = ""
    @State private var lastOpenedGroupId: String?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    var hideTitle: Bool = false

    init(viewModel: StashDBViewModel, hideTitle: Bool = false) {
        self.viewModel = viewModel
        self.hideTitle = hideTitle
    }
    

    /// Advanced criteria are sent as `liveFilter`, so edits apply without saving to the server first.
    private var effectiveLiveFilter: [String: Any]? {
        groupsCriteriaDocument.merged(with: [:])
    }

    private func saveGroupsFilterOverwrite() {
        guard let sid = ListLivePresetTag.parseServerId(groupsPresetRowSelection),
              let existing = viewModel.savedFilters[sid] else { return }
        viewModel.saveFullObjectFilter(
            mode: .groups,
            existingId: sid,
            name: existing.name,
            sortField: selectedSortOption.sortField == "random" ? "random" : selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            sortRaw: selectedSortOption.rawValue,
            objectFilter: groupsCriteriaDocument.sanitizedObjectFilter,
            randomSeedKind: .groups
        ) { result in
            switch result {
            case .success:
                HapticManager.success()
                viewModel.fetchSavedFilters()
            case .failure(let error):
                ToastManager.shared.show("Save failed: \(error.localizedDescription)", icon: "exclamationmark.triangle.fill", style: .error)
            }
        }
    }

    private func saveGroupsFilterAs(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveFullObjectFilter(
            mode: .groups,
            existingId: nil,
            name: trimmed,
            sortField: selectedSortOption.sortField == "random" ? "random" : selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            sortRaw: selectedSortOption.rawValue,
            objectFilter: groupsCriteriaDocument.sanitizedObjectFilter,
            randomSeedKind: .groups
        ) { result in
            switch result {
            case .success(let saved):
                HapticManager.success()
                groupsPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                selectedFilter = saved
                viewModel.fetchSavedFilters()
            case .failure(let error):
                ToastManager.shared.show("Save failed: \(error.localizedDescription)", icon: "exclamationmark.triangle.fill", style: .error)
            }
        }
    }

    private func renameGroupsFilter(to name: String) {
        guard let sid = ListLivePresetTag.parseServerId(groupsPresetRowSelection),
              let existing = viewModel.savedFilters[sid] else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.renameSavedFilter(existing, to: trimmed) { result in
            switch result {
            case .success:
                HapticManager.success()
                viewModel.fetchSavedFilters()
            case .failure(let error):
                ToastManager.shared.show("Rename failed: \(error.localizedDescription)", icon: "exclamationmark.triangle.fill", style: .error)
            }
        }
    }

    private func deleteGroupsFilter() {
        guard let sid = ListLivePresetTag.parseServerId(groupsPresetRowSelection) else { return }
        viewModel.destroySavedSceneFilter(id: sid) { result in
            switch result {
            case .success:
                HapticManager.success()
                groupsPresetRowSelection = ""
                selectedFilter = nil
                groupsCriteriaDocument.clear()
                viewModel.fetchSavedFilters()
                performSearch()
            case .failure(let error):
                ToastManager.shared.show("Delete failed: \(error.localizedDescription)", icon: "exclamationmark.triangle.fill", style: .error)
            }
        }
    }

    // Search function
    private func performSearch(isInitialLoad: Bool = true) {
        viewModel.fetchGroups(
            sortBy: selectedSortOption,
            searchQuery: searchText,
            isInitialLoad: isInitialLoad,
            filter: selectedFilter,
            liveFilter: effectiveLiveFilter
        )
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.isLoadingGroups && viewModel.groups.isEmpty {
                StandardLoadingView(message: "Loading groups...")
            } else if viewModel.groups.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.groups.isEmpty {
                emptyStateView
            } else {
                groupsGrid
            }
        }
        .navigationTitle("Groups")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .floatingActionBar(isPresented: true, catalogChrome: CatalogFloatingChromeState(hasActiveServerConfig: configManager.activeConfig != nil, primaryListIsEmpty: viewModel.groups.isEmpty, errorMessage: viewModel.errorMessage)) {
            HStack(spacing: 0) {
                // Search Pill (if active)
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        performSearch()
                    }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text(searchText)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
                            .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Sort Menu
                    Menu {
                        // Random
                        Button(action: { changeSortOption(to: .random) }) {
                            HStack {
                                Text("Random")
                                if selectedSortOption == .random { Image(systemName: "checkmark") }
                            }
                        }
                        
                        Divider()
                        
                        // Name
                        Menu {
                            Button(action: { changeSortOption(to: .nameAsc) }) {
                                HStack {
                                    Text("A → Z")
                                    if selectedSortOption == .nameAsc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .nameDesc) }) {
                                HStack {
                                    Text("Z → A")
                                    if selectedSortOption == .nameDesc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Name")
                                if selectedSortOption == .nameAsc || selectedSortOption == .nameDesc { Image(systemName: "checkmark") }
                            }
                        }

                        // Date
                        Menu {
                            Button(action: { changeSortOption(to: .dateDesc) }) {
                                HStack {
                                    Text("Newest First")
                                    if selectedSortOption == .dateDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .dateAsc) }) {
                                HStack {
                                    Text("Oldest First")
                                    if selectedSortOption == .dateAsc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Date")
                                if selectedSortOption == .dateAsc || selectedSortOption == .dateDesc { Image(systemName: "checkmark") }
                            }
                        }

                        // Rating
                        Menu {
                            Button(action: { changeSortOption(to: .ratingDesc) }) {
                                HStack {
                                    Text("High → Low")
                                    if selectedSortOption == .ratingDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .ratingAsc) }) {
                                HStack {
                                    Text("Low → High")
                                    if selectedSortOption == .ratingAsc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Rating")
                                if selectedSortOption == .ratingAsc || selectedSortOption == .ratingDesc { Image(systemName: "checkmark") }
                            }
                        }

                        // Counts
                        Menu {
                            Button(action: { changeSortOption(to: .sceneCountDesc) }) {
                                HStack {
                                    Text("Scenes (High → Low)")
                                    if selectedSortOption == .sceneCountDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .galleryCountDesc) }) {
                                HStack {
                                    Text("Galleries (High → Low)")
                                    if selectedSortOption == .galleryCountDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .performerCountDesc) }) {
                                HStack {
                                    Text("Performers (High → Low)")
                                    if selectedSortOption == .performerCountDesc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Counts")
                                if selectedSortOption == .sceneCountDesc || selectedSortOption == .galleryCountDesc || selectedSortOption == .performerCountDesc { Image(systemName: "checkmark") }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: DesignTokens.Chrome.fabIconSize, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)

                    CatalogFilterFABButton(isActive: selectedFilter != nil || !groupsCriteriaDocument.objectFilter.isEmpty) {
                        if let f = selectedFilter {
                            groupsPresetRowSelection = ListLivePresetTag.serverRow(f.id)
                            groupsCriteriaDocument.load(f.criteriaObjectFilter())
                        }
                        showGroupsFilterSheet = true
                    }
                    .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showGroupsFilterSheet) {
            GroupsCatalogFilterSortSheet(
                serverFilters: viewModel.savedFilters.values.filter { $0.mode == .groups }.sorted { $0.name < $1.name },
                selectedPresetRowId: $groupsPresetRowSelection,
                criteriaDocument: groupsCriteriaDocument,
                sortOption: selectedSortOption,
                onSortChange: { changeSortOption(to: $0) },
                onApply: { performSearch() },
                onReset: {
                    groupsPresetRowSelection = ""
                    selectedFilter = nil
                    groupsCriteriaDocument.clear()
                    performSearch()
                },
                onRequestSave: { saveGroupsFilterOverwrite() },
                onRequestSaveAs: {
                    groupsFilterNameInput = ""
                    showGroupsSaveAsAlert = true
                },
                onRequestRename: {
                    guard let sid = ListLivePresetTag.parseServerId(groupsPresetRowSelection) else { return }
                    groupsFilterNameInput = viewModel.savedFilters[sid]?.name ?? ""
                    showGroupsRenameAlert = true
                },
                onRequestDelete: { showGroupsDeleteAlert = true }
            )
            .environmentObject(viewModel)
        }
        .alert("Save filter as", isPresented: $showGroupsSaveAsAlert) {
            TextField("Name", text: $groupsFilterNameInput)
            Button("Save") { saveGroupsFilterAs(name: groupsFilterNameInput) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename filter", isPresented: $showGroupsRenameAlert) {
            TextField("Name", text: $groupsFilterNameInput)
            Button("Save") { renameGroupsFilter(to: groupsFilterNameInput) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete filter?", isPresented: $showGroupsDeleteAlert) {
            Button("Delete", role: .destructive) { deleteGroupsFilter() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            viewModel.fetchSavedFilters()

            if !coordinator.activeSearchText.isEmpty {
                searchText = coordinator.activeSearchText
                isSearchVisible = true
                coordinator.activeSearchText = ""
            }
            
            // Initial fetch if empty
            if viewModel.groups.isEmpty {
                // If no default filter is set, fetch immediately
                if TabManager.shared.getDefaultFilterId(for: .groups) == nil {
                    performSearch()
                }
            }
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // Apply default filter if set and none selected yet
            if selectedFilter == nil {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .groups),
                   let filter = newValue[defaultId] {
                    selectedFilter = filter
                    if viewModel.groups.isEmpty {
                        performSearch()
                    }
                } else if !viewModel.isLoadingSavedFilters && viewModel.groups.isEmpty {
                    performSearch()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.groups.rawValue {
                let newSort = StashDBViewModel.GroupSortOption(rawValue: TabManager.shared.getPersistentSortOption(for: .groups) ?? "") ?? .nameAsc
                changeSortOption(to: newSort)
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if newValue == self.searchText {
                    performSearch()
                }
            }
        }
    }

    private func changeSortOption(to newOption: StashDBViewModel.GroupSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        TabManager.shared.setSortOption(for: .groups, option: newOption.rawValue)
        performSearch()
    }

    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: "rectangle.stack.fill",
            title: "No groups found",
            buttonText: "Load Groups",
            onRetry: { performSearch() }
        )
    }

    @State private var gridWidth: CGFloat = 0

    private var columns: [GridItem] {
        DesignTokens.Grid.adaptiveColumns(
            width: gridWidth,
            ideal: DesignTokens.Grid.idealPosterCardWidth,
            minimum: 2,
            maximum: 8
        )
    }

    private var groupsGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.groups) { group in
                        NavigationLink(destination: GroupDetailView(selectedGroup: group)) {
                            GroupCardView(group: group)
                        }
                        .buttonStyle(.plain)
                        .id(group.id)
                        .simultaneousGesture(TapGesture().onEnded {
                            lastOpenedGroupId = group.id
                        })
                    }

                    // Loading indicator for pagination
                    if viewModel.isLoadingMoreGroups {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if viewModel.hasMoreGroups && !viewModel.groups.isEmpty {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                viewModel.loadMoreGroups()
                            }
                            .id("pagination-trigger")
                    }
                }
                .measuresGridWidth($gridWidth)
                .padding(16)
            }
            .refreshable { performSearch() }
            .onAppear {
                if let id = lastOpenedGroupId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
        }
    }
}

struct GroupCardView: View {
    let group: StashGroup
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Image
            GeometryReader { geometry in
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))

                    if let url = group.thumbnailURL {
                        CustomAsyncImage(url: url) { loader in
                            if loader.isLoading {
                                ProgressView()
                            } else if let image = loader.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                                    .clipped()
                            } else {
                                placeholderImageContent
                            }
                        }
                    } else {
                        placeholderImageContent
                    }
                }
            }
            .aspectRatio(9/12, contentMode: .fit) 
            
            // Gradient Overlay
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
            
            // Top Badges
            VStack {
                HStack(spacing: 8) {
                    Spacer()
                    // Gallery Badge (if available)
                    if let galleryCount = group.gallery_count, galleryCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(galleryCount)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 2)
                    }

                    // Scenes Badge
                    if let count = group.scene_count {
                        HStack(spacing: 3) {
                            Image(systemName: "film")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(count)")
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
                .padding(8)
                Spacer()
            }
            
            // Info Section (Bottom Name)
            VStack(alignment: .leading, spacing: 4) {
                 HStack(alignment: .bottom, spacing: 6) {
                    Text(group.name)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
    
    private var placeholderImageContent: some View {
        Image(systemName: "rectangle.stack")
            .font(.largeTitle)
            .foregroundColor(.secondary)
    }
}

struct GroupDetailView: View {
    @State private var selectedGroup: StashGroup
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var groupLiveFilterSheetPresented = false
    @State private var isHeaderExpanded = false
    @State private var showingEditGroupSheet = false
    @StateObject private var linkedPerformers: DetailLinkedPerformersFilterModel
    @StateObject private var linkedTags: DetailLinkedTagsFilterModel
    @StateObject private var linkedStudios: DetailLinkedStudiosFilterModel
    @StateObject private var linkedGalleries: DetailLinkedGalleriesFilterModel
    @StateObject private var linkedImages: DetailLinkedImagesFilterModel

    private var chromePillHeight: CGFloat { StashyExpandingDock.activeHeight }
    private var navActionGroupSpacing: CGFloat { 7 }
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
        case performers = "Performers"
        case studios = "Studios"
        case tags = "Tags"
        case images = "Images"

        var icon: String {
            switch self {
            case .scenes: return "film"
            case .galleries: return "photo.stack"
            case .performers: return "person.fill"
            case .studios: return "building.2"
            case .tags: return "tag"
            case .images: return "photo"
            }
        }
    }
    @State private var selectedDetailTab: DetailTab

    init(selectedGroup: StashGroup) {
        _selectedGroup = State(initialValue: selectedGroup)
        let sc = selectedGroup.scene_count ?? 0
        let gal = selectedGroup.gallery_count ?? 0
        _selectedDetailTab = State(initialValue: sc > 0 ? .scenes : (gal > 0 ? .galleries : .scenes))
        let gid = selectedGroup.id
        _linkedPerformers = StateObject(wrappedValue: DetailLinkedPerformersFilterModel(scope: .group(gid)))
        _linkedTags = StateObject(wrappedValue: DetailLinkedTagsFilterModel(scope: .group(gid)))
        _linkedStudios = StateObject(wrappedValue: DetailLinkedStudiosFilterModel(scope: .group(gid)))
        _linkedGalleries = StateObject(wrappedValue: DetailLinkedGalleriesFilterModel(scope: .group(gid)))
        _linkedImages = StateObject(wrappedValue: DetailLinkedImagesFilterModel(scope: .group(gid)))
    }

    private var effectiveScenes: Int {
        max(viewModel.totalGroupScenes, selectedGroup.scene_count ?? 0)
    }

    @State private var galleryGridWidth: CGFloat = 0

    private var galleryColumns: [GridItem] {
        DesignTokens.Grid.adaptiveColumns(
            width: galleryGridWidth,
            ideal: DesignTokens.Grid.idealPosterCardWidth,
            minimum: 2,
            maximum: 8
        )
    }

    private var effectiveGalleries: Int {
        max(viewModel.totalGroupGalleries, selectedGroup.gallery_count ?? 0)
    }

    private var availableTabs: [DetailTab] {
        var tabs: [DetailTab] = []
        if effectiveScenes > 0 { tabs.append(.scenes) }
        if effectiveGalleries > 0 { tabs.append(.galleries) }
        if viewModel.totalDetailPerformers > 0 { tabs.append(.performers) }
        if viewModel.totalDetailStudios > 0 { tabs.append(.studios) }
        if viewModel.totalDetailTags > 0 { tabs.append(.tags) }
        if viewModel.totalDetailImages > 0 { tabs.append(.images) }
        return tabs
    }

    private var showTabSwitcher: Bool {
        availableTabs.count > 1
    }

    private var groupDetailCatalogFloatingChromeForFooter: CatalogFloatingChromeState {
        let primaryEmpty: Bool = {
            switch selectedDetailTab {
            case .scenes: return viewModel.groupScenes.isEmpty
            case .galleries: return viewModel.groupGalleries.isEmpty
            case .performers: return viewModel.detailPerformers.isEmpty
            case .studios: return viewModel.detailStudios.isEmpty
            case .tags: return viewModel.detailTags.isEmpty
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

    @ViewBuilder
    private var groupScenesStack: some View {
        ScenesView(
            hideTitle: true,
            scope: .group(groupId: selectedGroup.id),
            sharedViewModel: viewModel,
            externalLiveFilterSheetBinding: $groupLiveFilterSheetPresented,
            showsFloatingFilterButton: false,
            scrollHeader: AnyView(headerView)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Custom top chrome (Performer/Studio template): Back · section icons · Edit.
    /// Groups have no favorite field in the Stash API.
    @ViewBuilder
    private var groupDetailNavBar: some View {
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

                if appearanceManager.isEditModeEnabled {
                    if showTabSwitcher {
                        Spacer()
                            .frame(width: navActionGroupSpacing)
                    }

                    Button {
                        HapticManager.light()
                        showingEditGroupSheet = true
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
                    .accessibilityLabel("Edit group")
                }
            }
            .frame(minHeight: chromePillHeight)
            .padding(.horizontal, StashyExpandingDock.edgePadding)
            .padding(.vertical, 8)

        }
    }

    @ViewBuilder
    private var nonScenesGroupScroll: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerView

                if selectedDetailTab == .galleries {
                    if !viewModel.groupGalleries.isEmpty {
                        galleryGrid
                    } else if viewModel.isLoadingGroupGalleries {
                        VStack {
                            InlineSpinner()
                            Text("Loading galleries...").font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        InlineEmptyStateView(icon: "photo.on.rectangle", title: "No galleries found")
                    }
                } else if selectedDetailTab == .performers {
                    performerGrid
                } else if selectedDetailTab == .studios {
                    studioGrid
                } else if selectedDetailTab == .tags {
                    tagGrid
                } else if selectedDetailTab == .images {
                    imageGrid
                }
            }
        }
        .background(Color.appBackground)
    }

    var body: some View {
        groupDetailWithLinkedGalleriesAndImagesSheets
    }

    private var groupDetailWithLinkedPerformersSheets: some View {
        groupDetailCoreChrome
            .sheet(isPresented: $linkedPerformers.showFilterSortSheet) {
                groupDetailPerformersFilterSheet
            }
            .onChange(of: linkedPerformers.catalogPresetRowSelection) { _, newId in
                linkedPerformers.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert("Save As", isPresented: $linkedPerformers.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $linkedPerformers.catalogPresetNameInput)
                Button("Save") { linkedPerformers.savePresetAs(name: linkedPerformers.catalogPresetNameInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $linkedPerformers.showRenameCatalogPresetAlert) {
                TextField("Name", text: $linkedPerformers.renameCatalogPresetInput)
                Button("Save") { linkedPerformers.renamePreset(to: linkedPerformers.renameCatalogPresetInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $linkedPerformers.showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { linkedPerformers.deletePreset(viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(linkedPerformers.deletePresetConfirmationText(viewModel: viewModel))
            }
    }

    private var groupDetailWithLinkedTagsSheets: some View {
        groupDetailWithLinkedPerformersSheets
            .sheet(isPresented: $linkedTags.showFilterSortSheet) {
                groupDetailTagsFilterSheet
            }
            .onChange(of: linkedTags.catalogPresetRowSelection) { _, newId in
                linkedTags.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert("Save As", isPresented: $linkedTags.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $linkedTags.catalogPresetNameInput)
                Button("Save") { linkedTags.savePresetAs(name: linkedTags.catalogPresetNameInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $linkedTags.showRenameCatalogPresetAlert) {
                TextField("Name", text: $linkedTags.renameCatalogPresetInput)
                Button("Save") { linkedTags.renamePreset(to: linkedTags.renameCatalogPresetInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $linkedTags.showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { linkedTags.deletePreset(viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(linkedTags.deletePresetConfirmationText(viewModel: viewModel))
            }
    }

    private var groupDetailWithLinkedStudiosSheets: some View {
        groupDetailWithLinkedTagsSheets
            .sheet(isPresented: $linkedStudios.showFilterSortSheet) {
                groupDetailStudiosFilterSheet
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

    private var groupDetailWithLinkedGalleriesAndImagesSheets: some View {
        groupDetailWithLinkedStudiosSheets
            .sheet(isPresented: $linkedGalleries.showFilterSortSheet) {
                groupDetailGalleriesFilterSheet
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
                groupDetailImagesFilterSheet
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

    private var groupDetailCoreChrome: some View {
        Group {
            if selectedDetailTab == .scenes {
                groupScenesStack
            } else {
                nonScenesGroupScroll
            }
        }
        .applyAppBackground()
        .sceneLiveUpdates(using: viewModel)
        .hideSystemNavigationBarForCustomChrome()
        .enableSwipeBackWhenNavBarHidden()
        .stashyCustomChromeInset(spacing: DesignTokens.Chrome.contentTopGap) {
            groupDetailNavBar
        }
        .sheet(isPresented: $showingEditGroupSheet) {
            EditGroupSheet(group: selectedGroup, viewModel: viewModel) { updated in
                selectedGroup = updated
            }
        }
        .floatingActionBar(isPresented: true, catalogChrome: groupDetailCatalogFloatingChromeForFooter) {
            HStack(spacing: 0) {
                if selectedDetailTab == .scenes {
                    CatalogFilterFABButton(isActive: true) {
                        HapticManager.light()
                        groupLiveFilterSheetPresented = true
                    }
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .galleries {
                    CatalogFilterFABButton(isActive: linkedGalleries.catalogFilterSortFABActive) {
                        HapticManager.light()
                        linkedGalleries.showFilterSortSheet = true
                    }
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .performers {
                    CatalogFilterFABButton(isActive: linkedPerformers.catalogFilterSortFABActive) {
                        HapticManager.light()
                        linkedPerformers.showFilterSortSheet = true
                    }
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .studios {
                    CatalogFilterFABButton(isActive: linkedStudios.catalogFilterSortFABActive) {
                        HapticManager.light()
                        linkedStudios.showFilterSortSheet = true
                    }
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .tags {
                    CatalogFilterFABButton(isActive: linkedTags.catalogFilterSortFABActive) {
                        HapticManager.light()
                        linkedTags.showFilterSortSheet = true
                    }
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .images {
                    CatalogFilterFABButton(isActive: linkedImages.catalogFilterSortFABActive) {
                        HapticManager.light()
                        linkedImages.showFilterSortSheet = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            if viewModel.groupGalleries.isEmpty {
                linkedGalleries.refetchGalleries(viewModel: viewModel, initial: true)
            }

            viewModel.fetchGroup(groupId: selectedGroup.id) { updated in
                if let updated {
                    selectedGroup = updated
                }
            }

            viewModel.fetchSavedFilters()
            linkedPerformers.refetchPerformers(viewModel: viewModel, initial: true)
            linkedStudios.refetchStudios(viewModel: viewModel, initial: true)
            linkedTags.refetchTags(viewModel: viewModel, initial: true)
            if viewModel.detailImages.isEmpty && !viewModel.isLoadingDetailImages {
                linkedImages.refetchImages(viewModel: viewModel, initial: true)
            }
        }
    }

    @ViewBuilder
    private var groupDetailPerformersFilterSheet: some View {
        PerformersCatalogFilterSortSheet(
            serverFilters: linkedPerformers.sortedServerPerformerFilters(viewModel: viewModel),
            localPresets: linkedPerformers.localCatalogPresets,
            selectedPresetRowId: $linkedPerformers.catalogPresetRowSelection,
            criteriaDocument: linkedPerformers.criteriaDocument,
            sortOption: linkedPerformers.selectedSortOption,
            onSortChange: { linkedPerformers.changeSortOption(to: $0, viewModel: viewModel) },
            liveAgeRange: $linkedPerformers.liveFilterAgeRange,
            liveHairColor: $linkedPerformers.liveFilterHairColor,
            liveGender: $linkedPerformers.liveFilterGender,
            liveCountry: $linkedPerformers.liveFilterCountry,
            liveImplants: $linkedPerformers.liveFilterImplants,
            liveFavorite: $linkedPerformers.liveFilterFavorite,
            liveMissingField: $linkedPerformers.liveFilterMissingField,
            liveOCounterTag: $linkedPerformers.liveFilterOCounterTag,
            onApply: { linkedPerformers.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedPerformers.catalogPresetRowSelection = ""
                linkedPerformers.selectedFilter = nil
                linkedPerformers.clearLiveChipsOnly()
                    linkedPerformers.criteriaDocument.clear()
                linkedPerformers.applyLiveFilter(viewModel: viewModel)
            },
            onRequestSave: { linkedPerformers.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                linkedPerformers.catalogPresetNameInput = ""
                linkedPerformers.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(linkedPerformers.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    linkedPerformers.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(linkedPerformers.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = linkedPerformers.localCatalogPresets.first(where: { $0.id == uuid }) {
                    linkedPerformers.renameCatalogPresetInput = p.name
                }
                linkedPerformers.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { linkedPerformers.showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            ListLivePresetTag.migrateLegacySelection(&linkedPerformers.catalogPresetRowSelection)
            linkedPerformers.refreshLocalPresets()
            linkedPerformers.applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var groupDetailTagsFilterSheet: some View {
        TagsCatalogFilterSortSheet(
            serverFilters: linkedTags.sortedServerTagFilters(viewModel: viewModel),
            localPresets: linkedTags.localCatalogPresets,
            selectedPresetRowId: $linkedTags.catalogPresetRowSelection,
            criteriaDocument: linkedTags.criteriaDocument,
            sortOption: linkedTags.selectedSortOption,
            onSortChange: { linkedTags.changeSortOption(to: $0, viewModel: viewModel) },
            liveFavorite: $linkedTags.liveFilterFavorite,
            liveHasScenes: $linkedTags.liveFilterHasScenes,
            onApply: { linkedTags.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedTags.catalogPresetRowSelection = ""
                linkedTags.selectedFilter = nil
                linkedTags.clearLiveChipsOnly()
                linkedTags.criteriaDocument.clear()
                linkedTags.applyLiveFilter(viewModel: viewModel)
            },
            onRequestSave: { linkedTags.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                linkedTags.catalogPresetNameInput = ""
                linkedTags.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(linkedTags.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    linkedTags.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(linkedTags.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = linkedTags.localCatalogPresets.first(where: { $0.id == uuid }) {
                    linkedTags.renameCatalogPresetInput = p.name
                }
                linkedTags.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { linkedTags.showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            ListLivePresetTag.migrateLegacySelection(&linkedTags.catalogPresetRowSelection)
            linkedTags.refreshLocalPresets()
            linkedTags.applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var groupDetailStudiosFilterSheet: some View {
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
    private var groupDetailGalleriesFilterSheet: some View {
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
    private var groupDetailImagesFilterSheet: some View {
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
            onRequestDelete: { linkedImages.showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            linkedImages.prepareCatalogFilterSortSheetUI(viewModel: viewModel)
        }
    }
    
    private var performerGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailPerformers) { performer in
                NavigationLink(destination: PerformerDetailView(performer: performer)) {
                    PerformerCardView(performer: performer)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailPerformers { ProgressView().padding() }
            else if viewModel.hasMoreDetailPerformers {
                Color.clear.onAppear { linkedPerformers.refetchPerformers(viewModel: viewModel, initial: false) }
            }
        }
        .measuresGridWidth($galleryGridWidth)
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }
    
    private var studioGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailStudios) { subStudio in
                NavigationLink(destination: StudioDetailView(studio: subStudio)) {
                    StudioCardView(studio: subStudio)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailStudios { ProgressView().padding() }
            else if viewModel.hasMoreDetailStudios {
                Color.clear.onAppear { linkedStudios.refetchStudios(viewModel: viewModel, initial: false) }
            }
        }
        .measuresGridWidth($galleryGridWidth)
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }
    
    private var tagGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailTags) { tag in
                NavigationLink(destination: TagDetailView(selectedTag: tag)) {
                    TagCardView(tag: tag)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailTags { ProgressView().padding() }
            else if viewModel.hasMoreDetailTags {
                Color.clear.onAppear { linkedTags.refetchTags(viewModel: viewModel, initial: false) }
            }
        }
        .measuresGridWidth($galleryGridWidth)
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }
    
    private var imageGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailImages) { image in
                NavigationLink(destination: FullScreenImageView(images: .constant(viewModel.detailImages), selectedImageId: image.id)) {
                    ImageThumbnailCard(image: image)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailImages { ProgressView().padding() }
            else if viewModel.hasMoreDetailImages {
                Color.clear.onAppear { linkedImages.refetchImages(viewModel: viewModel, initial: false) }
            }
        }
        .measuresGridWidth($galleryGridWidth)
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private var galleryGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
             ForEach(viewModel.groupGalleries) { gallery in
                 NavigationLink(destination: ImagesView(gallery: gallery)) {
                     GalleryCardView(gallery: gallery)
                 }
                 .buttonStyle(.plain)
             }
             if viewModel.isLoadingGroupGalleries {
                 VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading more galleries...").font(.caption).foregroundColor(.secondary)
                }.padding(.vertical, 20)
             } else if viewModel.hasMoreGroupGalleries {
                 Color.clear.frame(height: 1).onAppear { viewModel.loadMoreGroupGalleries(groupId: selectedGroup.id) }
             }
        }
        .measuresGridWidth($galleryGridWidth)
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private var headerView: some View {
        let collapsedHeight: CGFloat = 115
        let imageWidth: CGFloat = 72
        
        return HStack(alignment: .top, spacing: 0) {
            // Thumbnail: 9:16 portrait
            ZStack(alignment: .bottom) {
                if let url = selectedGroup.thumbnailURL {
                    CustomAsyncImage(url: url) { loader in
                        if loader.isLoading {
                            Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .overlay(InlineSpinner(scale: .compact))
                        } else if let image = loader.image {
                            image.resizable()
                                .scaledToFill()
                                .frame(width: imageWidth)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            defaultThumbnailContent(width: imageWidth)
                        }
                    }
                } else {
                    defaultThumbnailContent(width: imageWidth)
                }
            }
            .frame(width: imageWidth)
            .frame(minHeight: collapsedHeight)
            .frame(maxHeight: isHeaderExpanded ? .infinity : collapsedHeight)
            .background(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            
            // Details Section
            VStack(alignment: .leading, spacing: 4) {
                // Header: Name
                Text(selectedGroup.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(isHeaderExpanded ? nil : 2)
                
                // Grid for Group Info
                let allDetails = getGroupDetails()
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
                
                if isHeaderExpanded && !(selectedGroup.synopsis ?? "").isEmpty {
                    Text("Synopsis")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 4)
                    Text(selectedGroup.synopsis ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
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
        .padding(.horizontal, 16)
        .overlay(
            Group {
                let allDetails = getGroupDetails()
                if allDetails.count > 4 || !(selectedGroup.synopsis ?? "").isEmpty {
                    Button(action: {
                        withAnimation(.spring()) {
                            isHeaderExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isHeaderExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(appearanceManager.tintColor)
                            .padding(6)
                            .background(appearanceManager.tintColor.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 8)
                }
            },
            alignment: .bottomTrailing
        )
    }

    private func defaultThumbnailContent(width: CGFloat) -> some View {
        Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .overlay(Image(systemName: "rectangle.stack").font(.system(size: 24)).foregroundColor(.appAccent.opacity(0.5)))
    }

    private func getGroupDetails() -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        list.append((label: "SCENES", value: "\(viewModel.totalGroupScenes)"))
        if effectiveGalleries > 0 {
            list.append((label: "GALLERIES", value: "\(effectiveGalleries)"))
        }
        if let studio = selectedGroup.studio {
            list.append((label: "STUDIO", value: studio.name))
        }
        if let date = selectedGroup.date {
            list.append((label: "DATE", value: date))
        }
        if let rating = selectedGroup.rating100 {
            list.append((label: "RATING", value: "\(rating)%"))
        }
        return list
    }
}

// MARK: - Edit Group Sheet

struct EditGroupSheet: View {
    let group: StashGroup
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: (StashGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var name: String = ""
    @State private var date: String = ""
    @State private var ratingText: String = ""
    @State private var synopsis: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Date (YYYY-MM-DD)", text: $date)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numbersAndPunctuation)
                        .numericKeyboardDoneBar()
                    TextField("Rating (0–100)", text: $ratingText)
                        .keyboardType(.numberPad)
                        .numericKeyboardDoneBar()
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section("Synopsis") {
                    TextEditor(text: $synopsis)
                        .frame(minHeight: 120)
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome("Edit Group", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(
                    title: "Save",
                    enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isBusy: isSaving
                ) { save() }
            }
            .onAppear {
                name = group.name
                date = group.date ?? ""
                ratingText = group.rating100.map(String.init) ?? ""
                synopsis = group.synopsis ?? ""
            }
        }
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let rating = Int(ratingText.trimmingCharacters(in: .whitespacesAndNewlines)).map { min(100, max(0, $0)) }

        isSaving = true
        viewModel.updateGroupDetails(
            groupId: group.id,
            name: trimmedName,
            date: optionalTrimmed(date),
            synopsis: optionalTrimmed(synopsis),
            rating100: rating
        ) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    var updated = group
                    updated.name = trimmedName
                    updated.date = optionalTrimmed(date)
                    updated.synopsis = optionalTrimmed(synopsis)
                    updated.rating100 = rating
                    onComplete(updated)
                    ToastManager.shared.show("Group updated", icon: "checkmark.circle", style: .success)
                    dismiss()
                } else {
                    ToastManager.shared.show("Failed to update group", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}
#endif
