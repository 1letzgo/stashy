//
//  ImagesView.swift
//  stashy
//
//  Created by Daniel Goletz on 19.01.26.
//

#if !os(tvOS)
import SwiftUI

struct ImagesView: View {
    let gallery: Gallery?
    
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    @State private var selectedSortOption: StashDBViewModel.ImageSortOption = .dateDesc

    // Multi-Select State
    @State private var isSelectionMode = false
    @State private var selectedImageIds: Set<String> = []
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    
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
                .padding(.bottom, isSelectionMode ? 80 : 0) // Add padding for floating bar
        }
        .refreshable {
            if let gallery = gallery {
                viewModel.fetchGalleryImages(galleryId: gallery.id)
            } else {
                viewModel.fetchImages(sortBy: selectedSortOption)
            }
        }
        .navigationTitle(gallery?.title ?? "Images")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .overlay(alignment: .bottom) {
            if isSelectionMode {
                floatingDeleteBar
            }
        }
        .alert("Delete \(selectedImageIds.count) images?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSelectedImages()
            }
        } message: {
            Text("These images will be permanently deleted. This action cannot be undone.")
        }
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
        Group {
            if isSelectionMode {
                Button {
                    toggleSelection(for: image.id)
                } label: {
                    ImageThumbnailCard(image: image)
                        .overlay(
                            ZStack {
                                if selectedImageIds.contains(image.id) {
                                    Color.black.opacity(DesignTokens.Opacity.medium)
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title)
                                        .foregroundColor(appearanceManager.tintColor)
                                } else {
                                    Color.clear
                                    Image(systemName: "circle")
                                        .font(.title)
                                        .foregroundColor(.white.opacity(0.7))
                                        .shadow(radius: 2)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(destination: FullScreenImageView(images: Binding(
                    get: { displayedImages },
                    set: { newImages in
                        if gallery != nil {
                            viewModel.galleryImages = newImages
                        } else {
                            viewModel.allImages = newImages
                        }
                    }
                ), selectedImageId: image.id, onLoadMore: {
                    if let gallery = gallery {
                        viewModel.loadMoreGalleryImages(galleryId: gallery.id)
                    } else {
                        viewModel.loadMoreImages()
                    }
                })) {
                    ImageThumbnailCard(image: image)
                }
                .buttonStyle(.plain)
            }
        }
        // Pagination trigger
        .onAppear {
            if image.id == displayedImages.last?.id {
                print("Last image appeared. Loading more...")
                if let gallery = gallery {
                    viewModel.loadMoreGalleryImages(galleryId: gallery.id)
                } else {
                    viewModel.loadMoreImages()
                }
            }
        }
    }
    
    // MARK: - Multi-Select Logic
    
    private func toggleSelection(for id: String) {
        if selectedImageIds.contains(id) {
            selectedImageIds.remove(id)
        } else {
            selectedImageIds.insert(id)
        }
    }
    
    private func deleteSelectedImages() {
        isDeleting = true
        let idsToDelete = Array(selectedImageIds)
        
        // Simple batch delete (could be optimized with a dedicated batch API if available)
        // For now, we'll just iterate. This is not atomic but functional.
        let group = DispatchGroup()
        
        for id in idsToDelete {
            group.enter()
            viewModel.deleteImage(imageId: id) { _ in
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let count = idsToDelete.count
            isDeleting = false
            selectedImageIds.removeAll()
            withAnimation(DesignTokens.Animation.quick) { isSelectionMode = false }
            ToastManager.shared.show("\(count) image\(count == 1 ? "" : "s") deleted", icon: "trash", style: .success)

            // Refresh data
            if let gallery = gallery {
                viewModel.fetchGalleryImages(galleryId: gallery.id)
            } else {
                viewModel.fetchImages(sortBy: selectedSortOption)
            }
        }
    }
    
    private var floatingDeleteBar: some View {
        HStack(spacing: 16) {
             Text("\(selectedImageIds.count) Selected")
                 .font(.subheadline)
                 .fontWeight(.bold)
                 .foregroundColor(.primary)
             
             Button(role: .destructive) {
                 showDeleteConfirmation = true
             } label: {
                 Image(systemName: "trash")
                     .foregroundColor(.red)
             }
             .disabled(selectedImageIds.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.95))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        .floatingShadow()
        .padding(.bottom, 20)
    }
    
    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack {
                if isSelectionMode {
                    Button {
                         withAnimation(DesignTokens.Animation.quick) { isSelectionMode = false }
                         selectedImageIds.removeAll()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(appearanceManager.tintColor)
                    }
                } else {
                    Button {
                        withAnimation(DesignTokens.Animation.quick) { isSelectionMode = true }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(appearanceManager.tintColor)
                    }
                    
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
                        Color.gray.opacity(DesignTokens.Opacity.placeholder)
                        
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
                            .background(Color.black.opacity(DesignTokens.Opacity.medium))
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
                                     .background(Color.black.opacity(DesignTokens.Opacity.badge))
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
                                     .background(Color.black.opacity(DesignTokens.Opacity.badge))
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
                                    .background(Color.black.opacity(DesignTokens.Opacity.strong))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}
#endif
