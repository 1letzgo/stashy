
#if !os(tvOS)
import SwiftUI
import CoreImage
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Card dimension helpers

private let homeHeroCardWidthFraction: CGFloat = 0.8
private let homeHeroCardFixedWidth: CGFloat = 280

/// Up to this width the hero card follows the space it has (upright iPhone, closed iPhone Duo).
private let homeHeroCardFractionMaxWidth: CGFloat = 520

func homeHeroCardWidth(screenWidth: CGFloat) -> CGFloat {
    if screenWidth > 0, screenWidth < homeHeroCardFractionMaxWidth {
        return screenWidth * homeHeroCardWidthFraction
    }
    return homeHeroCardFixedWidth
}

extension EnvironmentValues {
    /// Width of the dashboard, measured in `HomeView`. Zero until its first layout.
    @Entry var homeContentWidth: CGFloat = 0
}

/// Edge length of the square dashboard cards (Channels, Statistics) — one source so the two
/// rows cannot drift apart.
let homeSquareCardSide: CGFloat = 125

func homeCardWidth(for config: HomeRowConfig, isLarge: Bool, screenWidth: CGFloat) -> CGFloat {
    if isLarge { return homeHeroCardWidth(screenWidth: screenWidth) }
    switch config.contentKind {
    case .performers:
        return 125 * 2 / 3
    case .galleries:
        return 125
    case .other where config.type == .channels:
        // Channels show a category logo, not a thumbnail — square card.
        return homeSquareCardSide
    default:
        return 125 * 16 / 9
    }
}

func homeCardHeight(for config: HomeRowConfig, isLarge: Bool, screenWidth: CGFloat) -> CGFloat {
    let width = homeCardWidth(for: config, isLarge: isLarge, screenWidth: screenWidth)
    if isLarge {
        switch config.contentKind {
        case .performers:
            return width * 3 / 2
        case .galleries:
            return 125
        case .other where config.type == .channels:
            return width
        default:
            return width * 9 / 16
        }
    }
    switch config.contentKind {
    case .performers:
        return width * 3 / 2
    case .galleries:
        return 125
    case .other where config.type == .channels:
        return width
    default:
        return 125
    }
}

// MARK: - Hero backdrop

/// Blurred wash behind the first (large) dashboard row. Equatable so horizontal
/// `scrollPosition` churn does not rebuild the safe-area-ignoring host unless the
/// focused thumbnail actually changes — that remount was flickering the status bar.
struct HomeDashboardHeroBackdrop: View, Equatable {
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
                            HeroBackdropImage(url: thumbnailURL)
                                .id(thumbnailURL.absoluteString)
                                .transition(.opacity)
                        } else if let last = HeroBackdropBlur.lastShown {
                            // Pull to refresh empties the row while it reloads: the wash stays
                            // instead of flashing to the plain background and back.
                            Image(uiImage: last)
                                .resizable()
                                .interpolation(.medium)
                                .scaledToFill()
                        }
                    }
                    .animation(.easeInOut(duration: 0.5), value: thumbnailURL?.absoluteString)
                    .scaleEffect(1.3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 1200)
                }
                .clipped()
                .offset(y: -500)
        }
        // Horizontal too: in landscape the backdrop otherwise ends hard at the safe area.
        .ignoresSafeArea(edges: [.top, .horizontal])
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The backdrop's image, blurred once on a small copy. A live `.blur(radius: 40)` over a
/// 1200 pt layer was redrawn by the GPU on every frame Home scrolled (with the glass chrome
/// sampling it once more), which held the Pro's display far below its refresh rate.
private struct HeroBackdropImage: View {
    let url: URL
    /// Starts from the blur cache: a rebuilt row (pull to refresh, scrolling back) shows the
    /// wash in its first frame instead of fading it in again.
    @State private var image: UIImage?

    init(url: URL) {
        self.url = url
        _image = State(initialValue: HeroBackdropBlur.cachedImage(for: url))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: image != nil)
        .task(id: url) {
            guard image == nil else { return }
            image = await HeroBackdropBlur.image(for: url)
        }
    }
}

enum HeroBackdropBlur {
    private static var cache: [URL: UIImage] = [:]
    nonisolated(unsafe) private static let context = CIContext()
    /// The wash shown last, kept on while the hero row reloads.
    private(set) static var lastShown: UIImage?

    static func cachedImage(for url: URL) -> UIImage? {
        if let cached = cache[url] { lastShown = cached }
        return cache[url]
    }

    static func image(for url: URL) async -> UIImage? {
        if let cached = cache[url] {
            lastShown = cached
            return cached
        }
        guard let source = await ImageLoader.uiImage(for: url)?.cgImage else { return nil }
        guard let blurred = await Task.detached(priority: .userInitiated, operation: {
            Self.blurred(source)
        }).value else { return nil }
        if cache.count > 24 { cache.removeAll() }
        let image = UIImage(cgImage: blurred)
        cache[url] = image
        lastShown = image
        return image
    }

    /// 64 px wide, then a Gaussian blur as wide as the old 40 pt one relative to the image.
    nonisolated private static func blurred(_ source: CGImage) -> CGImage? {
        let width = 64
        let height = max(1, Int((Double(source.height) * Double(width) / Double(max(source.width, 1))).rounded()))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = ctx.makeImage() else { return nil }
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        let output = CIImage(cgImage: small)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 4.5)
            .cropped(to: extent)
        return context.createCGImage(output, from: extent)
    }
}

// MARK: - HomeRowView

struct HomeRowView: View {
    let config: HomeRowConfig
    /// Deliberately **not** `@ObservedObject`: the row must not redraw on every publish
    /// of the big view model. It only observes its own `HomeRowStore`.
    let viewModel: StashDBViewModel
    @ObservedObject var store: HomeRowStore
    @ObservedObject var tabManager = TabManager.shared
    var isLarge: Bool = false
    var isFirst: Bool = false
    @State private var scrollID: String?
    @EnvironmentObject var coordinator: NavigationCoordinator

    init(config: HomeRowConfig, viewModel: StashDBViewModel, isLarge: Bool = false, isFirst: Bool = false) {
        self.config = config
        self.viewModel = viewModel
        self.store = viewModel.homeRowStore(for: config)
        self.isLarge = isLarge
        self.isFirst = isFirst
    }

    // MARK: - Derived content

    private var scenes: [Scene]       { store.scenes }
    private var performers: [Performer] { store.performers }
    private var studios: [Studio]     { store.studios }
    private var galleries: [Gallery]  { store.galleries }

    private var items: [String] {
        switch config.contentKind {
        case .performers: return performers.map(\.id)
        case .studios:    return studios.map(\.id)
        case .galleries:  return galleries.map(\.id)
        default:          return scenes.map(\.id)
        }
    }

    private var isEmpty: Bool { items.isEmpty }
    private var isLoading: Bool { isEmpty && store.isLoading }

    // MARK: - Body

    @Environment(\.homeContentWidth) private var homeContentWidth

    var body: some View {
        let screenWidth = homeContentWidth

        VStack(alignment: .leading, spacing: isLarge ? 8 : 12) {
            headerRow

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
                let focusedID = HomeHeroPreview.shared.focusedID(row: config.id.uuidString, current: scrollID, in: scenes.map(\.id))
                let focusedScene = scenes.first { $0.id == focusedID }
                // Keep the under-status-bar host mounted; only swap the image.
                // Remounting `.ignoresSafeArea` on every scroll snap flickers the status bar.
                HomeDashboardHeroBackdrop(thumbnailURL: focusedScene?.thumbnailURL)
                    .equatable()
            }
        }
        // Inside the dashboard's `LazyVStack` this fires when the row scrolls into view,
        // so rows below the fold load on demand. Filter / server / live-update listeners
        // live once in `HomeView`, not once per row.
        .onAppear { viewModel.loadHomeRowIfNeeded(config: config) }
        // A custom row whose filter or kind changed reloads (a new title alone does not).
        .onChange(of: config) { _, newConfig in
            if newConfig.type == .customFilter { viewModel.loadHomeRowIfNeeded(config: newConfig) }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        Button(action: openCatalogCategory) {
            HStack(spacing: 4) {
                Text(config.displayTitle)
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
        case .customFilter:
            openCustomFilterList()
        default:
            coordinator.navigateToScenes(sort: sortOption())
        }
    }

    /// A custom row opens its list with the row's saved filter and sort applied
    /// (`NavigationCoordinator.activeFilter`, taken by the list of the matching mode); a row
    /// built from a sort opens the list in that order.
    private func openCustomFilterList() {
        let filter = config.filterId.flatMap { viewModel.savedFilters[$0] }
        typealias VM = StashDBViewModel
        switch config.filterMode {
        case .performers:
            coordinator.navigateToPerformers(sort: customPerformerSort, filter: filter)
        case .studios:
            coordinator.navigateToStudios(sort: customStudioSort, filter: filter)
        case .galleries:
            let sort = filter.flatMap { VM.savedFilterSortOption($0, VM.GallerySortOption.self, raw: { VM.GallerySortOption(rawValue: $0) }, field: { $0.sortField }, direction: { $0.direction }) }
                ?? config.sortRaw.flatMap { VM.GallerySortOption(rawValue: $0) }
            coordinator.navigateToGalleries(sort: sort, filter: filter)
        default:
            let sort = filter.flatMap { VM.savedFilterSortOption($0, VM.SceneSortOption.self, raw: { VM.SceneSortOption(rawValue: $0) }, field: { $0.sortField }, direction: { $0.direction }) }
                ?? config.sortRaw.flatMap { VM.SceneSortOption(rawValue: $0) }
            coordinator.navigateToScenes(sort: sort, filter: filter)
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
        Text(store.missingFilter ? tr("action_filter_not_found") : tr("empty_content_found"))
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
                switch config.contentKind {
                case .performers:
                    ForEach(shownPerformers) { p in
                        cardLink(destination: PerformerDetailView(performer: p), id: p.id, width: w) {
                            HomePerformerCardView(performer: p, config: config, badgeType: performerBadge,
                                                 isLarge: isLarge, screenWidth: screenWidth)
                        }
                    }
                case .studios:
                    ForEach(studios) { s in
                        cardLink(destination: StudioDetailView(studio: s), id: s.id, width: w) {
                            HomeStudioCardView(studio: s, config: config, badge: studioBadge, isLarge: isLarge, screenWidth: screenWidth)
                        }
                    }
                case .galleries:
                    ForEach(galleries) { g in
                        cardLink(destination: ImagesView(gallery: g), id: g.id, width: w) {
                            GalleryCardView(gallery: g, compactTitle: !isLarge).frame(width: isLarge ? w : 125, height: 125)
                        }
                    }
                default:
                    ForEach(scenes) { scene in
                        cardLink(destination: SceneDetailView(scene: scene), id: scene.id, width: w) {
                            HomeSceneCardView(scene: scene, isLarge: isLarge, screenWidth: screenWidth,
                                              autoplaysPreview: heroAutoplays(scene.id))
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .scrollTargetLayout()
        }
        .homeRowPosition($scrollID, row: config.id.uuidString, ids: items)
        .scrollTargetBehavior(.viewAligned)
        .scrollContentBackground(.hidden)
    }

    private var performerBadge: PerformerBadgeType {
        switch config.type {
        case .performersHighestOCount: return .oCount
        case .performersHighestRating: return .rating
        case .customFilter:            return customPerformerSort.map(PerformerBadgeType.forSort) ?? .sceneCount
        default:                       return .sceneCount
        }
    }

    /// A custom row's order: its saved filter's sort, or the sort the row was built from.
    private var customPerformerSort: StashDBViewModel.PerformerSortOption? {
        typealias VM = StashDBViewModel
        let filter = config.filterId.flatMap { viewModel.savedFilters[$0] }
        return filter.flatMap { VM.savedFilterSortOption($0, VM.PerformerSortOption.self, raw: { VM.PerformerSortOption(rawValue: $0) }, field: { $0.sortField }, direction: { $0.direction }) }
            ?? config.sortRaw.flatMap { VM.PerformerSortOption(rawValue: $0) }
    }

    private var customStudioSort: StashDBViewModel.StudioSortOption? {
        typealias VM = StashDBViewModel
        let filter = config.filterId.flatMap { viewModel.savedFilters[$0] }
        return filter.flatMap { VM.savedFilterSortOption($0, VM.StudioSortOption.self, raw: { VM.StudioSortOption(rawValue: $0) }, field: { $0.sortField }, direction: { $0.direction }) }
            ?? config.sortRaw.flatMap { VM.StudioSortOption(rawValue: $0) }
    }

    /// Studio cards of a custom row show the count the row is sorted by.
    private var studioBadge: CatalogCardBadge {
        guard config.type == .customFilter, let sort = customStudioSort else { return .scenes }
        return CatalogCardBadge(sortField: sort.sortField)
    }

    private var shownPerformers: [Performer] {
        config.type == .performersHighestOCount
            ? Array(performers.sorted { ($0.oCounter ?? 0) > ($1.oCounter ?? 0) }.prefix(10))
            : performers
    }

    /// `destination` ist eine Autoclosure: die Detailseite entsteht erst beim Push,
    /// nicht für jede Karte der Reihe beim Scrollen.
    @ViewBuilder
    private func cardLink<Dest: View, Card: View>(
        destination: @autoclosure @escaping () -> Dest, id: String, width: CGFloat,
        @ViewBuilder card: () -> Card
    ) -> some View {
        NavigationLink(destination: LazyView(destination)) { card() }
            .buttonStyle(.plain)
            .frame(width: width)
            .id(id)
    }

    /// Hero Autoplay: the focused card of the first, large row.
    private func heroAutoplays(_ id: String) -> Bool {
        isLarge && isFirst && tabManager.dashboardHeroAutoplay && HomeHeroPreview.shared.focusedID(row: config.id.uuidString, current: scrollID, in: scenes.map(\.id)) == id
    }

    // MARK: - Sort mapping

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
                        Image(systemName: badgeType.icon(oCounterIcon: appearanceManager.oCounterIcon))
                            .font(.system(size: 8, weight: .bold))
                        Text("\(badgeType.value(for: performer))")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .stashyGlass(shape: Capsule())
                }
                Spacer()
                Text(performer.name)
                    .font(.system(size: 12, weight: .bold))
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
    var badge: CatalogCardBadge = .scenes
    var isLarge: Bool = false
    let screenWidth: CGFloat

    private var cardWidth: CGFloat { homeCardWidth(for: config, isLarge: isLarge, screenWidth: screenWidth) }

    /// The Studios list's card (counts as pills, logo centred, name below) at the row's width.
    var body: some View {
        StudioCardView(studio: studio, badge: badge)
            .frame(width: cardWidth)
    }
}

#endif
