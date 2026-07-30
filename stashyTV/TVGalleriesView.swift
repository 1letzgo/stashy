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
    @FocusState private var focusedGalleryID: String?

    init() {
        let defaultSort = StashDBViewModel.GallerySortOption(rawValue: TabManager.shared.getSortOption(for: .galleries) ?? "") ?? .dateDesc
        _sortBy = State(initialValue: defaultSort)
    }

    private let columns = [
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !hasValidConfig {
                TVConnectionErrorView(title: "Server not reachable", subtitle: "Add a server in Settings.") { reload() }
            } else if viewModel.galleries.isEmpty && (viewModel.errorMessage?.isEmpty == false) {
                TVConnectionErrorView(title: "Error loading galleries", subtitle: viewModel.errorMessage) { reload() }
            } else if viewModel.isLoadingGalleries && viewModel.galleries.isEmpty {
                loadingView
            } else if viewModel.galleries.isEmpty {
                emptyView
            } else {
                contentGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .onChange(of: viewModel.galleries.first?.id) { oldID, newID in
            if oldID != newID, let newID {
                focusedGalleryID = newID
            }
        }
        .onChange(of: sortBy) { _, newValue in
            viewModel.fetchGalleries(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
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

    private func sortButton(option: StashDBViewModel.GallerySortOption) -> some View {
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

    @ViewBuilder
    private var loadingView: some View {
        Spacer()
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5)
            Text("Loading galleries…")
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
            Image(systemName: "photo.stack")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            Text("No Galleries Found")
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

                LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
                    ForEach(viewModel.galleries) { gallery in
                        TVNavButton(value: TVGalleryLink(id: gallery.id, title: gallery.displayName)) {
                            TVGalleryCardView(gallery: gallery)
                        }
                        .focused($focusedGalleryID, equals: gallery.id)
                        .frame(width: 410)
                        .onAppear {
                            if gallery.id == viewModel.galleries.last?.id && viewModel.hasMoreGalleries {
                                viewModel.loadMoreGalleries()
                            }
                        }
                    }

                    if viewModel.isLoadingGalleries && !viewModel.galleries.isEmpty {
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
                sortButton(option: .imageCountDesc)
                sortButton(option: .imageCountAsc)
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

            let galleryFilters = viewModel.savedFilters.values
                .filter { $0.mode == .galleries }
                .sorted { $0.name < $1.name }

            if !galleryFilters.isEmpty {
                Divider()
                ForEach(galleryFilters) { filter in
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

// MARK: - Gallery Detail View

struct TVGalleryDetailView: View {
    let galleryId: String
    let galleryTitle: String

    @StateObject private var viewModel = StashDBViewModel()
    @State private var gallery: Gallery?
    @State private var isLoadingGallery: Bool = false
    @State private var presentedImage: TVImageLink?
    @FocusState private var emptyFocus: Bool
    @Environment(\.dismiss) private var dismiss

    /// Still images for the grid — GIFs hidden; still WebP kept (tvOS can decode still WebP).
    private var displayImages: [StashImage] {
        viewModel.galleryImages.filter { !$0.isGifFile && !$0.isVideo }
    }

    private let imageColumns = [
        GridItem(.fixed(300), spacing: 30),
        GridItem(.fixed(300), spacing: 30),
        GridItem(.fixed(300), spacing: 30),
        GridItem(.fixed(300), spacing: 30),
        GridItem(.fixed(300), spacing: 30)
    ]

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
                    LazyVGrid(columns: imageColumns, alignment: .leading, spacing: 30) {
                        ForEach(displayImages) { image in
                            Button {
                                presentedImage = TVImageLink(
                                    id: image.id,
                                    title: image.title ?? "Untitled",
                                    galleryId: galleryId
                                )
                            } label: {
                                TVImageCardView(image: image)
                            }
                            .buttonStyle(.card)
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

                        LazyVGrid(columns: [
                            GridItem(.fixed(240), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)
                        ], alignment: .leading, spacing: 12) {
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
