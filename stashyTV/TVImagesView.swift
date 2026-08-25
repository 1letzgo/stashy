//
//  TVImagesView.swift
//  stashyTV
//
//  Images grid for tvOS
//

import SwiftUI

struct TVImagesView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @State private var sortBy: StashDBViewModel.ImageSortOption
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var presentedImage: TVImageLink?
    @State private var focusResetToken = 0
    @FocusState private var focusedImageID: String?

    /// GIFs und Videos raus — tvOS zeigt hier nur Standbilder.
    private var displayImages: [StashImage] {
        viewModel.allImages.filter { !$0.isGifFile && !$0.isVideo }
    }

    init() {
        let defaultSort = StashDBViewModel.ImageSortOption(rawValue: TabManager.shared.getSortOption(for: .images) ?? "") ?? .dateDesc
        _sortBy = State(initialValue: defaultSort)
    }

    private static let sortOrder: [StashDBViewModel.ImageSortOption] = [.random, .titleAsc, .titleDesc, .dateDesc, .dateAsc, .ratingDesc, .ratingAsc, .createdAtDesc, .createdAtAsc, .updatedAtDesc, .updatedAtAsc]

    private var sortOptions: [TVPickerOption<StashDBViewModel.ImageSortOption>] {
        Self.sortOrder.map { TVPickerOption($0, label(for: $0)) }
    }

    var body: some View {
        TVCatalogGrid(
            items: displayImages,
            hasValidConfig: hasValidConfig,
            errorMessage: viewModel.imageFindListError,
            isLoading: viewModel.isLoadingImages,
            isLoadingMore: viewModel.isLoadingImages && !viewModel.allImages.isEmpty,
            hasMore: viewModel.hasMoreImages,
            columnWidth: 300,
            columnCount: 5,
            columnSpacing: 30,
            emptySystemImage: "photo",
            emptyTitle: "No Images Found",
            loadingText: "Loading images…",
            errorTitle: "Error loading images",
            focusResetToken: focusResetToken,
            loadMore: { viewModel.loadMoreImages() },
            reload: { reload() },
            focusedID: $focusedImageID,
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
            card: { image in
                Button {
                    presentedImage = TVImageLink(id: image.id, title: image.title ?? "Untitled")
                } label: {
                    TVImageCardView(image: image)
                }
                .buttonStyle(.card)
            }
        )
        .fullScreenCover(item: $presentedImage) { link in
            TVImageDetailView(imageId: link.id, imageTitle: link.title, galleryId: link.galleryId)
        }
        .onChange(of: sortBy) { _, newValue in
            focusResetToken += 1
            viewModel.fetchImages(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
            focusResetToken += 1
            viewModel.fetchImages(sortBy: sortBy, isInitialLoad: true, filter: newValue)
        }
        .onAppear {
            guard hasValidConfig else { return }
            viewModel.fetchSavedFilters { _ in
                applyDefaultFilterIfNeeded()
            }
            if viewModel.allImages.isEmpty {
                viewModel.fetchImages(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            viewModel.fetchImages(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashServerInitializationFinished)) { _ in
            if hasValidConfig && viewModel.allImages.isEmpty {
                viewModel.fetchImages(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
    }

    private var hasValidConfig: Bool { configManager.activeConfig?.hasValidConfig == true }

    private var savedFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .images }
            .sorted { $0.name < $1.name }
    }

    private func applyDefaultFilterIfNeeded() {
        guard selectedFilter == nil,
              let filterId = tabManager.getDefaultFilterId(for: .images),
              let filter = viewModel.savedFilters[filterId] else { return }
        selectedFilter = filter
    }

    private func reload() {
        guard hasValidConfig else { return }
        viewModel.testConnection()
        viewModel.fetchImages(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
    }

    private func label(for option: StashDBViewModel.ImageSortOption) -> String {
        switch option {
        case .titleAsc: return "Title (A-Z)"
        case .titleDesc: return "Title (Z-A)"
        case .dateDesc: return "Newest First"
        case .dateAsc: return "Oldest First"
        case .ratingDesc: return "Highest Rated"
        case .ratingAsc: return "Lowest Rated"
        case .createdAtDesc: return "Recently Added"
        case .createdAtAsc: return "Oldest Added"
        case .updatedAtDesc: return "Recently Updated"
        case .updatedAtAsc: return "Least Recently Updated"
        case .random: return "Random"
        }
    }
}
