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
    // Default-Filter nur einmal pro View-Lebensdauer anwenden — sonst kommt er
    // nach jedem Pop/Tab-Wechsel zurück, obwohl "No Filter" gewählt war.
    @State private var didApplyDefaultFilter = false
    @State private var presentedImage: TVImageLink?
    @State private var slideshow: TVSlideshowStart?
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

    private static let sortOrder: [StashDBViewModel.ImageSortOption] = [.random, .performerAgeDesc, .performerAgeAsc, .titleAsc, .titleDesc, .dateDesc, .dateAsc, .ratingDesc, .ratingAsc, .createdAtDesc, .createdAtAsc, .updatedAtDesc, .updatedAtAsc]

    private var sortOptions: [TVPickerOption<StashDBViewModel.ImageSortOption>] {
        Self.sortOrder.filter(\.isAvailableOnServer).map { TVPickerOption($0, label(for: $0)) }
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
            emptyTitle: tr("empty_images_found"),
            loadingText: tr("loading_images"),
            errorTitle: tr("error_loading_images"),
            focusResetToken: focusResetToken,
            loadMore: { viewModel.loadMoreImages() },
            reload: { reload() },
            focusedID: $focusedImageID,
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
                        if !displayImages.isEmpty {
                            TVSlideshowButton { slideshow = TVSlideshowStart(index: 0) }
                        }
                    }
                )
            },
            card: { image in
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        presentedImage = TVImageLink(
                            id: image.id,
                            title: image.displayTitle ?? tr("untitled")
                        )
                    } label: {
                        TVImageCardView(image: image)
                    }
                    .buttonStyle(.card)

                    TVImageCardTitleView(image: image)
                }
            }
        )
        .dismissOnAppLock {
            presentedImage = nil
            slideshow = nil
        }
        .fullScreenCover(item: $slideshow) { start in
            TVImageSlideshowView(
                images: displayImages,
                startIndex: start.index,
                onLoadMore: { viewModel.loadMoreImages() },
                hasMore: viewModel.hasMoreImages
            )
        }
        .fullScreenCover(item: $presentedImage) { link in
            TVImageDetailView(
                imageId: link.id,
                imageTitle: link.title,
                galleryId: link.galleryId,
                initialImages: displayImages,
                onLoadMore: { viewModel.loadMoreImages() },
                hasMore: viewModel.hasMoreImages
            )
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
            didApplyDefaultFilter = false
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
        guard !didApplyDefaultFilter else { return }
        didApplyDefaultFilter = true
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
        case .titleAsc: return tr("title_z")
        case .titleDesc: return tr("title_z_2")
        case .dateDesc: return tr("newest_first")
        case .dateAsc: return tr("oldest_first")
        case .ratingDesc: return tr("highest_rated")
        case .ratingAsc: return tr("lowest_rated")
        case .createdAtDesc: return tr("recently_added")
        case .createdAtAsc: return tr("oldest_added")
        case .updatedAtDesc: return tr("recently_updated")
        case .updatedAtAsc: return tr("least_recently_updated")
        case .performerAgeDesc, .performerAgeAsc: return option.displayName
        case .random: return tr("random")
        }
    }
}
