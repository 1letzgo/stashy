//
//  ReelsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI
import AVKit
import AVFoundation

struct ReelsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getSortOption(for: .reels) ?? "") ?? .random
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var selectedPerformer: ScenePerformer?
    @State private var selectedTags: [Tag] = []
    @State private var isMuted = !isHeadphonesConnected() // Shared mute state for Reels
    @State private var currentVisibleSceneId: String?
    @State private var showDeleteConfirmation = false
    @State private var sceneToDelete: Scene?
    @State private var reelsMode: ReelsMode = .scenes
    @State private var selectedMarkerSortOption: StashDBViewModel.SceneMarkerSortOption = .random

    enum ReelsMode: String, CaseIterable {
        case scenes = "Scenes"
        case markers = "Markers"
    }

    enum ReelItemData: Identifiable {
        case scene(Scene)
        case marker(SceneMarker)
        
        var id: String {
            switch self {
            case .scene(let s): return s.id
            case .marker(let m): return m.id
            }
        }
        
        var title: String? {
            switch self {
            case .scene(let s): return s.title
            case .marker(let m):
                if let markerTitle = m.title, !markerTitle.isEmpty {
                    return markerTitle
                }
                return m.scene?.title
            }
        }
        
        var performers: [ScenePerformer] {
            switch self {
            case .scene(let s): return s.performers
            case .marker(let m): return m.scene?.performers ?? []
            }
        }
        
        var tags: [Tag] {
            switch self {
            case .scene(let s): return s.tags ?? []
            case .marker(let m):
                var allTags = m.tags ?? []
                if let primary = m.primaryTag {
                    allTags.insert(primary, at: 0)
                }
                return allTags
            }
        }
        
        var thumbnailURL: URL? {
            switch self {
            case .scene(let s): return s.thumbnailURL
            case .marker(let m): return m.thumbnailURL
            }
        }
        
        var videoURL: URL? {
            switch self {
            case .scene(let s): return s.videoURL
            case .marker(let m): 
                // Always use the full scene stream for markers to allow seeking/looping
                // constructed manually from the scene ID found in the marker
                if let sceneID = m.scene?.id, let config = ServerConfigManager.shared.loadConfig() {
                    return URL(string: "\(config.baseURL)/scene/\(sceneID)/stream")
                }
                return m.videoURL
            }
        }
        
        var startTime: Double {
            switch self {
            case .scene: return 0
            case .marker(let m): return m.seconds
            }
        }
        
        var duration: Double? {
            switch self {
            case .scene(let s): return s.duration
            case .marker(let m): return m.scene?.files?.first?.duration
            }
        }
        
        var isPortrait: Bool {
            switch self {
            case .scene(let s): return s.isPortrait
            case .marker(let m):
                if let width = m.scene?.files?.first?.width, let height = m.scene?.files?.first?.height {
                    return height > width
                }
                return false
            }
        }
        
        var rating100: Int? {
            switch self {
            case .scene(let s): return s.rating100
            case .marker(let m): return m.scene?.rating100
            }
        }
        
        var oCounter: Int? {
            switch self {
            case .scene(let s): return s.oCounter
            case .marker(let m): return m.scene?.oCounter
            }
        }
        
        var playCount: Int? {
            switch self {
            case .scene(let s): return s.playCount
            case .marker(let m): return m.scene?.playCount
            }
        }
        
        var dateString: String? {
            switch self {
            case .scene(let s): return s.date
            case .marker(let m): return m.scene?.date
            }
        }
    }

    private func applySettings(sortBy: StashDBViewModel.SceneSortOption? = nil, markerSortBy: StashDBViewModel.SceneMarkerSortOption? = nil, filter: StashDBViewModel.SavedFilter?, performer: ScenePerformer? = nil, tags: [Tag] = [], mode: ReelsMode? = nil) {
        if let mode = mode { reelsMode = mode }
        
        if let sortBy = sortBy {
            selectedSortOption = sortBy
            TabManager.shared.setSortOption(for: .reels, option: sortBy.rawValue)
        }
        
        if let markerSortBy = markerSortBy {
            selectedMarkerSortOption = markerSortBy
        }
        
        selectedFilter = filter
        selectedPerformer = performer
        selectedTags = tags
        
        // Merge performer and tags into filter if needed
        let mergedFilter = viewModel.mergeFilterWithCriteria(filter: filter, performer: performer, tags: tags)
        
        if reelsMode == .scenes {
            viewModel.fetchScenes(sortBy: selectedSortOption, filter: mergedFilter)
        } else {
            viewModel.fetchSceneMarkers(sortBy: selectedMarkerSortOption, filter: mergedFilter)
        }
    }


    var body: some View {
        premiumContent
    }


    @ViewBuilder
    private var premiumContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            let isEmpty = (reelsMode == .scenes ? viewModel.scenes.isEmpty : viewModel.sceneMarkers.isEmpty)
            let isLoading = viewModel.isLoading && isEmpty

            if isLoading {
                loadingStateView
            } else if isEmpty && viewModel.errorMessage != nil {
                errorStateView
            } else {
                reelsListView
            }
        }
        .ignoresSafeArea()
        .navigationTitle(viewModel.scenes.isEmpty && viewModel.errorMessage != nil ? "StashTok" : "")
        .navigationBarTitleDisplayMode(.inline)
        // Toolbar Background Logic
        .toolbarBackground(
            viewModel.scenes.isEmpty && viewModel.errorMessage != nil ? .visible : .hidden,
            for: .navigationBar, .tabBar
        )
        .toolbarBackground(
            viewModel.scenes.isEmpty && viewModel.errorMessage != nil ? Color.black : Color.clear,
            for: .navigationBar, .tabBar
        )
        .toolbarColorScheme(.dark, for: .navigationBar, .tabBar)
        .toolbar {
            reelsToolbar
        }
        .onAppear {
            if viewModel.savedFilters.isEmpty {
                viewModel.fetchSavedFilters()
            }
            
            // Determine initial state from coordinator
            let initialPerformer: ScenePerformer? = coordinator.reelsPerformer
            let initialTags: [Tag] = coordinator.reelsTags
            
            // Priority 1: Navigation Context
            if initialPerformer != nil || !initialTags.isEmpty {
                coordinator.reelsPerformer = nil
                coordinator.reelsTags = []
                
                let savedSort = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getSortOption(for: .reels) ?? "") ?? .random
                applySettings(sortBy: savedSort, filter: selectedFilter, performer: initialPerformer, tags: initialTags)
            } else if viewModel.scenes.isEmpty {
                // Priority 2: Wait for filters if we expect a default but don't have it yet
                let defaultId = TabManager.shared.getDefaultFilterId(for: .reels)
                let hasFilters = !viewModel.savedFilters.isEmpty
                
                if defaultId != nil && !hasFilters {
                    // We need to wait for onChange(of: viewModel.savedFilters) to trigger applySettings
                    print("🕓 ReelsView: Waiting for filters before initial load...")
                } else {
                    // Filters are ready or no default filter set
                    var initialFilter = selectedFilter
                    if initialFilter == nil, let defId = defaultId {
                        initialFilter = viewModel.savedFilters[defId]
                    }
                    
                    let savedSort = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getSortOption(for: .reels) ?? "") ?? .random
                    applySettings(sortBy: savedSort, filter: initialFilter, performer: selectedPerformer, tags: selectedTags)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.reels.rawValue {
                let defaultId = TabManager.shared.getDefaultFilterId(for: .reels)
                let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                applySettings(sortBy: selectedSortOption, filter: newFilter, performer: selectedPerformer, tags: selectedTags)
            }
        }
        .onChange(of: viewModel.savedFilters) { _, newValue in
            // Only apply default filter if we haven't set a filter yet AND we are empty
            if selectedFilter == nil && viewModel.scenes.isEmpty {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .reels),
                   let filter = newValue[defaultId] {
                    print("✅ ReelsView: Applying default filter after lazy load")
                    applySettings(sortBy: selectedSortOption, filter: filter, performer: selectedPerformer, tags: selectedTags)
                } else if !newValue.isEmpty {
                    // Filters arrived but no default matches, or no default set - load unfiltered if still empty
                     let savedSort = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getSortOption(for: .reels) ?? "") ?? .random
                     applySettings(sortBy: savedSort, filter: nil, performer: selectedPerformer, tags: selectedTags)
                }
            }
        }
        }
    }

    @ViewBuilder
    private var loadingStateView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
            Text("Loading StashTok...")
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    @ViewBuilder
    private var errorStateView: some View {
        VStack {
            Spacer()
            ConnectionErrorView(onRetry: {
                applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags)
            }, isDark: true)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    @ViewBuilder
    private var reelsListView: some View {
        let items = reelsMode == .scenes ? viewModel.scenes.map { ReelItemData.scene($0) } : viewModel.sceneMarkers.map { ReelItemData.marker($0) }
        
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ReelItemView(
                        item: item,
                        isMuted: $isMuted,
                        onPerformerTap: { performer in
                            applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: performer, tags: selectedTags)
                        },
                        onTagTap: { tag in
                            var newTags = selectedTags
                            if !newTags.contains(where: { $0.id == tag.id }) {
                                newTags.append(tag)
                            }
                            applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: selectedPerformer, tags: newTags)
                        },
                        onRatingChanged: { newRating in
                            var targetSceneId: String?
                            if case .scene(let scene) = item { targetSceneId = scene.id }
                            else if case .marker(let marker) = item { targetSceneId = marker.scene?.id }
                            
                            if let sceneId = targetSceneId {
                                // Optimistic Update for Scene List
                                if let sceneIndex = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                                    let originalRating = viewModel.scenes[sceneIndex].rating100
                                    viewModel.scenes[sceneIndex] = viewModel.scenes[sceneIndex].withRating(newRating)
                                    
                                    viewModel.updateSceneRating(sceneId: sceneId, rating100: newRating) { success in
                                        if !success {
                                            DispatchQueue.main.async {
                                                viewModel.scenes[sceneIndex] = viewModel.scenes[sceneIndex].withRating(originalRating)
                                            }
                                        }
                                    }
                                } else {
                                     // Just update backend if not in scene list
                                     viewModel.updateSceneRating(sceneId: sceneId, rating100: newRating) { _ in }
                                }
                            }
                        },
                        viewModel: viewModel
                    )
                    .containerRelativeFrame(.vertical)
                    .id(item.id)
                    .onAppear {
                        if index == items.count - 2 {
                            if reelsMode == .scenes {
                                viewModel.loadMoreScenes()
                            } else {
                                viewModel.loadMoreMarkers()
                            }
                        }
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .onScrollGeometryChange(for: String?.self) { geo in
            // Find the ID of the scene that is closest to the center or top of the visible area
            let offsetY = geo.contentOffset.y
            let height = geo.containerSize.height
            if height > 0 {
                let index = Int(round(offsetY / height))
                if index >= 0 && index < viewModel.scenes.count {
                    return viewModel.scenes[index].id
                }
            }
            return nil
        } action: { old, new in
            if let newId = new {
                currentVisibleSceneId = newId
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    @ToolbarContentBuilder
    private var reelsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            HStack(spacing: 8) {
                if reelsMode == .scenes {
                    // Placeholder or empty for now, delete removed
                }
                
                Picker("Mode", selection: $reelsMode) {
                    ForEach(ReelsMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .onChange(of: reelsMode) { _, newValue in
                     if newValue == .markers {
                        // Load default MARKER filter if available, otherwise NO Filter
                        if selectedFilter == nil {
                             if let defaultId = TabManager.shared.getDefaultMarkerFilterId(for: .reels),
                                let filter = viewModel.savedFilters[defaultId] {
                                 applySettings(filter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                             } else {
                                 applySettings(filter: nil, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                             }
                        } else {
                            // Keep current filter if set? Usually switching modes resets filter context unless specialized logic.
                            // User asked: "Wenn kein filter auf dem server vorhanden ist, dann benutze auch keinen." implies explicit handling.
                            // Let's reset to default if switching modes generally.
                            if let defaultId = TabManager.shared.getDefaultMarkerFilterId(for: .reels),
                               let filter = viewModel.savedFilters[defaultId] {
                                 applySettings(filter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                            } else {
                                applySettings(filter: nil, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                            }
                        }
                     } else {
                        // Scenes Mode
                        if selectedFilter == nil {
                            if let defaultId = TabManager.shared.getDefaultFilterId(for: .reels),
                               let filter = viewModel.savedFilters[defaultId] {
                                applySettings(filter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                            } else {
                                applySettings(filter: nil, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                            }
                        } else {
                             // Reset to default scene filter when switching back
                             if let defaultId = TabManager.shared.getDefaultFilterId(for: .reels),
                                let filter = viewModel.savedFilters[defaultId] {
                                 applySettings(filter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                             } else {
                                 applySettings(filter: nil, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                             }
                        }
                     }
                }
            }
        }
        
        if !(viewModel.scenes.isEmpty && viewModel.errorMessage != nil) {
            ToolbarItem(placement: .principal) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let performer = selectedPerformer {
                            Button(action: {
                                applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: nil, tags: selectedTags)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                    Text(performer.name)
                                        .font(.system(size: 12, weight: .bold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                            }
                        }
                        
                        ForEach(selectedTags) { tag in
                            Button(action: {
                                var newTags = selectedTags
                                newTags.removeAll { $0.id == tag.id }
                                applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: selectedPerformer, tags: newTags)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("#\(tag.name)")
                                        .font(.system(size: 12, weight: .bold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 12) {
                sortMenu
                filterMenu
            }
        }
    }

    private var filterColor: Color {
        selectedFilter != nil ? appearanceManager.tintColor : .white
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            if reelsMode == .scenes {
                sceneSortOptions
            } else {
                markerSortOptions
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var sceneSortOptions: some View {
        // Random
        Button(action: { applySettings(sortBy: .random, filter: selectedFilter, performer: selectedPerformer) }) {
            HStack {
                Text("Random")
                if selectedSortOption == .random { Image(systemName: "checkmark") }
            }
        }
        
        Divider()
        
        // Date
        Menu {
            Button(action: { applySettings(sortBy: .dateDesc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Newest First")
                    if selectedSortOption == .dateDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .dateAsc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Oldest First")
                    if selectedSortOption == .dateAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Date")
                if selectedSortOption == .dateAsc || selectedSortOption == .dateDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Title
        Menu {
            Button(action: { applySettings(sortBy: .titleAsc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("A → Z")
                    if selectedSortOption == .titleAsc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .titleDesc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Z → A")
                    if selectedSortOption == .titleDesc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Title")
                if selectedSortOption == .titleAsc || selectedSortOption == .titleDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Duration
        Menu {
            Button(action: { applySettings(sortBy: .durationDesc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Longest First")
                    if selectedSortOption == .durationDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .durationAsc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Shortest First")
                    if selectedSortOption == .durationAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Duration")
                if selectedSortOption == .durationAsc || selectedSortOption == .durationDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Play Count
        Menu {
            Button(action: { applySettings(sortBy: .playCountDesc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Most Viewed")
                    if selectedSortOption == .playCountDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .playCountAsc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Least Viewed")
                    if selectedSortOption == .playCountAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Views")
                if selectedSortOption == .playCountAsc || selectedSortOption == .playCountDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Last Played
        Menu {
            Button(action: { applySettings(sortBy: .lastPlayedAtDesc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Recently Played")
                    if selectedSortOption == .lastPlayedAtDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .lastPlayedAtAsc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Least Recently")
                    if selectedSortOption == .lastPlayedAtAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Last Played")
                if selectedSortOption == .lastPlayedAtAsc || selectedSortOption == .lastPlayedAtDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Created
        Menu {
            Button(action: { applySettings(sortBy: .createdAtDesc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Newest First")
                    if selectedSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .createdAtAsc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Oldest First")
                    if selectedSortOption == .createdAtAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Created")
                if selectedSortOption == .createdAtAsc || selectedSortOption == .createdAtDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Counter (O-Counter)
        Menu {
            Button(action: { applySettings(sortBy: .oCounterDesc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("High → Low")
                    if selectedSortOption == .oCounterDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .oCounterAsc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Low → High")
                    if selectedSortOption == .oCounterAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("O-Counter")
                if selectedSortOption == .oCounterAsc || selectedSortOption == .oCounterDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Rating
        Menu {
            Button(action: { applySettings(sortBy: .ratingDesc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("High → Low")
                    if selectedSortOption == .ratingDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .ratingAsc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Low → High")
                    if selectedSortOption == .ratingAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Rating")
                if selectedSortOption == .ratingAsc || selectedSortOption == .ratingDesc { Image(systemName: "checkmark") }
            }
        }
    }

    @ViewBuilder
    private var markerSortOptions: some View {
        // Random
        Button(action: { applySettings(markerSortBy: .random, filter: selectedFilter, performer: selectedPerformer) }) {
            HStack {
                Text("Random")
                if selectedMarkerSortOption == .random { Image(systemName: "checkmark") }
            }
        }
        
        Divider()
        
        // Created
        Menu {
            Button(action: { applySettings(markerSortBy: .createdAtDesc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Newest First")
                    if selectedMarkerSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(markerSortBy: .createdAtAsc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Oldest First")
                    if selectedMarkerSortOption == .createdAtAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Created")
                if selectedMarkerSortOption == .createdAtAsc || selectedMarkerSortOption == .createdAtDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Title
        Menu {
            Button(action: { applySettings(markerSortBy: .titleAsc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("A → Z")
                    if selectedMarkerSortOption == .titleAsc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(markerSortBy: .titleDesc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Z → A")
                    if selectedMarkerSortOption == .titleDesc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Title")
                if selectedMarkerSortOption == .titleAsc || selectedMarkerSortOption == .titleDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Time
        Menu {
            Button(action: { applySettings(markerSortBy: .secondsAsc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Start Time")
                    if selectedMarkerSortOption == .secondsAsc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(markerSortBy: .secondsDesc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("End Time")
                    if selectedMarkerSortOption == .secondsDesc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Time")
                if selectedMarkerSortOption == .secondsAsc || selectedMarkerSortOption == .secondsDesc { Image(systemName: "checkmark") }
            }
        }
    }

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            Button(action: {
                applySettings(filter: nil, performer: selectedPerformer, tags: selectedTags)
            }) {
                HStack {
                    Text("No Filter")
                    if selectedFilter == nil { Image(systemName: "checkmark") }
                }
            }

            let mode: StashDBViewModel.FilterMode = (reelsMode == .scenes ? .scenes : .sceneMarkers)
            let activeFilters = viewModel.savedFilters.values
                .filter { $0.mode == mode && $0.id != "reels_temp" && $0.id != "reels_merged" }
                .sorted { $0.name < $1.name }

            ForEach(activeFilters) { filter in
                Button(action: {
                    applySettings(filter: filter, performer: selectedPerformer, tags: selectedTags)
                }) {
                    HStack {
                        Text(filter.name)
                        if selectedFilter?.id == filter.id { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: selectedFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundColor(filterColor)
        }
    }


struct ReelItemView: View {
    let item: ReelsView.ReelItemData
    @State private var player: AVPlayer?
    @State private var looper: Any?
    
    // Playback State
    @Binding var isMuted: Bool
    var onPerformerTap: (ScenePerformer) -> Void
    var onTagTap: (Tag) -> Void
    var onRatingChanged: (Int?) -> Void
    @ObservedObject var viewModel: StashDBViewModel
    @State private var isPlaying = true
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 1.0
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    @State private var showRatingOverlay = false
    @State private var showUI = true
    @State private var uiHideTask: Task<Void, Never>? = nil
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Video / Thumbnail layer
            Group {
                if let player = player {
                    FullScreenVideoPlayer(player: player, videoGravity: item.isPortrait ? .resizeAspectFill : .resizeAspect)
                        .onTapGesture {
                            if !showUI {
                                resetUITimer()
                            } else {
                                isPlaying.toggle()
                                if isPlaying { player.play() } else { player.pause() }
                                resetUITimer()
                            }
                        }
                } else {
                     if let url = item.thumbnailURL {
                         AsyncImage(url: url) { image in
                             image
                                 .resizable()
                                 .aspectRatio(contentMode: item.isPortrait ? .fill : .fit)
                         } placeholder: {
                             ProgressView()
                         }
                     }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            
            
            // Center Play Icon
            if !isPlaying {
                CenterPlayIcon()
            }
            
            // Sidebar layer (Right side)
            VStack(alignment: .trailing, spacing: 20) {
                Spacer()
                
                // Rating Button (Scenes & Markers)
                let rating = item.rating100 ?? 0
                let hasRating = item.rating100 != nil
                    if hasRating || true { // Always show button
                    SidebarButton(
                        icon: rating > 0 ? "star" : "star",
                        label: "Rating",
                        count: rating > 0 ? (rating / 20) : 0,
                        color: .white
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showRatingOverlay.toggle()
                        }
                        resetUITimer()
                    }
                    .overlay(alignment: .top) {
                        if showRatingOverlay {
                            VStack {
                                StarRatingView(
                                    rating100: rating,
                                    isInteractive: true,
                                    size: 25,
                                    spacing: 8,
                                    isVertical: true
                                ) { newRating in
                                    onRatingChanged(newRating)
                                    resetUITimer()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            showRatingOverlay = false
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 8)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .offset(y: -220)
                            .transition(.scale(scale: 0, anchor: .top).combined(with: .opacity))
                        }
                    }
                }
                
                // Mute Button
                SidebarButton(
                    icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: isMuted ? "Muted" : "Mute",
                    count: 0,
                    hideCount: true,
                    color: .white
                ) {
                    isMuted.toggle()
                    resetUITimer()
                }

                // O-Counter (Only for scenes)
                if let oCounter = item.oCounter {
                    SidebarButton(
                        icon: "heart",
                        label: "Counter",
                        count: oCounter,
                        color: .white
                    ) {
                        var targetSceneId: String?
                        if case .scene(let scene) = item { targetSceneId = scene.id }
                        else if case .marker(let marker) = item { targetSceneId = marker.scene?.id }
                        
                        if let sceneId = targetSceneId {
                            // Optimistic update
                            if let index = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                                let originalCount = viewModel.scenes[index].oCounter ?? 0
                                viewModel.scenes[index] = viewModel.scenes[index].withOCounter(originalCount + 1)
                                
                                viewModel.incrementOCounter(sceneId: sceneId) { newCount in
                                    if let count = newCount {
                                        DispatchQueue.main.async {
                                            viewModel.scenes[index] = viewModel.scenes[index].withOCounter(count)
                                        }
                                    } else {
                                        DispatchQueue.main.async {
                                            viewModel.scenes[index] = viewModel.scenes[index].withOCounter(originalCount)
                                        }
                                    }
                                }
                            } else {
                                 viewModel.incrementOCounter(sceneId: sceneId) { _ in }
                            }
                        }
                        resetUITimer()
                    }
                }
                
                // View Counter (Only for scenes)
                if let playCount = item.playCount {
                    SidebarButton(
                        icon: "stopwatch",
                        label: "Views",
                        count: playCount,
                        color: .white
                    ) { }
                }

                Spacer()
                    .frame(height: 0)
            }
            .frame(maxWidth: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 12)
            .padding(.bottom, 135)
            .opacity(showUI ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: showUI)
            
            // Interaction overlay (Labels + Scrubber)
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 8) {
                    // Row 1: Performer Name (Primary)
                    if let performer = item.performers.first {
                        Button(action: { onPerformerTap(performer) }) {
                            Text(performer.name)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Row 2: Title / Date (Secondary)
                    if let title = item.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                    
                    // Row 3: Tags (Tertiary) - Horizontal Scroll
                    let tags = item.tags
                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tags) { tag in
                                    Button(action: {
                                        let fullTag = Tag(id: tag.id, name: tag.name, imagePath: nil, sceneCount: nil, galleryCount: nil, favorite: nil, createdAt: nil, updatedAt: nil)
                                        onTagTap(fullTag)
                                    }) {
                                        Text("#\(tag.name)")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                CustomVideoScrubber(
                    value: Binding(get: { currentTime }, set: { val in
                        currentTime = val
                        seek(to: val)
                    }),
                    total: duration,
                    onEditingChanged: { editing in
                        isSeeking = editing
                        if editing {
                            player?.pause()
                        } else {
                            if isPlaying { player?.play() }
                            resetUITimer()
                        }
                    }
                )
                .padding(.bottom, 0)
        }
        .padding(.bottom, 95)
        .opacity(showUI ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: showUI)
        }
        .background(Color.black)
        .onAppear {
            setupPlayer()
            resetUITimer()
        }
        .onDisappear {
            player?.pause()
            if let timeObserver = timeObserver {
                player?.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
        }
        .onChange(of: isMuted) { _, newValue in
            player?.isMuted = newValue
        }
    }
    
    // Helper View
    func CenterPlayIcon() -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.7))
                    .shadow(radius: 10)
                Spacer()
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isPlaying = true
            player?.play()
            resetUITimer()
        }
    }
    
    func setupPlayer() {
        guard let streamURL = item.videoURL else { return }
         
        player = createPlayer(for: streamURL)
        
        if let player = player {
            player.isMuted = isMuted
            player.play()
            
            let startTime = item.startTime
            if startTime > 0 {
                player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
            }
            
            // Initial duration guess
            if let d = item.duration, d > 0 {
                self.duration = d
            }
            
            // Loop (Scenes only)
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                // Weak capture not needed in Struct-based View usually, but let's be safe if needed, 
                // though usually impossible in SwiftUI View structs.
                // standard closure is fine.
                if case .scene = self.item {
                    if startTime > 0 {
                        player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                    } else {
                        player.seek(to: .zero)
                    }
                    player.play()
                    incrementPlayCount()
                }
            }
            
            // Time Observer
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                if !self.isSeeking {
                    self.currentTime = time.seconds
                }
                
                // Marker Loop Logic (20s clip)
                if case .marker = self.item {
                     let start = self.item.startTime
                     let end = start + 20.0
                     if time.seconds >= end {
                         player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
                         player.play()
                     }
                } else {
                     // Scene duration update
                     if let d = player.currentItem?.duration.seconds, d > 0, !d.isNaN {
                         self.duration = d
                     }
                }
            }
            
            // Increment play count
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                incrementPlayCount()
            }
        }
    }
    
    func incrementPlayCount() {
        if case .scene(let scene) = item {
            viewModel.addScenePlay(sceneId: scene.id) { newCount in
                if let count = newCount {
                    if let index = viewModel.scenes.firstIndex(where: { $0.id == scene.id }) {
                        DispatchQueue.main.async {
                            viewModel.scenes[index] = viewModel.scenes[index].withPlayCount(count)
                        }
                    }
                }
            }
        }
    }
    
    func resetUITimer() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showUI = true
        }
        
        uiHideTask?.cancel()
        uiHideTask = Task {
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            
            if !showRatingOverlay && !isSeeking {
                withAnimation(.easeInOut(duration: 0.8)) {
                    showUI = false
                }
            } else if !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                if !Task.isCancelled {
                    resetUITimer()
                }
            }
        }
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
    }
}

struct SidebarButton: View {
    let icon: String
    let label: String
    let count: Int
    var hideCount: Bool = false
    let color: Color
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(color)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                
                // Fixed height container for the count to prevent shifting
                ZStack {
                    if !hideCount && count > 0 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    }
                }
                .frame(height: 12)
            }
            .frame(width: 45, height: 45) // Fixed total height for the button
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Custom Edge-to-Edge Video Scrubber

struct CustomVideoScrubber: View {
    @Binding var value: Double
    var total: Double
    var onEditingChanged: (Bool) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Background Track (Interactive Area)
                Rectangle()
                    .fill(Color.white.opacity(0.3)) // Slight visible track
                    .frame(height: 2) // Very thin default
                
                // Progress Bar
                Rectangle()
                    .fill(Color.white)
                    .frame(width: max(0, min(geometry.size.width, geometry.size.width * (value / total))), height: 2)
                
                // Expanded Touch Area (Invisible) for easier scrubbing
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                onEditingChanged(true)
                                let percentage = min(max(0, value.location.x / geometry.size.width), 1)
                                self.value = percentage * total
                            }
                            .onEnded { _ in
                                onEditingChanged(false)
                            }
                    )
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 10) // Small height container
    }
}
    
