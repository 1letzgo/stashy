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

    @StateObject private var viewModel = StashDBViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var images: [StashImage] = []
    @State private var hasLoaded: Bool = false
    @State private var loadFailed: Bool = false
    @State private var isLoading: Bool = true

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
                    Text(loadFailed ? "Failed to load images" : "No images")
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
                    Button("Retry") {
                        hasLoaded = false
                        loadFailed = false
                        loadImages()
                    }
                    .font(.title3)
                    Button("Close") { dismiss() }
                        .font(.title3)
                }
            } else {
                imageViewer
            }
        }
        .focusable()
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
        .onAppear {
            loadImages()
        }
        .onChange(of: viewModel.allImages) { _, allImages in
            guard galleryId == nil else { return }
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
            CustomAsyncImage(url: image.imageURL ?? image.thumbnailURL) { loader in
                if let img = loader.image {
                    img
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if loader.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
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
                if images.count > 1 {
                    Text("\(currentIndex + 1) / \(images.count)")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 40)
                }
            }
        }
    }

    private func loadImages() {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        loadFailed = false

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
        let nonAnimated = source.filter { !$0.isAnimated }
        guard !nonAnimated.isEmpty else {
            if !isLoading { loadFailed = true }
            return
        }
        let previousId = images.indices.contains(currentIndex) ? images[currentIndex].id : imageId
        images = nonAnimated
        isLoading = false
        loadFailed = false
        currentIndex = max(0, images.firstIndex(where: { $0.id == previousId || $0.id == imageId }) ?? 0)
    }

    private func maybeLoadMoreIfNeeded() {
        guard let galleryId else {
            if currentIndex >= images.count - 3, viewModel.hasMoreImages {
                viewModel.loadMoreImages()
            }
            return
        }
        if currentIndex >= images.count - 3, viewModel.hasMoreGalleryImages {
            viewModel.fetchGalleryImages(galleryId: galleryId, isInitialLoad: false)
        }
    }
}
