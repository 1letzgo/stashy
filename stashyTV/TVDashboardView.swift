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
                Spacer()
                    .frame(height: 60)

                // MARK: Content Rows
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
    
    // MARK: - Content Rows
    
    private var contentRows: some View {
        VStack(alignment: .leading, spacing: 50) {
            if isLoadingPlayed && isLoadingReleased && isLoadingAdded {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                }
                .padding(.top, 40)
            } else {
                if !recentlyPlayedScenes.isEmpty {
                    sceneRow(
                        title: "Continue Watching",
                        scenes: recentlyPlayedScenes,
                        sortBy: .lastPlayedAtDesc
                    )
                }

                if !recentlyReleasedScenes.isEmpty {
                    sceneRow(
                        title: "New Releases",
                        scenes: recentlyReleasedScenes,
                        sortBy: .dateDesc
                    )
                }

                if !recentlyAddedScenes.isEmpty {
                    sceneRow(
                        title: "Recently Added",
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
    private func sceneRow(title: String, scenes: [Scene], sortBy: StashDBViewModel.SceneSortOption) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section heading
            DashboardSectionHeading(title: title, sortBy: sortBy)

            // Horizontal card scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(scenes) { scene in
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink(value: DashboardDestination.scene(scene.id)) {
                                TVSceneCardView(scene: scene)
                            }
                            .buttonStyle(.card)
                            
                            TVSceneCardTitleView(scene: scene)
                        }
                        .frame(width: 400)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }
}

struct DashboardSectionHeading: View {
    let title: String
    let sortBy: StashDBViewModel.SceneSortOption

    var body: some View {
        NavigationLink(value: TVDashboardView.DashboardDestination.sceneList(sortBy)) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Text("See All")
                        .font(.callout)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
        }
        .buttonStyle(DashboardHeaderButtonStyle())
        .padding(.horizontal, 34)
    }
}

struct DashboardHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(configuration.isPressed ? .white.opacity(0.5) : .white)
            // On tvOS, checking if a button is focused can be tricky inside a ButtonStyle directly
            // but we can use an overlay or environment
            .modifier(DashboardHeaderFocusModifier())
    }
}

struct DashboardHeaderFocusModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    
    func body(content: Content) -> some View {
        content
            .background(isFocused ? AppearanceManager.shared.tintColor : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}
