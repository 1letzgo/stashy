//
//  TVImageDetailView.swift
//  stashyTV
//
//  Full-screen image viewer for tvOS with swipe navigation
//

import SwiftUI

struct TVImageDetailView: View {
    let imageId: String
    let imageTitle: String
    /// When set, Left/Right browse this gallery; otherwise the image library.
    var galleryId: String? = nil
    /// The list the grid is showing, handed over so the viewer opens the image that was picked.
    /// Its own fetch only knows page one of a default sort, so anything the user had scrolled to
    /// was missing from it and the viewer fell back to the first image.
    var initialImages: [StashImage] = []
    /// Asks the grid's view model for the next page — the viewer no longer pages on its own.
    var onLoadMore: (() -> Void)? = nil
    var hasMore: Bool = false

    @StateObject private var viewModel = StashDBViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var images: [StashImage] = []
    @State private var hasLoaded: Bool = false
    @State private var loadFailed: Bool = false
    @State private var isLoading: Bool = true
    @State private var slideshow: TVSlideshowStart?
    @State private var showingActions = false
    /// Local rating / O Count edits by image id, kept so a refreshed list from the grid does not undo them.
    @State private var ratingEdits: [String: Int?] = [:]
    @State private var oEdits: [String: Int] = [:]
    @AppStorage(ImageScalingMode.key) private var scalingRaw = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading && images.isEmpty {
                ProgressView()
                    .scaleEffect(1.5)
            } else if loadFailed || images.isEmpty {
                VStack(spacing: 24) {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(loadFailed ? tr("error_load_images_2") : tr("empty_images"))
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    if !imageTitle.isEmpty {
                        Text(imageTitle)
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 80)
                    }
                    Button(tr("action_retry")) {
                        hasLoaded = false
                        loadFailed = false
                        loadImages()
                    }
                    .font(.title3)
                    Button(tr("action_close")) { dismiss() }
                        .font(.title3)
                }
            } else {
                imageViewer
            }
        }
        .focusable()
        // Select: rating and O Count.
        .onTapGesture {
            guard images.indices.contains(currentIndex), slideshow == nil else { return }
            showingActions = true
        }
        .confirmationDialog(tr("rating"), isPresented: $showingActions, titleVisibility: .visible) {
            actionButtons
        }
        .onExitCommand {
            dismiss()
        }
        .onMoveCommand { direction in
            guard !images.isEmpty else { return }
            switch direction {
            case .left:
                if currentIndex > 0 { currentIndex -= 1 }
            case .right:
                if currentIndex < images.count - 1 {
                    currentIndex += 1
                    maybeLoadMoreIfNeeded()
                }
            default:
                break
            }
        }
        // Play/Pause starts a slideshow from the image on screen.
        .onPlayPauseCommand {
            guard images.indices.contains(currentIndex) else { return }
            slideshow = TVSlideshowStart(index: currentIndex)
        }
        .fullScreenCover(item: $slideshow) { start in
            slideshowView(start: start)
        }
        .onAppear {
            loadImages()
        }
        // More pages the grid loaded while the viewer is open.
        .onChange(of: initialImages) { _, images in
            guard !images.isEmpty else { return }
            applyImages(images)
        }
        .onChange(of: viewModel.allImages) { _, allImages in
            guard galleryId == nil, initialImages.isEmpty else { return }
            applyImages(allImages)
        }
        .onChange(of: viewModel.galleryImages) { _, galleryImages in
            guard galleryId != nil else { return }
            applyImages(galleryImages)
        }
    }

    @ViewBuilder
    private var imageViewer: some View {
        if currentIndex < images.count {
            let image = images[currentIndex]
            let fills = ImageScalingMode.resolve(scalingRaw).fills(
                mediaIsPortrait: (image.pixelSize.map { $0.height > $0.width }) ?? false,
                spaceIsPortrait: false
            )
            ZStack {
                ImageBackdrop(url: image.thumbnailURL)
                CustomAsyncImage(url: image.imageURL ?? image.thumbnailURL) { loader in
                    if let img = loader.image {
                        if fills {
                            img
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            img
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else if loader.isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .ignoresSafeArea()
            .id(image.id)

            VStack {
                HStack {
                    Text(image.title ?? imageTitle)
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 60)
                .padding(.top, 40)

                Spacer()
                HStack(spacing: 24) {
                    if images.count > 1 {
                        Text("\(currentIndex + 1) / \(images.count)")
                    }
                    TVImageRatingInfo(rating100: image.rating100, oCount: image.o_counter ?? 0)
                    if images.count > 1 {
                        Label(tr("slideshow"), systemImage: "playpause.fill")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.5), in: Capsule())
                .padding(.bottom, 40)
            }
        }
    }

    private func slideshowView(start: TVSlideshowStart) -> some View {
            return TVImageSlideshowView(
                images: images,
                startIndex: start.index,
                onLoadMore: { requestMoreImages() },
                hasMore: canLoadMore,
                onFinish: { imageId in
                    // Back in the viewer on the image the slideshow stopped at.
                    if let index = images.firstIndex(where: { $0.id == imageId }) {
                        currentIndex = index
                    }
                },
                onImageChanged: { updated in
                    ratingEdits[updated.id] = .some(updated.rating100)
                    oEdits[updated.id] = updated.o_counter ?? 0
                    if let index = images.firstIndex(where: { $0.id == updated.id }) {
                        images[index] = updated
                    }
                }
            )
    }

    @ViewBuilder
    private var actionButtons: some View {
        let current = images.indices.contains(currentIndex) ? TVEntityRating.stars(images[currentIndex].rating100) : 0
        Button(tr("action_add_o")) { addO() }
        ForEach((0...5).reversed(), id: \.self) { stars in
            let label = stars == 0 ? tr("empty_rating") : String(repeating: "★", count: stars)
            Button(stars == current ? "✓ \(label)" : label) {
                setRating(stars == 0 ? nil : stars * 20)
            }
        }
        Button(tr("action_cancel"), role: .cancel) {}
    }

    private func setRating(_ rating: Int?) {
        guard images.indices.contains(currentIndex) else { return }
        let imageId = images[currentIndex].id
        let original = images[currentIndex].rating100
        ratingEdits[imageId] = .some(rating)
        images[currentIndex] = images[currentIndex].withRating(rating)
        viewModel.updateImageRating(imageId: imageId, rating100: rating) { success in
            guard !success else { return }
            DispatchQueue.main.async {
                ratingEdits[imageId] = .some(original)
                if let index = images.firstIndex(where: { $0.id == imageId }) {
                    images[index] = images[index].withRating(original)
                }
                AppLog.error("TV: error_save_rating")
            }
        }
    }

    private func addO() {
        guard images.indices.contains(currentIndex) else { return }
        let imageId = images[currentIndex].id
        let original = images[currentIndex].o_counter ?? 0
        oEdits[imageId] = original + 1
        images[currentIndex] = images[currentIndex].withOCounter(original + 1)
        viewModel.incrementImageOCounter(imageId: imageId) { returned in
            DispatchQueue.main.async {
                let value = returned ?? original
                oEdits[imageId] = value
                if let index = images.firstIndex(where: { $0.id == imageId }) {
                    images[index] = images[index].withOCounter(value)
                }
                if returned == nil {
                    AppLog.error("TV: error_update_o_count")
                }
            }
        }
    }

    private func loadImages() {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        loadFailed = false

        // The grid's own list: it holds every page the user scrolled through, in the sort and
        // filter they are looking at.
        if !initialImages.isEmpty {
            applyImages(initialImages)
            return
        }

        if let galleryId {
            if !viewModel.galleryImages.isEmpty {
                applyImages(viewModel.galleryImages)
            }
            viewModel.fetchGalleryImages(galleryId: galleryId, isInitialLoad: true)
            // Timeout empty → failed
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                if images.isEmpty {
                    isLoading = false
                    loadFailed = true
                }
            }
            return
        }

        if !viewModel.allImages.isEmpty {
            applyImages(viewModel.allImages)
            return
        }

        viewModel.fetchImages(sortBy: .dateDesc, isInitialLoad: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if images.isEmpty {
                isLoading = false
                loadFailed = true
            }
        }
    }

    private func applyImages(_ source: [StashImage]) {
        // Keep still WebP; hide GIF/video. Matches tvOS grid filtering.
        let viewable = source.filter { !$0.isGifFile && !$0.isVideo }
        guard !viewable.isEmpty else {
            if !isLoading { loadFailed = true }
            return
        }
        let anchorId = images.indices.contains(currentIndex) ? images[currentIndex].id : imageId
        images = viewable.map { image in
            var image = image
            if let rating = ratingEdits[image.id] { image = image.withRating(rating) }
            if let o = oEdits[image.id] { image = image.withOCounter(o) }
            return image
        }
        isLoading = false
        loadFailed = false
        // Erst das aktuell gezeigte Bild suchen, **dann** erst das ursprünglich
        // geöffnete. Eine gemeinsame `||`-Bedingung nahm den ersten Treffer von
        // beidem — und das war ab Seite 2 fast immer das Startbild, weil es weiter
        // vorne steht. Genau das ließ den Betrachter nach 100 Bildern zurück-
        // springen.
        currentIndex = images.firstIndex(where: { $0.id == anchorId })
            ?? images.firstIndex(where: { $0.id == imageId })
            ?? 0
    }

    /// Whether the slideshow can ask for another page of the list it is showing.
    private var canLoadMore: Bool {
        if onLoadMore != nil { return hasMore }
        return galleryId != nil ? viewModel.hasMoreGalleryImages : viewModel.hasMoreImages
    }

    private func requestMoreImages() {
        if let onLoadMore {
            if hasMore { onLoadMore() }
        } else if let galleryId {
            if viewModel.hasMoreGalleryImages {
                viewModel.fetchGalleryImages(galleryId: galleryId, isInitialLoad: false)
            }
        } else if viewModel.hasMoreImages {
            viewModel.loadMoreImages()
        }
    }

    private func maybeLoadMoreIfNeeded() {
        guard let galleryId else {
            guard currentIndex >= images.count - 3 else { return }
            // Paging belongs to whoever owns the list; the viewer only says when it needs more.
            if let onLoadMore {
                if hasMore { onLoadMore() }
            } else if viewModel.hasMoreImages {
                viewModel.loadMoreImages()
            }
            return
        }
        guard currentIndex >= images.count - 3 else { return }
        if let onLoadMore {
            if hasMore { onLoadMore() }
        } else if viewModel.hasMoreGalleryImages {
            viewModel.fetchGalleryImages(galleryId: galleryId, isInitialLoad: false)
        }
    }
}

/// Current stars and O Count of an image, one line for the viewer and the slideshow.
struct TVImageRatingInfo: View {
    let rating100: Int?
    let oCount: Int

    var body: some View {
        let stars = TVEntityRating.stars(rating100)
        HStack(spacing: 20) {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= stars ? "star.fill" : "star")
                        .foregroundStyle(i <= stars ? Color.yellow : Color.white.opacity(0.4))
                }
            }
            .accessibilityLabel(tr("rating"))
            HStack(spacing: 6) {
                Image(systemName: oCount > 0 ? AppearanceManager.shared.oCounterIconFilled : AppearanceManager.shared.oCounterIcon)
                Text("\(oCount)")
            }
            .accessibilityLabel(tr("o_count"))
        }
    }
}
