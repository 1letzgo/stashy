#if !os(tvOS)
import SwiftUI
import Combine

/// Dashboard; mit ``catalogBrowserViewModel`` dasselbe VM wie die anderen Katalog-Tabs (Daten bleiben beim Unter-Tab-Wechsel warm).
struct HomeView: View {
    @StateObject private var ownedViewModel = StashDBViewModel()
    let catalogBrowserViewModel: StashDBViewModel?

    init(catalogBrowserViewModel: StashDBViewModel? = nil) {
        self.catalogBrowserViewModel = catalogBrowserViewModel
    }

    var body: some View {
        HomeViewContent(viewModel: catalogBrowserViewModel ?? ownedViewModel)
    }
}

private struct HomeViewContent: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var contentWidth: CGFloat = 0
    /// Mirrors `SceneRecommendationEngine.isFeatureOn` without observing the whole engine.
    @State private var isForYouOn = SceneRecommendationEngine.shared.isFeatureOn
    @State private var isForgottenOn = ForgottenFavoritesEngine.shared.isFeatureOn
    @State private var isForgottenEmpty = ForgottenFavoritesEngine.shared.isEmptyAndReady
    @State private var statisticsRefresh: Task<Void, Never>?

    private static let statisticsChanges = Publishers.MergeMany(
        ["SceneDeleted", "ScenePlayAdded", "SceneOCounterUpdated", "ImageDeleted", "ImageOCounterUpdated",
         "PerformerDeleted", "StudioDeleted", "TagDeleted", "GroupDeleted", "GalleryDeleted"]
            .map { NotificationCenter.default.publisher(for: NSNotification.Name($0)) }
    )

    var body: some View {
        // Workaround for occasional Swift compiler diagnostic/type-check issues:
        // keep the view builder shallow and apply modifiers on a separate value.
        let base = ZStack {
            if configManager.activeConfig == nil {
                ConnectionErrorView { viewModel.fetchStatistics() }
            } else if viewModel.statistics == nil && viewModel.errorMessage != nil {
                ConnectionErrorView { viewModel.fetchStatistics() }
            } else {
                dashboardContent
            }
        }

        return base
            // Custom catalogue chrome owns the top; a live `navigationTitle` under a
            // hidden system bar makes iOS toggle status-bar appearance while scrolling.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .statusBarHidden(false)
            .onAppear {
                guard configManager.activeConfig != nil else { return }
                if viewModel.statistics == nil {
                    viewModel.initializeServerConnection()
                } else {
                    // Within a session Home keeps what it loaded (pull to refresh reloads);
                    // only rows that are still empty load here.
                    loadRowsIfNeeded()
                }
            }
            // The server reset clears every row cache, so `loadHomeRowIfNeeded` refetches.
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
                viewModel.initializeServerConnection()
            }
            // Once for the whole dashboard. Each row used to subscribe on its own, so a
            // single resume-time update ran through every row's handler.
            .sceneLiveUpdates(using: viewModel)
            .onReceive(SceneRecommendationEngine.shared.$isFeatureOn.removeDuplicates()) { isForYouOn = $0 }
            .onReceive(ForgottenFavoritesEngine.shared.$isFeatureOn.removeDuplicates()) { isForgottenOn = $0 }
            .onReceive(ForgottenFavoritesEngine.shared.$isEmptyAndReady.removeDuplicates()) { isForgottenEmpty = $0 }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
                if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.dashboard.rawValue {
                    viewModel.homeRowScenes.removeAll()
                    viewModel.initializeServerConnection()
                }
            }
            // Statistics count scenes, plays, O counts and the catalog: refetch once shortly after
            // one of them changed (several changes in a row are one request).
            .onReceive(Self.statisticsChanges) { _ in
                statisticsRefresh?.cancel()
                statisticsRefresh = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled, viewModel.statistics != nil else { return }
                    viewModel.fetchStatistics()
                }
            }
            // Rows that waited for the default dashboard filter load once filters are in.
            .onChange(of: viewModel.savedFilters) { _, _ in loadRowsIfNeeded() }
            .onChange(of: viewModel.isLoadingSavedFilters) { old, new in
                if old && !new { loadRowsIfNeeded() }
            }
    }

    private func loadRowsIfNeeded() {
        for row in tabManager.homeRows where row.isEnabled && row.type != .statistics && !row.type.requiresStashyPlus {
            viewModel.loadHomeRowIfNeeded(config: row)
        }
    }

    /// Rows on screen: stashy+ rows drop out entirely while locked.
    private var activeRows: [HomeRowConfig] {
        tabManager.homeRows.filter {
            $0.isEnabled && (!$0.type.requiresStashyPlus || stashyPlus.isUnlocked)
                && ($0.type != .recommendations || isForYouOn)
                && ($0.type != .forgottenFavorites || (isForgottenOn && !isForgottenEmpty))
        }
    }

    /// For You and Forgotten Favorites are scene rows too and take the hero when first.
    private func firstSceneRowId(in rows: [HomeRowConfig]) -> UUID? {
        rows.first(where: {
            $0.type != .statistics && (!$0.type.requiresStashyPlus || $0.type == .recommendations
                || $0.type == .forgottenFavorites)
                // A custom row takes the hero only when it lists scenes.
                && ($0.type != .customFilter || $0.filterMode == .scenes)
        })?.id
    }

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            // Lazy: rows below the fold are built (and their cards, preview players and
            // image loaders allocated) only when they scroll into view.
            LazyVStack(spacing: 24) {
                let activeRows = activeRows
                let firstRowId = activeRows.first?.id
                let firstSceneRowId = firstSceneRowId(in: activeRows)

                ForEach(activeRows) { row in
                    if row.isEnabled {
                        if row.type == .statistics {
                            HomeStatisticsRowView(viewModel: viewModel, isFirst: row.id == firstRowId)
                        } else if row.type == .channels && stashyPlus.isUnlocked {
                            HomeChannelsRowView(config: row,
                                                viewModel: viewModel,
                                                isFirst: row.id == firstRowId)
                        } else if row.type == .recommendations {
                            HomeRecommendationsRowView(config: row,
                                                       isLarge: row.id == firstSceneRowId,
                                                       isFirst: row.id == firstRowId)
                        } else if row.type == .forgottenFavorites {
                            HomeForgottenFavoritesRowView(config: row,
                                                          isLarge: row.id == firstSceneRowId,
                                                          isFirst: row.id == firstRowId)
                        } else {
                            HomeRowView(config: row,
                                        viewModel: viewModel,
                                        isLarge: row.id == firstSceneRowId,
                                        isFirst: row.id == firstRowId)
                        }
                    }
                }
            }
            // Same gap above the tab bar as the catalog lists leave under their last card.
            .padding(.bottom, 16)
            #if os(iOS)
            .background(RefreshControlOnTop())
            #endif
        }
        .collapsesCatalogChrome()
        .scrollContentBackground(.hidden)
        // Hero Autoplay: pause the hero preview while Home is off screen, carry on when back.
        .onAppear { HomeHeroPreview.shared.setHomeVisible(true) }
        .onDisappear { HomeHeroPreview.shared.setHomeVisible(false) }
        .onChange(of: tabManager.dashboardHeroAutoplay) { _, on in
            if !on { HomeHeroPreview.shared.stop() }
        }
        .environment(\.homeContentWidth, contentWidth)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            guard abs(width - contentWidth) > 1 else { return }
            contentWidth = width
        }
        .refreshable {
            // Unstructured: the rows reload in place and publish at once, the view updates, and
            // SwiftUI cancels the `.refreshable` task on that. Every wait below then returned
            // immediately and the spinner was gone before anything had reloaded.
            await Task { @MainActor in await reloadDashboard() }.value
        }
    }

    private func reloadDashboard() async {
        // The rows keep their cards and reload in place. Emptied first, every row fell back
        // to "No content found" for the length of the request, the hero row shrank and the
        // rows below jumped up and back.
        viewModel.initializeServerConnection()
        for row in tabManager.homeRows where row.isEnabled && row.type != .statistics && !row.type.requiresStashyPlus {
            viewModel.loadHomeRowIfNeeded(config: row, maxAge: 0)
        }
        // The spinner stays until the new For You list is on screen and the rows are back.
        async let forgotten: Void = ForgottenFavoritesEngine.shared.rebuildAndWait()
        await SceneRecommendationEngine.shared.rebuildAndWait()
        await forgotten
        // Short floor so the spinner is seen at all, then until the row requests are done
        // (capped: a hanging request must not pin it).
        try? await Task.sleep(nanoseconds: 400_000_000)
        var waited = 0
        while viewModel.isFetchingAnyHomeRow, waited < 80 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
    }
}
#if os(iOS)
/// The hero backdrop reaches 500 pt above the first row and is scroll content, so it draws over
/// the system's refresh spinner, which sits behind the content: the pulled gap showed only the
/// backdrop. This lifts the scroll view's own refresh control above the content, so Home shows
/// the same single spinner as every list.
private struct RefreshControlOnTop: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) { uiView.raise() }

    final class Probe: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            raise()
            // The refresh control may be attached right after the content.
            DispatchQueue.main.async { [weak self] in self?.raise() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            raise()
        }

        func raise() {
            var view = superview
            while let current = view {
                if let scroll = current as? UIScrollView {
                    scroll.refreshControl?.layer.zPosition = 1
                    return
                }
                view = current.superview
            }
        }
    }
}
#endif
#endif
