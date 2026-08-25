//
//  TVScenesView.swift
//  stashyTV
//
//  Scenes grid for tvOS — 4-column layout
//

import SwiftUI

struct TVScenesView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @State private var sortBy: StashDBViewModel.SceneSortOption
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var focusResetToken = 0
    @FocusState private var focusedSceneID: String?

    init(sortBy: StashDBViewModel.SceneSortOption? = nil) {
        let defaultSort = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getSortOption(for: .scenes) ?? "") ?? .dateDesc
        _sortBy = State(initialValue: sortBy ?? defaultSort)
    }

    private static let sortOrder: [StashDBViewModel.SceneSortOption] = [.random, .dateDesc, .dateAsc, .createdAtDesc, .createdAtAsc, .lastPlayedAtDesc, .lastPlayedAtAsc, .titleAsc, .titleDesc, .durationDesc, .durationAsc, .playCountDesc, .playCountAsc, .oCounterDesc, .oCounterAsc, .ratingDesc, .ratingAsc]

    private var sortOptions: [TVPickerOption<StashDBViewModel.SceneSortOption>] {
        Self.sortOrder.map { TVPickerOption($0, label(for: $0)) }
    }

    var body: some View {
        TVCatalogGrid(
            items: viewModel.scenes,
            hasValidConfig: hasValidConfig,
            errorMessage: viewModel.errorMessage,
            isLoading: viewModel.isLoadingScenes,
            isLoadingMore: viewModel.isLoadingMoreScenes,
            hasMore: viewModel.hasMoreScenes,
            columnWidth: 410,
            emptySystemImage: "film",
            emptyTitle: "No scenes found",
            loadingText: "Loading scenes…",
            errorTitle: "Error loading scenes",
            focusResetToken: focusResetToken,
            loadMore: { viewModel.loadMoreScenes() },
            reload: { reload() },
            focusedID: $focusedSceneID,
            header: {
                STVHeaderView(
                    sortMenu: {
                        TVOptionPickerButton(
                            title: "Sort By",
                            icon: "arrow.up.arrow.down",
                            options: sortOptions,
                            selection: $sortBy
                        )
                    },
                    filterMenu: {
                        TVFilterPickerButton(filters: savedFilters, selection: $selectedFilter)
                    },
                    onRefresh: { reload() }
                )
            },
            card: { scene in
                VStack(alignment: .leading, spacing: 10) {
                    TVNavButton(value: TVSceneLink(sceneId: scene.id)) {
                        TVSceneCardView(scene: scene)
                    }
                    TVSceneCardTitleView(scene: scene)
                }
            }
        )
        .onChange(of: sortBy) { _, newValue in
            focusResetToken += 1
            viewModel.fetchScenes(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
            focusResetToken += 1
            viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true, filter: newValue)
        }
        .onAppear {
            guard hasValidConfig else { return }
            viewModel.fetchSavedFilters { _ in
                applyDefaultFilterIfNeeded()
            }
            if viewModel.scenes.isEmpty {
                viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashServerInitializationFinished)) { _ in
            if hasValidConfig && viewModel.scenes.isEmpty {
                viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
    }

    private var hasValidConfig: Bool { configManager.activeConfig?.hasValidConfig == true }

    private var savedFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .scenes }
            .sorted { $0.name < $1.name }
    }

    private func applyDefaultFilterIfNeeded() {
        guard selectedFilter == nil,
              let filterId = tabManager.getDefaultFilterId(for: .scenes),
              let filter = viewModel.savedFilters[filterId] else { return }
        selectedFilter = filter
    }

    private func reload() {
        guard hasValidConfig else { return }
        viewModel.testConnection()
        viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
    }

    private func label(for option: StashDBViewModel.SceneSortOption) -> String {
        switch option {
        case .dateDesc: return "Recently Released"
        case .dateAsc: return "Oldest First"
        case .createdAtDesc: return "Recently Added"
        case .createdAtAsc: return "Oldest Added"
        case .lastPlayedAtDesc: return "Recently Played"
        case .lastPlayedAtAsc: return "Least Recently Played"
        case .titleAsc: return "Title (A-Z)"
        case .titleDesc: return "Title (Z-A)"
        case .durationDesc: return "Longest First"
        case .durationAsc: return "Shortest First"
        case .playCountDesc: return "Most Viewed"
        case .playCountAsc: return "Least Viewed"
        case .playDurationDesc: return "Most Watch Time"
        case .playDurationAsc: return "Least Watch Time"
        case .oCounterDesc: return "O Count (High-Low)"
        case .oCounterAsc: return "O Count (Low-High)"
        case .ratingDesc: return "Highest Rated"
        case .ratingAsc: return "Lowest Rated"
        case .random: return "Random"
        }
    }
}
