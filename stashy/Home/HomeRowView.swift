
#if !os(tvOS)
import SwiftUI
import UIKit

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Card dimension helpers

private let homeHeroCardWidthFraction: CGFloat = 0.8
private let homeHeroCardFixedWidth: CGFloat = 280

func homeHeroCardWidth(screenWidth: CGFloat) -> CGFloat {
    let screenHeight = UIScreen.main.bounds.height
    let isPortrait = screenHeight > screenWidth
    let isPhone = UIDevice.current.userInterfaceIdiom == .phone
    if isPhone && isPortrait {
        return screenWidth * homeHeroCardWidthFraction
    }
    return homeHeroCardFixedWidth
}

func homeCardWidth(for config: HomeRowConfig, isLarge: Bool, screenWidth: CGFloat) -> CGFloat {
    if isLarge { return homeHeroCardWidth(screenWidth: screenWidth) }
    switch config.type {
    case .newPerformers, .performersHighestSceneCount, .performersHighestOCount, .performersHighestRating:
        return 125 * 2 / 3
    case .newGalleries, .recentlyUpdatedGalleries, .galleriesHighestImageCount:
        return 125
    case .channels:
        // Channels show a category logo, not a thumbnail — square card.
        return 125
    default:
        return 125 * 16 / 9
    }
}

func homeCardHeight(for config: HomeRowConfig, isLarge: Bool, screenWidth: CGFloat) -> CGFloat {
    let width = homeCardWidth(for: config, isLarge: isLarge, screenWidth: screenWidth)
    if isLarge {
        switch config.type {
        case .newPerformers, .performersHighestSceneCount, .performersHighestOCount, .performersHighestRating:
            return width * 3 / 2
        case .newGalleries, .recentlyUpdatedGalleries, .galleriesHighestImageCount:
            return 125
        case .channels:
            return width
        default:
            return width * 9 / 16
        }
    }
    switch config.type {
    case .newPerformers, .performersHighestSceneCount, .performersHighestOCount, .performersHighestRating:
        return width * 3 / 2
    case .newGalleries, .recentlyUpdatedGalleries, .galleriesHighestImageCount:
        return 125
    case .channels:
        return width
    default:
        return 125
    }
}

// MARK: - Hero backdrop

/// Blurred wash behind the first (large) dashboard row. Equatable so horizontal
/// `scrollPosition` churn does not rebuild the safe-area-ignoring host unless the
/// focused thumbnail actually changes — that remount was flickering the status bar.
private struct HomeDashboardHeroBackdrop: View, Equatable {
    let thumbnailURL: URL?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.thumbnailURL == rhs.thumbnailURL
    }

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .frame(height: geo.size.height + 500 + 12) // 500pt top + 12pt bottom extension
                .overlay(alignment: .bottom) {
                    ZStack {
                        if let thumbnailURL {
                            CustomAsyncImage(url: thumbnailURL) { loader in
                                if let image = loader.image {
                                    image.resizable().scaledToFill()
                                }
                            }
                            .id(thumbnailURL.absoluteString)
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.5), value: thumbnailURL?.absoluteString)
                    .scaleEffect(1.3)
                    .blur(radius: 40)
                    .frame(maxWidth: .infinity)
                    .frame(height: 1200)
                }
                .clipped()
                .offset(y: -500)
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - HomeRowView

struct HomeRowView: View {
    let config: HomeRowConfig
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var tabManager = TabManager.shared
    var isLarge: Bool = false
    var isFirst: Bool = false
    @State private var scrollID: String?
    @EnvironmentObject var coordinator: NavigationCoordinator

    // MARK: - Derived content

    private var scenes: [Scene]       { viewModel.homeRowScenes[config.type] ?? [] }
    private var performers: [Performer] { viewModel.homeRowPerformers[config.type] ?? [] }
    private var studios: [Studio]     { viewModel.homeRowStudios[config.type] ?? [] }
    private var galleries: [Gallery]  { viewModel.homeRowGalleries[config.type] ?? [] }

    private var items: [String] {
        switch config.type {
        case .newPerformers, .performersHighestSceneCount, .performersHighestOCount, .performersHighestRating: return performers.map(\.id)
        case .newStudios, .studiosHighestSceneCount:                                 return studios.map(\.id)
        case .newGalleries, .recentlyUpdatedGalleries, .galleriesHighestImageCount:  return galleries.map(\.id)
        default:                                                                     return scenes.map(\.id)
        }
    }

    private var isEmpty: Bool { items.isEmpty }
    private var isLoading: Bool { isEmpty && (viewModel.homeRowLoadingState[config.type] ?? true) }

    // MARK: - Body

    var body: some View {
        let screenWidth = UIScreen.main.bounds.width

        VStack(alignment: .leading, spacing: isLarge ? 8 : 12) {
            headerRow
                .padding(.top, isFirst ? 16 : 0)

            if isLoading {
                loadingPlaceholder(screenWidth: screenWidth)
            } else if isEmpty {
                emptyState
            } else {
                mainContent(screenWidth: screenWidth)
            }
        }
        .padding(.top, 0)
        .padding(.bottom, 0)
        .background {
            if isLarge && isFirst && tabManager.showDashboardHeroBackground {
                let focusedScene = scenes.first { $0.id == scrollID } ?? scenes.first
                // Keep the under-status-bar host mounted; only swap the image.
                // Remounting `.ignoresSafeArea` on every scroll snap flickers the status bar.
                HomeDashboardHeroBackdrop(thumbnailURL: focusedScene?.thumbnailURL)
                    .equatable()
            }
        }
        .onAppear { checkAndLoad() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { n in
            if let tabId = n.userInfo?["tab"] as? String, tabId == AppTab.dashboard.rawValue {
                viewModel.homeRowScenes[config.type] = nil
                checkAndLoad()
            }
        }
        // Keep in-place row caches in sync with SceneDetailView changes.
        .sceneLiveUpdates(using: viewModel)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            viewModel.homeRowScenes[config.type] = nil
            viewModel.homeRowPerformers[config.type] = nil
            viewModel.homeRowStudios[config.type] = nil
            viewModel.homeRowGalleries[config.type] = nil
            checkAndLoad()
        }
        .onChange(of: viewModel.savedFilters) { _, _ in checkAndLoad() }
        .onChange(of: viewModel.isLoadingSavedFilters) { old, new in
            if old && !new { checkAndLoad() }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        Button(action: openCatalogCategory) {
            HStack(spacing: 4) {
                Text(config.title)
                    .font(.headline)
                    .foregroundColor(isLarge ? .white : .primary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isLarge ? .white.opacity(0.7) : .secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Switch Home catalogue sub-tab (menu selection) instead of pushing a nested list.
    private func openCatalogCategory() {
        switch config.type {
        case .newPerformers:
            coordinator.navigateToPerformers(sort: .createdAtDesc)
        case .performersHighestSceneCount:
            coordinator.navigateToPerformers(sort: .sceneCountDesc)
        case .performersHighestOCount:
            coordinator.navigateToPerformers(sort: .oCountDesc)
        case .performersHighestRating:
            coordinator.navigateToPerformers(sort: .ratingDesc)
        case .newStudios:
            coordinator.navigateToStudios(sort: .createdAtDesc)
        case .studiosHighestSceneCount:
            coordinator.navigateToStudios(sort: .sceneCountDesc)
        case .newGalleries:
            coordinator.navigateToGalleries(sort: .createdAtDesc)
        case .recentlyUpdatedGalleries:
            coordinator.navigateToGalleries(sort: .updatedAtDesc)
        case .galleriesHighestImageCount:
            coordinator.navigateToGalleries(sort: .imageCountDesc)
        default:
            coordinator.navigateToScenes(sort: sortOption())
        }
    }

    // MARK: - States

    @ViewBuilder
    private func loadingPlaceholder(screenWidth: CGFloat) -> some View {
        let w = homeCardWidth(for: config, isLarge: isLarge, screenWidth: screenWidth)
        let h = homeCardHeight(for: config, isLarge: isLarge, screenWidth: screenWidth)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                        .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                        .frame(width: w, height: h)
                        .overlay(ProgressView())
                }
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Text("No content found")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
    }

    private func contentHeight(screenWidth: CGFloat) -> CGFloat {
        let cardH = homeCardHeight(for: config, isLarge: isLarge, screenWidth: screenWidth)
        let headerH: CGFloat = 24   // headline
        let spacing: CGFloat = isLarge ? 8 : 12
        return headerH + spacing + cardH
    }

    // MARK: - Main scroll content

    @ViewBuilder
    private func mainContent(screenWidth: CGFloat) -> some View {
        let w = homeCardWidth(for: config, isLarge: isLarge, screenWidth: screenWidth)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                switch config.type {
                case .newPerformers, .performersHighestSceneCount:
                    ForEach(performers) { p in
                        cardLink(destination: PerformerDetailView(performer: p), id: p.id, width: w) {
                            HomePerformerCardView(performer: p, config: config, badgeType: .sceneCount,
                                                 isLarge: isLarge, screenWidth: screenWidth)
                        }
                    }
                case .performersHighestOCount:
                    ForEach(performers.sorted { ($0.oCounter ?? 0) > ($1.oCounter ?? 0) }.prefix(10)) { p in
                        cardLink(destination: PerformerDetailView(performer: p), id: p.id, width: w) {
                            HomePerformerCardView(performer: p, config: config, badgeType: .oCount,
                                                 isLarge: isLarge, screenWidth: screenWidth)
                        }
                    }
                case .performersHighestRating:
                    ForEach(performers) { p in
                        cardLink(destination: PerformerDetailView(performer: p), id: p.id, width: w) {
                            HomePerformerCardView(performer: p, config: config, badgeType: .rating,
                                                 isLarge: isLarge, screenWidth: screenWidth)
                        }
                    }
                case .newStudios, .studiosHighestSceneCount:
                    ForEach(studios) { s in
                        cardLink(destination: StudioDetailView(studio: s), id: s.id, width: w) {
                            HomeStudioCardView(studio: s, config: config, isLarge: isLarge, screenWidth: screenWidth)
                        }
                    }
                case .newGalleries, .recentlyUpdatedGalleries, .galleriesHighestImageCount:
                    ForEach(galleries) { g in
                        cardLink(destination: ImagesView(gallery: g), id: g.id, width: w) {
                            GalleryCardView(gallery: g).frame(width: isLarge ? w : 125, height: 125)
                        }
                    }
                default:
                    ForEach(scenes) { scene in
                        cardLink(destination: SceneDetailView(scene: scene), id: scene.id, width: w) {
                            HomeSceneCardView(scene: scene, isLarge: isLarge, screenWidth: screenWidth)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollID)
        .scrollTargetBehavior(.viewAligned)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func cardLink<Dest: View, Card: View>(
        destination: Dest, id: String, width: CGFloat,
        @ViewBuilder card: () -> Card
    ) -> some View {
        NavigationLink(destination: destination) { card() }
            .buttonStyle(.plain)
            .frame(width: width)
            .id(id)
    }

    // MARK: - Load logic

    private func checkAndLoad() {
        if let filterId = TabManager.shared.getDefaultFilterId(for: .dashboard) {
            if viewModel.savedFilters[filterId] != nil || !viewModel.isLoadingSavedFilters {
                viewModel.refreshHomeRow(config: config, limit: 10)
            }
        } else {
            viewModel.refreshHomeRow(config: config, limit: 10)
        }
    }

    private func sortOption() -> StashDBViewModel.SceneSortOption? {
        switch config.type {
        case .lastPlayed:    return .lastPlayedAtDesc
        case .lastAdded3Min: return .createdAtDesc
        case .newest3Min:    return .dateDesc
        case .mostViewed3Min: return .playCountDesc
        case .topCounter3Min: return .oCounterDesc
        case .topRating3Min: return .ratingDesc
        case .random:        return .random
        default:             return nil
        }
    }
}

// MARK: - HomePerformerCardView

struct HomePerformerCardView: View {
    let performer: Performer
    let config: HomeRowConfig
    var badgeType: PerformerBadgeType = .sceneCount
    var isLarge: Bool = false
    let screenWidth: CGFloat
    @ObservedObject var appearanceManager = AppearanceManager.shared

    private var cardWidth: CGFloat  { homeCardWidth(for: config, isLarge: isLarge, screenWidth: screenWidth) }
    private var cardHeight: CGFloat { cardWidth * (isLarge ? 9.0 / 16.0 : 3.0 / 2.0) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                ZStack {
                    Rectangle().fill(Color.gray.opacity(0.2))
                    if let url = performer.thumbnailURL {
                        CustomAsyncImage(url: url) { loader in
                            if loader.isLoading {
                                ProgressView()
                            } else if let image = loader.image {
                                image.resizable().scaledToFill()
                                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                                    .clipped()
                            } else {
                                Image(systemName: "person.fill").foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Image(systemName: "person.fill").foregroundColor(.secondary)
                    }
                }
            }

            LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                .frame(height: 50)
                .frame(maxHeight: .infinity, alignment: .bottom)

            VStack {
                HStack(alignment: .top) {
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: badgeType == .oCount ? appearanceManager.oCounterIcon : (badgeType == .rating ? "star.fill" : "film"))
                            .font(.system(size: 8, weight: .bold))
                        Text(
                            badgeType == .oCount
                                ? "\(performer.oCounter ?? 0)"
                                : (badgeType == .rating ? "\(performer.rating100 ?? 0)" : "\(performer.sceneCount)")
                        )
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                    .clipShape(Capsule())
                }
                Spacer()
                Text(performer.name)
                    .font(.system(size: isLarge ? 12 : 10, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
            }
            .padding(6)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .contentShape(Rectangle())
    }
}

// MARK: - HomeStudioCardView

struct HomeStudioCardView: View {
    let studio: Studio
    let config: HomeRowConfig
    var isLarge: Bool = false
    let screenWidth: CGFloat
    @ObservedObject var appearanceManager = AppearanceManager.shared

    private var cardWidth: CGFloat  { homeCardWidth(for: config, isLarge: isLarge, screenWidth: screenWidth) }
    private var cardHeight: CGFloat { cardWidth * 9 / 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                Color.studioHeaderGray
                StudioImageView(studio: studio)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: cardHeight - (isLarge ? 36 : 32))

            HStack(spacing: 8) {
                Text(studio.name)
                    .font(.system(size: isLarge ? 12 : 10, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Image(systemName: "film").font(.system(size: isLarge ? 10 : 8))
                        Text("\(studio.sceneCount)").font(.system(size: isLarge ? 11 : 9, weight: .medium))
                    }
                    if let gc = studio.galleryCount, gc > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "photo.stack").font(.system(size: isLarge ? 10 : 8))
                            Text("\(gc)").font(.system(size: isLarge ? 11 : 9, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.1))
                        .clipShape(Capsule())
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
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .contentShape(Rectangle())
        .cardShadow()
    }
}

#endif
