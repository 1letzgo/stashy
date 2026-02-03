//
//  HomeView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI
import AVKit

struct HomeView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.openURL) var openURL

    var body: some View {
        ZStack {
            if configManager.activeConfig == nil {
                ConnectionErrorView { viewModel.fetchStatistics() }
            } else if viewModel.isLoading && viewModel.statistics == nil {
                VStack {
                    Spacer()
                    ProgressView("Loading Dashboard...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.statistics == nil && viewModel.errorMessage != nil {
                ConnectionErrorView { viewModel.fetchStatistics() }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        let firstSceneRowId = tabManager.homeRows.first(where: { $0.isEnabled && $0.type != .statistics })?.id
                        
                        ForEach(tabManager.homeRows) { row in
                            if row.isEnabled {
                                if row.type == .statistics {
                                    HomeStatisticsRowView(viewModel: viewModel)
                                } else {
                                    HomeRowView(config: row, viewModel: viewModel, isLarge: row.id == firstSceneRowId)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.bottom, 80) // Floating bar space
                }
            }
        }

        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isTestFlightBuild() {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if let url = URL(string: "https://apps.apple.com/us/app/stashy/id6754876029") {
                            openURL(url)
                        }
                    }) {
                        Image(systemName: "bag.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .onAppear {
            if configManager.activeConfig != nil {
                viewModel.fetchStatistics()
                viewModel.fetchSavedFilters() // Fetch filters so dashboard rows can use them
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            // Reload data when server config changes (e.g., after wizard setup)
            viewModel.fetchStatistics()
            viewModel.fetchSavedFilters()
        }
        // Scene Update Listeners - update home row scenes in place
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneResumeTimeUpdated"))) { notification in
            if let sceneId = notification.userInfo?["sceneId"] as? String,
               let resumeTime = notification.userInfo?["resumeTime"] as? Double {
                viewModel.updateSceneResumeTime(id: sceneId, newResumeTime: resumeTime)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneDeleted"))) { notification in
            if let sceneId = notification.userInfo?["sceneId"] as? String {
                viewModel.removeScene(id: sceneId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.dashboard.rawValue {
                // Reload dashboard if its filter changed
                viewModel.fetchStatistics()
                viewModel.fetchSavedFilters() // Ensure filter dict is up to date
                // We might need to force reload cached rows too
                // For now, fetching stats should be enough if rows are reactive
            }
        }
    }
    
}
