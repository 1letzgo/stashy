//
//  UniversalSearchView.swift
//  stashy
//

import SwiftUI

struct UniversalSearchView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    
    @State private var searchText = ""
    @State private var isSearching = false
    
    // Search results
    @State private var performers: [Performer] = []
    @State private var studios: [Studio] = []
    @State private var tags: [Tag] = []
    @State private var scenes: [Scene] = []
    @State private var galleries: [Gallery] = []
    
    // Per-category result limits
    private let scenesLimit = 20
    private let performersLimit = 20
    private let galleriesLimit = 20
    private let tagsLimit = 50
    private let studiosLimit = 50
    
    // Get ordered content types based on TabManager
    private var orderedSections: [AppTab] {
        tabManager.tabs
            .filter { [.scenes, .performers, .studios, .tags, .galleries].contains($0.id) && $0.isVisible }
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
            .searchable(text: $searchText, prompt: "Search everything...")
            .onChange(of: searchText) { oldValue, newValue in
                performSearch()
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
                
                Text("Find scenes, performers, studios, tags, and galleries")
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
                    HStack {
                        Spacer()
                        ProgressView("Searching...")
                        Spacer()
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(orderedSections, id: \.self) { section in
                        sectionView(for: section)
                    }
                    
                    // Show no results message if all empty
                    if performers.isEmpty && studios.isEmpty && tags.isEmpty && scenes.isEmpty && galleries.isEmpty {
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
                        NavigationLink(destination: PerformerDetailView(performer: performer)) {
                            performerCard(performer)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
    
    private func performerCard(_ performer: Performer) -> some View {
        VStack(spacing: 8) {
            if let imageURL = performer.thumbnailURL {
                CustomAsyncImage(url: imageURL) { loader in
                    if loader.isLoading {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 80)
                            .overlay(ProgressView())
                    } else if let image = loader.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 120)
                            .clipped()
                            .clipShape(Circle())
                            .alignmentGuide(.top) { d in d[.top] }
                    } else {
                        performerPlaceholder
                    }
                }
            } else {
                performerPlaceholder
            }
            
            Text(performer.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(width: 80)
        }
    }
    
    private var performerPlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundColor(.secondary)
            )
    }
    
    private var studiosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Studios", count: studios.count, limit: studiosLimit) {
                coordinator.navigateToStudios(search: searchText)
            }
            
            VStack(spacing: 0) {
                ForEach(studios) { studio in
                    NavigationLink(destination: StudioDetailView(studio: studio)) {
                        HStack {
                            Image(systemName: "building.2")
                                .foregroundColor(.appAccent)
                                .frame(width: 30)
                            
                            Text(studio.name)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text("\(studio.sceneCount) scenes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    
                    if studio.id != studios.last?.id {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal, 12)
        }
    }
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Tags", count: tags.count, limit: tagsLimit) {
                coordinator.navigateToTags(search: searchText)
            }
            
            FlowLayout(spacing: 8) {
                ForEach(tags) { tag in
                    NavigationLink(destination: TagDetailView(selectedTag: tag)) {
                        Text("\(tag.name) (\(tag.sceneCount ?? 0))")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.appAccent.opacity(0.15))
                            .foregroundColor(.appAccent)
                            .cornerRadius(16)
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
                HStack(spacing: 12) {
                    ForEach(scenes) { scene in
                        NavigationLink(destination: SceneDetailView(scene: scene)) {
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
        HomeSceneCardView(scene: scene, isLarge: false)
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
                        NavigationLink(destination: GalleryDetailView(gallery: gallery)) {
                            galleryCard(gallery)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
    
    private func galleryCard(_ gallery: Gallery) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let coverURL = gallery.coverURL {
                CustomAsyncImage(url: coverURL) { loader in
                    if loader.isLoading {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 120, height: 120)
                            .overlay(ProgressView())
                    } else if let image = loader.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipped()
                    } else {
                        galleryPlaceholder
                    }
                }
            } else {
                galleryPlaceholder
            }
            
            Text(gallery.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)
        }
        .cornerRadius(8)
    }
    
    private var galleryPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 120, height: 120)
            .overlay(
                Image(systemName: "photo.stack")
                    .foregroundColor(.secondary)
            )
    }
    
    // MARK: - Helpers
    
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
        guard query.count >= 2 else { return }
        
        isSearching = true
        
        // Run all searches in parallel using async let
        Task { @MainActor in
            async let performersTask = viewModel.searchPerformersAsync(query: query, limit: performersLimit)
            async let studiosTask = viewModel.searchStudiosAsync(query: query, limit: studiosLimit)
            async let tagsTask = viewModel.searchTagsAsync(query: query, limit: tagsLimit)
            async let scenesTask = viewModel.searchScenesAsync(query: query, limit: scenesLimit)
            async let galleriesTask = viewModel.searchGalleriesAsync(query: query, limit: galleriesLimit)
            
            // Await all results
            let (performersResult, studiosResult, tagsResult, scenesResult, galleriesResult) = await (
                performersTask,
                studiosTask,
                tagsTask,
                scenesTask,
                galleriesTask
            )
            
            // Update state on main actor
            performers = performersResult
            studios = studiosResult
            tags = tagsResult
            scenes = scenesResult
            galleries = galleriesResult
            isSearching = false
        }
    }
    
    private func clearResults() {
        performers = []
        studios = []
        tags = []
        scenes = []
        galleries = []
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
