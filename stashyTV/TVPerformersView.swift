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
    // Default-Filter nur einmal pro View-Lebensdauer anwenden — sonst kommt er
    // nach jedem Pop/Tab-Wechsel zurück, obwohl "No Filter" gewählt war.
    @State private var didApplyDefaultFilter = false
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
            emptyTitle: tr("empty_performers_found"),
            loadingText: tr("loading_performers"),
            errorTitle: tr("error_loading_performers"),
            focusResetToken: focusResetToken,
            loadMore: { viewModel.loadMorePerformers() },
            reload: { reload() },
            focusedID: $focusedPerformerID,
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
            didApplyDefaultFilter = false
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
        guard !didApplyDefaultFilter else { return }
        didApplyDefaultFilter = true
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
        case .nameAsc: return tr("name_z")
        case .nameDesc: return tr("name_z_2")
        case .sceneCountDesc: return tr("most_scenes")
        case .sceneCountAsc: return tr("least_scenes")
        case .imageCountDesc: return tr("most_images")
        case .imageCountAsc: return tr("least_images")
        case .galleryCountDesc: return tr("most_galleries")
        case .galleryCountAsc: return tr("least_galleries")
        case .birthdateDesc: return tr("youngest_first")
        case .birthdateAsc: return tr("oldest_first")
        case .createdAtDesc: return tr("recently_added")
        case .createdAtAsc: return tr("oldest_added")
        case .updatedAtDesc: return tr("recently_updated")
        case .updatedAtAsc: return tr("least_recently_updated")
        case .oCountDesc: return tr("o_count_high_low")
        case .oCountAsc: return tr("o_count_low_high")
        case .ratingDesc: return tr("highest_rated")
        case .ratingAsc: return tr("lowest_rated")
        case .random: return tr("random")
        }
    }
}
