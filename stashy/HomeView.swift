#if !os(tvOS)
import SwiftUI
import AVKit

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
                    for row in tabManager.homeRows where row.isEnabled && row.type != .statistics {
                        viewModel.refreshHomeRow(config: row, limit: 10)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
                viewModel.initializeServerConnection()
            }
            .sceneLiveUpdates(using: viewModel)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
                if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.dashboard.rawValue {
                    viewModel.initializeServerConnection()
                }
            }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                let activeRows = tabManager.homeRows.filter { $0.isEnabled }
                let firstRowId = activeRows.first?.id
                let firstSceneRowId = activeRows.first(where: { $0.type != .statistics })?.id

                ForEach(tabManager.homeRows) { row in
                    if row.isEnabled {
                        if row.type == .statistics {
                            HomeStatisticsRowView(viewModel: viewModel, isFirst: row.id == firstRowId)
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
            viewModel.initializeServerConnection()
        }
    }
}
#endif
