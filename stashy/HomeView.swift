#if !os(tvOS)
import SwiftUI

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

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            // Lazy: rows below the fold are built (and their cards, preview players and
            // image loaders allocated) only when they scroll into view.
            LazyVStack(spacing: 24) {
                // stashy+ rows drop out entirely while locked.
                let activeRows = tabManager.homeRows.filter {
                    $0.isEnabled && (!$0.type.requiresStashyPlus || stashyPlus.isUnlocked)
                        && ($0.type != .recommendations || isForYouOn)
                        && ($0.type != .forgottenFavorites || (isForgottenOn && !isForgottenEmpty))
                }
                let firstRowId = activeRows.first?.id
                // For You and Forgotten Favorites are scene rows too and take the hero when first.
                let firstSceneRowId = activeRows.first(where: {
                    $0.type != .statistics && (!$0.type.requiresStashyPlus || $0.type == .recommendations
                        || $0.type == .forgottenFavorites)
                })?.id

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
            // The rows keep their cards and reload in place. Emptied first, every row fell back
            // to "No content found" for the length of the request, the hero row shrank and the
            // rows below jumped up and back.
            viewModel.initializeServerConnection()
            for row in tabManager.homeRows where row.isEnabled && row.type != .statistics && !row.type.requiresStashyPlus {
                viewModel.loadHomeRowIfNeeded(config: row, maxAge: 0)
            }
            // The spinner stays until the new For You list is on screen.
            async let forgotten: Void = ForgottenFavoritesEngine.shared.rebuildAndWait()
            await SceneRecommendationEngine.shared.rebuildAndWait()
            await forgotten
        }
    }
}
#endif
