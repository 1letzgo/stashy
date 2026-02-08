
import SwiftUI

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
                            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                                .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
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
            checkAndLoadScenes()
        }
        .onChange(of: viewModel.savedFilters) { _, _ in
            // When filters are updated (loaded), try to load scenes.
            // checkAndLoadScenes will decide if it's safe to load now.
            checkAndLoadScenes()
        }
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, newValue in
            // If we finished loading filters (true -> false), check if we can load scenes now
            if oldValue == true && newValue == false {
                checkAndLoadScenes()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.dashboard.rawValue {
                // Force reload this row by clearing cache first
                viewModel.homeRowScenes[config.type] = nil
                checkAndLoadScenes()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            // Clear cache and reload on server switch
            viewModel.homeRowScenes[config.type] = nil
            checkAndLoadScenes()
        }
    }
    
    private func checkAndLoadScenes() {
        // If a default filter is set but not loaded yet, wait.
        if let filterId = TabManager.shared.getDefaultFilterId(for: .dashboard) {
            // We load if:
            // 1. The filter is found
            // 2. OR we finished loading all filters and it's NOT found (fallback)
            if viewModel.savedFilters[filterId] != nil || !viewModel.isLoadingSavedFilters {
                loadScenes()
            } else {
                // Filter set but not loaded. Do nothing, wait for onChange.
                print("⏳ HomeRowView: Waiting for dashboard filter \(filterId) to load...")
            }
        } else {
            // No filter set based on ID, load immediately (standard logic)
            loadScenes()
        }
    }
    
    private func loadScenes() {
        // ViewModel handles caching - this will return immediately if cached
        // Request 20 for the hero row (isLarge), 5 for others
        let limit = isLarge ? 20 : 5
        viewModel.fetchScenesForHomeRow(config: config, limit: limit) { _ in
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
        case .topCounter3Min:
            return .oCounterDesc
        case .topRating3Min:
            return .ratingDesc
        case .random:
            return .random
        case .statistics:
            return nil
        }
    }
}
