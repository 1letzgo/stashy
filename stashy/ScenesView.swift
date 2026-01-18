//
//  ScenesView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

import SwiftUI


struct ScenesView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @StateObject private var viewModel = StashDBViewModel()
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getSortOption(for: .scenes) ?? "") ?? .dateDesc
    @State private var isChangingSort = false
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var scrollPosition: String? = nil
    @State private var shouldRestoreScroll = false
    @State private var hasInjectedSort = false  // Flag to preserve coordinator sort
    var hideTitle: Bool = false
    
    // Optional init for direct sort/filter passing (cleaner than coordinator timing)
    init(sort: StashDBViewModel.SceneSortOption? = nil, filter: StashDBViewModel.SavedFilter? = nil, hideTitle: Bool = false) {
        self.hideTitle = hideTitle
        let defaultSort = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getSortOption(for: .scenes) ?? "") ?? .dateDesc
        _selectedSortOption = State(initialValue: sort ?? defaultSort)
        _selectedFilter = State(initialValue: filter)
        _hasInjectedSort = State(initialValue: sort != nil)
    }


    // Dynamische Spalten basierend auf adaptivem Grid
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 300), spacing: 12)]
    }

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.SceneSortOption) {
        selectedSortOption = newOption
        scrollPosition = nil
        shouldRestoreScroll = false
        
        // Save to TabManager
        TabManager.shared.setSortOption(for: .scenes, option: newOption.rawValue)

        // Fetch new data immediately
        viewModel.fetchScenes(sortBy: newOption, searchQuery: searchText, filter: selectedFilter)
    }
    
    // Search function with debouncing
    private func performSearch() {
        viewModel.fetchScenes(sortBy: selectedSortOption, searchQuery: searchText, filter: selectedFilter)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Content
            Group {
                if configManager.activeConfig == nil {
                    ConnectionErrorView { performSearch() }
                } else if viewModel.isLoading && viewModel.scenes.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView("Loading scenes...")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if viewModel.scenes.isEmpty && viewModel.errorMessage != nil {
                    ConnectionErrorView { performSearch() }
                } else if viewModel.scenes.isEmpty {
                    emptyStateView
                } else {
                    scenesGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        .navigationTitle("Scenes")
        .navigationBarTitleDisplayMode(.inline)

        .onChange(of: searchText) { oldValue, newValue in
            // Debounce: Nur suchen wenn Nutzer aufhört zu tippen (0.5s Delay)
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if newValue == self.searchText {
                    self.performSearch()
                }
            }
        }
        .toolbar {
            // Search pill in title area when active
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
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 0) {


                    Menu {
                        // --- FILTER SECTION ---
                        Section {
                            // "None" option
                            Button(action: {
                                selectedFilter = nil
                                viewModel.fetchScenes(sortBy: selectedSortOption, searchQuery: searchText, filter: nil)
                            }) {
                                HStack {
                                    Text("No Filter")
                                    if selectedFilter == nil { Image(systemName: "checkmark") }
                                }
                            }

                            let activeFilters = viewModel.savedFilters.values
                                .filter { $0.mode == .scenes }
                                .sorted { $0.name < $1.name }
                            
                            ForEach(activeFilters) { filter in
                                Button(action: {
                                    selectedFilter = filter
                                    viewModel.fetchScenes(sortBy: selectedSortOption, searchQuery: searchText, filter: filter)
                                }) {
                                    HStack {
                                        Text(filter.name)
                                        if selectedFilter?.id == filter.id { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } header: {
                            Text("Saved Filters")
                        }

                        // --- SORT SECTION ---
                        Section {
                            ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                                Button(action: {
                                    changeSortOption(to: option)
                                }) {
                                    HStack {
                                        Text(option.displayName)
                                        if option == selectedSortOption { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } header: {
                            Text("Sort By")
                        }
                    } label: {
                        Image(systemName: selectedFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(appearanceManager.tintColor)
                    }
                }
            }
        }
        .onAppear {
            // Check for injected sort from coordinator FIRST (before filters load)
            if let injectedSortStr = coordinator.activeSortOption,
               let injectedSort = StashDBViewModel.SceneSortOption(rawValue: injectedSortStr) {
                selectedSortOption = injectedSort
                coordinator.activeSortOption = nil
                hasInjectedSort = true  // Mark that we have an injected sort
            }
            
            if let injectedFilter = coordinator.activeFilter {
                selectedFilter = injectedFilter
                coordinator.activeFilter = nil
            }
            
            if !coordinator.activeSearchText.isEmpty {
                searchText = coordinator.activeSearchText
                isSearchVisible = true
                coordinator.activeSearchText = ""
            }
            
            // Fetch filters - onChange will handle loading scenes with correct sort
            viewModel.fetchSavedFilters()
            
            // If no default filter is set, fetch immediately
            if TabManager.shared.getDefaultFilterId(for: .scenes) == nil {
                viewModel.fetchScenes(sortBy: selectedSortOption, searchQuery: searchText, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            performSearch()
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // CRITICAL: Check coordinator FIRST - filters may load before onAppear runs!
            if let injectedSortStr = coordinator.activeSortOption,
               let injectedSort = StashDBViewModel.SceneSortOption(rawValue: injectedSortStr) {
                selectedSortOption = injectedSort
                coordinator.activeSortOption = nil
                hasInjectedSort = true
            }
            
            // Check if we should skip default filter (e.g., from universal search)
            if coordinator.noDefaultFilter {
                coordinator.noDefaultFilter = false
                // Fetch with current state, no default filter
                viewModel.fetchScenes(sortBy: selectedSortOption, searchQuery: searchText, filter: nil)
                return
            }
            
            // Apply default filter if set and none selected yet
            // Uses selectedSortOption which may have just been set from coordinator above
            if selectedFilter == nil, let defaultId = TabManager.shared.getDefaultFilterId(for: .scenes) {
                if let filter = newValue[defaultId] {
                    selectedFilter = filter
                    viewModel.fetchScenes(sortBy: selectedSortOption, searchQuery: searchText, filter: filter)
                    // Reset flag after using injected sort with default filter
                    if hasInjectedSort {
                        hasInjectedSort = false
                    }
                }
            }
        }

        // Scene Update Listeners - update in place without full reload
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneResumeTimeUpdated"))) { notification in
            if let sceneId = notification.userInfo?["sceneId"] as? String,
               let resumeTime = notification.userInfo?["resumeTime"] as? Double {
                viewModel.updateSceneResumeTime(id: sceneId, newResumeTime: resumeTime)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneDeleted"))) { notification in
            if let sceneId = notification.userInfo?["sceneId"] as? String {
                viewModel.removeScene(id: sceneId)
            }
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading scenes...")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: "film",
            title: "No scenes found",
            buttonText: "Load Scenes",
            onRetry: { performSearch() }
        )
    }

    private var scenesGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.scenes) { scene in
                        NavigationLink(destination: SceneDetailView(scene: scene)) {
                            SceneCardView(scene: scene)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(scene.id)
                    }

                    // Loading indicator for pagination
                    if viewModel.isLoadingMoreScenes {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Loading more scenes...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else if viewModel.hasMoreScenes && !viewModel.scenes.isEmpty {
                        // Invisible element to trigger loading more scenes
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                // Save scroll position before loading - use element around 3/4 of current list
                                let currentCount = viewModel.scenes.count
                                if currentCount > 4 {
                                    let targetIndex = currentCount * 3 / 4
                                    if targetIndex < currentCount {
                                        scrollPosition = viewModel.scenes[targetIndex].id
                                        shouldRestoreScroll = true
                                    }
                                } else if let lastScene = viewModel.scenes.last {
                                    scrollPosition = lastScene.id
                                    shouldRestoreScroll = true
                                }
                                viewModel.loadMoreScenes()
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 80) // Add padding so bar doesn't cover content
            }
            .background(Color.appBackground)
            .onChange(of: viewModel.isLoadingMoreScenes) { oldValue, isLoading in
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

// Card-based view for grid layout
#Preview {
    ScenesView()
}
