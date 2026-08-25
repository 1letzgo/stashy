//
//  TVPerformersView.swift
//  stashyTV
//
//  Performers grid for tvOS
//

import SwiftUI

struct TVPerformersView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @State private var sortBy: StashDBViewModel.PerformerSortOption
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var focusResetToken = 0
    @FocusState private var focusedPerformerID: String?

    init() {
        let defaultSort = StashDBViewModel.PerformerSortOption(rawValue: TabManager.shared.getSortOption(for: .performers) ?? "") ?? .nameAsc
        _sortBy = State(initialValue: defaultSort)
    }

    private static let sortOrder: [StashDBViewModel.PerformerSortOption] = [.random, .nameAsc, .nameDesc, .sceneCountDesc, .sceneCountAsc, .birthdateDesc, .birthdateAsc, .oCountDesc, .oCountAsc, .ratingDesc, .ratingAsc, .createdAtDesc, .createdAtAsc, .updatedAtDesc, .updatedAtAsc]

    private var sortOptions: [TVPickerOption<StashDBViewModel.PerformerSortOption>] {
        Self.sortOrder.map { TVPickerOption($0, label(for: $0)) }
    }

    var body: some View {
        TVCatalogGrid(
            items: viewModel.performers,
            hasValidConfig: hasValidConfig,
            errorMessage: viewModel.errorMessage,
            isLoading: viewModel.isLoadingPerformers,
            isLoadingMore: viewModel.isLoadingMorePerformers,
            hasMore: viewModel.hasMorePerformers,
            columnWidth: 260,
            columnCount: 6,
            emptySystemImage: "person.3",
            emptyTitle: "No Performers Found",
            loadingText: "Loading performers…",
            errorTitle: "Error loading performers",
            focusResetToken: focusResetToken,
            loadMore: { viewModel.loadMorePerformers() },
            reload: { reload() },
            focusedID: $focusedPerformerID,
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
            card: { item in
                TVNavButton(value: TVPerformerLink(id: item.id, name: item.name)) {
                    TVPerformerCardView(performer: item)
                }
            }
        )
        .onChange(of: sortBy) { _, newValue in
            focusResetToken += 1
            viewModel.fetchPerformers(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
            focusResetToken += 1
            viewModel.fetchPerformers(sortBy: sortBy, isInitialLoad: true, filter: newValue)
        }
        .onAppear {
            guard hasValidConfig else { return }
            viewModel.fetchSavedFilters { _ in
                applyDefaultFilterIfNeeded()
            }
            if viewModel.performers.isEmpty {
                viewModel.fetchPerformers(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            viewModel.fetchPerformers(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashServerInitializationFinished)) { _ in
            if hasValidConfig && viewModel.performers.isEmpty {
                viewModel.fetchPerformers(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
    }

    private var hasValidConfig: Bool { configManager.activeConfig?.hasValidConfig == true }

    private var savedFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .performers }
            .sorted { $0.name < $1.name }
    }

    private func applyDefaultFilterIfNeeded() {
        guard selectedFilter == nil,
              let filterId = tabManager.getDefaultFilterId(for: .performers),
              let filter = viewModel.savedFilters[filterId] else { return }
        selectedFilter = filter
    }

    private func reload() {
        guard hasValidConfig else { return }
        viewModel.testConnection()
        viewModel.fetchPerformers(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
    }

    private func label(for option: StashDBViewModel.PerformerSortOption) -> String {
        switch option {
        case .nameAsc: return "Name (A-Z)"
        case .nameDesc: return "Name (Z-A)"
        case .sceneCountDesc: return "Most Scenes"
        case .sceneCountAsc: return "Least Scenes"
        case .imageCountDesc: return "Most Images"
        case .imageCountAsc: return "Least Images"
        case .galleryCountDesc: return "Most Galleries"
        case .galleryCountAsc: return "Least Galleries"
        case .birthdateDesc: return "Youngest First"
        case .birthdateAsc: return "Oldest First"
        case .createdAtDesc: return "Recently Added"
        case .createdAtAsc: return "Oldest Added"
        case .updatedAtDesc: return "Recently Updated"
        case .updatedAtAsc: return "Least Recently Updated"
        case .oCountDesc: return "O Count (High-Low)"
        case .oCountAsc: return "O Count (Low-High)"
        case .ratingDesc: return "Highest Rated"
        case .ratingAsc: return "Lowest Rated"
        case .random: return "Random"
        }
    }
}
