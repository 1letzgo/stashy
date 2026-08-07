//
//  UniversalSearchView.swift
//  stashy
//

#if !os(tvOS)
import SwiftUI

struct UniversalSearchView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.dismissSearch) private var dismissSearch
    
    @State private var searchText = ""
    @State private var isSearching = false
    
    // Search results
    @State private var performers: [Performer] = []
    @State private var studios: [Studio] = []
    @State private var tags: [Tag] = []
    @State private var scenes: [Scene] = []
    @State private var galleries: [Gallery] = []
    @State private var groups: [StashGroup] = []
    @State private var markers: [SceneMarker] = []
    
    // Per-category result limits
    private let scenesLimit = 20
    private let performersLimit = 20
    private let galleriesLimit = 20
    private let tagsLimit = 50
    private let studiosLimit = 50
    private let groupsLimit = 20
    private let markersLimit = 20
    
    // Get ordered content types based on TabManager
    private var orderedSections: [AppTab] {
        tabManager.tabs
            .filter { [.scenes, .performers, .studios, .tags, .galleries, .groups, .markers].contains($0.id) && $0.isVisible }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.id }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if configManager.activeConfig == nil {
                    ConnectionErrorView { }
                } else if searchText.isEmpty {
                    emptySearchView
                } else {
                    searchResultsView
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .applyAppBackground()
            .searchable(text: $searchText, prompt: "Search everything...")
            .onChange(of: searchText) { oldValue, newValue in
                let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.count < 2 {
                    clearResults()
                } else {
                    performSearch()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PerformerImageUpdated"))) { notification in
                guard let targetId = notification.userInfo?["performerId"] as? String,
                      let newPath = notification.userInfo?["newImagePath"] as? String else { return }

                var updatedPerformers = performers
                for i in updatedPerformers.indices where updatedPerformers[i].id == targetId {
                    updatedPerformers[i].imagePath = newPath
                }
                performers = updatedPerformers

                var updatedGalleries = galleries
                for i in updatedGalleries.indices {
                    guard var mutablePerformers = updatedGalleries[i].performers,
                          let pIndex = mutablePerformers.firstIndex(where: { $0.id == targetId }) else { continue }
                    mutablePerformers[pIndex].image_path = newPath
                    updatedGalleries[i].performers = mutablePerformers
                }
                galleries = updatedGalleries
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptySearchView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("Search Your Library")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Find scenes, performers, studios, tags, galleries, groups and markers")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
    
    // MARK: - Search Results
    
    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if isSearching {
                    StandardLoadingView(message: "Searching...", fillsScreen: false)
                } else {
                    ForEach(orderedSections, id: \.self) { section in
                        sectionView(for: section)
                    }
                    
                    // Show no results message if all empty
                    if performers.isEmpty && studios.isEmpty && tags.isEmpty && scenes.isEmpty && galleries.isEmpty && groups.isEmpty && markers.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            
                            Text("No results for \"\(searchText)\"")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.appBackground)
    }
    
    // MARK: - Section Views
    
    @ViewBuilder
    private func sectionView(for tab: AppTab) -> some View {
        switch tab {
        case .performers:
            if !performers.isEmpty {
                performersSection
            }
        case .studios:
            if !studios.isEmpty {
                studiosSection
            }
        case .tags:
            if !tags.isEmpty {
                tagsSection
            }
        case .scenes:
            if !scenes.isEmpty {
                scenesSection
            }
        case .galleries:
            if !galleries.isEmpty {
                galleriesSection
            }
        case .groups:
            if !groups.isEmpty {
                groupsSection
            }
        case .markers:
            if !markers.isEmpty {
                markersSection
            }
        default:
            EmptyView()
        }
    }
    
    private var performersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Performers", count: performers.count, limit: performersLimit) {
                coordinator.navigateToPerformers(search: searchText)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(performers) { performer in
                        NavigationLink(destination: searchPushDestination {
                            PerformerDetailView(performer: performer)
                        }) {
                            performerCard(performer)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
    
    private func performerCard(_ performer: Performer) -> some View {
        ZStack(alignment: .bottom) {
            // Thumbnail Circle
            ZStack {
                if let imageURL = performer.thumbnailURL {
                    CustomAsyncImage(url: imageURL) { loader in
                        if loader.isLoading {
                            Circle()
                                .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .frame(width: 80, height: 80)
                                .overlay(ProgressView())
                        } else if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80, alignment: .top)
                                .clipShape(Circle())
                        } else {
                            performerPlaceholder
                        }
                    }
                } else {
                    performerPlaceholder
                }
            }
            .padding(4)
            .background(appearanceManager.tintColor)
            .clipShape(Circle())
            .overlay(Circle().stroke(appearanceManager.tintColor.opacity(0.1), lineWidth: 0.2))
            
            // Name Pill Overlaid at Bottom
            InfoPill(icon: nil, text: performer.name)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .offset(y: 8)
        }
        .frame(width: 100) // Ensure enough width for the pill overflow if needed
    }
    
    private var performerPlaceholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: 80, height: 80)
            .foregroundColor(appearanceManager.tintColor.opacity(0.4))
    }
    
    private var studiosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Studios", count: studios.count, limit: studiosLimit) {
                coordinator.navigateToStudios(search: searchText)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(studios) { studio in
                        NavigationLink(destination: searchPushDestination {
                            StudioDetailView(studio: studio)
                        }) {
                            studioCard(studio)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
    
    private func studioCard(_ studio: Studio) -> some View {
        ZStack(alignment: .bottom) {
            // Logo Container
            ZStack {
                StudioImageView(studio: studio)
                    .padding(8)
            }
            .frame(width: 120, height: 90)
            .background(appearanceManager.tintColor)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card).stroke(appearanceManager.tintColor.opacity(0.1), lineWidth: 0.2))
            
            // Name Pill
            InfoPill(icon: nil, text: studio.name)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .offset(y: 8)
        }
    }
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Tags", count: tags.count, limit: tagsLimit) {
                coordinator.navigateToTags(search: searchText)
            }
            
            FlowLayout(spacing: 8) {
                ForEach(tags) { tag in
                    NavigationLink(destination: searchPushDestination {
                        TagDetailView(selectedTag: tag)
                    }) {
                        InfoPill(
                            icon: "tag.fill",
                            text: "\(tag.name) (\(tag.sceneCount ?? 0))",
                            style: .filled
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }
    
    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Scenes", count: scenes.count, limit: scenesLimit) {
                coordinator.navigateToScenes(search: searchText, noDefaultFilter: true)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(scenes) { scene in
                        NavigationLink(destination: searchPushDestination {
                            SceneDetailView(scene: scene)
                        }) {
                            sceneCard(scene)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
    
    private func sceneCard(_ scene: Scene) -> some View {
        HomeSceneCardView(scene: scene, isLarge: false,
                          screenWidth: UIScreen.main.bounds.width)
    }
    
    private var scenePlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 200, height: 112)
            .overlay(
                Image(systemName: "film")
                    .foregroundColor(.secondary)
            )
    }
    
    private var galleriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Galleries", count: galleries.count, limit: galleriesLimit) {
                coordinator.navigateToGalleries(search: searchText)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(galleries) { gallery in
                        NavigationLink(destination: searchPushDestination {
                            ImagesView(gallery: gallery)
                        }) {
                            galleryCard(gallery)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
    
    private func galleryCard(_ gallery: Gallery) -> some View {
        ZStack(alignment: .bottom) {
            // Cover Image
            if let coverURL = gallery.coverURL {
                CustomAsyncImage(url: coverURL) { loader in
                    if loader.isLoading {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(ProgressView())
                    } else if let image = loader.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        galleryPlaceholder
                    }
                }
            } else {
                galleryPlaceholder
            }
        }
        .frame(width: 140, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            InfoPill(icon: "photo.stack", text: gallery.title)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .offset(y: 8)
            , alignment: .bottom
        )
        // Ensure the pill draws outside the clip
        .zIndex(1)
    }
    
    private var galleryPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "photo.stack")
                    .foregroundColor(.secondary)
            )
    }

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Groups", count: groups.count, limit: groupsLimit) {
                coordinator.navigateToGroups(search: searchText)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(groups) { group in
                        NavigationLink(destination: searchPushDestination {
                            GroupDetailView(selectedGroup: group)
                        }) {
                            groupCard(group)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
    
    private func groupCard(_ group: StashGroup) -> some View {
        ZStack(alignment: .bottom) {
            // Cover Image
            if let thumbnailURL = group.thumbnailURL {
                CustomAsyncImage(url: thumbnailURL) { loader in
                    if loader.isLoading {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(ProgressView())
                    } else if let image = loader.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        groupPlaceholder
                    }
                }
            } else {
                groupPlaceholder
            }
        }
        .frame(width: 100, height: 133) // 3:4 aspect ratio for groups
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            InfoPill(icon: "rectangle.stack.fill", text: group.name)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .offset(y: 8)
            , alignment: .bottom
        )
        .zIndex(1)
    }
    
    private var groupPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "rectangle.stack.fill")
                    .foregroundColor(.secondary)
            )
    }
    
    private var markersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Markers", count: markers.count, limit: markersLimit) {
                coordinator.navigateToMarkers(search: searchText)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(markers) { marker in
                        if let scene = marker.scene?.toScene() {
                            let mappedScene = scene.withResumeTime(marker.seconds)
                            NavigationLink(destination: searchPushDestination {
                                SceneDetailView(scene: mappedScene, autoPlay: true)
                            }) {
                                searchMarkerCard(marker)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
    
    /// Dismisses the Search field so pushed custom-chrome details are not covered by the native search bar.
    @ViewBuilder
    private func searchPushDestination<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .onAppear { dismissSearch() }
    }

    private func searchMarkerCard(_ marker: SceneMarker) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                if let thumbURL = marker.thumbnailURL {
                    CustomAsyncImage(url: thumbURL) { loader in
                        if loader.isLoading {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .overlay(ProgressView())
                        } else if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            markerPlaceholder
                        }
                    }
                } else {
                    markerPlaceholder
                }
                
                // Timestamp badge
                Text(formatDuration(marker.seconds))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                    .padding(4)
            }
            .frame(width: 160, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(marker.title ?? marker.scene?.title ?? "Unknown Marker")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let tagName = marker.primaryTag?.name {
                    Text(tagName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(appearanceManager.tintColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(appearanceManager.tintColor.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 160)
    }
    
    private var markerPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.secondary)
            )
    }
    
    private func sectionHeader(title: String, count: Int, limit: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("(\(count))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if count >= limit {
                    HStack(spacing: 4) {
                        Text("Show All")
                            .font(.subheadline)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundColor(.appAccent)
                }
            }
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    // MARK: - Search Logic
    
    private func performSearch() {
        guard !searchText.isEmpty else {
            clearResults()
            return
        }
        
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            clearResults()
            return
        }
        
        isSearching = true
        
        // Run all searches in parallel using async let
        Task { @MainActor in
            async let performersTask = viewModel.searchPerformersAsync(query: query, limit: performersLimit)
            async let studiosTask = viewModel.searchStudiosAsync(query: query, limit: studiosLimit)
            async let tagsTask = viewModel.searchTagsAsync(query: query, limit: tagsLimit)
            async let scenesTask = viewModel.searchScenesAsync(query: query, limit: scenesLimit)
            async let galleriesTask = viewModel.searchGalleriesAsync(query: query, limit: galleriesLimit)
            async let groupsTask = viewModel.searchGroupsAsync(query: query, limit: groupsLimit)
            async let markersTask = viewModel.searchMarkersAsync(query: query, limit: markersLimit)
            
            // Await all results
            let (performersResult, studiosResult, tagsResult, scenesResult, galleriesResult, groupsResult, markersResult) = await (
                performersTask,
                studiosTask,
                tagsTask,
                scenesTask,
                galleriesTask,
                groupsTask,
                markersTask
            )
            
            // Update state on main actor
            performers = performersResult
            studios = studiosResult
            tags = tagsResult
            scenes = scenesResult
            galleries = galleriesResult
            groups = groupsResult
            markers = markersResult
            isSearching = false
        }
    }
    
    private func clearResults() {
        performers = []
        studios = []
        tags = []
        scenes = []
        galleries = []
        groups = []
        markers = []
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in containerWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > containerWidth && x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                maxHeight = max(maxHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: containerWidth, height: y + maxHeight)
        }
    }
}
#endif
