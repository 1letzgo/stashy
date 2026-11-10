//
//  CatalogsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

#if !os(tvOS)
import Combine
import PhotosUI
import SwiftUI

struct CatalogsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    /// Ein ViewModel für alle Katalog-Listen-Tabs (Scenes, Images, …): Daten bleiben beim Unter-Tab-Wechsel warm, ein Verbindungstest.
    @StateObject private var catalogBrowserViewModel = StashDBViewModel()
    /// Filter / sort state of every catalog sub-tab list — lives here so it survives the sub-tab
    /// switch remounting the list (and, for Images, pushing FullScreenImageView).
    @StateObject private var rootFilters = CatalogRootFilterMemories()
    @AppStorage(MagazineMode.enabledKey) private var isMagazineEnabled = false
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    /// Settings / select actions of the active sub-tab, shown pinned right in the Home chrome.
    
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
        case magazine = "Magazin"
        
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
            case .magazine: return "magazine.fill"
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
            case .magazine: return .magazine
            default: return nil
            }
        }
    }
    
    private var sortedVisibleTabs: [CatalogsTab] {
        var tabs = tabManager.tabs
            .filter { ($0.id == .dashboard || $0.id == .performers || $0.id == .studios || $0.id == .tags || $0.id == .scenes || $0.id == .galleries || $0.id == .images || $0.id == .groups || $0.id == .markers || ($0.id == .magazine && isMagazineEnabled && stashyPlus.isUnlocked)) && $0.isVisible }
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
                case .magazine: return .magazine
                default: return nil
                }
            }
        // Search → Show All / stats deep links can target a hidden catalog tab.
        if let current = CatalogsTab(rawValue: coordinator.catalogueSubTab), !tabs.contains(current), current != .magazine {
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
        // Every list draws its own breadcrumb (Home › view › sort); only the dashboard uses this one.
        sortedVisibleTabs.count > 1 && (effectiveTab == .dashboard || effectiveTab == nil)
    }

    private var homeViewsMenu: HomeViewsMenu {
        HomeViewsMenu(tabs: sortedVisibleTabs, selection: selectedTabBinding)
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
            ScenesView.catalogTab(viewModel: catalogBrowserViewModel, filterMemory: rootFilters.scenes)
        case .images:
            ImagesView(
                catalogBrowserViewModel: catalogBrowserViewModel,
                sharedImageListFilters: rootFilters.images,
                // A remount keeps the list's search: the shared view model still fetches with it.
                initialSearch: coordinator.activeSearchText.isEmpty
                    ? catalogBrowserViewModel.currentImageSearchQuery
                    : coordinator.activeSearchText
            )
        case .galleries:
            GalleriesView(catalogBrowserViewModel: catalogBrowserViewModel, filterMemory: rootFilters.galleries)
        case .performers:
            PerformersView(catalogBrowserViewModel: catalogBrowserViewModel, filterMemory: rootFilters.performers)
        case .studios:
            StudiosView(hideTitle: false, catalogBrowserViewModel: catalogBrowserViewModel, filterMemory: rootFilters.studios)
        case .tags:
            TagsView(hideTitle: false, catalogBrowserViewModel: catalogBrowserViewModel, filterMemory: rootFilters.tags)
        case .groups:
            GroupsView(hideTitle: false, catalogBrowserViewModel: catalogBrowserViewModel, filterMemory: rootFilters.groups)
        case .markers:
            MarkersView(hideTitle: false, catalogBrowserViewModel: catalogBrowserViewModel, filterMemory: rootFilters.markers)
        case .magazine:
            MagazineListView(filterMemory: rootFilters.magazine)
        }
    }
    
    /// With the dashboard on, Home is a real stack: the dashboard is the root and every library
    /// view is pushed onto it, so the system's own swipe-back, corners, shadow and parallax take
    /// it back. Without the dashboard there is nothing to return to and the view is the root.
    private var pushesLibraryViews: Bool {
        sortedVisibleTabs.contains(.dashboard) && sortedVisibleTabs.count > 1
    }

    /// Pushed while the open view is not the dashboard. A pop (swipe-back, tab re-tap) writes the
    /// dashboard back, so the breadcrumb, the dropdown and deep links all go through one value.
    private var libraryPushedBinding: Binding<Bool> {
        Binding(
            get: { effectiveTab.map { $0 != .dashboard } ?? false },
            set: { pushed in
                if !pushed, effectiveTab != .dashboard {
                    coordinator.catalogueSubTab = CatalogsTab.dashboard.rawValue
                }
            }
        )
    }

    /// The dashboard's own row always draws the icon strip, also while a library page is pushed
    /// on top: it shows through during the swipe-back.
    private var dashboardRowMenu: HomeViewsMenu {
        HomeViewsMenu(
            tabs: sortedVisibleTabs,
            selection: Binding(get: { .dashboard }, set: { selectedTabBinding.wrappedValue = $0 })
        )
    }

    /// The pushed page keeps showing the last library view while it slides away; the open view
    /// is already the dashboard by then.
    @State private var lastLibraryTab: CatalogsTab?

    @ViewBuilder
    private var libraryPage: some View {
        if let tab = (effectiveTab == .dashboard ? nil : effectiveTab) ?? lastLibraryTab {
            catalogRoot(for: tab)
                .environment(\.homeBreadcrumbMenu, homeViewsMenu)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // A pushed page doesn't inherit the root's background (MainTabView sets it on
                // the dashboard); lists without their own (Tags) would show plain black.
                .applyAppBackground()
                // The dropdown swaps the view inside this page, instantly.
                .transaction(value: coordinator.catalogueSubTab) { $0.animation = nil }
                .animation(nil, value: coordinator.catalogueSubTab)
                // A switch in the dropdown or a deep link clears details pushed above this page.
                .background(CatalogueStackTrim(
                    trigger: "\(coordinator.catalogueSubTab)|\(coordinator.cataloguePopToken.uuidString)",
                    keepsLibraryPage: true
                ))
                .hideSystemNavigationBarForCustomChrome()
                .enableSwipeBackWhenNavBarHidden()
        }
    }

    var body: some View {
        if pushesLibraryViews {
            catalogRoot(for: .dashboard)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationDestination(isPresented: libraryPushedBinding) { libraryPage }
                .onChange(of: effectiveTab, initial: true) { _, tab in
                    if let tab, tab != .dashboard { lastLibraryTab = tab }
                }
                // A deep link to the dashboard clears what was pushed from it.
                .background(CatalogueStackTrim(
                    trigger: coordinator.cataloguePopToken.uuidString,
                    keepsLibraryPage: false,
                    isEnabled: effectiveTab == .dashboard
                ))
                .stashySectionChrome(showsSwitcher: true) {
                    HomeBreadcrumbRow(menu: dashboardRowMenu) { EmptyView() }
                }
        } else {
            switchedRoot
        }
    }

    /// Without a dashboard: the single library view is the root and the dropdown switches it.
    private var switchedRoot: some View {
        Group {
            if let tab = effectiveTab {
                catalogRoot(for: tab)
                    .environment(\.homeBreadcrumbMenu, tab == .dashboard || sortedVisibleTabs.count < 2 ? nil : homeViewsMenu)
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
        // Swipe-back can desync UIKit/SwiftUI stacks; menu switches must always clear details.
        .popNavigationToRootOnChange("\(coordinator.catalogueSubTab)|\(coordinator.cataloguePopToken.uuidString)")
        .stashySectionChrome(showsSwitcher: showTabSwitcher) {
            HomeBreadcrumbRow(menu: homeViewsMenu) { EmptyView() }
        }
    }
}

#if os(iOS)
/// Trims the catalogue stack when `trigger` changes. On the pushed library page it keeps the
/// dashboard and that page (details above it go, and so do details a deep link left beneath it);
/// on the dashboard it pops to the root. With `isEnabled` false a change is only noted.
struct CatalogueStackTrim: UIViewControllerRepresentable {
    let trigger: String
    let keepsLibraryPage: Bool
    var isEnabled = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> Host {
        let host = Host()
        host.view.isHidden = true
        host.view.isUserInteractionEnabled = false
        host.keepsLibraryPage = keepsLibraryPage
        return host
    }

    func updateUIViewController(_ host: Host, context: Context) {
        guard context.coordinator.lastTrigger != trigger else { return }
        let isFirst = context.coordinator.lastTrigger == nil
        context.coordinator.lastTrigger = trigger
        guard !isFirst, isEnabled else { return }
        // Defer so SwiftUI finishes its own push / swap first.
        DispatchQueue.main.async { host.trim(keepingAbove: false) }
    }

    final class Coordinator {
        var lastTrigger: String?
    }

    final class Host: UIViewController {
        var keepsLibraryPage = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // A page pushed by a deep link while a dashboard detail was open sits above that
            // detail; drop what lies between the dashboard and this page.
            if keepsLibraryPage { trim(keepingAbove: true) }
        }

        /// The view controller of this page: the ancestor whose parent is the navigation controller.
        private var page: UIViewController? {
            var current: UIViewController? = self
            while let vc = current {
                if vc.parent is UINavigationController { return vc }
                current = vc.parent
            }
            return nil
        }

        func trim(keepingAbove: Bool) {
            guard let nav = navigationController, nav.transitionCoordinator == nil,
                  let root = nav.viewControllers.first else { return }
            guard keepsLibraryPage else {
                if nav.viewControllers.count > 1 { nav.popToRootViewController(animated: false) }
                return
            }
            guard let page, let index = nav.viewControllers.firstIndex(of: page) else { return }
            let above = keepingAbove ? Array(nav.viewControllers[(index + 1)...]) : []
            let wanted = [root, page] + above
            if wanted != nav.viewControllers {
                nav.setViewControllers(wanted, animated: false)
            }
        }
    }
}
#else
/// macOS: the stack is remounted on `cataloguePopToken` (MainTabView); nothing to trim here.
struct CatalogueStackTrim: View {
    let trigger: String
    let keepsLibraryPage: Bool
    var isEnabled = true
    var body: some View { Color.clear.frame(width: 0, height: 0) }
}
#endif

// MARK: - Catalog root filter memory

/// Sheet / chrome state of a catalog list that is not kept in the shared view model.
struct CatalogListFilterSnapshot<Sort> {
    var sortOption: Sort
    var selectedFilter: StashDBViewModel.SavedFilter?
    var presetSelection: String
    var searchText: String
    var isSearchVisible: Bool
    var didApplyDefaultFilter: Bool
}

/// Filter / sort state of one catalog list, owned above the view so a remount (Home sub-tab
/// switch) restores what the list was fetched with. The criteria document is shared live; the
/// remaining `@State` is captured on disappear and restored in the list's `init`.
@MainActor
final class CatalogListFilterMemory<Snapshot> {
    let criteriaDocument: FilterCriteriaDocument
    var snapshot: Snapshot?

    init(mode: StashDBViewModel.FilterMode) {
        criteriaDocument = FilterCriteriaDocument(mode: mode, pinsDefaults: true)
    }

    func reset() {
        snapshot = nil
        criteriaDocument.clear()
    }
}

/// Markers also keep live scene chips (they feed the fetch).
struct MarkersListFilterSnapshot {
    var base: CatalogListFilterSnapshot<StashDBViewModel.SceneMarkerSortOption>
    var chips: SceneLiveChipRowState
}

/// One filter memory per `CatalogsView` sub-tab list. Cleared on `"ServerConfigChanged"`: saved
/// filters, presets and criteria ids belong to the previous server.
@MainActor
final class CatalogRootFilterMemories: ObservableObject {
    let scenes = ScenesListFilterMemory()
    let performers = CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.PerformerSortOption>>(mode: .performers)
    let studios = CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.StudioSortOption>>(mode: .studios)
    let tags = CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.TagSortOption>>(mode: .tags)
    let galleries = CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.GallerySortOption>>(mode: .galleries)
    let magazine = CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.GallerySortOption>>(mode: .galleries)
    let groups = CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.GroupSortOption>>(mode: .groups)
    let markers = CatalogListFilterMemory<MarkersListFilterSnapshot>(mode: .sceneMarkers)
    /// Images keep their whole session in the filter model (also survives FullScreenImageView).
    let images = DetailLinkedImagesFilterModel(scope: .catalogRoot)

    private var serverChangeObserver: AnyCancellable?

    init() {
        serverChangeObserver = NotificationCenter.default
            .publisher(for: NSNotification.Name("ServerConfigChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.resetAll() }
            }
    }

    private func resetAll() {
        scenes.reset()
        performers.reset()
        studios.reset()
        tags.reset()
        galleries.reset()
        magazine.reset()
        groups.reset()
        markers.reset()
        images.resetForServerChange()
    }
}
#endif

// MARK: - Groups Support Views

#if !os(tvOS)
struct GroupsView: View {
    @StateObject private var ownedViewModel = StashDBViewModel()
    let catalogBrowserViewModel: StashDBViewModel?
    var hideTitle: Bool = false
    let filterMemory: CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.GroupSortOption>>?

    init(hideTitle: Bool = false, catalogBrowserViewModel: StashDBViewModel? = nil, filterMemory: CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.GroupSortOption>>? = nil) {
        self.hideTitle = hideTitle
        self.catalogBrowserViewModel = catalogBrowserViewModel
        self.filterMemory = filterMemory
    }

    var body: some View {
        var content = GroupsViewContent(viewModel: catalogBrowserViewModel ?? ownedViewModel, hideTitle: hideTitle, filterMemory: filterMemory)
        return content
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
    @StateObject private var groupsCriteriaDocument = FilterCriteriaDocument(mode: .groups, pinsDefaults: true)
    @State private var showGroupsSaveAsAlert = false
    @State private var showGroupsRenameAlert = false
    @State private var showGroupsDeleteAlert = false
    @State private var groupsFilterNameInput = ""
    @State private var lastOpenedGroupId: String?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    var hideTitle: Bool = false
    /// Host-owned filter state (Home sub-tab, see `CatalogRootFilterMemories`); `nil` = the
    /// state lives and dies with this view.
    private let filterMemory: CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.GroupSortOption>>?

    init(viewModel: StashDBViewModel, hideTitle: Bool = false, filterMemory: CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.GroupSortOption>>? = nil) {
        self.viewModel = viewModel
        self.hideTitle = hideTitle
        self.filterMemory = filterMemory
        if let filterMemory {
            _groupsCriteriaDocument = StateObject(wrappedValue: filterMemory.criteriaDocument)
            // Remount (Home sub-tab switch): restore what the list was fetched with.
            if let snap = filterMemory.snapshot {
                _selectedSortOption = State(initialValue: snap.sortOption)
                _selectedFilter = State(initialValue: snap.selectedFilter)
                _groupsPresetRowSelection = State(initialValue: snap.presetSelection)
                _searchText = State(initialValue: snap.searchText)
                _isSearchVisible = State(initialValue: snap.isSearchVisible)
            }
        }
    }

    private var filterMemorySnapshot: CatalogListFilterSnapshot<StashDBViewModel.GroupSortOption> {
        CatalogListFilterSnapshot(
            sortOption: selectedSortOption,
            selectedFilter: selectedFilter,
            presetSelection: groupsPresetRowSelection,
            searchText: searchText,
            isSearchVisible: isSearchVisible,
            didApplyDefaultFilter: false
        )
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

    /// Setzt den in Settings gewählten Standardfilter, sofern noch keiner aktiv ist.
    /// Gibt zurück, ob etwas gesetzt wurde.
    @discardableResult
    private func applySettingsDefaultFilterIfNeeded() -> Bool {
        guard !hideTitle, selectedFilter == nil else { return false }
        guard !coordinator.noDefaultFilter else { return false }
        guard let defaultId = TabManager.shared.getDefaultFilterId(for: .groups),
              let filter = viewModel.savedFilters[defaultId] else { return false }

        selectedFilter = filter
        // Keep the sheet's preset row in sync so the default shows as selected.
        groupsPresetRowSelection = ListLivePresetTag.serverRow(filter.id)
        groupsCriteriaDocument.load(filter.criteriaObjectFilter())
        return true
    }

    // Search function
    private func performSearch(isInitialLoad: Bool = true) {
        viewModel.fetchGroups(
            sortBy: selectedSortOption,
            searchQuery: searchText,
            isInitialLoad: isInitialLoad,
            filter: fetchBaseFilter,
            liveFilter: effectiveLiveFilter
        )
    }

    /// Nil while the document holds the copy of the filter's criteria; the filter itself while the document is still empty.
    private var fetchBaseFilter: StashDBViewModel.SavedFilter? {
        groupsCriteriaDocument.isEmpty ? selectedFilter : nil
    }

    /// The sheet's filter picker changed the selection (only while the sheet is open, so code that sets it does not refetch twice).
    private func handleGroupsPresetSelectionChange(_ newId: String) {
        guard showGroupsFilterSheet else { return }
        if newId.isEmpty {
            selectedFilter = nil
            groupsCriteriaDocument.clear()
            performSearch()
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            selectedFilter = f
            groupsCriteriaDocument.load(f.criteriaObjectFilter())
            performSearch()
        }
    }

    private var catalogChromeConfig: CatalogChromeConfig {
        CatalogChromeConfig(
            title: "Groups",
            ownsNavigationBar: !hideTitle,
            visibility: CatalogFloatingChromeState(
                hasActiveServerConfig: configManager.activeConfig != nil,
                primaryListIsEmpty: viewModel.groups.isEmpty,
                errorMessage: viewModel.errorMessage
            ),
            isPresented: true,
            search: CatalogSearchChrome(
                text: $searchText,
                isVisible: $isSearchVisible,
                prompt: "Search groups...",
                onClear: { performSearch() }
            )
        )
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.isLoadingGroups && viewModel.groups.isEmpty {
                // Keep the bar while a sort/filter change refetches, so it does not jump away.
                VStack(spacing: 0) {
                    quickBar
                    StandardLoadingView(message: "Loading groups...")
                }
            } else if viewModel.groups.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.groups.isEmpty {
                VStack(spacing: 0) {
                    if !groupsCriteriaDocument.isEmpty || activePresetName != nil { quickBar }
                    emptyStateView
                }
            } else {
                // Pinned above the list so it always shows, also after coming back from a detail page.
                groupsGrid
                    .catalogPinnedQuickBar { quickBar }
            }
        }
        .applyAppBackground()
        .stashyCatalogChrome(catalogChromeConfig)
        .homeBreadcrumbChrome(homeMenu) { quickBar(part: .sortMenu) }
        .onChange(of: groupsPresetRowSelection) { _, newId in
            handleGroupsPresetSelectionChange(newId)
        }
        .sheet(isPresented: $showGroupsFilterSheet) {
            GroupsCatalogFilterSortSheet(
                serverFilters: viewModel.savedFilters.values.filter { $0.mode == .groups }.sorted { $0.name < $1.name },
                selectedPresetRowId: $groupsPresetRowSelection,
                criteriaDocument: groupsCriteriaDocument,
                sortOption: selectedSortOption,
                onSortChange: { changeSortOption(to: $0) },
                onApply: { performSearch() },
                onReset: { resetAllGroupFilters() },
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

            // Waren die Filter schon geladen, feuert `onChange(of: savedFilters)` nie -
            // dann bliebe der Standardfilter ungenutzt. Hier direkt anwenden.
            if applySettingsDefaultFilterIfNeeded() {
                performSearch()
            } else if TabManager.shared.getDefaultFilterId(for: .groups) == nil {
                // Ohne Standardfilter muss nicht darauf gewartet werden.
                if viewModel.groups.isEmpty {
                    performSearch()
                }
            }
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // Apply default filter if set and none selected yet
            if selectedFilter == nil {
                if applySettingsDefaultFilterIfNeeded() {
                    // Immer nachladen: `CatalogsView` hält ein ViewModel über alle Sub-Tabs
                    // warm, die Liste ist beim Öffnen also selten leer. Unter der alten
                    // Bedingung stand der Filter nur in der Variable und wirkte nie.
                    performSearch()
                } else if !viewModel.isLoadingSavedFilters && viewModel.groups.isEmpty {
                    performSearch()
                }
            }
        }
        .onDisappear {
            filterMemory?.snapshot = filterMemorySnapshot
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            // Saved filter / criteria ids belong to the previous server.
            selectedFilter = nil
            groupsPresetRowSelection = ""
            groupsCriteriaDocument.clear()
            performSearch()
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

    /// Sheet "Reset" and the saved-filter chip's ✕: drops the saved filter and every criterion.
    private func resetAllGroupFilters() {
        groupsPresetRowSelection = ""
        selectedFilter = nil
        groupsCriteriaDocument.clear()
        performSearch()
    }

    private var activePresetName: String? {
        if let sid = ListLivePresetTag.parseServerId(groupsPresetRowSelection) {
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
            mode: .groups,
            sort: selectedSortOption,
            onSort: { changeSortOption(to: $0) },
            document: groupsCriteriaDocument,
            presetName: activePresetName,
            onClearPreset: { resetAllGroupFilters() },
            onFiltersChanged: { performSearch() },
            onOpenFilters: {
                if let f = selectedFilter {
                    groupsPresetRowSelection = ListLivePresetTag.serverRow(f.id)
                    if groupsCriteriaDocument.isEmpty {
                        groupsCriteriaDocument.load(f.criteriaObjectFilter())
                    }
                }
                showGroupsFilterSheet = true
            },
            collapsesOnScroll: !hideTitle,
            part: part
        )
    }

    private var groupsGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
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
                .padding([.horizontal, .bottom], 16)
                }
            }
            .collapsesCatalogChrome(enabled: !hideTitle)
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
                        .stashyGlass(shape: Capsule())
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
                        .stashyGlass(shape: Capsule())
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
    @Environment(\.stashyDismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var groupLiveFilterSheetPresented = false
    @State private var showingSceneDownloadOptions = false
    @State private var groupSceneFilterActive = false
    @State private var isHeaderExpanded = false
    /// A cover opened full screen.
    @State private var coverFullscreen: HeroImageFullscreenItem?
    @State private var showingEditGroupSheet = false
    @StateObject private var linkedPerformers: DetailLinkedPerformersFilterModel
    @StateObject private var linkedTags: DetailLinkedTagsFilterModel
    @StateObject private var linkedStudios: DetailLinkedStudiosFilterModel
    @StateObject private var linkedGalleries: DetailLinkedGalleriesFilterModel
    /// Scenes tab filter / sort, kept here so it survives the tab remounting `ScenesView`.
    @StateObject private var scenesFilterMemory = ScenesListFilterMemory()
    @StateObject private var linkedImages: DetailLinkedImagesFilterModel

    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        /// Direct sub-groups, so groups nest like folders.
        case groups = "Groups"
        case galleries = "Galleries"
        case performers = "Performers"
        case studios = "Studios"
        case tags = "Tags"
        case images = "Images"

        var icon: String {
            switch self {
            case .scenes: return "film"
            case .groups: return "rectangle.stack"
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
        let sub = selectedGroup.sub_group_count ?? 0
        // A folder-like group (only sub-groups) opens on them, not on "No scenes found".
        _selectedDetailTab = State(initialValue: sc > 0 ? .scenes : (gal > 0 ? .galleries : (sub > 0 ? .groups : .scenes)))
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

    /// Sub-groups load into this page's own `viewModel.groups` (the overview has its own model).
    private var effectiveSubGroups: Int {
        max(viewModel.totalGroups, selectedGroup.sub_group_count ?? 0)
    }

    @State private var subGroupGridWidth: CGFloat = 0
    @State private var didLoadSubGroups = false

    private func loadSubGroupsIfNeeded() {
        guard !didLoadSubGroups, (selectedGroup.sub_group_count ?? 0) > 0 else { return }
        didLoadSubGroups = true
        viewModel.fetchGroups(sortBy: .nameAsc, liveFilter: [
            "containing_groups": ["value": [selectedGroup.id], "modifier": "INCLUDES", "depth": 0]
        ])
    }

    private var subGroupGrid: some View {
        LazyVGrid(columns: DesignTokens.Grid.adaptiveColumns(
            width: subGroupGridWidth,
            ideal: DesignTokens.Grid.idealPosterCardWidth,
            minimum: 2,
            maximum: 8
        ), spacing: 12) {
            ForEach(viewModel.groups) { group in
                NavigationLink(destination: GroupDetailView(selectedGroup: group)) {
                    GroupCardView(group: group)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingMoreGroups || (viewModel.isLoadingGroups && viewModel.groups.isEmpty) {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if viewModel.hasMoreGroups && !viewModel.groups.isEmpty {
                Color.clear.frame(height: 1).onAppear { viewModel.loadMoreGroups() }
            }
        }
        .measuresGridWidth($subGroupGridWidth)
        .padding([.horizontal, .bottom], 16)
    }

    /// "In: <parent>" links under the header, one per group this one sits in.
    @ViewBuilder
    private var parentGroupLinks: some View {
        if let parents = selectedGroup.containing_groups, !parents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(parents, id: \.group.id) { relation in
                    NavigationLink(destination: GroupDetailView(selectedGroup: StashGroup(
                        id: relation.group.id, name: relation.group.name, synopsis: nil, date: nil,
                        scene_count: nil, gallery_count: nil, rating100: nil, updatedAt: nil,
                        front_image_path: nil, back_image_path: nil, studio: nil))) {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.stack")
                            Text("In: \(relation.group.name)").lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline)
                        .foregroundColor(appearanceManager.tintColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Same inset as the info grid above it.
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var availableTabs: [DetailTab] {
        var tabs: [DetailTab] = []
        if effectiveScenes > 0 { tabs.append(.scenes) }
        if effectiveSubGroups > 0 { tabs.append(.groups) }
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
            case .groups: return viewModel.groups.isEmpty
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
            externalLiveFilterActiveBinding: $groupSceneFilterActive,
            showsFloatingFilterButton: false,
            scrollHeader: AnyView(headerView),
            filterMemory: scenesFilterMemory
        )
        .environment(\.detailBreadcrumb, detailCrumb)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Back · section dropdown, like the overviews' breadcrumb (PerformerDetail template).
    private var detailCrumb: DetailBreadcrumb {
        DetailBreadcrumb(
            sections: availableTabs.map { .init(id: $0.rawValue, title: $0.rawValue, systemImage: $0.icon) },
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
    private var groupDetailNavBar: some View {
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
            case .performers:
                CatalogQuickSortMenu(mode: .performers, sort: linkedPerformers.selectedSortOption) {
                    linkedPerformers.changeSortOption(to: $0, viewModel: viewModel)
                }
            case .tags:
                CatalogQuickSortMenu(mode: .tags, sort: linkedTags.selectedSortOption) {
                    linkedTags.changeSortOption(to: $0, viewModel: viewModel)
                }
            case .scenes, .groups:
                EmptyView()
            }
            // Sub-groups are a plain list: nothing to filter.
            if selectedDetailTab != .groups {
                DetailTopBarSlotButton(slot: sectionFilterSlot)
            }
        }
    }

    /// The shown section's filter and sort sheet.
    private var sectionFilterSlot: CatalogChromeSlot {
        func slot(active: Bool, open: @escaping () -> Void) -> CatalogChromeSlot {
            CatalogChromeSlot(systemImage: "slider.horizontal.3", isActive: active, accessibilityLabel: "Filter and sort") {
                HapticManager.light()
                open()
            }
        }
        switch selectedDetailTab {
        case .scenes: return slot(active: groupSceneFilterActive) { groupLiveFilterSheetPresented = true }
        case .groups: return slot(active: false) {}
        case .galleries: return slot(active: linkedGalleries.catalogFilterSortFABActive) { linkedGalleries.showFilterSortSheet = true }
        case .performers: return slot(active: linkedPerformers.catalogFilterSortFABActive) { linkedPerformers.showFilterSortSheet = true }
        case .studios: return slot(active: linkedStudios.catalogFilterSortFABActive) { linkedStudios.showFilterSortSheet = true }
        case .tags: return slot(active: linkedTags.catalogFilterSortFABActive) { linkedTags.showFilterSortSheet = true }
        case .images: return slot(active: linkedImages.catalogFilterSortFABActive) { linkedImages.showFilterSortSheet = true }
        }
    }

    @ViewBuilder
    private var nonScenesGroupScroll: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerView
                    // Same gap under the chrome as the Scenes tab, whose list carries the header.
                    .padding(.top, 16)

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
                } else if selectedDetailTab == .groups {
                    subGroupGrid
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
            .alert("Save as new", isPresented: $linkedPerformers.showSaveAsCatalogPresetAlert) {
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
            .alert("Save as new", isPresented: $linkedTags.showSaveAsCatalogPresetAlert) {
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
            .alert("Save as new", isPresented: $linkedStudios.showSaveAsCatalogPresetAlert) {
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
            .alert("Save as new", isPresented: $linkedGalleries.showSaveAsCatalogPresetAlert) {
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
            .alert("Save as new", isPresented: $linkedImages.showSaveAsCatalogPresetAlert) {
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

    // MARK: - Shared detail chrome

    /// Per-tab slots for the embedded list, mirroring the previous floating action bar content.
    private var groupDetailListSlots: CatalogSlotSet {
        var slots = CatalogSlotSet(visibility: groupDetailCatalogFloatingChromeForFooter)
        // Edit sits in the floating bar like on performer / studio / tag pages.
        if appearanceManager.isEditModeEnabled {
            slots.entityActions = [CatalogChromeSlot(systemImage: "pencil", accessibilityLabel: "Edit group") {
                HapticManager.light()
                showingEditGroupSheet = true
            }]
        }
        // Filter & sort live in the top bar now (breadcrumb row); the bar keeps the actions.
        if selectedDetailTab == .scenes {
            slots.contextual = SceneBulkDownloadChrome.slot {
                showingSceneDownloadOptions = true
            }
        }
        return slots
    }

    private var groupDetailChromeConfig: StashyDetailChromeConfig {
        StashyDetailChromeConfig(
            listSlots: groupDetailListSlots,
            insetSpacing: 0
        )
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
        .sceneBulkDownloadDialog(
            isPresented: $showingSceneDownloadOptions,
            scope: .group(id: selectedGroup.id),
            scopeName: selectedGroup.name,
            sceneCount: selectedGroup.scene_count,
        )
        .stashyDetailChrome(groupDetailChromeConfig) {
            groupDetailNavBar
        }
        .sheet(isPresented: $showingEditGroupSheet) {
            EditGroupSheet(group: selectedGroup, viewModel: viewModel, onDeleted: { dismiss() }) { updated in
                selectedGroup = updated
            }
        }
        .onAppear {
            if viewModel.groupGalleries.isEmpty {
                linkedGalleries.refetchGalleries(viewModel: viewModel, initial: true)
            }

            loadSubGroupsIfNeeded()
            viewModel.fetchGroup(groupId: selectedGroup.id) { updated in
                if let updated {
                    selectedGroup = updated
                    // Opened from a link that only knew id and name: the counts arrive here.
                    loadSubGroupsIfNeeded()
                    if selectedDetailTab == .scenes, (updated.scene_count ?? 0) == 0,
                       (updated.gallery_count ?? 0) == 0, (updated.sub_group_count ?? 0) > 0 {
                        selectedDetailTab = .groups
                    }
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
            cardColumnScope: CatalogCardColumnScope.images
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

    /// Header card (`DetailHeroCard`): the front cover blurred as the compact band backdrop,
    /// the cover (a poster) top-cropped in the circle straddling the band edge, name, stats
    /// and synopsis in the solid section. Editing stays on the nav-bar pencil.
    private var headerView: some View {
        let coverURL = selectedGroup.thumbnailURL
        return DetailHeroCard(
            title: selectedGroup.name,
            items: getGroupDetails().map { DetailHeroItem(label: $0.label, value: $0.value) },
            description: selectedGroup.synopsis,
            showsHero: coverURL != nil,
            heroAccessibilityLabel: "Group cover",
            onHeroTap: nil,
            isExpanded: $isHeaderExpanded,
            placeholderSystemImage: "rectangle.stack",
            // DVD case instead of the circle: front cover, and the back cover beside it if any.
            leadingAvatars: AnyView(
                HStack(alignment: .top, spacing: 6) {
                    coverButton(coverURL, label: "Front cover")
                    if let back = selectedGroup.backImageURL {
                        coverButton(back, label: "Back cover")
                    }
                }
            ),
            backdrop: { groupHeroImage(coverURL, alignment: .center) },
            avatar: { groupHeroImage(coverURL, alignment: .top) },
            accessory: { _ in EmptyView() },
            footer: { parentGroupLinks }
        )
        .padding(.horizontal, 16)
        .fullScreenCover(item: $coverFullscreen) { RemoteHeroImageFullscreen(url: $0.url) }
    }

    /// A DVD cover that opens full screen.
    @ViewBuilder
    private func coverButton(_ url: URL?, label: String) -> some View {
        if let url {
            Button {
                coverFullscreen = HeroImageFullscreenItem(url: url)
            } label: {
                GroupDVDCover(url: url, accessibilityLabel: label)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the cover full screen")
        } else {
            GroupDVDCover(url: nil, accessibilityLabel: label)
        }
    }

    /// Front cover filling its frame; `alignment` picks the crop (top for the circle).
    @ViewBuilder
    private func groupHeroImage(_ url: URL?, alignment: Alignment) -> some View {
        if let url {
            CustomAsyncImage(url: url) { loader in
                if let image = loader.image {
                    image.resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: alignment)
                        .clipped()
                } else if loader.isLoading {
                    Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                        .overlay(InlineSpinner(scale: .compact))
                } else {
                    Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                        .overlay(
                            Image(systemName: "rectangle.stack")
                                .font(.system(size: 24))
                                .foregroundColor(.appAccent.opacity(0.5))
                        )
                }
            }
        }
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

// MARK: - DVD cover

/// A group cover drawn as a DVD case: portrait 5:7, hinge strip on the left edge, a soft sheen,
/// hairline rim and a drop shadow. Used in the group detail header in place of the circle.
struct GroupDVDCover: View {
    let url: URL?
    var accessibilityLabel: String = "Cover"

    static let width: CGFloat = 72
    static var height: CGFloat { width * 7 / 5 }
    private static let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)

    var body: some View {
        ZStack(alignment: .leading) {
            Color.gray.opacity(DesignTokens.Opacity.placeholder)
            if let url {
                CustomAsyncImage(url: url) { loader in
                    if let image = loader.image {
                        image.resizable().scaledToFill()
                    } else if loader.isLoading {
                        InlineSpinner(scale: .compact)
                    } else {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 22))
                            .foregroundColor(.appAccent.opacity(0.5))
                    }
                }
                .frame(width: Self.width, height: Self.height)
                .clipped()
            }
            // Case hinge: a dark strip with a light ridge, as on a DVD keep case.
            HStack(spacing: 0) {
                Color.black.opacity(0.45).frame(width: 5)
                Color.white.opacity(0.25).frame(width: 1)
                Spacer(minLength: 0)
            }
            // Plastic sleeve sheen.
            LinearGradient(
                colors: [.white.opacity(0.18), .clear, .clear, .white.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(Self.shape)
        .overlay(Self.shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 3)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }
}

// MARK: - Edit Group Sheet

struct EditGroupSheet: View {
    let group: StashGroup
    @ObservedObject var viewModel: StashDBViewModel
    var onDeleted: (() -> Void)? = nil
    var onComplete: (StashGroup) -> Void

    @Environment(\.stashyDismiss) private var dismiss
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var name: String = ""
    @State private var aliases: String = ""
    @State private var date: String = ""
    @State private var durationText: String = ""
    @State private var ratingText: String = ""
    @State private var director: String = ""
    @State private var synopsis: String = ""
    @State private var urls: [String] = []
    @State private var studio: FilterEntityOption?
    @State private var tags: [FilterEntityOption] = []
    /// The extra fields are written back only once they were loaded, so a failed load never
    /// wipes aliases, studio, tags … on save.
    @State private var extraFieldsLoaded = false
    @State private var frontItem: PhotosPickerItem?
    @State private var backItem: PhotosPickerItem?
    @State private var newFront: GroupCoverUpload?
    @State private var newBack: GroupCoverUpload?
    @State private var removeBack = false
    @State private var picker: GroupEntityPickerKind?
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showingDeleteConfirmation = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && StashDateInput.isAcceptable(date)
            && GroupDurationText.seconds(from: durationText) != .invalid
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Covers") {
                    HStack(alignment: .top, spacing: 16) {
                        coverColumn(
                            title: "Front",
                            preview: newFront?.preview,
                            url: group.thumbnailURL,
                            item: $frontItem,
                            onRemove: nil
                        )
                        coverColumn(
                            title: "Back",
                            preview: newBack?.preview,
                            url: removeBack ? nil : group.backImageURL,
                            item: $backItem,
                            onRemove: (newBack != nil || (!removeBack && group.backImageURL != nil)) ? {
                                newBack = nil
                                backItem = nil
                                removeBack = true
                            } : nil
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Aliases", text: $aliases)
                    StashDateField(placeholder: "Date (YYYY-MM-DD)", text: $date)
                    TextField("Duration (h:mm:ss)", text: $durationText)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Rating (0–100)", text: $ratingText)
                        .keyboardType(.numberPad)
                        .numericKeyboardDoneBar()
                    TextField("Director", text: $director)
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section("Studio & Tags") {
                    pickerRow(title: "Studio", value: studio?.name ?? "None") { picker = .studio }
                    pickerRow(
                        title: "Tags",
                        value: tags.isEmpty ? "None" : tags.map(\.name).joined(separator: ", ")
                    ) { picker = .tags }
                }
                .listRowBackground(Color.secondaryAppBackground)
                .disabled(!extraFieldsLoaded)

                Section("URLs") {
                    ForEach(urls.indices, id: \.self) { index in
                        HStack {
                            TextField("https://…", text: $urls[index])
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button {
                                urls.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove URL")
                        }
                    }
                    Button {
                        urls.append("")
                    } label: {
                        Label("Add URL", systemImage: "plus.circle.fill")
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
                .disabled(!extraFieldsLoaded)

                Section("Synopsis") {
                    TextEditor(text: $synopsis)
                        .frame(minHeight: 120)
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            if isDeleting {
                                InlineSpinner(tint: .red)
                            } else {
                                Label("Delete Group", systemImage: "trash")
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
            .stashyModalSheetChrome("Edit Group", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(
                    title: "Save",
                    enabled: canSave,
                    isBusy: isSaving
                ) { save() }
            }
            .onAppear {
                name = group.name
                date = group.date ?? ""
                ratingText = group.rating100.map(String.init) ?? ""
                synopsis = group.synopsis ?? ""
                loadExtraFields()
            }
            .onChange(of: frontItem) { _, item in
                loadCover(item) { newFront = $0 }
            }
            .onChange(of: backItem) { _, item in
                loadCover(item) { upload in
                    newBack = upload
                    if upload != nil { removeBack = false }
                }
            }
            .sheet(item: $picker) { kind in
                GroupEntityPickerSheet(
                    kind: kind,
                    studio: $studio,
                    tags: $tags
                )
            }
            .alert("Delete Group", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { performDelete() }
            } message: {
                Text("Delete '\(group.name)'? This cannot be undone.")
            }
        }
    }

    // MARK: Rows

    private func pickerRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One cover: the current (or newly picked) image as a DVD case, Change / Remove below.
    private func coverColumn(
        title: String,
        preview: UIImage?,
        url: URL?,
        item: Binding<PhotosPickerItem?>,
        onRemove: (() -> Void)?
    ) -> some View {
        VStack(spacing: 8) {
            Group {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: GroupDVDCover.width, height: GroupDVDCover.height)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else if url != nil {
                    GroupDVDCover(url: url, accessibilityLabel: "\(title) cover")
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .frame(width: GroupDVDCover.width, height: GroupDVDCover.height)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
            PhotosPicker(selection: item, matching: .images) {
                Text(url == nil && preview == nil ? "Add" : "Change").font(.caption.weight(.semibold))
            }
            if let onRemove {
                Button("Remove", role: .destructive, action: onRemove)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: Loading

    private func loadExtraFields() {
        viewModel.fetchGroupEditFields(groupId: group.id) { fields in
            DispatchQueue.main.async {
                guard let fields else {
                    ToastManager.shared.show("Couldn't load all group fields", icon: "exclamationmark.triangle", style: .error)
                    return
                }
                aliases = fields.aliases ?? ""
                durationText = GroupDurationText.format(fields.duration)
                director = fields.director ?? ""
                urls = fields.urls ?? []
                studio = fields.studio.map { FilterEntityOption(id: $0.id, name: $0.name) }
                tags = (fields.tags ?? []).map { FilterEntityOption(id: $0.id, name: $0.name) }
                extraFieldsLoaded = true
            }
        }
    }

    /// Photos hands out HEIC; Stash wants JPEG or PNG, so the pick is re-encoded as JPEG.
    private func loadCover(_ item: PhotosPickerItem?, apply: @escaping (GroupCoverUpload?) -> Void) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.9) else {
                await MainActor.run {
                    ToastManager.shared.show("Couldn't read that image", icon: "exclamationmark.triangle", style: .error)
                }
                return
            }
            let upload = GroupCoverUpload(preview: image, dataURL: "data:image/jpeg;base64," + jpeg.base64EncodedString())
            await MainActor.run { apply(upload) }
        }
    }

    // MARK: Delete / save

    private func performDelete() {
        isDeleting = true
        viewModel.deleteGroup(groupId: group.id) { result in
            DispatchQueue.main.async {
                isDeleting = false
                switch result {
                case .success:
                    ToastManager.shared.show("Group deleted", icon: "trash", style: .success)
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

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let rating = Int(ratingText.trimmingCharacters(in: .whitespacesAndNewlines)).map { min(100, max(0, $0)) }

        var extra: [String: Any] = [:]
        if extraFieldsLoaded {
            extra["aliases"] = optionalTrimmed(aliases) ?? NSNull()
            if case .seconds(let value) = GroupDurationText.seconds(from: durationText) {
                extra["duration"] = value ?? NSNull()
            }
            extra["director"] = optionalTrimmed(director) ?? NSNull()
            extra["studio_id"] = studio?.id ?? NSNull()
            extra["tag_ids"] = tags.map(\.id)
            extra["urls"] = urls.compactMap { optionalTrimmed($0) }
        }
        if let newFront { extra["front_image"] = newFront.dataURL }
        if let newBack {
            extra["back_image"] = newBack.dataURL
        } else if removeBack {
            extra["back_image"] = NSNull()
        }

        isSaving = true
        viewModel.updateGroupDetails(
            groupId: group.id,
            name: trimmedName,
            date: optionalTrimmed(date),
            synopsis: optionalTrimmed(synopsis),
            rating100: rating,
            extra: extra
        ) { success in
            guard success else {
                DispatchQueue.main.async {
                    isSaving = false
                    ToastManager.shared.show("Failed to update group", icon: "exclamationmark.triangle", style: .error)
                }
                return
            }
            // Reload: the new `updated_at` refreshes the cover URLs, and a new back cover
            // only appears once `back_image_path` comes back set.
            viewModel.fetchGroup(groupId: group.id) { fresh in
                DispatchQueue.main.async {
                    isSaving = false
                    var updated = fresh ?? group
                    if fresh == nil {
                        updated.name = trimmedName
                        updated.date = optionalTrimmed(date)
                        updated.synopsis = optionalTrimmed(synopsis)
                        updated.rating100 = rating
                    }
                    onComplete(updated)
                    ToastManager.shared.show("Group updated", icon: "checkmark.circle", style: .success)
                    dismiss()
                }
            }
        }
    }
}

/// A picked cover, re-encoded for Stash's `front_image` / `back_image`.
private struct GroupCoverUpload {
    let preview: UIImage
    let dataURL: String
}

/// Group duration as typed: "1:32:05", "92:05" or plain minutes ("92").
enum GroupDurationText {
    enum Parsed: Equatable {
        case seconds(Int?)
        case invalid
    }

    static func format(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func seconds(from text: String) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .seconds(nil) }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.contains(where: { $0 == nil || $0! < 0 }) else { return .invalid }
        let values = parts.compactMap { $0 }
        // Overflow-safe: a very long number is invalid, not a crash.
        func total(_ weights: [Int]) -> Int? {
            var sum = 0
            for (value, weight) in zip(values, weights) {
                let (product, o1) = value.multipliedReportingOverflow(by: weight)
                let (next, o2) = sum.addingReportingOverflow(product)
                if o1 || o2 { return nil }
                sum = next
            }
            return sum
        }
        switch values.count {
        case 1, 2, 3:
            let weights = values.count == 1 ? [60] : values.count == 2 ? [60, 1] : [3600, 60, 1]
            guard let t = total(weights) else { return .invalid }
            return .seconds(t)
        default: return .invalid
        }
    }
}

enum GroupEntityPickerKind: String, Identifiable {
    case studio, tags
    var id: String { rawValue }
}

/// Studio (single) or tags (multi) for the group edit sheet, from the shared option cache;
/// typing also searches the server, so entries beyond the cached list are reachable.
private struct GroupEntityPickerSheet: View {
    let kind: GroupEntityPickerKind
    @Binding var studio: FilterEntityOption?
    @Binding var tags: [FilterEntityOption]

    @Environment(\.stashyDismiss) private var dismiss
    @ObservedObject private var store = FilterPickerOptionsStore.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @State private var query = ""

    private var storeKind: FilterPickerOptionsStore.Kind { kind == .studio ? .studios : .allTags }

    private var options: [FilterEntityOption] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = Set(tags.map(\.id))
        return store.availableOptions(storeKind).filter { option in
            (kind == .studio || !chosen.contains(option.id))
                && (term.isEmpty || option.name.localizedCaseInsensitiveContains(term))
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Search…", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .listRowBackground(Color.secondaryAppBackground)

                if kind == .studio {
                    Section {
                        row(name: "None", selected: studio == nil) { studio = nil; dismiss() }
                    }
                    .listRowBackground(Color.secondaryAppBackground)
                } else if !tags.isEmpty {
                    // Chosen tags lead, whatever the search says.
                    Section("Selected") {
                        ForEach(tags) { tag in
                            row(name: tag.name, selected: true) { tags.removeAll { $0.id == tag.id } }
                        }
                    }
                    .listRowBackground(Color.secondaryAppBackground)
                }

                Section(kind == .studio ? "Studios" : "Tags") {
                    if store.isLoading(storeKind) && options.isEmpty {
                        HStack { Spacer(); InlineSpinner(); Spacer() }
                    } else {
                        ForEach(options.prefix(200)) { option in
                            row(name: option.name, selected: kind == .studio && studio?.id == option.id) {
                                if kind == .studio {
                                    studio = option
                                    dismiss()
                                } else {
                                    tags.append(option)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome(kind == .studio ? "Studio" : "Tags", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(title: "Done") { dismiss() }
            }
            .onAppear { store.load(storeKind) }
            .onChange(of: query) { _, newValue in
                let term = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if term.count >= 2 { store.search(storeKind, query: term) }
            }
        }
    }

    private func row(name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(appearanceManager.tintColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
