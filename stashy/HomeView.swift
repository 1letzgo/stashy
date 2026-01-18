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
        .onAppear {
            if configManager.activeConfig != nil {
                viewModel.fetchStatistics()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            // Reload data when server config changes (e.g., after wizard setup)
            viewModel.fetchStatistics()
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
    }
}

struct HomeStatisticsRowView: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var tabManager = TabManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
            
            VStack(alignment: .leading, spacing: 10) {
                if let stats = viewModel.statistics {
                    let columns = [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ]
                    
                    let sortedTabs = tabManager.tabs
                        .filter { tab in
                            (tab.id == .scenes || tab.id == .galleries || 
                             tab.id == .performers || tab.id == .studios || tab.id == .tags) && tab.isVisible
                        }
                        .sorted { $0.sortOrder < $1.sortOrder }

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(sortedTabs) { tab in
                            Group {
                                switch tab.id {
                                case .scenes:
                                    StatCard(title: "Scenes", value: formatCount(stats.sceneCount), icon: "film", color: .blue)
                                        .onTapGesture { coordinator.navigateToScenes() }
                                case .galleries:
                                    StatCard(title: "Galleries", value: formatCount(stats.galleryCount), icon: "photo.stack", color: .green)
                                        .onTapGesture { coordinator.navigateToGalleries() }
                                    // Binde images immer hinter galleries
                                    StatCard(title: "Images", value: formatCount(stats.imageCount), icon: "photo", color: .teal)
                                        .onTapGesture { coordinator.navigateToGalleries() }
                                case .performers:
                                    StatCard(title: "Performers", value: formatCount(stats.performerCount), icon: "person.2", color: .purple)
                                        .onTapGesture { coordinator.navigateToPerformers() }
                                case .studios:
                                    StatCard(title: "Studios", value: formatCount(stats.studioCount), icon: "building.2", color: .orange)
                                        .onTapGesture { coordinator.navigateToStudios() }
                                case .tags:
                                    StatCard(title: "Tags", value: formatCount(stats.tagCount), icon: "tag", color: .pink)
                                        .onTapGesture { coordinator.navigateToTags() }
                                default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                } else if viewModel.isLoading {
                    let columns = [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ]
                    
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(0..<6) { _ in
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 46)
                        }
                    }
                    .padding(.horizontal, 12)
                } else {
                    // Error state
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.secondary)
                        Text("Stats unavailable")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }
    
    // MARK: - Formatting Helpers
    
    private func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current // Respect user's country/region
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    private func formatSize(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useTB, .useGB, .useMB]
        formatter.includesUnit = true
        return formatter.string(fromByteCount: value)
    }
    
    private func formatDuration(_ value: Float) -> String {
        let totalSeconds = Int(value)
        let hours = totalSeconds / 3600
        
        // Formatter for nicer output "124h 30m"
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        
        return formatter.string(from: TimeInterval(value)) ?? "\(hours)h"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 22, alignment: .center)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(
            LinearGradient(
                colors: [color, color.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(10)
    }
}

struct HomeRowView: View {
    let config: HomeRowConfig
    @ObservedObject var viewModel: StashDBViewModel
    @EnvironmentObject var coordinator: NavigationCoordinator
    var isLarge: Bool = false
    
    // Use ViewModel cache instead of local @State
    private var scenes: [Scene] {
        viewModel.homeRowScenes[config.type] ?? []
    }
    
    private var isLoading: Bool {
        // Loading if: no cached data AND currently fetching
        scenes.isEmpty && (viewModel.homeRowLoadingState[config.type] ?? true)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(destination: ScenesView(sort: getSortOption())) {
                HStack(spacing: 4) {
                    Text(config.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<5) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: isLarge ? 280 : 200, height: (isLarge ? 280 : 200) * 9 / 16)
                                .overlay(ProgressView())
                        }
                    }
                    .padding(.horizontal, 12)
                }
            } else if scenes.isEmpty {
                Text("No scenes found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(scenes) { scene in
                            NavigationLink(destination: SceneDetailView(scene: scene)) {
                                HomeSceneCardView(scene: scene, isLarge: isLarge)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .onAppear {
            loadScenes()
        }
    }
    
    private func loadScenes() {
        // ViewModel handles caching - this will return immediately if cached
        viewModel.fetchScenesForHomeRow(config: config) { _ in
            // Completion now handled via @Published homeRowScenes
        }
    }

    private func getSortOption() -> StashDBViewModel.SceneSortOption? {
        switch config.type {
        case .lastPlayed:
            return .lastPlayedAtDesc
        case .lastAdded3Min:
            return .createdAtDesc
        case .newest3Min:
            return .dateDesc
        case .mostViewed3Min:
            return .playCountDesc
        case .random:
            return .random
        case .statistics:
            return nil
        }
    }
}

struct HomeSceneCardView: View {
    let scene: Scene
    var isLarge: Bool = false
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    // Preview Video State
    @State private var previewPlayer: AVPlayer?
    @State private var isPreviewing = false
    @State private var isPressing = false

    
    private var cardWidth: CGFloat { isLarge ? 280 : 200 }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Image
            GeometryReader { geometry in
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                    
                    if let thumbnailURL = scene.thumbnailURL {
                        CustomAsyncImage(url: thumbnailURL) { loader in
                            if loader.isLoading {
                                ProgressView()
                            } else if let image = loader.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .clipped()
                            } else {
                                Image(systemName: "film")
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Image(systemName: "film")
                            .foregroundColor(.secondary)
                    }
                    
                    // Video Preview Overlay
                    if isPreviewing, let previewPlayer = previewPlayer {
                        AspectFillVideoPlayer(player: previewPlayer)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
            }
            .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in
                isPressing = pressing
                if pressing {
                    startPreview()
                } else {
                    stopPreview()
                }
            }, perform: {})
            
            // Gradient Overlay for Text Readability
            LinearGradient(
                colors: [.black.opacity(0.8), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 60)
            .frame(maxHeight: .infinity, alignment: .bottom)
            
            // Content Overlays
            VStack {
                // Top Row
                HStack(alignment: .top) {
                    // Studio Badge (Top Left)
                    if let studio = scene.studio {
                        Text(studio.name.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    Spacer()
                    
                    // Duration Badge (Top Right, moved from bottom)
                    if let duration = scene.files?.first?.duration {
                        Text(formatDuration(duration))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                
                Spacer()
                
                // Bottom Row
                VStack(alignment: .leading, spacing: 4) {
                    // Title (Bottom Left)
                    Text(scene.title ?? "Untitled Scene")
                        .font(isLarge ? .subheadline : .caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .bottomLeading)
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    
                    // Resume Progress
                    if let resumeTime = scene.resumeTime, resumeTime > 0, let duration = scene.sceneDuration {
                        ProgressView(value: resumeTime, total: duration)
                            .progressViewStyle(LinearProgressViewStyle(tint: appearanceManager.tintColor))
                            .frame(height: 3)
                    }
                }
            }
            .padding(8)
        }
        .frame(width: cardWidth, height: cardWidth * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onDisappear {
            stopPreview()
        }
    }
    
    private func startPreview() {
        guard let previewURL = scene.previewURL else { return }
        
        if previewPlayer == nil {
            previewPlayer = createMutedPreviewPlayer(for: previewURL)
        }
        
        withAnimation(.easeIn(duration: 0.2)) {
            isPreviewing = true
        }
        previewPlayer?.play()
    }
    
    private func stopPreview() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPreviewing = false
        }
        previewPlayer?.pause()
        previewPlayer?.seek(to: .zero)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
