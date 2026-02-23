//
//  TVGalleriesView.swift
//  stashyTV
//
//  Created for tvOS on 08.02.26.
//

import SwiftUI

struct TVGalleriesView: View {
    @StateObject private var viewModel = StashDBViewModel()

    // 3-4 column adaptive grid for TV
    private let columns = [
        GridItem(.adaptive(minimum: 340, maximum: 460), spacing: 48)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Content
                if viewModel.isLoadingGalleries && viewModel.galleries.isEmpty {
                    Spacer()
                    ProgressView("Loading galleries...")
                        .font(.title2)
                    Spacer()
                } else if viewModel.galleries.isEmpty {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 72))
                            .foregroundColor(.secondary)
                        Text("No galleries found")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Button("Load Galleries") {
                            viewModel.fetchGalleries(sortBy: .dateDesc, isInitialLoad: true)
                        }
                        .font(.title3)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 48) {
                            ForEach(viewModel.galleries) { gallery in
                                NavigationLink(destination: TVGalleryDetailView(galleryId: gallery.id, galleryTitle: gallery.displayName)) {
                                    TVGalleryCardView(gallery: gallery)
                                }
                                .buttonStyle(.card)
                                .onAppear {
                                    // Pagination: load more when the last item appears
                                    if gallery.id == viewModel.galleries.last?.id && viewModel.hasMoreGalleries {
                                        viewModel.fetchGalleries(sortBy: .dateDesc, isInitialLoad: false)
                                    }
                                }
                            }

                            // Loading more indicator
                            if viewModel.isLoadingGalleries && !viewModel.galleries.isEmpty {
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
                if viewModel.galleries.isEmpty {
                    viewModel.fetchGalleries(sortBy: .dateDesc, isInitialLoad: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
                viewModel.fetchGalleries(sortBy: .dateDesc, isInitialLoad: true)
            }
        }
    }
}

// MARK: - Gallery Card for tvOS

private struct TVGalleryCardView: View {
    let gallery: Gallery

    var body: some View {
        // Square aspect ratio card
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                GeometryReader { geometry in
                    ZStack(alignment: .bottomLeading) {
                        // Cover image
                        ZStack {
                            Color.gray.opacity(0.15)

                            if let url = gallery.coverURL {
                                CustomAsyncImage(url: url) { loader in
                                    if loader.isLoading {
                                        ProgressView()
                                    } else if let image = loader.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.system(size: 48))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()

                        // Gradient overlay
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.85)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: geometry.size.height * 0.45)

                        // Top badges
                        VStack {
                            HStack(alignment: .top) {
                                // Studio badge
                                if let studio = gallery.studio {
                                    Text(studio.name)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .lineLimit(1)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(Capsule())
                                }

                                Spacer()

                                // Date badge
                                if let date = gallery.date {
                                    Text(date)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(10)

                            Spacer()
                        }

                        // Bottom content
                        HStack(alignment: .bottom) {
                            // Title
                            Text(gallery.displayName)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .shadow(radius: 2)

                            Spacer()

                            // Image count badge
                            if let count = gallery.imageCount {
                                HStack(spacing: 5) {
                                    Image(systemName: "photo")
                                        .font(.caption.weight(.bold))
                                    Text("\(count)")
                                        .font(.caption.weight(.bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.7))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(14)
                    }
                }
            )
            .background(Color(UIColor.systemGray.withAlphaComponent(0.15)))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Gallery Detail View for tvOS

struct TVGalleryDetailView: View {
    let galleryId: String
    let galleryTitle: String

    @StateObject private var viewModel = StashDBViewModel()

    // 4-5 column grid for images
    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 32)
    ]

    var body: some View {
        ScrollView {
            if viewModel.isLoadingGalleryImages && viewModel.galleryImages.isEmpty {
                VStack {
                    Spacer(minLength: 200)
                    ProgressView("Loading images...")
                        .font(.title2)
                    Spacer(minLength: 200)
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.galleryImages.isEmpty {
                VStack(spacing: 20) {
                    Spacer(minLength: 200)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("No images in this gallery")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 200)
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 32) {
                    ForEach(viewModel.galleryImages) { image in
                        NavigationLink(destination: TVFullscreenImageView(imageURL: image.imageURL, title: image.displayFilename)) {
                            TVImageThumbnailView(image: image)
                        }
                        .buttonStyle(.card)
                        .onAppear {
                            // Pagination
                            if image.id == viewModel.galleryImages.last?.id && viewModel.hasMoreGalleryImages {
                                viewModel.fetchGalleryImages(galleryId: galleryId)
                            }
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 32)
            }
        }
        .navigationTitle("")
        .onAppear {
            if viewModel.galleryImages.isEmpty {
                viewModel.fetchGalleryImages(galleryId: galleryId)
            }
        }
    }
}
