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
                    viewModel.fetchStatistics()
                    // Only rows whose cache is older than the freshness window refetch.
                    // Coming back from a detail page used to reload every row.
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
        for row in tabManager.homeRows where row.isEnabled && row.type != .statistics && row.type != .channels {
            viewModel.loadHomeRowIfNeeded(config: row)
        }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            // Lazy: rows below the fold are built (and their cards, preview players and
            // image loaders allocated) only when they scroll into view.
            LazyVStack(spacing: 24) {
                let activeRows = tabManager.homeRows.filter { $0.isEnabled }
                let firstRowId = activeRows.first?.id
                let firstSceneRowId = activeRows.first(where: { $0.type != .statistics && $0.type != .channels })?.id

                ForEach(tabManager.homeRows) { row in
                    if row.isEnabled {
                        if row.type == .statistics {
                            HomeStatisticsRowView(viewModel: viewModel, isFirst: row.id == firstRowId)
                        } else if row.type == .channels && stashyPlus.isUnlocked {
                            HomeChannelsRowView(config: row,
                                                viewModel: viewModel,
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
        .scrollContentBackground(.hidden)
        .refreshable {
            viewModel.homeRowScenes.removeAll()
            viewModel.homeRowPerformers.removeAll()
            viewModel.homeRowStudios.removeAll()
            viewModel.homeRowGalleries.removeAll()
            viewModel.initializeServerConnection()
        }
    }
}
#endif
