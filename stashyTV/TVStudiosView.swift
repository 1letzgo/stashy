//
//  TVStudiosView.swift
//  stashyTV
//
//  Studios grid for tvOS
//

import SwiftUI

struct TVStudiosView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @State private var sortBy: StashDBViewModel.StudioSortOption
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var focusResetToken = 0
    @FocusState private var focusedStudioID: String?

    init() {
        let defaultSort = StashDBViewModel.StudioSortOption(rawValue: TabManager.shared.getSortOption(for: .studios) ?? "") ?? .nameAsc
        _sortBy = State(initialValue: defaultSort)
    }

    private static let sortOrder: [StashDBViewModel.StudioSortOption] = [.random, .nameAsc, .nameDesc, .sceneCountDesc, .sceneCountAsc, .createdAtDesc, .createdAtAsc, .updatedAtDesc, .updatedAtAsc]

    private var sortOptions: [TVPickerOption<StashDBViewModel.StudioSortOption>] {
        Self.sortOrder.map { TVPickerOption($0, label(for: $0)) }
    }

    var body: some View {
        TVCatalogGrid(
            items: viewModel.studios,
            hasValidConfig: hasValidConfig,
            errorMessage: viewModel.errorMessage,
            isLoading: viewModel.isLoadingStudios,
            isLoadingMore: viewModel.isLoadingMoreStudios,
            hasMore: viewModel.hasMoreStudios,
            columnWidth: 410,
            columnCount: 4,
            emptySystemImage: "building.2",
            emptyTitle: "No Studios Found",
            loadingText: "Loading studios…",
            errorTitle: "Error loading studios",
            focusResetToken: focusResetToken,
            loadMore: { viewModel.loadMoreStudios() },
            reload: { reload() },
            focusedID: $focusedStudioID,
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
                TVNavButton(value: TVStudioLink(id: item.id, name: item.name)) {
                    TVStudioCardView(studio: item)
                }
            }
        )
        .onChange(of: sortBy) { _, newValue in
            focusResetToken += 1
            viewModel.fetchStudios(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
            focusResetToken += 1
            viewModel.fetchStudios(sortBy: sortBy, isInitialLoad: true, filter: newValue)
        }
        .onAppear {
            guard hasValidConfig else { return }
            viewModel.fetchSavedFilters { _ in
                applyDefaultFilterIfNeeded()
            }
            if viewModel.studios.isEmpty {
                viewModel.fetchStudios(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            viewModel.fetchStudios(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashServerInitializationFinished)) { _ in
            if hasValidConfig && viewModel.studios.isEmpty {
                viewModel.fetchStudios(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
    }

    private var hasValidConfig: Bool { configManager.activeConfig?.hasValidConfig == true }

    private var savedFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .studios }
            .sorted { $0.name < $1.name }
    }

    private func applyDefaultFilterIfNeeded() {
        guard selectedFilter == nil,
              let filterId = tabManager.getDefaultFilterId(for: .studios),
              let filter = viewModel.savedFilters[filterId] else { return }
        selectedFilter = filter
    }

    private func reload() {
        guard hasValidConfig else { return }
        viewModel.testConnection()
        viewModel.fetchStudios(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
    }

    private func label(for option: StashDBViewModel.StudioSortOption) -> String {
        switch option {
        case .nameAsc: return "Name (A-Z)"
        case .nameDesc: return "Name (Z-A)"
        case .sceneCountDesc: return "Most Scenes"
        case .sceneCountAsc: return "Least Scenes"
        case .createdAtDesc: return "Recently Added"
        case .createdAtAsc: return "Oldest Added"
        case .updatedAtDesc: return "Recently Updated"
        case .updatedAtAsc: return "Least Recently Updated"
        case .ratingDesc: return "Highest Rated"
        case .ratingAsc: return "Lowest Rated"
        case .performerCountDesc: return "Most Performers"
        case .performerCountAsc: return "Least Performers"
        case .galleryCountDesc: return "Most Galleries"
        case .galleryCountAsc: return "Least Galleries"
        case .imageCountDesc: return "Most Images"
        case .imageCountAsc: return "Least Images"
        case .random: return "Random"
        }
    }
}
