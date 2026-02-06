//
//  ImagesView.swift
//  stashy
//
//  Created by Daniel Goletz on 19.01.26.
//

import SwiftUI

struct ImagesView: View {
    let gallery: Gallery?
    
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    @State private var selectedSortOption: StashDBViewModel.ImageSortOption = .dateDesc
    
    init(gallery: Gallery? = nil) {
        self.gallery = gallery
    }
    
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
    
    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.ImageSortOption) {
        selectedSortOption = newOption
        
        // Save to TabManager
        TabManager.shared.setSortOption(for: .images, option: newOption.rawValue)
        
        // Fetch new data immediately
        if let gallery = gallery {
             viewModel.fetchGalleryImages(galleryId: gallery.id)
        } else {
             viewModel.fetchImages(sortBy: newOption)
        }
    }

    var body: some View {
        ScrollView {
            gridContent
                .padding(16)
        }
        .navigationTitle(gallery?.title ?? "Images")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .onAppear {
            // Apply default sort option
            let defaultSortStr = TabManager.shared.getPersistentSortOption(for: .images) ?? "dateDesc"
            if let defaultSort = StashDBViewModel.ImageSortOption(rawValue: defaultSortStr) {
                 selectedSortOption = defaultSort
                 viewModel.currentImageSortOption = defaultSort
            }

            if let gallery = gallery {
                if viewModel.galleryImages.isEmpty {
                    viewModel.fetchGalleryImages(galleryId: gallery.id)
                }
            } else {
                if viewModel.allImages.isEmpty {
                    viewModel.fetchImages(sortBy: selectedSortOption)
                }
            }
        }
        .toolbar {
            navigationToolbar
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ImageDeleted"))) { notification in
            if let imageId = notification.userInfo?["imageId"] as? String {
                viewModel.removeImage(id: imageId)
            }
        }
    }
    
    private var displayedImages: [StashImage] {
        gallery != nil ? viewModel.galleryImages : viewModel.allImages
    }
    
    @ViewBuilder
    private var gridContent: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(displayedImages) { image in
                imageCell(image)
            }
            
            // Loading Indicator
            if viewModel.isLoadingImages || viewModel.isLoadingGalleryImages {
                ProgressView()
                    .padding()
            }
        }
    }
    
    @ViewBuilder
    private func imageCell(_ image: StashImage) -> some View {
        NavigationLink(destination: FullScreenImageView(images: Binding(
            get: { displayedImages },
            set: { _ in } // images are generally read-only from this view
        ), selectedImageId: image.id)) {
            ImageThumbnailCard(image: image)
                .onAppear {
                    if image.id == displayedImages.last?.id {
                        if let gallery = gallery {
                            viewModel.loadMoreGalleryImages(galleryId: gallery.id)
                        } else {
                            viewModel.loadMoreImages()
                        }
                    }
                }
        }
        .buttonStyle(.plain)
    }
    
    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                // Title
                Menu {
                    Button(action: { changeSortOption(to: .titleAsc) }) {
                        HStack {
                            Text("A → Z")
                            if selectedSortOption == .titleAsc { Image(systemName: "checkmark") }
                        }
                    }
                    Button(action: { changeSortOption(to: .titleDesc) }) {
                        HStack {
                            Text("Z → A")
                            if selectedSortOption == .titleDesc { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    HStack {
                        Text("Title")
                        if selectedSortOption == .titleAsc || selectedSortOption == .titleDesc { Image(systemName: "checkmark") }
                    }
                }
                
                // Date
                Menu {
                    Button(action: { changeSortOption(to: .dateDesc) }) {
                        HStack {
                            Text("Newest First")
                            if selectedSortOption == .dateDesc { Image(systemName: "checkmark") }
                        }
                    }
                    Button(action: { changeSortOption(to: .dateAsc) }) {
                        HStack {
                            Text("Oldest First")
                            if selectedSortOption == .dateAsc { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    HStack {
                        Text("Date")
                        if selectedSortOption == .dateDesc || selectedSortOption == .dateAsc { Image(systemName: "checkmark") }
                    }
                }
                
                // Rating
                Menu {
                    Button(action: { changeSortOption(to: .ratingDesc) }) {
                        HStack {
                            Text("High → Low")
                            if selectedSortOption == .ratingDesc { Image(systemName: "checkmark") }
                        }
                    }
                    Button(action: { changeSortOption(to: .ratingAsc) }) {
                        HStack {
                            Text("Low → High")
                            if selectedSortOption == .ratingAsc { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    HStack {
                        Text("Rating")
                        if selectedSortOption == .ratingDesc || selectedSortOption == .ratingAsc { Image(systemName: "checkmark") }
                    }
                }
                
                // Created
                Menu {
                    Button(action: { changeSortOption(to: .createdAtDesc) }) {
                        HStack {
                            Text("Newest First")
                            if selectedSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                        }
                    }
                    Button(action: { changeSortOption(to: .createdAtAsc) }) {
                        HStack {
                            Text("Oldest First")
                            if selectedSortOption == .createdAtAsc { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    HStack {
                        Text("Created")
                        if selectedSortOption == .createdAtDesc || selectedSortOption == .createdAtAsc { Image(systemName: "checkmark") }
                    }
                }
                
                // Updated
                Menu {
                    Button(action: { changeSortOption(to: .updatedAtDesc) }) {
                        HStack {
                            Text("Newest First")
                            if selectedSortOption == .updatedAtDesc { Image(systemName: "checkmark") }
                        }
                    }
                    Button(action: { changeSortOption(to: .updatedAtAsc) }) {
                        HStack {
                            Text("Oldest First")
                            if selectedSortOption == .updatedAtAsc { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    HStack {
                        Text("Updated")
                        if selectedSortOption == .updatedAtDesc || selectedSortOption == .updatedAtAsc { Image(systemName: "checkmark") }
                    }
                }
                
                // Random
                Button(action: { changeSortOption(to: .random) }) {
                    HStack {
                        Text("Random")
                        if selectedSortOption == .random { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .foregroundColor(.appAccent)
            }
        }
    }
}

struct ImageThumbnailCard: View {
    let image: StashImage
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    // Image
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
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    
                    // Video Play Icon Overlay
                    if image.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // Gradient Overlay
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.height * 0.5)
                    
                    // Badges Layer
                    VStack {
                        // Top Badges
                        HStack(alignment: .top) {
                             // Studio (Top Left)
                             if let studio = image.studio {
                                 Text(studio.name)
                                     .font(.system(size: 8, weight: .bold))
                                     .lineLimit(1)
                                     .foregroundColor(.white)
                                     .padding(.horizontal, 5)
                                     .padding(.vertical, 2)
                                     .background(Color.black.opacity(0.6))
                                     .clipShape(Capsule())
                             }
                             
                             Spacer()
                             
                             // Date (Top Right)
                             if let date = image.date {
                                 Text(date)
                                     .font(.system(size: 8, weight: .bold))
                                     .lineLimit(1)
                                     .foregroundColor(.white)
                                     .padding(.horizontal, 5)
                                     .padding(.vertical, 2)
                                     .background(Color.black.opacity(0.6))
                                     .clipShape(Capsule())
                             }
                        }
                        .padding(6)
                        
                        Spacer()
                        
                        // Bottom Layer
                        HStack(alignment: .bottom) {
                            // Performer Name (Bottom Left)
                            if let performers = image.performers, let first = performers.first {
                                Text(first.name)
                                    .font(.system(size: geometry.size.width * 0.08, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .shadow(radius: 2)
                            } else {
                                // Fallback to title/filename
                                Text(image.title ?? "Image")
                                    .font(.system(size: geometry.size.width * 0.08, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .shadow(radius: 2)
                            }
                            
                            Spacer()
                            
                            // Format Badge (Bottom Right)
                            if let ext = image.fileExtension {
                                Text(ext)
                                    .font(.system(size: 8, weight: .bold))
                                    .lineLimit(1)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.8))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}
