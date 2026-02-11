//
//  GalleriesView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

#if !os(tvOS)
import SwiftUI
import AVKit
import AVFoundation

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
                .refreshable { performSearch() }
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
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            performSearch()
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
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
            if oldValue == true && isLoading == false {
                if viewModel.galleries.isEmpty && !viewModel.isLoadingGalleries && selectedFilter == nil {
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
                                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
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
                                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
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
                                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(8)
                        }
                    }
                }
            )
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)) // Ensure hit testing works on entire card
            .cardShadow()
    }
}

// MARK: - Gallery Item View (StashTok-style per-item view)

struct GalleryItemView: View {
    let image: StashImage
    @Binding var isMuted: Bool
    @ObservedObject var viewModel: StashDBViewModel
    @Binding var images: [StashImage]

    // Playback State
    @State private var player: AVPlayer?
    @State private var isPlaying = true
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 1.0
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    @State private var showRatingOverlay = false
    @State private var showUI = true
    @State private var uiHideTask: Task<Void, Never>? = nil

    private var isGIFImage: Bool {
        image.fileExtension?.uppercased() == "GIF"
    }

    private var isPortrait: Bool {
        if let file = image.visual_files?.first {
            return (file.height ?? 0) > (file.width ?? 0)
        }
        return false
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Media layer — matches ReelItemView pattern exactly
            Group {
                if isGIFImage {
                    ZoomableScrollView {
                        if let url = image.imageURL {
                            CustomAsyncImage(url: url) { loader in
                                if let data = loader.imageData, isGIF(data) {
                                    GIFView(data: data)
                                        .frame(maxWidth: .infinity)
                                } else if let img = loader.image {
                                    img
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else if loader.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                } else if image.isVideo {
                    if let player = player {
                        FullScreenVideoPlayer(player: player, videoGravity: isPortrait ? .resizeAspectFill : .resizeAspect)
                            .onTapGesture {
                                if !showUI {
                                    resetUITimer()
                                } else {
                                    isPlaying.toggle()
                                    if isPlaying { player.play() } else { player.pause() }
                                    resetUITimer()
                                }
                            }
                    } else {
                        if let url = image.thumbnailURL {
                            AsyncImage(url: url) { img in
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: isPortrait ? .fill : .fit)
                            } placeholder: {
                                ProgressView()
                                    .tint(.white)
                            }
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                } else {
                    // Static image
                    ZoomableScrollView {
                        if let url = image.imageURL {
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            // Center Play Icon
            if image.isVideo && !isPlaying {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.7))
                            .shadow(radius: 10)
                        Spacer()
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isPlaying = true
                    player?.play()
                    resetUITimer()
                }
            }

            // Sidebar layer (Right side)
            VStack(alignment: .trailing, spacing: 20) {
                Spacer()

                // Rating Button
                let rating = image.rating100 ?? 0
                SidebarButton(
                    icon: "star",
                    label: "Rating",
                    count: rating > 0 ? (rating / 20) : 0,
                    color: .white
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showRatingOverlay.toggle()
                    }
                    resetUITimer()
                }
                .overlay(alignment: .top) {
                    if showRatingOverlay {
                        VStack {
                            StarRatingView(
                                rating100: rating,
                                isInteractive: true,
                                size: 25,
                                spacing: 8,
                                isVertical: true
                            ) { newRating in
                                // Optimistic update
                                if let index = images.firstIndex(where: { $0.id == image.id }) {
                                    let original = images[index].rating100
                                    images[index] = images[index].withRating(newRating)

                                    viewModel.updateImageRating(imageId: image.id, rating100: newRating) { success in
                                        if !success {
                                            DispatchQueue.main.async {
                                                images[index] = images[index].withRating(original)
                                                ToastManager.shared.show("Failed to save rating", icon: "exclamationmark.triangle", style: .error)
                                            }
                                        }
                                    }
                                }
                                resetUITimer()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        showRatingOverlay = false
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(Color.black.opacity(DesignTokens.Opacity.strong))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .offset(y: -150)
                        .transition(.scale(scale: 0, anchor: .top).combined(with: .opacity))
                    }
                }

                // O-Counter
                // O-Counter
                SidebarButton(
                    icon: AppearanceManager.shared.oCounterIcon,
                    label: "Counter",
                    count: image.o_counter ?? 0,
                    color: .white
                ) {
                    // Direct update to the binding array
                    if let index = images.firstIndex(where: { $0.id == image.id }) {
                        let originalCount = images[index].o_counter ?? 0
                        let newCount = originalCount + 1
                        
                        // Optimistic UI update
                        images[index] = images[index].withOCounter(newCount)
                        
                        viewModel.incrementImageOCounter(imageId: image.id) { returnedCount in
                            if let count = returnedCount {
                                DispatchQueue.main.async {
                                    images[index] = images[index].withOCounter(count)
                                }
                            } else {
                                DispatchQueue.main.async {
                                    if let revertIndex = images.firstIndex(where: { $0.id == image.id }) {
                                        images[revertIndex] = images[revertIndex].withOCounter(originalCount)
                                    }
                                    ToastManager.shared.show("Counter update failed", icon: "exclamationmark.triangle", style: .error)
                                }
                            }
                        }
                    }
                    resetUITimer()
                }
                .contentShape(Rectangle()) // Ensure good hit target

                // Mute Button (video only)
                if image.isVideo {
                    SidebarButton(
                        icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: isMuted ? "Muted" : "Mute",
                        count: 0,
                        hideCount: true,
                        color: .white
                    ) {
                        isMuted.toggle()
                        resetUITimer()
                    }
                }

                Spacer()
                    .frame(height: 0)
            }
            .frame(maxWidth: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 12)
            .padding(.bottom, 135)
            .opacity(showUI ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: showUI)

            // Metadata + Scrubber overlay
            VStack(alignment: .leading, spacing: 6) {
                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    // Row 1: Performer • Gallery
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let performers = image.performers, let firstPerf = performers.first {
                            let performerObj = Performer(
                                id: firstPerf.id, name: firstPerf.name, disambiguation: nil, birthdate: nil, country: nil, imagePath: nil, sceneCount: 0, galleryCount: nil, gender: nil, ethnicity: nil, height: nil, weight: nil, measurements: nil, fakeTits: nil, careerLength: nil, tattoos: nil, piercings: nil, aliasList: nil, favorite: nil, rating100: nil, createdAt: nil, updatedAt: nil
                            )
                            NavigationLink(destination: PerformerDetailView(performer: performerObj)) {
                                Text(firstPerf.name)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)

                            if let galleries = image.galleries, let gallery = galleries.first {
                                Text("•")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                                let galleryObj = Gallery(id: gallery.id, title: gallery.title ?? "Gallery", date: nil, details: nil, imageCount: nil, organized: nil, createdAt: nil, updatedAt: nil, studio: nil, performers: nil, cover: nil)

                                NavigationLink(destination: ImagesView(gallery: galleryObj)) {
                                    Text(gallery.title ?? "Unknown Gallery")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                }
                                .buttonStyle(.plain)
                            }
                        } else if let galleries = image.galleries, let gallery = galleries.first {
                            let galleryObj = Gallery(id: gallery.id, title: gallery.title ?? "Gallery", date: nil, details: nil, imageCount: nil, organized: nil, createdAt: nil, updatedAt: nil, studio: nil, performers: nil, cover: nil)

                            NavigationLink(destination: ImagesView(gallery: galleryObj)) {
                                Text(gallery.title ?? "Unknown Gallery")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Row 2: Title
                    if let title = image.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }

                    // Row 3: Tags
                    if let tags = image.tags, !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tags) { tag in
                                    Text("#\(tag.name)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Video scrubber
                if image.isVideo {
                    CustomVideoScrubber(
                        value: Binding(get: { currentTime }, set: { val in
                            currentTime = val
                            seek(to: val)
                        }),
                        total: duration,
                        onEditingChanged: { editing in
                            isSeeking = editing
                            if editing {
                                player?.pause()
                            } else {
                                if isPlaying { player?.play() }
                                resetUITimer()
                            }
                        }
                    )
                    .padding(.bottom, 0)
                }
            }
            .padding(.bottom, 95)
            .opacity(showUI ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: showUI)
        }
        .background(Color.black)
        .onAppear {
            if image.isVideo {
                setupPlayer()
            }
            resetUITimer()
        }
        .onDisappear {
            player?.pause()
            if let timeObserver = timeObserver {
                player?.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
        }
        .onChange(of: isMuted) { _, newValue in
            player?.isMuted = newValue
        }
    }

    // MARK: - Player Setup (matches ReelItemView.initPlayer)

    private func initPlayer(with streamURL: URL) {
        let headers = ["ApiKey": ServerConfigManager.shared.activeConfig?.secureApiKey ?? ""]
        let asset = AVURLAsset(url: streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let newItem = AVPlayerItem(asset: asset)

        if let existingPlayer = self.player {
            // Reuse existing player to prevent FullScreenVideoPlayer re-renders
            if let observer = timeObserver {
                existingPlayer.removeTimeObserver(observer)
                self.timeObserver = nil
            }
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: existingPlayer.currentItem)
            existingPlayer.replaceCurrentItem(with: newItem)
        } else {
            self.player = createPlayer(for: streamURL)
        }

        guard let player = self.player else { return }

        player.isMuted = isMuted
        if isPlaying { player.play() }

        // Loop on end
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            player.seek(to: .zero)
            player.play()
        }

        // Time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            if !self.isSeeking {
                self.currentTime = time.seconds
            }
            if let d = player.currentItem?.duration.seconds, d > 0, !d.isNaN {
                self.duration = d
            }
        }
    }

    private func setupPlayer() {
        guard let url = image.imageURL else { return }
        initPlayer(with: url)
    }

    private func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
    }

    private func resetUITimer() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showUI = true
        }

        uiHideTask?.cancel()
        uiHideTask = Task {
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            guard !Task.isCancelled else { return }

            if !showRatingOverlay && !isSeeking {
                withAnimation(.easeInOut(duration: 0.8)) {
                    showUI = false
                }
            } else if !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                if !Task.isCancelled {
                    resetUITimer()
                }
            }
        }
    }
}

// MARK: - Full Screen Image View (StashTok-style vertical paging)

struct FullScreenImageView: View {
    @Binding var images: [StashImage]
    @State var selectedImageId: String
    var onLoadMore: (() -> Void)?
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var isMuted: Bool = !isHeadphonesConnected()
    @State private var currentVisibleId: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                        GalleryItemView(
                            image: image,
                            isMuted: $isMuted,
                            viewModel: viewModel,
                            images: $images
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(image.id)
                        .onAppear {
                            if image.id == images.last?.id {
                                onLoadMore?()
                            }
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentVisibleId)
            .ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
        .onAppear {
            currentVisibleId = selectedImageId
        }
    }

    private func deleteCurrentImage() {
        let targetId = currentVisibleId ?? selectedImageId
        guard let currentIndex = images.firstIndex(where: { $0.id == targetId }) else { return }
        let imageToDelete = images[currentIndex]

        viewModel.deleteImage(imageId: imageToDelete.id) { success in
            DispatchQueue.main.async {
                if success {
                    ToastManager.shared.show("Image deleted", icon: "trash", style: .success)
                    dismiss()
                } else {
                    ToastManager.shared.show("Failed to delete image", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}
#endif
