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
    // Default-Filter nur einmal pro View-Lebensdauer anwenden — sonst kommt er
    // nach jedem Pop/Tab-Wechsel zurück, obwohl "No Filter" gewählt war.
    @State private var didApplyDefaultFilter = false
    @State private var focusResetToken = 0
    @FocusState private var focusedSceneID: String?

    init(sortBy: StashDBViewModel.SceneSortOption? = nil) {
        let defaultSort = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getSortOption(for: .scenes) ?? "") ?? .dateDesc
        _sortBy = State(initialValue: sortBy ?? defaultSort)
    }

    private static let sortOrder: [StashDBViewModel.SceneSortOption] = [.random, .productionDateDesc, .productionDateAsc, .dateDesc, .dateAsc, .createdAtDesc, .createdAtAsc, .lastPlayedAtDesc, .lastPlayedAtAsc, .titleAsc, .titleDesc, .durationDesc, .durationAsc, .playCountDesc, .playCountAsc, .oCounterDesc, .oCounterAsc, .ratingDesc, .ratingAsc]

    private var sortOptions: [TVPickerOption<StashDBViewModel.SceneSortOption>] {
        Self.sortOrder.filter(\.isAvailableOnServer).map { TVPickerOption($0, label(for: $0)) }
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
            emptyTitle: tr("empty_scenes_found"),
            loadingText: tr("loading_scenes"),
            errorTitle: tr("error_loading_scenes"),
            focusResetToken: focusResetToken,
            loadMore: { viewModel.loadMoreScenes() },
            reload: { reload() },
            focusedID: $focusedSceneID,
            header: {
                STVHeaderView(
                    sortMenu: {
                        TVOptionPickerButton(
                            title: tr("action_sort_by"),
                            icon: "arrow.up.arrow.down",
                            options: sortOptions,
                            selection: $sortBy
                        )
                    },
                    filterMenu: {
                        TVFilterPickerButton(filters: savedFilters, selection: $selectedFilter)
                    }
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
            didApplyDefaultFilter = false
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
        guard !didApplyDefaultFilter else { return }
        didApplyDefaultFilter = true
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
        case .dateDesc: return tr("recently_released")
        case .dateAsc: return tr("oldest_first")
        case .createdAtDesc: return tr("recently_added")
        case .createdAtAsc: return tr("oldest_added")
        case .lastPlayedAtDesc: return tr("recently_played")
        case .lastPlayedAtAsc: return tr("least_recently_played")
        case .titleAsc: return tr("title_z")
        case .titleDesc: return tr("title_z_2")
        case .durationDesc: return tr("longest_first")
        case .durationAsc: return tr("shortest_first")
        case .playCountDesc: return tr("most_viewed")
        case .playCountAsc: return tr("least_viewed")
        case .playDurationDesc: return tr("most_watch_time")
        case .playDurationAsc: return tr("least_watch_time")
        case .oCounterDesc: return tr("o_count_high_low")
        case .oCounterAsc: return tr("o_count_low_high")
        case .ratingDesc: return tr("highest_rated")
        case .ratingAsc: return tr("lowest_rated")
        case .random: return tr("random")
        case .sceneNumberAsc, .sceneNumberDesc, .productionDateDesc, .productionDateAsc, .forYou: return option.displayName
        }
    }
}
