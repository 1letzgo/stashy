//
//  TVDashboardView.swift
//  stashyTV
//
//  Dashboard for tvOS — Netflix/Prime style rows
//

import SwiftUI

struct TVDashboardView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var recentlyPlayedScenes: [Scene] = []
    @State private var recentlyReleasedScenes: [Scene] = []
    @State private var recentlyAddedScenes: [Scene] = []
    @State private var topRatedScenes: [Scene] = []
    @State private var randomScenes: [Scene] = []

    @State private var isLoadingPlayed: Bool = true
    @State private var isLoadingReleased: Bool = true
    @State private var isLoadingAdded: Bool = true
    @State private var isLoadingTopRated: Bool = true
    @State private var isLoadingRandom: Bool = true

    var body: some View {
        Group {
            if !hasValidConfig {
                TVConnectionErrorView(title: "Server not reachable", subtitle: "Add a server in Settings.") { loadData() }
            } else {
                ScrollView([.vertical], showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer()
                            .frame(height: 60)

                        // MARK: Content Rows
                        contentRows
                    }
                }
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 60).focusable(false) }
            }
        }
        .background(Color.appBackground)
        .onAppear { loadData(forceRefresh: true) }
        // Nicht auf `ServerConfigChanged` laden: `handleServerChange` bricht alle GraphQL-Tasks ab —
        // ein sofortiges `loadData()` würde nur leer/cancelled enden. Stattdessen nach init neu laden.
        .onReceive(NotificationCenter.default.publisher(for: .stashServerInitializationFinished)) { _ in
            loadData(forceRefresh: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneResumeTimeUpdated"))) { _ in
            refreshContinueWatching()
        }
        .sceneLiveUpdates(using: viewModel)
    }
    
    // MARK: - Content Rows
    
    private var contentRows: some View {
        VStack(alignment: .leading, spacing: 50) {
            HStack {
                Spacer()
                Button {
                    loadData(forceRefresh: true)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .padding(.horizontal, 50)

            if isLoadingPlayed || isLoadingReleased || isLoadingAdded || isLoadingTopRated || isLoadingRandom {
                if recentContentIsEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Spacer()
                    }
                    .padding(.top, 40)
                }
            }

            if !recentlyPlayedScenes.isEmpty {
                sceneRow(
                    title: "Continue Watching",
                    scenes: recentlyPlayedScenes,
                    sortBy: .lastPlayedAtDesc,
                    cardWidth: 560,
                    cardHeight: 315
                )
                .focusSection()
            }

            if !recentlyReleasedScenes.isEmpty {
                sceneRow(
                    title: "New Releases",
                    scenes: recentlyReleasedScenes,
                    sortBy: .dateDesc
                )
                .focusSection()
            }

            if !recentlyAddedScenes.isEmpty {
                sceneRow(
                    title: "Recently Added",
                    scenes: recentlyAddedScenes,
                    sortBy: .createdAtDesc
                )
                .focusSection()
            }

            if !topRatedScenes.isEmpty {
                sceneRow(
                    title: "Top Rated",
                    scenes: topRatedScenes,
                    sortBy: .ratingDesc
                )
                .focusSection()
            }

            if !randomScenes.isEmpty {
                sceneRow(
                    title: "Random Picks",
                    scenes: randomScenes,
                    sortBy: .random
                )
                .focusSection()
            }

            if !isLoadingPlayed && !isLoadingReleased && !isLoadingAdded && !isLoadingTopRated && !isLoadingRandom && recentContentIsEmpty {
                VStack(spacing: 24) {
                    Image(systemName: "film.stack")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No scenes to show yet")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Button("Reload") { loadData(forceRefresh: true) }
                        .font(.title3)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            }
        }
        .padding(.bottom, 80)
    }

    private var recentContentIsEmpty: Bool {
        recentlyPlayedScenes.isEmpty
            && recentlyReleasedScenes.isEmpty
            && recentlyAddedScenes.isEmpty
            && topRatedScenes.isEmpty
            && randomScenes.isEmpty
    }

    private var hasValidConfig: Bool { configManager.activeConfig?.hasValidConfig == true }

    // MARK: - Data Loading

    private func loadData(forceRefresh: Bool = false) {
        guard hasValidConfig else { return }
        fetchHomeRows(forceRefresh: forceRefresh)
    }

    private func refreshContinueWatching() {
        guard hasValidConfig else { return }
        isLoadingPlayed = true
        let playedConfig = HomeRowConfig(
            id: UUID(),
            title: "Recently Played",
            isEnabled: true,
            sortOrder: 0,
            type: .lastPlayed
        )
        viewModel.fetchScenesForHomeRow(config: playedConfig, limit: 15, forceRefresh: true) { scenes in
            recentlyPlayedScenes = scenes
            isLoadingPlayed = false
        }
    }

    private func fetchHomeRows(forceRefresh: Bool) {
        isLoadingPlayed = true
        let playedConfig = HomeRowConfig(
            id: UUID(),
            title: "Recently Played",
            isEnabled: true,
            sortOrder: 0,
            type: .lastPlayed
        )
        viewModel.fetchScenesForHomeRow(config: playedConfig, limit: 15, forceRefresh: forceRefresh) { scenes in
            recentlyPlayedScenes = scenes
            isLoadingPlayed = false
        }

        isLoadingReleased = true
        let releasedConfig = HomeRowConfig(
            id: UUID(),
            title: "Recently Released",
            isEnabled: true,
            sortOrder: 1,
            type: .newest3Min
        )
        viewModel.fetchScenesForHomeRow(config: releasedConfig, limit: 15, forceRefresh: forceRefresh) { scenes in
            recentlyReleasedScenes = scenes
            isLoadingReleased = false
        }

        isLoadingAdded = true
        let addedConfig = HomeRowConfig(
            id: UUID(),
            title: "Recently Added",
            isEnabled: true,
            sortOrder: 2,
            type: .lastAdded3Min
        )
        viewModel.fetchScenesForHomeRow(config: addedConfig, limit: 15, forceRefresh: forceRefresh) { scenes in
            recentlyAddedScenes = scenes
            isLoadingAdded = false
        }

        isLoadingTopRated = true
        let topRatedConfig = HomeRowConfig(
            id: UUID(),
            title: "Top Rated",
            isEnabled: true,
            sortOrder: 3,
            type: .topRating3Min
        )
        viewModel.fetchScenesForHomeRow(config: topRatedConfig, limit: 15, forceRefresh: forceRefresh) { scenes in
            topRatedScenes = scenes
            isLoadingTopRated = false
        }

        isLoadingRandom = true
        let randomConfig = HomeRowConfig(
            id: UUID(),
            title: "Random",
            isEnabled: true,
            sortOrder: 4,
            type: .random
        )
        viewModel.fetchScenesForHomeRow(config: randomConfig, limit: 15, forceRefresh: forceRefresh) { scenes in
            randomScenes = scenes
            isLoadingRandom = false
        }
    }

    // MARK: - Scene Row

    @ViewBuilder
    private func sceneRow(title: String, scenes: [Scene], sortBy: StashDBViewModel.SceneSortOption, cardWidth: CGFloat = 400, cardHeight: CGFloat = 225) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section heading (Static)
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 50)

            // Horizontal card scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(scenes) { scene in
                        VStack(alignment: .leading, spacing: 10) {
                            TVNavButton(value: TVSceneLink(sceneId: scene.id)) {
                                TVSceneCardView(scene: scene, width: cardWidth + 10, height: cardHeight + 5)
                            }
                            
                            TVSceneCardTitleView(scene: scene)
                        }
                        .frame(width: cardWidth)
                    }

                    // See All Card at the end
                    TVNavButton(value: TVSceneListLink(sortBy: sortBy)) {
                        VStack(spacing: 20) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Text("See All")
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }
}
