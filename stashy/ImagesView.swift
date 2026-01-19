//
//  ImagesView.swift
//  stashy
//
//  Created by Daniel Goletz on 19.01.26.
//

import SwiftUI

struct ImagesView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // Dynamic Columns to match GalleriesView
    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            // iPad: 4 columns
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
            // iPhone: 2 columns
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
    }
    
    var body: some View {
        ScrollView {
            gridContent
                .padding(16)
        }
        .navigationTitle("Images")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .onAppear {
            if viewModel.allImages.isEmpty {
                viewModel.fetchImages()
            }
        }
        .toolbar {
            navigationToolbar
        }
    }
    
    @ViewBuilder
    private var gridContent: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.allImages) { image in
                imageCell(image)
            }
            
            // Loading Indicator
            if viewModel.isLoadingImages {
                ProgressView()
                    .padding()
            }
        }
    }
    
    @ViewBuilder
    private func imageCell(_ image: StashImage) -> some View {
        // Calculate index safely
        let index = viewModel.allImages.firstIndex(where: { $0.id == image.id }) ?? 0
        
        NavigationLink(destination: FullScreenImageView(images: $viewModel.allImages, currentIndex: index)) {
            ImageThumbnailCard(image: image)
                .onAppear {
                    if image.id == viewModel.allImages.last?.id {
                        viewModel.loadMoreImages()
                    }
                }
        }
        .buttonStyle(.plain)
    }
    
    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Picker("Sort By", selection: Binding(
                    get: { viewModel.currentImageSortOption },
                    set: { viewModel.fetchImages(sortBy: $0) }
                )) {
                    ForEach(StashDBViewModel.ImageSortOption.allCases, id: \.self) { option in
                        Text(option.rawValue.capitalized).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
    }
}

struct ImageThumbnailCard: View {
    let image: StashImage
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    // Image (Strictly filling the square)
                    ZStack {
                        Color.gray.opacity(0.1)
                        
                        if let url = image.thumbnailURL {
                            CustomAsyncImage(url: url) { loader in
                                if loader.isLoading {
                                    ProgressView()
                                } else if let uiImage = loader.image {
                                    uiImage
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "photo")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.width)
                    .clipped()
                    
                    // Gradient Overlay (Bottom)
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.width * 0.4)
                    
                    // Top Pills Overlay
                    VStack {
                        HStack(alignment: .top) {
                            // Studio Badge (Top Left)
                            if let studio = image.studio {
                                Text(studio.name)
                                    .font(.system(size: 9, weight: .bold))
                                    .lineLimit(1)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Capsule())
                            }
                            
                            Spacer()
                            
                            // Date Badge (Top Right)
                            if !image.formattedDate.isEmpty {
                                Text(image.formattedDate)
                                    .font(.system(size: 9, weight: .bold))
                                    .lineLimit(1)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(6)
                        
                        Spacer()
                    }
                    
                    // Metadata Overlay (Bottom)
                    VStack(alignment: .leading, spacing: 2) {
                        // Performer (Top priority)
                        if let performers = image.performers, let performer = performers.first {
                            Text(performer.name)
                                .font(.system(size: geometry.size.width * 0.08, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .shadow(radius: 2)
                        }
                    }
                    .padding(8)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}
