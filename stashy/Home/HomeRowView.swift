
#if !os(tvOS)
import SwiftUI

struct HomeRowView: View {
    let config: HomeRowConfig
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var tabManager = TabManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    var isLarge: Bool = false
    
    @State private var scrollID: String?
    
    // Use ViewModel cache instead of local @State
    private var scenes: [Scene] {
        viewModel.homeRowScenes[config.type] ?? []
    }
    
    private var performers: [Performer] {
        viewModel.homeRowPerformers[config.type] ?? []
    }
    
    private var studios: [Studio] {
        viewModel.homeRowStudios[config.type] ?? []
    }
    
    private var galleries: [Gallery] {
        viewModel.homeRowGalleries[config.type] ?? []
    }
    
    private var isLoading: Bool {
        // Loading if: no cached data AND currently fetching
        let isEmpty: Bool
        switch config.type {
        case .newPerformers, .performersHighestSceneCount:
            isEmpty = performers.isEmpty
        case .newStudios, .studiosHighestSceneCount:
            isEmpty = studios.isEmpty
        case .newGalleries, .recentlyUpdatedGalleries:
            isEmpty = galleries.isEmpty
        default:
            isEmpty = scenes.isEmpty
        }
        return isEmpty && (viewModel.homeRowLoadingState[config.type] ?? true)
    }
    
    private var isContentEmpty: Bool {
        switch config.type {
        case .newPerformers, .performersHighestSceneCount:
            return performers.isEmpty
        case .newStudios, .studiosHighestSceneCount:
            return studios.isEmpty
        case .newGalleries, .recentlyUpdatedGalleries:
            return galleries.isEmpty
        default:
            return scenes.isEmpty
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(destination: destinationView) {
                HStack(spacing: 4) {
                    Text(config.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<5) { _ in
                            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                                .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .frame(width: getItemWidth(), height: getItemHeight())
                                .overlay(ProgressView())
                        }
                    }
                    .padding(.horizontal, 12)
                }
            } else if isContentEmpty {
                Text("No content found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: (isLarge && tabManager.dashboardHeroSize == .big) ? 0 : 12) {
                        if config.type == .newPerformers || config.type == .performersHighestSceneCount {
                            ForEach(performers) { performer in
                                NavigationLink(destination: PerformerDetailView(performer: performer)) {
                                    HomePerformerCardView(performer: performer, isLarge: isLarge)
                                        .padding(.horizontal, (isLarge && tabManager.dashboardHeroSize == .big) ? 12 : 0)
                                }
                                .buttonStyle(.plain)
                                .id(performer.id)
                            }
                        } else if config.type == .newStudios || config.type == .studiosHighestSceneCount {
                            ForEach(studios) { studio in
                                NavigationLink(destination: StudioDetailView(studio: studio)) {
                                    HomeStudioCardView(studio: studio, isLarge: isLarge)
                                        .padding(.horizontal, (isLarge && tabManager.dashboardHeroSize == .big) ? 12 : 0)
                                }
                                .buttonStyle(.plain)
                                .id(studio.id)
                            }
                        } else if config.type == .newGalleries || config.type == .recentlyUpdatedGalleries {
                            ForEach(galleries) { gallery in
                                NavigationLink(destination: ImagesView(gallery: gallery)) {
                                    HomeGalleryCardView(gallery: gallery, isLarge: isLarge)
                                        .padding(.horizontal, (isLarge && tabManager.dashboardHeroSize == .big) ? 12 : 0)
                                }
                                .buttonStyle(.plain)
                                .id(gallery.id)
                            }
                        } else {
                            ForEach(scenes) { scene in
                                NavigationLink(destination: SceneDetailView(scene: scene)) {
                                    HomeSceneCardView(scene: scene, isLarge: isLarge)
                                        .padding(.horizontal, (isLarge && tabManager.dashboardHeroSize == .big) ? 12 : 0)
                                }
                                .buttonStyle(.plain)
                                .id(scene.id)
                            }
                        }
                    }
                    .padding(.horizontal, (isLarge && tabManager.dashboardHeroSize == .big) ? 0 : 12)
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $scrollID)
                .scrollTargetBehavior((isLarge && tabManager.dashboardHeroSize == .big) ? .paging : .init())
                .overlay(alignment: .bottom) {
                    if isLarge && tabManager.dashboardHeroSize == .big {
                        PageIndicator(itemCount: getItemCount(), selectedID: scrollID, items: getItems())
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .onAppear {
            checkAndLoadScenes()
        }
        .onChange(of: viewModel.savedFilters) { _, _ in
            checkAndLoadScenes()
        }
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, newValue in
            if oldValue == true && newValue == false {
                checkAndLoadScenes()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.dashboard.rawValue {
                viewModel.homeRowScenes[config.type] = nil
                checkAndLoadScenes()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScenePlayAdded"))) { _ in
            guard config.type == .lastPlayed else { return }
            viewModel.homeRowScenes[config.type] = nil
            checkAndLoadScenes()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            viewModel.homeRowScenes[config.type] = nil
            viewModel.homeRowPerformers[config.type] = nil
            viewModel.homeRowStudios[config.type] = nil
            viewModel.homeRowGalleries[config.type] = nil
            checkAndLoadScenes()
        }
    }
    
    private func checkAndLoadScenes() {
        if let filterId = TabManager.shared.getDefaultFilterId(for: .dashboard) {
            if viewModel.savedFilters[filterId] != nil || !viewModel.isLoadingSavedFilters {
                loadScenes()
            }
        } else {
            loadScenes()
        }
    }
    
    private func loadScenes() {
        let limit = 10
        
        if config.type == .newPerformers || config.type == .performersHighestSceneCount {
            viewModel.fetchPerformersForHomeRow(config: config, limit: limit) { _ in }
        } else if config.type == .newStudios || config.type == .studiosHighestSceneCount {
            viewModel.fetchStudiosForHomeRow(config: config, limit: limit) { _ in }
        } else if config.type == .newGalleries || config.type == .recentlyUpdatedGalleries {
            viewModel.fetchGalleriesForHomeRow(config: config, limit: limit) { _ in }
        } else {
            viewModel.fetchScenesForHomeRow(config: config, limit: limit) { _ in }
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        if config.type == .newPerformers {
            PerformersView(initialSort: .createdAtDesc)
        } else if config.type == .performersHighestSceneCount {
            PerformersView(initialSort: .sceneCountDesc)
        } else if config.type == .newStudios {
            StudiosView(initialSort: .createdAtDesc)
        } else if config.type == .studiosHighestSceneCount {
            StudiosView(initialSort: .sceneCountDesc)
        } else if config.type == .newGalleries {
            GalleriesView(initialSort: .createdAtDesc)
        } else if config.type == .recentlyUpdatedGalleries {
            GalleriesView(initialSort: .updatedAtDesc)
        } else {
            ScenesView(sort: getSortOption())
        }
    }
    
    private func getItemWidth() -> CGFloat {
        if isLarge {
            if tabManager.dashboardHeroSize == .big {
                return UIScreen.main.bounds.width - 24 // 12pt padding on each side
            } else {
                return 280 // Standard "Small Hero" width
            }
        }
        
        // Standard width for non-hero rows
        let baseWidth: CGFloat = 200
        
        if config.type == .newPerformers || config.type == .performersHighestSceneCount {
            // Performers are portrait (2:3), but matched to the height of 16:9 scenes
            let matchedHeight = baseWidth * 9 / 16
            return matchedHeight * 2 / 3
        } else if config.type == .newGalleries || config.type == .recentlyUpdatedGalleries {
            // Galleries are square, matched to height
            return baseWidth * 9 / 16
        } else {
            return baseWidth
        }
    }
    
    private func getItemHeight() -> CGFloat {
        if isLarge {
            let width = getItemWidth()
            return width * 9 / 16
        }
        return 200 * 9 / 16
    }

    private func getSortOption() -> StashDBViewModel.SceneSortOption? {
        switch config.type {
        case .lastPlayed: return .lastPlayedAtDesc
        case .lastAdded3Min: return .createdAtDesc
        case .newest3Min: return .dateDesc
        case .mostViewed3Min: return .playCountDesc
        case .topCounter3Min: return .oCounterDesc
        case .topRating3Min: return .ratingDesc
        case .random: return .random
        case .statistics, .newPerformers, .performersHighestSceneCount, .newStudios, .studiosHighestSceneCount, .newGalleries, .recentlyUpdatedGalleries:
            return nil
        }
    }
    
    private func getItemCount() -> Int {
        switch config.type {
        case .newPerformers, .performersHighestSceneCount: return performers.count
        case .newStudios, .studiosHighestSceneCount: return studios.count
        case .newGalleries, .recentlyUpdatedGalleries: return galleries.count
        default: return scenes.count
        }
    }
    
    private func getItems() -> [String] {
        switch config.type {
        case .newPerformers, .performersHighestSceneCount: return performers.map { $0.id }
        case .newStudios, .studiosHighestSceneCount: return studios.map { $0.id }
        case .newGalleries, .recentlyUpdatedGalleries: return galleries.map { $0.id }
        default: return scenes.map { $0.id }
        }
    }
}

struct PageIndicator: View {
    let itemCount: Int
    let selectedID: String?
    let items: [String]
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<itemCount, id: \.self) { index in
                Circle()
                    .fill((selectedID ?? items.first) == (items[safe: index] ?? "") ? Color.white : Color.white.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.3))
        .clipShape(Capsule())
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct HomePerformerCardView: View {
    let performer: Performer
    var isLarge: Bool = false
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    // Calculate width based on fixed height to match Scene cards
    // HomeSceneCardView height = cardWidth * 9/16
    // isLarge ? 280 * 9/16 : 200 * 9/16  => 157.5 : 112.5
    private var cardWidth: CGFloat {
        if isLarge {
            if tabManager.dashboardHeroSize == .big {
                return UIScreen.main.bounds.width - 24
            } else {
                return 280
            }
        } else {
            // Standard height is 200 * 9/16 = 112.5
            // Width is 2/3 of that for portrait
            return (200 * 9 / 16) * 2 / 3
        }
    }
    
    private var cardHeight: CGFloat {
        return cardWidth * (isLarge ? 9 / 16 : 3 / 2)
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Image
            GeometryReader { geometry in
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                    
                    if let thumbnailURL = performer.thumbnailURL {
                        CustomAsyncImage(url: thumbnailURL) { loader in
                            if loader.isLoading {
                                ProgressView()
                            } else if let image = loader.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                                    .clipped()
                            } else {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Image(systemName: "person.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Gradient Overlay for Text Readability
            LinearGradient(
                colors: [.black.opacity(0.8), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 50)
            .frame(maxHeight: .infinity, alignment: .bottom)
            
            // Content Overlays
            VStack {
                HStack(alignment: .top) {
                    Spacer()
                    
                    // Scene Count Badge (Top Right)
                    HStack(spacing: 2) {
                        Image(systemName: "film")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(performer.sceneCount)")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                Spacer()
                
                // Name (Bottom Left)
                Text(performer.name)
                    .font(.system(size: isLarge ? 12 : 10, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
            }
            .padding(6)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }
}

struct HomeStudioCardView: View {
    let studio: Studio
    var isLarge: Bool = false
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    // Use same height as scenes, but standard width (16:9 like scenes)
    private var cardWidth: CGFloat { 
        if isLarge {
            if tabManager.dashboardHeroSize == .big {
                return UIScreen.main.bounds.width - 24
            } else {
                return 280
            }
        }
        return 200 
    }
    private var cardHeight: CGFloat { cardWidth * 9 / 16 }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo Block (Top)
            ZStack(alignment: .bottom) {
                // Background
                Color.studioHeaderGray
                
                // Logo Image
                StudioImageView(studio: studio)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: cardHeight - (isLarge ? 36 : 32)) // Leave space for bottom bar
            
            // Name & Info Area (Below)
            HStack(spacing: 8) {
                Text(studio.name)
                    .font(.system(size: isLarge ? 12 : 10, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                HStack(spacing: 6) {
                    // Scenes
                    HStack(spacing: 2) {
                        Image(systemName: "film")
                            .font(.system(size: isLarge ? 10 : 8))
                        Text("\(studio.sceneCount)")
                            .font(.system(size: isLarge ? 11 : 9, weight: .medium))
                    }
                    
                    // Galleries
                    if let galleryCount = studio.galleryCount, galleryCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: isLarge ? 10 : 8))
                            Text("\(galleryCount)")
                                .font(.system(size: isLarge ? 11 : 9, weight: .medium))
                        }
                    }
                }
                .foregroundColor(.secondary)
                .layoutPriority(1)
            }
            .padding(.horizontal, isLarge ? 10 : 8)
            .padding(.vertical, isLarge ? 8 : 6)
            .frame(height: isLarge ? 36 : 32)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}

struct HomeGalleryCardView: View {
    let gallery: Gallery
    var isLarge: Bool = false
    @ObservedObject var tabManager = TabManager.shared
    
    private var cardWidth: CGFloat { 
        if isLarge {
            if tabManager.dashboardHeroSize == .big {
                return UIScreen.main.bounds.width - 24
            } else {
                return 280
            }
        }
        return 200 
    }
    private var cardHeight: CGFloat { cardWidth * 9 / 16 }
    
    var body: some View {
        GalleryCardView(gallery: gallery)
            .frame(width: isLarge ? cardWidth : cardHeight, height: cardHeight)
    }
}

#endif
