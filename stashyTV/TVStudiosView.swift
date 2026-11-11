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
    // Default-Filter nur einmal pro View-Lebensdauer anwenden — sonst kommt er
    // nach jedem Pop/Tab-Wechsel zurück, obwohl "No Filter" gewählt war.
    @State private var didApplyDefaultFilter = false
    @State private var focusResetToken = 0
    @FocusState private var focusedStudioID: String?

    init() {
        let defaultSort = StashDBViewModel.StudioSortOption(rawValue: TabManager.shared.getSortOption(for: .studios) ?? "") ?? .nameAsc
        _sortBy = State(initialValue: defaultSort)
    }

    private static let sortOrder: [StashDBViewModel.StudioSortOption] = [.random, .performerCountDesc, .performerCountAsc, .performerCountAllDesc, .performerCountAllAsc, .oCounterDesc, .oCounterAsc, .oCounterAllDesc, .oCounterAllAsc, .markerCountDesc, .markerCountAsc, .nameAsc, .nameDesc, .sceneCountDesc, .sceneCountAsc, .createdAtDesc, .createdAtAsc, .updatedAtDesc, .updatedAtAsc]

    private var sortOptions: [TVPickerOption<StashDBViewModel.StudioSortOption>] {
        Self.sortOrder.filter(\.isAvailableOnServer).map { TVPickerOption($0, label(for: $0)) }
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
            emptyTitle: tr("empty_studios_found"),
            loadingText: tr("loading_studios"),
            errorTitle: tr("error_loading_studios"),
            focusResetToken: focusResetToken,
            loadMore: { viewModel.loadMoreStudios() },
            reload: { reload() },
            focusedID: $focusedStudioID,
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
            didApplyDefaultFilter = false
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
        guard !didApplyDefaultFilter else { return }
        didApplyDefaultFilter = true
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
        case .nameAsc: return tr("name_z")
        case .nameDesc: return tr("name_z_2")
        case .sceneCountDesc: return tr("most_scenes")
        case .sceneCountAsc: return tr("least_scenes")
        case .createdAtDesc: return tr("recently_added")
        case .createdAtAsc: return tr("oldest_added")
        case .updatedAtDesc: return tr("recently_updated")
        case .updatedAtAsc: return tr("least_recently_updated")
        case .ratingDesc: return tr("highest_rated")
        case .ratingAsc: return tr("lowest_rated")
        case .performerCountDesc: return tr("most_performers")
        case .performerCountAsc: return tr("least_performers")
        case .galleryCountDesc: return tr("most_galleries")
        case .galleryCountAsc: return tr("least_galleries")
        case .imageCountDesc: return tr("most_images")
        case .imageCountAsc: return tr("least_images")
        case .oCounterDesc, .oCounterAsc, .oCounterAllDesc, .oCounterAllAsc, .performerCountAllDesc, .performerCountAllAsc, .markerCountDesc, .markerCountAsc: return option.displayName
        case .random: return tr("random")
        }
    }
}
