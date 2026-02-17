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
    
    @State private var isLoadingPlayed: Bool = true
    @State private var isLoadingReleased: Bool = true
    @State private var isLoadingAdded: Bool = true

    enum DashboardDestination: Hashable {
        case scene(String)
        case sceneList(StashDBViewModel.SceneSortOption)
    }

    var body: some View {
        ScrollView([.vertical], showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Greeting header
                headerSection
                    .padding(.horizontal, 50)
                    .padding(.top, 60)
                    .padding(.bottom, 44)

                contentRows
            }
        }
        .background(Color.black)
        .navigationBarHidden(true)
        .navigationDestination(for: DashboardDestination.self) { destination in
            switch destination {
            case .scene(let id):
                TVSceneDetailView(sceneId: id)
            case .sceneList(let sort):
                TVScenesView(sortBy: sort)
            }
        }
        .onAppear {
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            loadData()
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingText)
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(.white)
            
            if let serverName = configManager.activeConfig?.name, !serverName.isEmpty {
                Text(serverName)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default: return "Good Night"
        }
    }
    
    // MARK: - Content Rows
    
    private var contentRows: some View {
        VStack(alignment: .leading, spacing: 60) {
            if isLoadingPlayed && isLoadingReleased && isLoadingAdded {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                }
                .padding(.top, 100)
            } else {
                if !recentlyPlayedScenes.isEmpty {
                    sceneRow(
                        title: "Continue Watching",
                        icon: "play.circle.fill",
                        scenes: recentlyPlayedScenes,
                        sortBy: .lastPlayedAtDesc
                    )
                }

                if !recentlyReleasedScenes.isEmpty {
                    sceneRow(
                        title: "New Releases",
                        icon: "sparkles.tv.fill",
                        scenes: recentlyReleasedScenes,
                        sortBy: .dateDesc
                    )
                }

                if !recentlyAddedScenes.isEmpty {
                    sceneRow(
                        title: "Recently Added",
                        icon: "plus.rectangle.on.folder.fill",
                        scenes: recentlyAddedScenes,
                        sortBy: .createdAtDesc
                    )
                }
            }
        }
        .padding(.bottom, 80)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard configManager.activeConfig != nil else { return }
        fetchHomeRows()
    }

    private func fetchHomeRows() {
        isLoadingPlayed = true
        let playedConfig = HomeRowConfig(
            id: UUID(),
            title: "Recently Played",
            isEnabled: true,
            sortOrder: 0,
            type: .lastPlayed
        )
        viewModel.fetchScenesForHomeRow(config: playedConfig, limit: 15) { scenes in
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
        viewModel.fetchScenesForHomeRow(config: releasedConfig, limit: 15) { scenes in
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
        viewModel.fetchScenesForHomeRow(config: addedConfig, limit: 15) { scenes in
            recentlyAddedScenes = scenes
            isLoadingAdded = false
        }
    }

    // MARK: - Scene Row

    @ViewBuilder
    private func sceneRow(title: String, icon: String, scenes: [Scene], sortBy: StashDBViewModel.SceneSortOption) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section heading
            NavigationLink(value: DashboardDestination.sceneList(sortBy)) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(appearanceManager.tintColor)
                    
                    Text(title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Text("See All")
                            .font(.callout)
                            .foregroundColor(.white.opacity(0.35))
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.25))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 50)

            // Horizontal card scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(scenes) { scene in
                        NavigationLink(value: DashboardDestination.scene(scene.id)) {
                            TVSceneCardView(scene: scene)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }
}
