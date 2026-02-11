//
//  TVDashboardView.swift
//  stashyTV
//
//  Created for stashy tvOS.
//

import SwiftUI

struct TVDashboardView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared

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
        ScrollView {
            VStack(alignment: .leading, spacing: 60) {
                    // MARK: - Recently Played Row
                    if !recentlyPlayedScenes.isEmpty {
                        sceneRow(title: "Recently Played", scenes: recentlyPlayedScenes, sortBy: .lastPlayedAtDesc)
                    } else if isLoadingPlayed {
                        placeholderRow(title: "Recently Played")
                    }

                    // MARK: - Recently Released Row
                    if !recentlyReleasedScenes.isEmpty {
                        sceneRow(title: "Recently Released", scenes: recentlyReleasedScenes, sortBy: .dateDesc)
                    } else if isLoadingReleased {
                        placeholderRow(title: "Recently Released")
                    }

                    // MARK: - Recently Added Row
                    if !recentlyAddedScenes.isEmpty {
                        sceneRow(title: "Recently Added", scenes: recentlyAddedScenes, sortBy: .createdAtDesc)
                    } else if isLoadingAdded {
                        placeholderRow(title: "Recently Added")
                    }
                }
                .padding(.vertical, 40)
            }
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

    // MARK: - Data Loading

    private func loadData() {
        guard configManager.activeConfig != nil else { return }
        fetchHomeRows()
    }

    private func fetchHomeRows() {
        // Recently Played
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

        // Recently Released
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

        // Recently Added
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

    // MARK: - Statistics Section

    // MARK: - Scene Row

    @ViewBuilder
    private func sceneRow(title: String, scenes: [Scene], sortBy: StashDBViewModel.SceneSortOption) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            NavigationLink(value: DashboardDestination.sceneList(sortBy)) {
                HStack {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 60)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 40) {
                    ForEach(scenes) { scene in
                        NavigationLink(value: DashboardDestination.scene(scene.id)) {
                            TVSceneCardView(scene: scene)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 30)
            }
        }
    }

    @ViewBuilder
    private func placeholderRow(title: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 60)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 40) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.systemGray.withAlphaComponent(0.2)))
                            .frame(width: 380, height: 213.75)
                            .overlay(ProgressView())
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 30)
            }
        }
    }

    // MARK: - Helpers

    private func formattedDuration(_ seconds: Float) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1000 {
            return String(format: "%.1f TB", gb / 1024.0)
        }
        return String(format: "%.1f GB", gb)
    }
}

// Note: TVSceneDetailView is in TVSceneDetailView.swift
