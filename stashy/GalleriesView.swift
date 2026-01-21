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
                            NavigationLink(destination: ImagesView(gallery: gallery)) {
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
                HStack(spacing: 12) {
                    // Sort Menu with grouped options
                    Menu {
                        // Title/Name
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
                                Text("Name")
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
                                if selectedSortOption == .dateAsc || selectedSortOption == .dateDesc { Image(systemName: "checkmark") }
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

                    // Filter Menu
                    Menu {
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
                        
                        let galleryFilters = viewModel.savedFilters.values
                            .filter { $0.mode == .galleries }
                            .sorted { $0.name < $1.name }
                        
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
            selectedFilter = nil
            performSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.galleries.rawValue {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .galleries),
                   let newFilter = viewModel.savedFilters[defaultId] {
                    selectedFilter = newFilter
                } else {
                    selectedFilter = nil
                }
                performSearch()
            }
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // Apply default filter if set and none selected yet
            if selectedFilter == nil {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .galleries),
                   let filter = newValue[defaultId] {
                    selectedFilter = filter
                    performSearch()
                } else if !viewModel.isLoadingSavedFilters {
                    // Default filter was set but not found, or filters finished loading and none match
                    performSearch()
                }
            }
        }
    }
}

struct GalleryCardView: View {
    let gallery: Gallery
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                GeometryReader { geometry in
                    ZStack(alignment: .bottomLeading) {
                        // Image (Strictly filling the square)
                        ZStack {
                            Color.gray.opacity(0.2)

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
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        
                        // Gradient Overlay
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: geometry.size.height * 0.4)
                        
                        // Badges Overlay Layer
                        VStack {
                            HStack(alignment: .top) {
                                // Studio Badge (Top Left)
                                if let studio = gallery.studio {
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
                                if let date = gallery.date {
                                    Text(date)
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
                            
                            HStack(alignment: .bottom) {
                                // Info Section (Bottom Left Title)
                                Text(gallery.displayName)
                                   .font(.system(size: geometry.size.width * 0.08, weight: .bold))
                                   .foregroundColor(.white)
                                   .lineLimit(1)
                                   .shadow(radius: 2)
                                
                                Spacer()
                                
                                // Image Count Badge (Bottom Right)
                                if let count = gallery.imageCount {
                                    HStack(spacing: 3) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("\(count)")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(8)
                        }
                    }
                }
            )
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12)) // Ensure hit testing works on entire card
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}


struct FullScreenImageView: View {
    @Binding var images: [StashImage]
    @State var selectedImageId: String
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Image Pager
            TabView(selection: $selectedImageId) {
                ForEach(images) { image in
                    ZoomableScrollView {
                        if let url = image.imageURL {
                            CustomAsyncImage(url: url) { loader in
                                if let data = loader.imageData, isGIF(data) {
                                    GIFView(data: data)
                                        .frame(maxWidth: .infinity)
                                } else if let img = loader.image {
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
                    .tag(image.id)
                    .ignoresSafeArea()
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .ignoresSafeArea()
            
            // Metadata Overlay (Bottom)
            if let image = images.first(where: { $0.id == selectedImageId }) {
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            // Performer Link
                            if let performers = image.performers, let firstPerf = performers.first {
                                let performerObj = Performer(
                                    id: firstPerf.id, name: firstPerf.name, disambiguation: nil, birthdate: nil, country: nil, imagePath: nil, sceneCount: 0, galleryCount: nil, gender: nil, ethnicity: nil, height: nil, weight: nil, measurements: nil, fakeTits: nil, careerLength: nil, tattoos: nil, piercings: nil, aliasList: nil, favorite: nil, rating100: nil, createdAt: nil, updatedAt: nil
                                )
                                 NavigationLink(destination: PerformerDetailView(performer: performerObj)) {
                                    Text(firstPerf.name)
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                }
                                .buttonStyle(.plain)
                                
                                Text("-")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            
                            // Gallery Link
                            if let galleries = image.galleries, let gallery = galleries.first {
                                 let galleryObj = Gallery(id: gallery.id, title: gallery.title ?? "Gallery", date: nil, details: nil, imageCount: nil, organized: nil, createdAt: nil, updatedAt: nil, studio: nil, performers: nil, cover: nil)
                                 
                                 NavigationLink(destination: ImagesView(gallery: galleryObj)) {
                                     Text(gallery.title ?? "Unknown Gallery")
                                         .font(.body)
                                         .fontWeight(.semibold)
                                         .foregroundColor(.white)
                                         .lineLimit(1)
                                         .shadow(radius: 2)
                                 }
                                 .buttonStyle(.plain)
                            } else {
                                 // Fallback Title if no gallery
                                 Text(image.title ?? "Image")
                                     .font(.body)
                                     .fontWeight(.semibold)
                                     .foregroundColor(.white)
                                     .lineLimit(1)
                                     .shadow(radius: 2)
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(appearanceManager.tintColor)
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
        guard let currentIndex = images.firstIndex(where: { $0.id == selectedImageId }) else { return }
        let imageToDelete = images[currentIndex]
        
        // Find next ID before deletion
        let nextId: String?
        if images.count > 1 {
            if currentIndex < images.count - 1 {
                nextId = images[currentIndex + 1].id
            } else {
                nextId = images[currentIndex - 1].id
            }
        } else {
            nextId = nil
        }
        
        viewModel.deleteImage(imageId: imageToDelete.id) { success in
            DispatchQueue.main.async {
                if success {
                    // Update selection to next image first
                    if let nextId = nextId {
                        selectedImageId = nextId
                    }
                    
                    // Remove from binding - will update parent view automatically
                    images.removeAll { $0.id == imageToDelete.id }
                    
                    // Exit if empty
                    if images.isEmpty {
                        dismiss()
                    }
                }
            }
        }
    }
}
