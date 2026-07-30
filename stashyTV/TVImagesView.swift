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
    @FocusState private var focusedImageID: String?

    private var displayImages: [StashImage] {
        viewModel.allImages.filter { !$0.isGifFile && !$0.isVideo }
    }

    init() {
        let defaultSort = StashDBViewModel.ImageSortOption(rawValue: TabManager.shared.getSortOption(for: .images) ?? "") ?? .dateDesc
        _sortBy = State(initialValue: defaultSort)
    }

    private let columns = [
        GridItem(.fixed(300), spacing: 30),
        GridItem(.fixed(300), spacing: 30),
        GridItem(.fixed(300), spacing: 30),
        GridItem(.fixed(300), spacing: 30),
        GridItem(.fixed(300), spacing: 30)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !hasValidConfig {
                TVConnectionErrorView(title: "Server not reachable", subtitle: "Add a server in Settings.") { reload() }
            } else if viewModel.allImages.isEmpty && (viewModel.imageFindListError?.isEmpty == false) {
                TVConnectionErrorView(title: "Error loading images", subtitle: viewModel.imageFindListError) { reload() }
            } else if viewModel.isLoadingImages && viewModel.allImages.isEmpty {
                loadingView
            } else if viewModel.allImages.isEmpty {
                emptyView
            } else {
                contentGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .onChange(of: viewModel.allImages.first?.id) { oldID, newID in
            if oldID != newID, let newID {
                focusedImageID = newID
            }
        }
        .onChange(of: sortBy) { _, newValue in
            viewModel.fetchImages(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
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

    private func sortButton(option: StashDBViewModel.ImageSortOption) -> some View {
        Button {
            sortBy = option
        } label: {
            HStack {
                Text(label(for: option))
                if sortBy == option {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
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

    @ViewBuilder
    private var loadingView: some View {
        Spacer()
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5)
            Text("Loading images…")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        Spacer()
    }

    @ViewBuilder
    private var emptyView: some View {
        Spacer()
        VStack(spacing: 32) {
            Image(systemName: "photo")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            Text("No Images Found")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        Spacer()
    }

    @ViewBuilder
    private var contentGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                STVHeaderView(
                    sortMenu: { sortMenu },
                    filterMenu: { filterMenu },
                    onRefresh: { reload() }
                )

                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                    ForEach(displayImages) { image in
                        Button {
                            presentedImage = TVImageLink(id: image.id, title: image.title ?? "Untitled")
                        } label: {
                            TVImageCardView(image: image)
                        }
                        .buttonStyle(.card)
                        .focused($focusedImageID, equals: image.id)
                        .onAppear {
                            if image.id == displayImages.last?.id && viewModel.hasMoreImages {
                                viewModel.loadMoreImages()
                            }
                        }
                    }

                    if viewModel.isLoadingImages && !viewModel.allImages.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 80)
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 60).focusable(false) }
        .fullScreenCover(item: $presentedImage) { link in
            TVImageDetailView(imageId: link.id, imageTitle: link.title, galleryId: link.galleryId)
        }
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            Section("Sort By") {
                sortButton(option: .random)
                Divider()
                sortButton(option: .titleAsc)
                sortButton(option: .titleDesc)
                sortButton(option: .dateDesc)
                sortButton(option: .dateAsc)
                sortButton(option: .ratingDesc)
                sortButton(option: .ratingAsc)
                sortButton(option: .createdAtDesc)
                sortButton(option: .createdAtAsc)
                sortButton(option: .updatedAtDesc)
                sortButton(option: .updatedAtAsc)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.arrow.down")
                Text(label(for: sortBy))
            }
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .buttonStyle(.card)
    }

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            Button {
                selectedFilter = nil
            } label: {
                HStack {
                    Text("No Filter")
                    if selectedFilter == nil {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }

            let imageFilters = viewModel.savedFilters.values
                .filter { $0.mode == .images }
                .sorted { $0.name < $1.name }

            if !imageFilters.isEmpty {
                Divider()
                ForEach(imageFilters) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        HStack {
                            Text(filter.name)
                            if selectedFilter?.id == filter.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                Text(selectedFilter?.name ?? "No Filter")
            }
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .buttonStyle(.card)
    }
}
