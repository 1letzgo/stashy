//
//  TVImagesView.swift
//  stashyTV
//
//  Created for tvOS on 08.02.26.
//

import SwiftUI

struct TVImagesView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @State private var selectedSortOption: StashDBViewModel.ImageSortOption = .dateDesc

    // 4-5 column grid for image thumbnails
    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 32)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Content
                if viewModel.isLoadingImages && viewModel.allImages.isEmpty {
                    Spacer()
                    ProgressView("Loading images...")
                        .font(.title2)
                    Spacer()
                } else if viewModel.allImages.isEmpty {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 72))
                            .foregroundColor(.secondary)
                        Text("No images found")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Button("Load Images") {
                            viewModel.fetchImages(sortBy: selectedSortOption, isInitialLoad: true)
                        }
                        .font(.title3)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 32) {
                            ForEach(viewModel.allImages) { image in
                                NavigationLink(destination: TVFullscreenImageView(imageURL: image.imageURL, title: image.displayFilename)) {
                                    TVImageThumbnailView(image: image)
                                }
                                .buttonStyle(.card)
                                .onAppear {
                                    // Pagination: load more when the last item appears
                                    if image.id == viewModel.allImages.last?.id && viewModel.hasMoreImages {
                                        viewModel.loadMoreImages()
                                    }
                                }
                            }

                            // Loading more indicator
                            if viewModel.isLoadingImages && !viewModel.allImages.isEmpty {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                            }
                        }
                        .padding(.horizontal, 48)
                        .padding(.top, 40)
                        .padding(.bottom, 80)
                    }
                }
            }
            .onAppear {
                if viewModel.allImages.isEmpty {
                    viewModel.fetchImages(sortBy: selectedSortOption, isInitialLoad: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
                viewModel.fetchImages(sortBy: selectedSortOption, isInitialLoad: true)
            }
        }
    }
}

// MARK: - Image Thumbnail View (Shared between TVImagesView and TVGalleryDetailView)

struct TVImageThumbnailView: View {
    let image: StashImage

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    GeometryReader { geometry in
                        ZStack {
                            Color.gray.opacity(0.15)

                            if let url = image.thumbnailURL {
                                CustomAsyncImage(url: url) { loader in
                                    if loader.isLoading {
                                        ProgressView()
                                    } else if let image = loader.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: geometry.size.width, height: geometry.size.height)
                                            .clipped()
                                    } else {
                                        Image(systemName: "photo")
                                            .font(.system(size: 40))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                )

            // Bottom gradient for text readability
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.7)]),
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 80)

            // Title overlay
            VStack(alignment: .leading, spacing: 4) {
                Spacer()

                if let title = image.title, !title.isEmpty {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .shadow(radius: 2)
                }

                HStack(spacing: 12) {
                    // Rating stars (compact)
                    if let rating100 = image.rating100, rating100 > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text("\(rating100 / 20)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }

                    // O-Counter
                    if let oCounter = image.o_counter, oCounter > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.pink)
                            Text("\(oCounter)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(Color(UIColor.systemGray.withAlphaComponent(0.15)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Fullscreen Image View

struct TVFullscreenImageView: View {
    let imageURL: URL?
    let title: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = imageURL {
                CustomAsyncImage(url: url) { loader in
                    if loader.isLoading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(2)
                    } else if let image = loader.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 64))
                                .foregroundColor(.white.opacity(0.6))
                            Text("Failed to load image")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "photo")
                        .font(.system(size: 64))
                        .foregroundColor(.white.opacity(0.6))
                    Text("No image URL available")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .navigationTitle(title)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
