//
//  GalleriesView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI

struct GalleriesView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.GallerySortOption = StashDBViewModel.GallerySortOption(rawValue: TabManager.shared.getSortOption(for: .galleries) ?? "") ?? .dateDesc
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var scrollPosition: String? = nil
    @State private var shouldRestoreScroll = false
    var hideTitle: Bool = false
    
    // Grid Setup
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // Dynamische Spalten
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
    private func changeSortOption(to newOption: StashDBViewModel.GallerySortOption) {
        selectedSortOption = newOption
        scrollPosition = nil
        shouldRestoreScroll = false
        
        // Save to TabManager
        TabManager.shared.setSortOption(for: .galleries, option: newOption.rawValue)
        
        // Fetch new data immediately
        viewModel.fetchGalleries(sortBy: newOption, searchQuery: searchText, isInitialLoad: true, filter: selectedFilter)
    }

    private func performSearch(isInitialLoad: Bool = true) {
        viewModel.fetchGalleries(sortBy: selectedSortOption, searchQuery: searchText, isInitialLoad: isInitialLoad, filter: selectedFilter)
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.isLoadingGalleries && viewModel.galleries.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading galleries...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.galleries.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.galleries.isEmpty {
                SharedEmptyStateView(
                    icon: "photo.stack",
                    title: "No galleries found",
                    buttonText: "Reload",
                    onRetry: { performSearch() }
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.galleries) { gallery in
                            NavigationLink(destination: GalleryDetailView(gallery: gallery)) {
                                GalleryCardView(gallery: gallery)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Loading Indicator / Infinite Scroll
                        if viewModel.isLoadingGalleries {
                            ProgressView()
                                .padding()
                        } else if viewModel.hasMoreGalleries {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    viewModel.loadMoreGalleries(searchQuery: searchText)
                                }
                        }
                    }
                    .padding(16)
                }
                .background(Color.appBackground)
            }
        }
        .navigationTitle(hideTitle ? "" : "Galleries")
        .navigationBarTitleDisplayMode(.inline)
        .conditionalSearchable(isVisible: isSearchVisible, text: $searchText, prompt: "Search galleries...")
        .onChange(of: searchText) { oldValue, newValue in
            // Debounce
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if newValue == self.searchText {
                    performSearch()
                }
            }
        }
        .toolbar {
            if !searchText.isEmpty {
                ToolbarItem(placement: .principal) {
                    Button(action: {
                        searchText = ""
                        performSearch()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                            Text(searchText)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 0) {


                    Menu {
                        Section {
                            let galleryFilters = viewModel.savedFilters.values
                            .filter { $0.mode == .galleries }
                            .sorted { $0.name < $1.name }
                        
                        Button(action: {
                            selectedFilter = nil
                            performSearch()
                        }) {
                            HStack {
                                Text("No Filter")
                                if selectedFilter == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        ForEach(galleryFilters) { filter in
                            Button(action: {
                                selectedFilter = filter
                                performSearch()
                            }) {
                                HStack {
                                    Text(filter.name)
                                    if selectedFilter?.id == filter.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Saved Filters")
                    }

                    Section {
                        ForEach(StashDBViewModel.GallerySortOption.allCases, id: \.self) { option in
                            Button(action: {
                                changeSortOption(to: option)
                            }) {
                                HStack {
                                    Text(option.displayName)
                                    if option == selectedSortOption {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Sort By")
                    }
                    } label: {
                        Image(systemName: selectedFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(selectedFilter != nil ? .appAccent : .primary)
                    }
                }
            }
        }
        .onAppear {
            // Check for search text from navigation
            if !coordinator.activeSearchText.isEmpty {
                searchText = coordinator.activeSearchText
                isSearchVisible = true
                coordinator.activeSearchText = ""
                performSearch()
                viewModel.fetchSavedFilters()
                return
            }
            
            if TabManager.shared.getDefaultFilterId(for: .galleries) == nil || !viewModel.savedFilters.isEmpty {
                if viewModel.galleries.isEmpty {
                    performSearch()
                }
            }
            viewModel.fetchSavedFilters()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            performSearch()
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // Apply default filter if set and none selected yet
            if selectedFilter == nil, let defaultId = TabManager.shared.getDefaultFilterId(for: .galleries) {
                if let filter = newValue[defaultId] {
                    selectedFilter = filter
                    performSearch()
                }
            }
        }
    }
}

struct GalleryCardView: View {
    let gallery: Gallery
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Image
            GeometryReader { geometry in
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))

                    if let url = gallery.coverURL {
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
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit) 
            
            // Gradient Overlay
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
            
            // Top Badges
            VStack {
                HStack {
                    // Studio Badge (Top Left)
                    if let studio = gallery.studio {
                        HStack(spacing: 3) {
                            Image(systemName: "building.2")
                                .font(.system(size: 10, weight: .bold))
                            Text(studio.name)
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 2)
                    }
                    
                    Spacer()
                    
                    // Count Badge (Top Right)
                    if let count = gallery.imageCount {
                        HStack(spacing: 3) {
                            Image(systemName: "photo")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 2)
                    }
                }
                .padding(8)
                
                Spacer()
                
                HStack {
                    Spacer()
                    
                    // Performer Count Badge (Bottom Right)
                    if let performers = gallery.performers, !performers.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(performers.count)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 2)
                        .padding(8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Info Section (Bottom Title)
            VStack(alignment: .leading, spacing: 4) {
                 Text(gallery.displayName)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct GalleryDetailView: View {
    let gallery: Gallery
    @StateObject private var viewModel = StashDBViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var selectedSortOption: StashDBViewModel.ImageSortOption = StashDBViewModel.ImageSortOption(rawValue: TabManager.shared.getDetailSortOption(for: "gallery_detail") ?? "") ?? .dateDesc
    
    private func changeSortOption(to newOption: StashDBViewModel.ImageSortOption) {
        selectedSortOption = newOption
        // Save to TabManager (Session)
        TabManager.shared.setDetailSortOption(for: "gallery_detail", option: newOption.rawValue)
        viewModel.fetchGalleryImages(galleryId: gallery.id, sortBy: newOption, isInitialLoad: true)
    }

    // Grid Setup
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
        Group {
            if viewModel.isLoadingGalleryImages && viewModel.galleryImages.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading images...")
                    Spacer()
                }
            } else if viewModel.galleryImages.isEmpty && !viewModel.isLoadingGalleryImages {
                SharedEmptyStateView(
                    icon: "photo.on.rectangle",
                    title: "No images found",
                    buttonText: "Reload",
                    onRetry: { 
                        viewModel.fetchGalleryImages(galleryId: gallery.id, sortBy: selectedSortOption, isInitialLoad: true)
                    }
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(viewModel.galleryImages.enumerated()), id: \.element.id) { index, image in
                            NavigationLink(destination: FullScreenImageView(images: $viewModel.galleryImages, currentIndex: index)) {
                                GalleryImageCard(image: image)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.isLoadingGalleryImages {
                            ProgressView()
                                .padding()
                        } else if viewModel.hasMoreGalleryImages {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    viewModel.loadMoreGalleryImages(galleryId: gallery.id)
                                }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(gallery.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel.galleryImages.isEmpty {
                viewModel.fetchGalleryImages(galleryId: gallery.id, sortBy: selectedSortOption)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(StashDBViewModel.ImageSortOption.allCases, id: \.self) { option in
                        Button(action: {
                            changeSortOption(to: option)
                        }) {
                            HStack {
                                Text(option.displayName)
                                if option == selectedSortOption {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundColor(.appAccent)
                }
            }
        }
    }
}

struct GalleryImageCard: View {
    let image: StashImage
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    Rectangle().fill(Color.gray.opacity(0.1))
                    
                    if let url = image.thumbnailURL {
                        CustomAsyncImage(url: url) { loader in
                             if let img = loader.image {
                                 img.resizable().scaledToFill()
                             } else {
                                 ProgressView()
                             }
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.width) // Square
                .clipped()
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct FullScreenImageView: View {
    @Binding var images: [StashImage]
    @State var currentIndex: Int
    @StateObject private var viewModel = StashDBViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            TabView(selection: $currentIndex) {
                ForEach(images.indices, id: \.self) { (index: Int) in
                    ZStack {
                        if let url = images[index].imageURL {
                            CustomAsyncImage(url: url) { loader in
                                if let img = loader.image {
                                    img
                                        .resizable()
                                        .scaledToFit()
                                } else if loader.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    VStack(spacing: 12) {
                                        Image(systemName: "exclamationmark.triangle")
                                            .font(.largeTitle)
                                            .foregroundColor(.white)
                                        Text("Failed to load image")
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .alert("Really delete image?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCurrentImage()
            }
        } message: {
            Text("This image will be permanently deleted. This action cannot be undone.")
        }
    }
    
    private func deleteCurrentImage() {
        guard currentIndex < images.count else { return }
        let imageToDelete = images[currentIndex]
        
        viewModel.deleteImage(imageId: imageToDelete.id) { success in
            if success {
                DispatchQueue.main.async {
                    // Remove from binding - will update parent view automatically
                    images.remove(at: currentIndex)
                    
                    // Navigate back or adjust index
                    if images.isEmpty {
                        dismiss()
                    } else if currentIndex >= images.count {
                        currentIndex = images.count - 1
                    }
                }
            }
        }
    }
}
