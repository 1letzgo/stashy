//
//  TVGalleriesView.swift
//  stashyTV
//
//  Galleries grid + gallery detail for tvOS
//

import SwiftUI

struct TVGalleriesView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @State private var sortBy: StashDBViewModel.GallerySortOption
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var focusResetToken = 0
    @FocusState private var focusedGalleryID: String?

    init() {
        let defaultSort = StashDBViewModel.GallerySortOption(rawValue: TabManager.shared.getSortOption(for: .galleries) ?? "") ?? .dateDesc
        _sortBy = State(initialValue: defaultSort)
    }

    private static let sortOrder: [StashDBViewModel.GallerySortOption] = [.random, .titleAsc, .titleDesc, .dateDesc, .dateAsc, .imageCountDesc, .imageCountAsc, .ratingDesc, .ratingAsc, .createdAtDesc, .createdAtAsc, .updatedAtDesc, .updatedAtAsc]

    private var sortOptions: [TVPickerOption<StashDBViewModel.GallerySortOption>] {
        Self.sortOrder.map { TVPickerOption($0, label(for: $0)) }
    }

    var body: some View {
        TVCatalogGrid(
            items: viewModel.galleries,
            hasValidConfig: hasValidConfig,
            errorMessage: viewModel.errorMessage,
            isLoading: viewModel.isLoadingGalleries,
            isLoadingMore: viewModel.isLoadingGalleries && !viewModel.galleries.isEmpty,
            hasMore: viewModel.hasMoreGalleries,
            columnWidth: 410,
            emptySystemImage: "photo.stack",
            emptyTitle: "No Galleries Found",
            loadingText: "Loading galleries…",
            errorTitle: "Error loading galleries",
            focusResetToken: focusResetToken,
            loadMore: { viewModel.loadMoreGalleries() },
            reload: { reload() },
            focusedID: $focusedGalleryID,
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
            card: { gallery in
                TVNavButton(value: TVGalleryLink(id: gallery.id, title: gallery.displayName)) {
                    TVGalleryCardView(gallery: gallery)
                }
            }
        )
        .onChange(of: sortBy) { _, newValue in
            focusResetToken += 1
            viewModel.fetchGalleries(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
            focusResetToken += 1
            viewModel.fetchGalleries(sortBy: sortBy, isInitialLoad: true, filter: newValue)
        }
        .onAppear {
            guard hasValidConfig else { return }
            viewModel.fetchSavedFilters { _ in
                applyDefaultFilterIfNeeded()
            }
            if viewModel.galleries.isEmpty {
                viewModel.fetchGalleries(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            viewModel.fetchGalleries(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashServerInitializationFinished)) { _ in
            if hasValidConfig && viewModel.galleries.isEmpty {
                viewModel.fetchGalleries(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
    }

    private var hasValidConfig: Bool { configManager.activeConfig?.hasValidConfig == true }

    private var savedFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .galleries }
            .sorted { $0.name < $1.name }
    }

    private func applyDefaultFilterIfNeeded() {
        guard selectedFilter == nil,
              let filterId = tabManager.getDefaultFilterId(for: .galleries),
              let filter = viewModel.savedFilters[filterId] else { return }
        selectedFilter = filter
    }

    private func reload() {
        guard hasValidConfig else { return }
        viewModel.testConnection()
        viewModel.fetchGalleries(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
    }

    private func label(for option: StashDBViewModel.GallerySortOption) -> String {
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
        case .imageCountDesc: return "Most Images"
        case .imageCountAsc: return "Least Images"
        case .random: return "Random"
        }
    }
}

// MARK: - Gallery Detail View

struct TVGalleryDetailView: View {
    let galleryId: String
    let galleryTitle: String

    @StateObject private var viewModel = StashDBViewModel()
    @State private var gallery: Gallery?
    @State private var isLoadingGallery: Bool = false
    @State private var presentedImage: TVImageLink?
    @FocusState private var emptyFocus: Bool
    @Environment(\.tvContentWidth) private var contentWidth

    private var imageSpec: TVGridSpec { .images }
    @Environment(\.dismiss) private var dismiss

    /// Still images for the grid — GIFs hidden; still WebP kept (tvOS can decode still WebP).
    private var displayImages: [StashImage] {
        viewModel.galleryImages.filter { !$0.isGifFile && !$0.isVideo }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                headerSection

                if viewModel.isLoadingGalleryImages && viewModel.galleryImages.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView().scaleEffect(1.5)
                        Spacer()
                    }
                    .padding(.vertical, 60)
                    // Gegenstück zum `emptyFocus`-Anker im Leer-Zweig.
                    .focusable()
                } else if viewModel.galleryImages.isEmpty || displayImages.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text(viewModel.galleryImages.isEmpty
                                  ? "No images in this gallery"
                                  : "No supported images in this gallery")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            if !viewModel.galleryImages.isEmpty && displayImages.isEmpty {
                                Text("Only unsupported or animated formats (e.g. GIF) were found.")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 80)
                            }
                            // Focus anchor so Menu/Back hits tvExitDismissable instead of exiting the app.
                            Button("Back") { dismiss() }
                                .focused($emptyFocus)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 60)
                    .onAppear { emptyFocus = true }
                } else {
                    LazyVGrid(columns: imageSpec.columns(for: contentWidth), alignment: .leading, spacing: imageSpec.spacing) {
                        ForEach(displayImages) { image in
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    presentedImage = TVImageLink(
                                        id: image.id,
                                        title: image.displayTitle ?? "Untitled",
                                        galleryId: galleryId
                                    )
                                } label: {
                                    TVImageCardView(image: image)
                                }
                                .buttonStyle(.card)

                                TVImageCardTitleView(image: image)
                            }
                            .frame(width: imageSpec.columnWidth)
                            .onAppear {
                                if image.id == displayImages.last?.id && viewModel.hasMoreGalleryImages {
                                    viewModel.fetchGalleryImages(galleryId: galleryId, isInitialLoad: false)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                }
            }
            .padding(.bottom, 80)
        }
        .background(Color.appBackground)
        .fullScreenCover(item: $presentedImage) { link in
            TVImageDetailView(imageId: link.id, imageTitle: link.title, galleryId: link.galleryId)
        }
        .onAppear {
            loadGalleryData()
        }
        .onChange(of: viewModel.galleries) { _, galleries in
            // Statt fixem 0.5s-Timer die Galerie zuweisen, sobald die Liste
            // vom Fetch zurückkommt — vermeidet Race bei langsamen Verbindungen,
            // bei denen der Timer leer lieferte und `gallery` nil blieb.
            if gallery == nil, let match = galleries.first(where: { $0.id == galleryId }) {
                gallery = match
                isLoadingGallery = false
            }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 50) {
            if let thumbnailURL = gallery?.thumbnailURL {
                CustomAsyncImage(url: thumbnailURL) { loader in
                    if let image = loader.image {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.08))
                            .overlay(ProgressView())
                    }
                }
                .frame(width: 400, height: 225)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.08))
                    .overlay(
                        Image(systemName: "photo.stack")
                            .font(.system(size: 56))
                            .foregroundColor(.secondary)
                    )
                    .frame(width: 400, height: 225)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 16) {
                Text(gallery?.displayName ?? galleryTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                if isLoadingGallery {
                    ProgressView().scaleEffect(1.2)
                } else if let gallery = gallery {
                    VStack(alignment: .leading, spacing: 14) {
                        if let details = gallery.details, !details.isEmpty {
                            Text(details)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                        }

                        Divider()
                            .background(Color.secondary)

                        LazyVGrid(columns: TVGridSpec.infoColumns, alignment: .leading, spacing: 12) {
                            if let count = gallery.imageCount {
                                Text("Images").font(.title3).foregroundStyle(.secondary)
                                Text("\(count)").font(.title3).foregroundColor(.white)
                            }
                            if let date = gallery.date, !date.isEmpty {
                                Text("Date").font(.title3).foregroundStyle(.secondary)
                                Text(date).font(.title3).foregroundColor(.white)
                            }
                            if let studio = gallery.studio {
                                Text("Studio").font(.title3).foregroundStyle(.secondary)
                                Text(studio.name).font(.title3).foregroundColor(.white)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 60)
        .padding(.top, 40)
    }

    private func loadGalleryData() {
        // Vorab prüfen, ob die Galerie bereits in der (ggf. noch nicht geleerten)
        // Liste enthalten ist — dann kein Refetch nötig.
        if gallery == nil, let match = viewModel.galleries.first(where: { $0.id == galleryId }) {
            gallery = match
        }
        if !isLoadingGallery && gallery == nil {
            isLoadingGallery = true
            viewModel.fetchGalleries(sortBy: .titleAsc, isInitialLoad: true)
            // Die eigentliche Zuweisung übernimmt `.onChange(of: viewModel.galleries)`,
            // sobald der Fetch zurückkommt — kein fixer Timer mehr, der raced.
        }
        viewModel.fetchGalleryImages(galleryId: galleryId, isInitialLoad: true)
    }
}
