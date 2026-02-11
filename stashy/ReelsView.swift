//
//  ReelsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

#if !os(tvOS)
import SwiftUI
import AVKit
import AVFoundation

struct ReelsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .scenes) ?? "") ?? .random
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var selectedPerformer: ScenePerformer?
    @State private var selectedTags: [Tag] = []
    @State private var isMuted = !isHeadphonesConnected() // Shared mute state for Reels
    @State private var currentVisibleSceneId: String?
    @State private var showDeleteConfirmation = false
    @State private var sceneToDelete: Scene?
    @State private var reelsMode: ReelsMode = ReelsMode(from: TabManager.shared.enabledReelsModes.first ?? .scenes)
    @State private var selectedMarkerSortOption: StashDBViewModel.SceneMarkerSortOption = StashDBViewModel.SceneMarkerSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .markers) ?? "") ?? .random
    @State private var selectedClipSortOption: StashDBViewModel.ImageSortOption = StashDBViewModel.ImageSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .clips) ?? "") ?? .random
    @State private var selectedClipFilter: StashDBViewModel.SavedFilter?

    enum ReelsMode: String, CaseIterable {
        case scenes = "Scenes"
        case markers = "Markers"
        case clips = "Clips"
        
        var icon: String {
            switch self {
            case .scenes: return "film"
            case .markers: return "mappin.and.ellipse"
            case .clips: return "photo.on.rectangle.angled"
            }
        }
        
        var toModeType: ReelsModeType {
            switch self {
            case .scenes: return .scenes
            case .markers: return .markers
            case .clips: return .clips
            }
        }
        
        init(from type: ReelsModeType) {
            switch type {
            case .scenes: self = .scenes
            case .markers: self = .markers
            case .clips: self = .clips
            }
        }
    }

    enum ReelItemData: Identifiable {
        case scene(Scene)
        case marker(SceneMarker)
        case clip(StashImage)
        
        var id: String {
            switch self {
            case .scene(let s): return s.id
            case .marker(let m): return m.id
            case .clip(let c): return c.id
            }
        }
        
        var title: String? {
            switch self {
            case .scene(let s): return s.title
            case .marker(let m): return m.scene?.title
            case .clip(let c): return c.title
            }
        }
        
        var performers: [ScenePerformer] {
            switch self {
            case .scene(let s): return s.performers
            case .marker(let m): return m.scene?.performers ?? []
            case .clip(let c): return c.performers?.map { ScenePerformer(id: $0.id, name: $0.name, sceneCount: nil, galleryCount: nil) } ?? []
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
            case .clip(let c): return c.tags ?? []
            }
        }
        
        var thumbnailURL: URL? {
            switch self {
            case .scene(let s): return s.thumbnailURL
            case .marker(let m): return m.thumbnailURL
            case .clip(let c): return c.thumbnailURL
            }
        }
        
        var videoURL: URL? {
            let quality = ServerConfigManager.shared.activeConfig?.reelsQuality ?? .sd
            switch self {
            case .scene(let s):
                // 0. Check local first
                if let local = s.videoURL, !local.absoluteString.hasPrefix("http") {
                    return local
                }
                return s.bestStream(for: quality) ?? s.videoURL
                
            case .marker(let m):
                // 0. Check local first (using the scene's video)
                if let scene = m.scene, let local = scene.videoURL, !local.absoluteString.hasPrefix("http") {
                    print("📂 Reels: Using local download for marker's scene")
                    return local
                }
                
                // Always use the full scene stream for markers to allow seeking/looping
                if let sceneID = m.scene?.id, let config = ServerConfigManager.shared.loadConfig() {
                    // Try to get HLS stream for the scene with reels quality first
                    if let scene = m.scene, let url = scene.bestStream(for: quality) {
                        return url
                    }
                    
                    var urlString = "\(config.baseURL)/scene/\(sceneID)/stream"
                    if let key = config.secureApiKey {
                        urlString += "?apikey=\(key)"
                    }
                    return URL(string: urlString)
                }
                return m.videoURL
                
            case .clip(let c):
                // For clips (images that are videos), the imagePath IS the video path
                return c.imageURL
            }
        }
        
        var startTime: Double {
            switch self {
            case .scene: return 0
            case .marker(let m): return m.seconds
            case .clip: return 0
            }
        }

        var endTime: Double? {
            switch self {
            case .marker(let m): return m.endSeconds
            default: return nil
            }
        }

        var duration: Double? {
            switch self {
            case .scene(let s): return s.duration
            case .marker(let m): return m.scene?.files?.first?.duration
            case .clip: return nil  // Images don't have duration in Stash
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
            case .clip(let c):
                if let file = c.visual_files?.first {
                    return (file.height ?? 0) > (file.width ?? 0)
                }
                return false
            }
        }
        
        var rating100: Int? {
            switch self {
            case .scene(let s): return s.rating100
            case .marker(let m): return m.scene?.rating100
            case .clip(let c): return c.rating100
            }
        }
        
        var oCounter: Int? {
            switch self {
            case .scene(let s): return s.oCounter
            case .marker(let m): return m.scene?.oCounter
            case .clip(let c): return c.o_counter
            }
        }
        
        var playCount: Int? {
            switch self {
            case .scene(let s): return s.playCount
            case .marker(let m): return m.scene?.playCount
            case .clip: return nil  // Images don't track play count
            }
        }
        
        var dateString: String? {
            switch self {
            case .scene(let s): return s.date
            case .marker(let m): return m.scene?.date
            case .clip(let c): return c.date
            }
        }
        
        var sceneID: String? {
            switch self {
            case .scene(let s): return s.id
            case .marker(let m): return m.scene?.id
            case .clip: return nil  // Clips are images, not scenes
            }
        }
        
        var isGIF: Bool {
            switch self {
            case .clip(let c):
                return c.fileExtension?.uppercased() == "GIF"
            case .scene: return false
            case .marker: return false
            }
        }

    }

    

    private func applySettings(sortBy: StashDBViewModel.SceneSortOption? = nil, markerSortBy: StashDBViewModel.SceneMarkerSortOption? = nil, clipSortBy: StashDBViewModel.ImageSortOption? = nil, filter: StashDBViewModel.SavedFilter?, clipFilter: StashDBViewModel.SavedFilter? = nil, performer: ScenePerformer? = nil, tags: [Tag] = [], mode: ReelsMode? = nil) {
        if let mode = mode { reelsMode = mode }
        
        // Update local state and persist to Mode-Specific Config
        if let sortBy = sortBy {
            selectedSortOption = sortBy
            TabManager.shared.setReelsDefaultSort(for: .scenes, option: sortBy.rawValue)
        }
        
        if let markerSortBy = markerSortBy {
            selectedMarkerSortOption = markerSortBy
            TabManager.shared.setReelsDefaultSort(for: .markers, option: markerSortBy.rawValue)
        }
        
        if let clipSortBy = clipSortBy {
            selectedClipSortOption = clipSortBy
        }
        
        if let clipFilter = clipFilter {
            selectedClipFilter = clipFilter
        }
        
        selectedFilter = filter
        selectedPerformer = performer
        selectedTags = tags
        
        // Merge performer and tags into filter if needed
        let mergedFilter = viewModel.mergeFilterWithCriteria(filter: filter, performer: performer, tags: tags)
        let mergedClipFilter = viewModel.mergeFilterWithCriteria(filter: selectedClipFilter, performer: performer, tags: tags)

        switch reelsMode {
        case .scenes:
            viewModel.fetchScenes(sortBy: selectedSortOption, filter: mergedFilter)
        case .markers:
            viewModel.fetchSceneMarkers(sortBy: selectedMarkerSortOption, filter: mergedFilter)
        case .clips:
            viewModel.fetchClips(sortBy: selectedClipSortOption, filter: mergedClipFilter, isInitialLoad: true)
        }
    }



    private func handleRatingChange(item: ReelItemData, newRating: Int?) {
        var targetSceneId: String?
        if case .scene(let scene) = item { targetSceneId = scene.id }
        else if case .marker(let marker) = item { targetSceneId = marker.scene?.id }
        
        if let sceneId = targetSceneId {
            // 1. Optimistic Update for Scene List
            if let sceneIndex = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                let originalRating = viewModel.scenes[sceneIndex].rating100
                viewModel.scenes[sceneIndex] = viewModel.scenes[sceneIndex].withRating(newRating)
                
                if let r = newRating {
                    viewModel.updateSceneRating(sceneId: sceneId, rating100: r) { success in
                        if !success {
                            DispatchQueue.main.async {
                                viewModel.scenes[sceneIndex] = viewModel.scenes[sceneIndex].withRating(originalRating)
                                ToastManager.shared.show("Failed to save rating", icon: "exclamationmark.triangle", style: .error)
                            }
                        }
                    }
                }
            }
            
            // 2. Optimistic Update for Scene Markers
            let markerIndices = viewModel.sceneMarkers.enumerated().compactMap { index, marker in
                marker.scene?.id == sceneId ? index : nil
            }
            
            for index in markerIndices {
                if let markerScene = viewModel.sceneMarkers[index].scene {
                    viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withScene(markerScene.withRating(newRating))
                }
            }
            
            // If not in scenes list
            if !viewModel.scenes.contains(where: { $0.id == sceneId }) {
                if let r = newRating {
                    viewModel.updateSceneRating(sceneId: sceneId, rating100: r) { _ in }
                }
            }
        } else if case .clip(let image) = item {
            // 3. Optimistic Update for Clips List
            if let clipIndex = viewModel.clips.firstIndex(where: { $0.id == image.id }) {
                let originalRating = viewModel.clips[clipIndex].rating100
                viewModel.clips[clipIndex] = viewModel.clips[clipIndex].withRating(newRating)
                
                if let r = newRating {
                    viewModel.updateImageRating(imageId: image.id, rating100: r) { success in
                        if !success {
                            DispatchQueue.main.async {
                                viewModel.clips[clipIndex] = viewModel.clips[clipIndex].withRating(originalRating)
                                ToastManager.shared.show("Failed to save rating", icon: "exclamationmark.triangle", style: .error)
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleOCounterChange(item: ReelItemData, newCount: Int) {
        var targetSceneId: String?
        if case .scene(let scene) = item { targetSceneId = scene.id }
        else if case .marker(let marker) = item { targetSceneId = marker.scene?.id }
        
        if let sceneId = targetSceneId {
            // 1. Scene List Update
            if let index = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                let originalCount = viewModel.scenes[index].oCounter ?? 0
                viewModel.scenes[index] = viewModel.scenes[index].withOCounter(newCount)
                
                viewModel.incrementOCounter(sceneId: sceneId) { returnedCount in
                    if let count = returnedCount {
                        DispatchQueue.main.async {
                            viewModel.scenes[index] = viewModel.scenes[index].withOCounter(count)
                        }
                    } else {
                        DispatchQueue.main.async {
                            viewModel.scenes[index] = viewModel.scenes[index].withOCounter(originalCount)
                            ToastManager.shared.show("Counter update failed", icon: "exclamationmark.triangle", style: .error)
                        }
                    }
                }
            }
            
            // 2. Scene Markers Update
            let markerIndices = viewModel.sceneMarkers.enumerated().compactMap { index, marker in
                marker.scene?.id == sceneId ? index : nil
            }
            
            for index in markerIndices {
                if let markerScene = viewModel.sceneMarkers[index].scene {
                    let originalCount = markerScene.oCounter ?? 0
                    viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withScene(markerScene.withOCounter(newCount))
                    
                    // If NOT already handled by scene list update
                    if !viewModel.scenes.contains(where: { $0.id == sceneId }) {
                         viewModel.incrementOCounter(sceneId: sceneId) { returnedCount in
                            if let count = returnedCount {
                                DispatchQueue.main.async {
                                    viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withScene(markerScene.withOCounter(count))
                                }
                            } else {
                                DispatchQueue.main.async {
                                    viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withScene(markerScene.withOCounter(originalCount))
                                }
                            }
                         }
                    }
                }
            }
            
            // 3. Fallback (if not in any list)
            if !viewModel.scenes.contains(where: { $0.id == sceneId }) && markerIndices.isEmpty {
                viewModel.incrementOCounter(sceneId: sceneId) { _ in }
            }
            
        } else if case .clip(let image) = item {
            // 4. Clip Update
            if let index = viewModel.clips.firstIndex(where: { $0.id == image.id }) {
                let originalCount = viewModel.clips[index].o_counter ?? 0
                
                // Optimistic Update
                viewModel.clips[index] = viewModel.clips[index].withOCounter(newCount)
                
                viewModel.incrementImageOCounter(imageId: image.id) { returnedCount in
                    if let count = returnedCount {
                        DispatchQueue.main.async {
                            viewModel.clips[index] = viewModel.clips[index].withOCounter(count)
                        }
                    } else {
                        DispatchQueue.main.async {
                            if let revertIndex = viewModel.clips.firstIndex(where: { $0.id == image.id }) {
                                viewModel.clips[revertIndex] = viewModel.clips[revertIndex].withOCounter(originalCount)
                            }
                            ToastManager.shared.show("Counter update failed", icon: "exclamationmark.triangle", style: .error)
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        premiumContent
    }


    @ViewBuilder
    private var premiumContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            let isEmpty: Bool = {
                switch reelsMode {
                case .scenes: return viewModel.scenes.isEmpty
                case .markers: return viewModel.sceneMarkers.isEmpty
                case .clips: return viewModel.clips.isEmpty
                }
            }()
            let isLoading = viewModel.isLoading && isEmpty

            if isLoading {
                loadingStateView
            } else if isEmpty && viewModel.errorMessage != nil {
                errorStateView
            } else {
                reelsListView
            }
        }
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
                
                // Load saved sort for Scenes mode (default for nav context)
                let savedSortStr = TabManager.shared.getReelsDefaultSort(for: .scenes)
                let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                
                applySettings(sortBy: savedSort, filter: selectedFilter, performer: initialPerformer, tags: initialTags)
            } else {
                let isCurrentlyEmpty = (reelsMode == .scenes ? viewModel.scenes.isEmpty : viewModel.sceneMarkers.isEmpty)
                if isCurrentlyEmpty {
                    // Priority 2: Try to apply default filter
                    let defaultId: String? = {
                        switch reelsMode {
                        case .scenes: return TabManager.shared.getDefaultFilterId(for: .reels)
                        case .markers: return TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                        case .clips: return TabManager.shared.getDefaultClipFilterId(for: .reels)
                        }
                    }()
                        
                    let hasFiltersArrived = !viewModel.savedFilters.isEmpty
                    
                    if defaultId != nil, !hasFiltersArrived {
                        // We need to wait for onChange(of: viewModel.savedFilters) to trigger applySettings
                        print("🕓 ReelsView: Waiting for filters before initial load...")
                    } else {
                        // Filters are ready OR no default filter is configured
                        var initialFilter = selectedFilter
                        if initialFilter == nil, let defId = defaultId {
                            initialFilter = viewModel.savedFilters[defId]
                        }
                        
                        // Load saved sort for current mode
                        let currentModeType = reelsMode.toModeType
                        let savedSortStr = TabManager.shared.getReelsDefaultSort(for: currentModeType)
                        
                        // Apply based on mode
                        switch reelsMode {
                        case .scenes:
                            let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                            applySettings(sortBy: savedSort, filter: initialFilter, performer: selectedPerformer, tags: selectedTags)
                        case .markers:
                            let savedSort = StashDBViewModel.SceneMarkerSortOption(rawValue: savedSortStr ?? "") ?? .random
                            applySettings(markerSortBy: savedSort, filter: initialFilter, performer: selectedPerformer, tags: selectedTags)
                        case .clips:
                            let savedSort = StashDBViewModel.ImageSortOption(rawValue: savedSortStr ?? "") ?? .random
                            var clipFilter = selectedClipFilter
                            if clipFilter == nil, let defId = defaultId {
                                clipFilter = viewModel.savedFilters[defId]
                            }
                            selectedClipFilter = clipFilter
                            applySettings(clipSortBy: savedSort, filter: nil, clipFilter: clipFilter)
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.reels.rawValue {
                switch reelsMode {
                case .scenes:
                    let defaultId = TabManager.shared.getDefaultFilterId(for: .reels)
                    let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                    applySettings(sortBy: selectedSortOption, filter: newFilter, performer: selectedPerformer, tags: selectedTags)
                case .markers:
                    let defaultId = TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                    let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                    applySettings(markerSortBy: selectedMarkerSortOption, filter: newFilter, performer: selectedPerformer, tags: selectedTags)
                case .clips:
                    let defaultId = TabManager.shared.getDefaultClipFilterId(for: .reels)
                    let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                    selectedClipFilter = newFilter
                    applySettings(clipSortBy: selectedClipSortOption, filter: nil, clipFilter: newFilter, performer: selectedPerformer, tags: selectedTags)
                }
            }
        }
        .onChange(of: viewModel.savedFilters) { _, newValue in
            // Only apply default filter if we haven't set a filter yet AND we are empty
            let isCurrentlyEmpty: Bool = {
                switch reelsMode {
                case .scenes: return viewModel.scenes.isEmpty
                case .markers: return viewModel.sceneMarkers.isEmpty
                case .clips: return viewModel.clips.isEmpty
                }
            }()

            let noFilterSet = (reelsMode == .clips ? selectedClipFilter == nil : selectedFilter == nil) && selectedPerformer == nil && selectedTags.isEmpty

            if noFilterSet && isCurrentlyEmpty {
                let defaultId: String? = {
                    switch reelsMode {
                    case .scenes: return TabManager.shared.getDefaultFilterId(for: .reels)
                    case .markers: return TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                    case .clips: return TabManager.shared.getDefaultClipFilterId(for: .reels)
                    }
                }()

                if let defId = defaultId, let filter = newValue[defId] {
                    print("✅ ReelsView: Applying default \(reelsMode.rawValue) filter after lazy load")
                    switch reelsMode {
                    case .scenes:
                        applySettings(sortBy: selectedSortOption, filter: filter, performer: selectedPerformer, tags: selectedTags)
                    case .markers:
                        applySettings(markerSortBy: selectedMarkerSortOption, filter: filter, performer: selectedPerformer, tags: selectedTags)
                    case .clips:
                        selectedClipFilter = filter
                        applySettings(clipSortBy: selectedClipSortOption, filter: nil, clipFilter: filter, performer: selectedPerformer, tags: selectedTags)
                    }
                } else {
                    print("ℹ️ ReelsView: No default filter found on server, loading unfiltered \(reelsMode.rawValue)")
                    let currentModeType = reelsMode.toModeType
                    let savedSortStr = TabManager.shared.getReelsDefaultSort(for: currentModeType)

                    switch reelsMode {
                    case .scenes:
                        let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                        applySettings(sortBy: savedSort, filter: nil, performer: selectedPerformer, tags: selectedTags)
                    case .markers:
                        let savedSort = StashDBViewModel.SceneMarkerSortOption(rawValue: savedSortStr ?? "") ?? .random
                        applySettings(markerSortBy: savedSort, filter: nil, performer: selectedPerformer, tags: selectedTags)
                    case .clips:
                        let savedSort = StashDBViewModel.ImageSortOption(rawValue: savedSortStr ?? "") ?? .random
                        applySettings(clipSortBy: savedSort, filter: nil, clipFilter: nil, performer: selectedPerformer, tags: selectedTags)
                    }
                }
            }
        }
        .onChange(of: viewModel.isLoadingSavedFilters) { _, isLoading in
            if !isLoading {
                let isCurrentlyEmpty: Bool = {
                    switch reelsMode {
                    case .scenes: return viewModel.scenes.isEmpty
                    case .markers: return viewModel.sceneMarkers.isEmpty
                    case .clips: return viewModel.clips.isEmpty
                    }
                }()
                let noFilterSet = (reelsMode == .clips ? selectedClipFilter == nil : selectedFilter == nil) && selectedPerformer == nil && selectedTags.isEmpty

                if noFilterSet && isCurrentlyEmpty {
                    print("ℹ️ ReelsView: Filter loading finished, ensuring content loads...")
                    let defaultId: String? = {
                        switch reelsMode {
                        case .scenes: return TabManager.shared.getDefaultFilterId(for: .reels)
                        case .markers: return TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                        case .clips: return TabManager.shared.getDefaultClipFilterId(for: .reels)
                        }
                    }()

                    if let defId = defaultId, let filter = viewModel.savedFilters[defId] {
                        switch reelsMode {
                        case .scenes:
                            applySettings(sortBy: selectedSortOption, filter: filter, performer: selectedPerformer, tags: selectedTags)
                        case .markers:
                            applySettings(markerSortBy: selectedMarkerSortOption, filter: filter, performer: selectedPerformer, tags: selectedTags)
                        case .clips:
                            selectedClipFilter = filter
                            applySettings(clipSortBy: selectedClipSortOption, filter: nil, clipFilter: filter, performer: selectedPerformer, tags: selectedTags)
                        }
                    } else {
                        let currentModeType = reelsMode.toModeType
                        let savedSortStr = TabManager.shared.getReelsDefaultSort(for: currentModeType)

                        switch reelsMode {
                        case .scenes:
                            let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                            applySettings(sortBy: savedSort, filter: nil, performer: selectedPerformer, tags: selectedTags)
                        case .markers:
                            let savedSort = StashDBViewModel.SceneMarkerSortOption(rawValue: savedSortStr ?? "") ?? .random
                            applySettings(markerSortBy: savedSort, filter: nil, performer: selectedPerformer, tags: selectedTags)
                        case .clips:
                            let savedSort = StashDBViewModel.ImageSortOption(rawValue: savedSortStr ?? "") ?? .random
                            applySettings(clipSortBy: savedSort, filter: nil, clipFilter: nil, performer: selectedPerformer, tags: selectedTags)
                        }
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
        let items: [ReelItemData] = {
            switch reelsMode {
            case .scenes: return viewModel.scenes.map { ReelItemData.scene($0) }
            case .markers: return viewModel.sceneMarkers.map { ReelItemData.marker($0) }
            case .clips: return viewModel.clips.map { ReelItemData.clip($0) }
            }
        }()
        
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
                            handleRatingChange(item: item, newRating: newRating)
                        },
                        onOCounterChanged: { newCount in
                            handleOCounterChange(item: item, newCount: newCount)
                        },
                        viewModel: viewModel
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(item.id)
                    .onAppear {
                        if index == items.count - 2 {
                            switch reelsMode {
                            case .scenes: viewModel.loadMoreScenes()
                            case .markers: viewModel.loadMoreMarkers()
                            case .clips: viewModel.loadMoreClips()
                            }
                        }
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .onScrollGeometryChange(for: String?.self) { geo in
            // Find the ID of the scene/item that is closest to the center or top of the visible area
            let offsetY = geo.contentOffset.y
            let height = geo.containerSize.height
            if height > 0 {
                let index = Int(round(offsetY / height))
                let currentItems: [ReelItemData] = {
                    switch reelsMode {
                    case .scenes: return viewModel.scenes.map { .scene($0) }
                    case .markers: return viewModel.sceneMarkers.map { .marker($0) }
                    case .clips: return viewModel.clips.map { .clip($0) }
                    }
                }()
                if index >= 0 && index < currentItems.count {
                    return currentItems[index].id
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
        .onAppear {
            // 1. Initialize reelsMode ONLY if current mode is disabled in settings
            let enabledTypes = tabManager.enabledReelsModes
            if !enabledTypes.contains(reelsMode.toModeType) {
                if let first = enabledTypes.first {
                    reelsMode = ReelsMode(from: first)
                }
            }
            
            // 2. Load and apply default sort for current mode
            let currentModeType = reelsMode.toModeType
            if let defaultSort = tabManager.getReelsDefaultSort(for: currentModeType) {
                switch reelsMode {
                case .scenes:
                    if let option = StashDBViewModel.SceneSortOption(rawValue: defaultSort) {
                        selectedSortOption = option
                    }
                case .markers:
                    if let option = StashDBViewModel.SceneMarkerSortOption(rawValue: defaultSort) {
                        selectedMarkerSortOption = option
                    }
                case .clips:
                    if let option = StashDBViewModel.ImageSortOption(rawValue: defaultSort) {
                        selectedClipSortOption = option
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var reelsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                Picker("Mode", selection: $reelsMode) {
                    ForEach(tabManager.enabledReelsModes, id: \.self) { modeType in
                        let mode = ReelsMode(from: modeType)
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: reelsMode.icon)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
            }
            .onChange(of: reelsMode) { _, newValue in
                switch newValue {
                case .markers:
                    // Load default MARKER filter if available
                    if let defaultId = TabManager.shared.getDefaultMarkerFilterId(for: .reels),
                       let filter = viewModel.savedFilters[defaultId] {
                        applySettings(filter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                    } else {
                        applySettings(filter: nil, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                    }
                    
                case .scenes:
                    // Load default SCENE filter if available
                    if let defaultId = TabManager.shared.getDefaultFilterId(for: .reels),
                       let filter = viewModel.savedFilters[defaultId] {
                        applySettings(filter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                    } else {
                        applySettings(filter: nil, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                    }
                    
                case .clips:
                    // Load default clip filter if available
                    if let defaultId = TabManager.shared.getDefaultClipFilterId(for: .reels),
                       let filter = viewModel.savedFilters[defaultId] {
                        selectedClipFilter = filter
                        applySettings(filter: nil, clipFilter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                    } else {
                        applySettings(filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                    }
                }
            }
        }
        
        let isEmpty: Bool = {
            switch reelsMode {
            case .scenes: return viewModel.scenes.isEmpty
            case .markers: return viewModel.sceneMarkers.isEmpty
            case .clips: return viewModel.clips.isEmpty
            }
        }()
        
        if !(isEmpty && viewModel.errorMessage != nil) {
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
                                .background(Color.black.opacity(DesignTokens.Opacity.badge))
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
                                .background(Color.black.opacity(DesignTokens.Opacity.badge))
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
            switch reelsMode {
            case .scenes:
                sceneSortOptions
            case .markers:
                markerSortOptions
            case .clips:
                clipSortOptions
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var sceneSortOptions: some View {
        // Random
        Button(action: { applySettings(sortBy: .random, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
            HStack {
                Text("Random")
                if selectedSortOption == .random { Image(systemName: "checkmark") }
            }
        }
        
        Divider()
        
        // Date
        Menu {
            Button(action: { applySettings(sortBy: .dateDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Newest First")
                    if selectedSortOption == .dateDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .dateAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
            Button(action: { applySettings(sortBy: .titleAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("A → Z")
                    if selectedSortOption == .titleAsc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .titleDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
            Button(action: { applySettings(sortBy: .durationDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Longest First")
                    if selectedSortOption == .durationDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .durationAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
            Button(action: { applySettings(sortBy: .createdAtDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Newest First")
                    if selectedSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .createdAtAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
            Button(action: { applySettings(sortBy: .oCounterDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("High → Low")
                    if selectedSortOption == .oCounterDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .oCounterAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
            Button(action: { applySettings(sortBy: .ratingDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("High → Low")
                    if selectedSortOption == .ratingDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .ratingAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
        Button(action: { applySettings(markerSortBy: .random, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
            HStack {
                Text("Random")
                if selectedMarkerSortOption == .random { Image(systemName: "checkmark") }
            }
        }
        
        Divider()
        
        // Created
        Menu {
            Button(action: { applySettings(markerSortBy: .createdAtDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Newest First")
                    if selectedMarkerSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(markerSortBy: .createdAtAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
            Button(action: { applySettings(markerSortBy: .titleAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("A → Z")
                    if selectedMarkerSortOption == .titleAsc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(markerSortBy: .titleDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
            Button(action: { applySettings(markerSortBy: .secondsAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Start Time")
                    if selectedMarkerSortOption == .secondsAsc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(markerSortBy: .secondsDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
    private var clipSortOptions: some View {
        // Random
        Button(action: { applySettings(clipSortBy: .random, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
            HStack {
                Text("Random")
                if selectedClipSortOption == .random { Image(systemName: "checkmark") }
            }
        }
        
        Divider()
        
        // Date
        Menu {
            Button(action: { applySettings(clipSortBy: .dateDesc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Newest First")
                    if selectedClipSortOption == .dateDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(clipSortBy: .dateAsc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Oldest First")
                    if selectedClipSortOption == .dateAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Date")
                if selectedClipSortOption == .dateAsc || selectedClipSortOption == .dateDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Title
        Menu {
            Button(action: { applySettings(clipSortBy: .titleAsc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("A → Z")
                    if selectedClipSortOption == .titleAsc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(clipSortBy: .titleDesc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Z → A")
                    if selectedClipSortOption == .titleDesc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Title")
                if selectedClipSortOption == .titleAsc || selectedClipSortOption == .titleDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Rating
        Menu {
            Button(action: { applySettings(clipSortBy: .ratingDesc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Highest First")
                    if selectedClipSortOption == .ratingDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(clipSortBy: .ratingAsc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Lowest First")
                    if selectedClipSortOption == .ratingAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Rating")
                if selectedClipSortOption == .ratingAsc || selectedClipSortOption == .ratingDesc { Image(systemName: "checkmark") }
            }
        }
    }

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            if reelsMode == .clips {
                // Clips uses image filters
                Button(action: {
                    selectedClipFilter = nil
                    applySettings(filter: nil, clipFilter: nil, performer: selectedPerformer, tags: selectedTags, mode: .clips)
                }) {
                    HStack {
                        Text("No Filter")
                        if selectedClipFilter == nil { Image(systemName: "checkmark") }
                    }
                }
                
                let imageFilters = viewModel.savedFilters.values
                    .filter { $0.mode == .images && $0.id != "reels_temp" && $0.id != "reels_merged" }
                    .sorted { $0.name < $1.name }
                
                ForEach(imageFilters) { filter in
                    Button(action: {
                        selectedClipFilter = filter
                        applySettings(filter: nil, clipFilter: filter, performer: selectedPerformer, tags: selectedTags, mode: .clips)
                    }) {
                        HStack {
                            Text(filter.name)
                            if selectedClipFilter?.id == filter.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            } else {
                // Scenes/Markers share scene or sceneMarker filters
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
            }
        } label: {
            let hasActiveFilter = (reelsMode == .clips ? selectedClipFilter != nil : selectedFilter != nil)
            Image(systemName: hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundColor(hasActiveFilter ? appearanceManager.tintColor : .white)
        }
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
    var onOCounterChanged: (Int) -> Void
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
                if item.isGIF {
                    ZoomableScrollView {
                        CustomAsyncImage(url: item.videoURL) { loader in
                            if let data = loader.imageData, isGIF(data) {
                                GIFView(data: data)
                                    .frame(maxWidth: .infinity)
                            } else if let img = loader.image {
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else if loader.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.white)
                            }
                        }
                    }
                } else if let player = player {
                    FullScreenVideoPlayer(player: player, videoGravity: item.isPortrait ? .resizeAspectFill : .resizeAspect)
                        .onTapGesture {
                            if !showUI {
                                resetUITimer()
                            } else {
                                isPlaying.toggle()
                                if isPlaying {
                                    player.play()
                                } else {
                                    player.pause()
                                }
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
                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
                            .clipShape(Capsule())
                            .offset(y: -220)
                            .transition(.scale(scale: 0, anchor: .top).combined(with: .opacity))
                        }
                    }
                }
                

                // O-Counter (Available for scenes, markers & clips)
                let oCounter = item.oCounter ?? 0
                SidebarButton(
                    icon: AppearanceManager.shared.oCounterIcon,
                    label: "Counter",
                    count: oCounter,
                    color: .white
                ) {
                    onOCounterChanged(oCounter + 1)
                }
                .contentShape(Rectangle()) // Ensure good hit target
                
                // View Counter (Available for scenes & markers)
                if let playCount = item.playCount {
                    SidebarButton(
                        icon: "stopwatch",
                        label: "Views",
                        count: playCount,
                        color: .white
                    ) { }
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
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(2)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            
                            // Download Indicator
                            let sceneId: String? = {
                                if case .scene(let s) = item { return s.id }
                                if case .marker(let m) = item { return m.scene?.id }
                                return nil
                            }()
                            
                            if let sId = sceneId, DownloadManager.shared.isDownloaded(id: sId) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .padding(3)
                                    .background(Color.green)
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }
                        }
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
                                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
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
        guard let sid = item.sceneID else {
            if let url = item.videoURL { initPlayer(with: url) }
            return
        }
        
        // 1. Start with the immediate URL (legacy or cached) for instant playback
        if let url = item.videoURL {
            initPlayer(with: url)
        }
        
        // 2. Background fetch for the "best" stream (MP4/HLS)
        viewModel.fetchSceneStreams(sceneId: sid) { streams in
            guard !streams.isEmpty else { return }
            
            let quality = ServerConfigManager.shared.activeConfig?.reelsQuality ?? .sd
            
            // Re-evaluate the best URL now that we have the full stream list
            let bestURL: URL?
            switch item {
            case .scene(let s):
                bestURL = s.withStreams(streams).bestStream(for: quality)
            case .marker(let m):
                bestURL = m.scene?.withStreams(streams).bestStream(for: quality)
            case .clip:
                bestURL = nil  // Clips don't use scene streams
            }
            
            if let targetURL = bestURL {
                // Only switch if the target is significantly different from current (e.g. not just apikey diff)
                let currentURL = (player?.currentItem?.asset as? AVURLAsset)?.url
                if currentURL?.path != targetURL.path {
                    // Priority: Upgrade to MP4 if current is legacy, or better HLS if current is HLS
                    print("⚡ Reels: Optimization found (\(targetURL.pathExtension)). Switching to improved stream.")
                    initPlayer(with: targetURL)
                }
            }
        }
    }
    
    private func initPlayer(with streamURL: URL) {
        let headers = ["ApiKey": ServerConfigManager.shared.activeConfig?.secureApiKey ?? ""]
        let asset = AVURLAsset(url: streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let newItem = AVPlayerItem(asset: asset)
        
        let startTime = item.startTime
        
        if let existingPlayer = self.player {
            // Reuse existing player for smoothness and to prevent VideoPlayer re-renders
            if let observer = timeObserver {
                existingPlayer.removeTimeObserver(observer)
                self.timeObserver = nil
            }
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: existingPlayer.currentItem)
            
            existingPlayer.replaceCurrentItem(with: newItem)
        } else {
            // First time player creation
            self.player = createPlayer(for: streamURL) // createPlayer handles AVAudioSession
        }
        
        guard let player = self.player else { return }
        
        player.isMuted = isMuted
        if isPlaying { 
            player.play() 
        }
        
        if startTime > 0 {
            player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        }
        
        // Initial duration guess from model
        if let d = item.duration, d > 0 {
            self.duration = d
        }
        
        // Loop (Scenes and Clips)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            if case .scene = self.item {
                if startTime > 0 {
                    player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                } else {
                    player.seek(to: .zero)
                }
                player.play()
                incrementPlayCount()
            } else if case .clip = self.item {
                player.seek(to: .zero)
                player.play()
            }
        }
        
        // Time Observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            if !self.isSeeking {
                self.currentTime = time.seconds
            }
            
            // Marker Loop Logic (use end_seconds if available, otherwise 20s clip)
            if case .marker = self.item {
                 let start = self.item.startTime
                 let end = self.item.endTime ?? (start + 20.0)
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
        
        // Increment play count (initial)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            incrementPlayCount()
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
        Button(action: {
            HapticManager.light()
            action()
        }) {
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
            .contentShape(Rectangle())
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
#endif
