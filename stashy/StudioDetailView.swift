//
//  StudioDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

import SwiftUI


struct StudioDetailView: View {
    let studio: Studio
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @State private var refreshTrigger = UUID()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getDetailSortOption(for: "studio_detail") ?? "") ?? .dateDesc
    @State private var isChangingSort = false
    @State private var isFavorite: Bool = false
    @State private var isUpdatingFavorite: Bool = false
    @State private var isHeaderExpanded = false // Added state for expansion
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
    }
    @State private var selectedDetailTab: DetailTab = .scenes
    
    // Computed properties for counts
    private var effectiveScenesCount: Int {
        max(viewModel.totalStudioScenes, studio.sceneCount)
    }
    
    private var effectiveGalleriesCount: Int {
        max(viewModel.totalStudioGalleries, studio.galleryCount ?? 0)
    }
    
    private var showTabSwitcher: Bool {
        effectiveScenesCount > 0 && effectiveGalleriesCount > 0
    }

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.SceneSortOption) {
        selectedSortOption = newOption
        
        // Save to TabManager (Session)
        TabManager.shared.setDetailSortOption(for: "studio_detail", option: newOption.rawValue)

        // Force view refresh
        refreshTrigger = UUID()

        // Fetch new data immediately
        viewModel.fetchStudioScenes(studioId: studio.id, sortBy: newOption, isInitialLoad: true)
    }
    
    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        } else {
            return [GridItem(.flexible(), spacing: 12)]
        }
    }
    
    private var galleryColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header Card
                headerCard
                
                if selectedDetailTab == .scenes {
                    if !viewModel.studioScenes.isEmpty {
                        sceneGrid
                    } else if viewModel.isLoadingStudioScenes {
                        loadingView(message: "Loading scenes...")
                    } else {
                        emptyView(message: "No scenes found", icon: "film")
                    }
                } else {
                    if !viewModel.studioGalleries.isEmpty {
                        galleryGrid
                    } else if viewModel.isLoadingStudioGalleries {
                        loadingView(message: "Loading galleries...")
                    } else {
                        emptyView(message: "No galleries found", icon: "photo.on.rectangle")
                    }
                }
            }
            .padding(16)
        }
        .background(Color.appBackground)
        .onAppear {
            // If we know from the passed studio object that there are no scenes but there are galleries,
            // switch immediately so the user sees content.
            if effectiveScenesCount == 0 && effectiveGalleriesCount > 0 {
                selectedDetailTab = .galleries
            }
            loadData()
            // Fetch updated studio details (like favorite status) which might be missing from list view objects
            viewModel.fetchStudio(studioId: studio.id) { updatedStudio in
                if let updated = updatedStudio {
                    self.isFavorite = updated.favorite ?? false
                } else {
                    self.isFavorite = studio.favorite ?? false
                }
            }
        }
        .onChange(of: viewModel.isLoadingStudioScenes) { oldValue, newValue in
            // If scene loading finished and we found 0 scenes, but we have galleries, switch to galleries
            if !newValue && effectiveScenesCount == 0 && effectiveGalleriesCount > 0 {
                selectedDetailTab = .galleries
            }
        }
        .onChange(of: effectiveGalleriesCount) { oldValue, newValue in
            if !viewModel.isLoadingStudioScenes && effectiveScenesCount == 0 && newValue > 0 {
                selectedDetailTab = .galleries
            }
        }
        .onChange(of: effectiveScenesCount) { oldValue, newValue in
            if newValue > 0 {
                selectedDetailTab = .scenes
            } else if newValue == 0 && effectiveGalleriesCount > 0 {
                selectedDetailTab = .galleries
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneDeleted"))) { _ in
            print("🔄 STUDIO DETAIL: Recieved SceneDeleted notification, refreshing...")
            refreshTrigger = UUID()
            viewModel.fetchStudioScenes(studioId: studio.id, sortBy: selectedSortOption, isInitialLoad: true)
        }
        .navigationTitle("")
#if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                if showTabSwitcher {
                    Picker("View", selection: $selectedDetailTab) {
                        Text("Scenes").tag(DetailTab.scenes)
                        Text("Galleries").tag(DetailTab.galleries)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                } else {
                    Text(studio.name)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                     Button {
                         guard !isUpdatingFavorite else { return }
                         isUpdatingFavorite = true
                         let newState = !isFavorite
                         isFavorite = newState
                         
                         viewModel.toggleStudioFavorite(studioId: studio.id, favorite: newState) { success in
                             DispatchQueue.main.async {
                                 if !success {
                                     isFavorite = !newState
                                 }
                                 isUpdatingFavorite = false
                             }
                         }
                     } label: {
                         Image(systemName: isFavorite ? "heart.fill" : "heart")
                             .foregroundColor(isFavorite ? .red : appearanceManager.tintColor)
                     }

                    if selectedDetailTab == .scenes {
                        sortMenu
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(studio.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Spacer()
            }
            
            // Info List
            let details = getStudioDetails(studio)
            // User wants "hide starting from 3rd line".
            // Line 1: Details 1-2
            // Line 2: Details 3-4 OR URL (if <= 2 details)
            // So we always allow up to 4 details (2 rows) visible if no URL conflict,
            // or if URL exists but we prioritize details 3-4 over URL to maximize info density?
            // User complaint: "You hide the second row [Item 3] already".
            // So we MUST show Item 3+4 if present. This takes 2 rows.
            // If 2 rows taken by details, URL (Row 3) must be hidden.
            let visibleDetails = isHeaderExpanded ? details : Array(details.prefix(4))
            let hasURL = studio.url != nil && !studio.url!.isEmpty
            
            if !visibleDetails.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        ForEach(visibleDetails, id: \.label) { detail in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(detail.label)
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(detail.value)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            
            // URL Link (Always on its own row)
            // Show if expanded OR if we have space (details <= 2, i.e. 1 row used)
            if hasURL && (isHeaderExpanded || details.count <= 2) {
                 VStack(alignment: .leading, spacing: 2) {
                     Text("URL")
                         .font(.system(size: 8))
                         .foregroundColor(.secondary)
                         .textCase(.uppercase)
                     Link(destination: URL(string: studio.url!) ?? URL(string: "https://google.com")!) {
                         Text(studio.url!)
                             .font(.system(size: 11, weight: .bold))
                             .foregroundColor(.appAccent)
                             .lineLimit(1)
                     }
                 }
            }
            
            // Description (Full width if present)
            if let desc = studio.details, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.leading, 140 + 12) // Logo width + spacing
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 115, alignment: .topLeading) // Ensure minimum height for logo and top alignment
        .overlay(
            ZStack {
                Color.studioHeaderGray
                StudioImageView(studio: studio)
                    .padding(8)
            }
            .frame(width: 140)
            , alignment: .leading
        )
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(
            Group {
                let details = getStudioDetails(studio)
                let hasURL = studio.url != nil && !studio.url!.isEmpty
                
                // Button needed if:
                // 1. More details than shown (count > 4)
                // 2. URL exists but is hidden (count > 2)
                if details.count > 4 || (hasURL && details.count > 2) {
                    Button(action: {
                        withAnimation(.spring()) {
                            isHeaderExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isHeaderExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(appearanceManager.tintColor)
                            .padding(6)
                            .background(appearanceManager.tintColor.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .padding(8)
                }
            },
            alignment: .bottomTrailing
        )
    }

    private func getStudioDetails(_ s: Studio) -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        
        // Add Scenes and Galleries as the first row (matching PerformerDetailView)
        list.append((label: "SCENES", value: "\(effectiveScenesCount)"))
        
        if effectiveGalleriesCount > 0 {
            list.append((label: "GALLERIES", value: "\(effectiveGalleriesCount)"))
        } else {
             // Optional: Add placeholder if needed for grid alignment, but usually fine to omit
        }
        
        if let count = s.performerCount, count > 0 {
            list.append((label: "PERFORMERS", value: "\(count)"))
        }
        
        // URL is now handled separately in the view to ensure it gets its own row
        
        return list
    }

    private func miniBadge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
    }
    
    private func labelBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(appearanceManager.tintColor)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var sceneGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.studioScenes) { scene in
                NavigationLink(destination: SceneDetailView(scene: scene)) {
                    SceneCardView(scene: scene)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if viewModel.isLoadingStudioScenes {
                loadingIndicator(message: "Loading more scenes...")
            } else if viewModel.hasMoreStudioScenes && !viewModel.studioScenes.isEmpty {
                Color.clear.frame(height: 1).onAppear { viewModel.loadMoreStudioScenes(studioId: studio.id) }
            }
        }
        .id(refreshTrigger)
    }
    
    private var galleryGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.studioGalleries) { gallery in
                NavigationLink(destination: ImagesView(gallery: gallery)) {
                    GalleryCardView(gallery: gallery)
                }
                .buttonStyle(.plain)
            }

            if viewModel.isLoadingStudioGalleries {
                loadingIndicator(message: "Loading more galleries...")
            } else if viewModel.hasMoreStudioGalleries && !viewModel.studioGalleries.isEmpty {
                Color.clear.frame(height: 1).onAppear { viewModel.loadMoreStudioGalleries(studioId: studio.id) }
            }
        }
    }
    
    private var sortMenu: some View {
        Menu {
            // Random
            Button(action: { changeSortOption(to: .random) }) {
                HStack {
                    Text("Random")
                    if selectedSortOption == .random { Image(systemName: "checkmark") }
                }
            }
            
            Divider()
            
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
            
            // Duration
            Menu {
                Button(action: { changeSortOption(to: .durationDesc) }) {
                    HStack {
                        Text("Longest First")
                        if selectedSortOption == .durationDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeSortOption(to: .durationAsc) }) {
                    HStack {
                        Text("Shortest First")
                        if selectedSortOption == .durationAsc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Duration")
                    if selectedSortOption == .durationAsc || selectedSortOption == .durationDesc { Image(systemName: "checkmark") }
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
                    if selectedSortOption == .ratingAsc || selectedSortOption == .ratingDesc { Image(systemName: "checkmark") }
                }
            }
            
            // Counter
            Menu {
                Button(action: { changeSortOption(to: .oCounterDesc) }) {
                    HStack {
                        Text("High → Low")
                        if selectedSortOption == .oCounterDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeSortOption(to: .oCounterAsc) }) {
                    HStack {
                        Text("Low → High")
                        if selectedSortOption == .oCounterAsc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Counter")
                    if selectedSortOption == .oCounterAsc || selectedSortOption == .oCounterDesc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundColor(appearanceManager.tintColor)
        }
    }
    
    private func loadingView(message: String) -> some View {
        VStack {
            Spacer()
            ProgressView(message)
            Spacer()
        }.frame(height: 200)
    }
    
    private func emptyView(message: String, icon: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text(message)
                .font(.title3)
                .foregroundColor(.secondary)
        }.padding(.top, 40)
    }
    
    private func loadingIndicator(message: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(message).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private func loadData() {
        if viewModel.studioGalleries.isEmpty && !viewModel.isLoadingStudioGalleries {
            viewModel.fetchStudioGalleries(studioId: studio.id, isInitialLoad: true)
        }
        
        if viewModel.studioScenes.isEmpty && !viewModel.isLoadingStudioScenes {
            viewModel.fetchStudioScenes(studioId: studio.id, sortBy: selectedSortOption, isInitialLoad: true)
        }
    }
}

#Preview {
    let sampleStudio = Studio(
        id: "1",
        name: "Sample Studio",
        url: "https://samplestudio.com",
        sceneCount: 25,
        performerCount: 5,
        galleryCount: 10,
        details: "This is a sample studio description that might span multiple lines.",
        imagePath: nil,
        favorite: false,
        rating100: nil,
        createdAt: nil,
        updatedAt: nil
    )
    StudioDetailView(studio: sampleStudio)
}

