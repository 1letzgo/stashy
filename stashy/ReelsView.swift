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
    @State private var isMenuOpen = false
    @State private var isMediaZoomed = false
    @State private var isRotating = false

    // Extracted binding to help the Swift compiler with type-checking
    // Native scroll binding
    private var scrollPositionBinding: Binding<String?> {
        Binding<String?>(
            get: { currentVisibleSceneId },
            set: { newValue in
                currentVisibleSceneId = newValue
            }
        )
    }

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
            case .scene(let s): return "scene-\(s.id)"
            case .marker(let m): return "marker-\(m.id)"
            case .clip(let c): return "clip-\(c.id)"
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
            case .clip(let c): return c.visual_files?.first?.duration
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

    private var currentReelItems: [ReelItemData] {
        switch reelsMode {
        case .scenes: return viewModel.scenes.map { ReelItemData.scene($0) }
        case .markers: return viewModel.sceneMarkers.map { ReelItemData.marker($0) }
        case .clips: return viewModel.clips.map { ReelItemData.clip($0) }
        }
    }

    

    private func applySettings(sortBy: StashDBViewModel.SceneSortOption? = nil, markerSortBy: StashDBViewModel.SceneMarkerSortOption? = nil, clipSortBy: StashDBViewModel.ImageSortOption? = nil, filter: StashDBViewModel.SavedFilter?, clipFilter: StashDBViewModel.SavedFilter? = nil, performer: ScenePerformer? = nil, tags: [Tag] = [], mode: ReelsMode? = nil) {
        // Prevent redundant fetching if nothing substantial changed and we're already loading
        let newMode = mode ?? reelsMode
        let isSameMode = (newMode == reelsMode)
        let isSameFilter = (filter?.id == selectedFilter?.id)
        let isSameClipFilter = (clipFilter?.id == selectedClipFilter?.id)
        let isSamePerformer = (performer?.id == selectedPerformer?.id)
        let isSameTags = (tags.map { $0.id } == selectedTags.map { $0.id })
        
        let isSameSort: Bool = {
            if let s = sortBy, s != selectedSortOption { return false }
            if let m = markerSortBy, m != selectedMarkerSortOption { return false }
            if let c = clipSortBy, c != selectedClipSortOption { return false }
            return true
        }()
        
        let isModeEmpty: Bool = {
            switch newMode {
            case .scenes: return viewModel.scenes.isEmpty
            case .markers: return viewModel.sceneMarkers.isEmpty
            case .clips: return viewModel.clips.isEmpty
            }
        }()
        
        if isSameMode && isSameFilter && isSameClipFilter && isSamePerformer && isSameTags && isSameSort && !isModeEmpty {
            print("ℹ️ ReelsView: Skipping redundant applySettings call (Data already present for \(newMode.rawValue))")
            return
        }

        if let mode = mode { reelsMode = mode }
        currentVisibleSceneId = nil // Reset to allow onAppear to pick up the new first item
        
        // Update local state only (session-scoped, does NOT persist to settings default)
        if let sortBy = sortBy {
            selectedSortOption = sortBy
        }
        
        if let markerSortBy = markerSortBy {
            selectedMarkerSortOption = markerSortBy
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
    
    private func autoSelectFirstItem() {
        // Only auto-select if nothing is selected OR if the selected ID belongs to another mode
        let currentPrefix = currentVisibleSceneId?.split(separator: "-").first.map(String.init)
        let expectedPrefix: String
        switch reelsMode {
        case .scenes: expectedPrefix = "scene"
        case .markers: expectedPrefix = "marker"
        case .clips: expectedPrefix = "clip"
        }

        if currentVisibleSceneId == nil || currentPrefix != expectedPrefix {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                switch reelsMode {
                case .scenes:
                    if let firstId = viewModel.scenes.first?.id {
                        currentVisibleSceneId = "scene-\(firstId)"
                    }
                case .markers:
                    if let firstId = viewModel.sceneMarkers.first?.id {
                        currentVisibleSceneId = "marker-\(firstId)"
                    }
                case .clips:
                    if let firstId = viewModel.clips.first?.id {
                        currentVisibleSceneId = "clip-\(firstId)"
                    }
                }
            }
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

    private var isListEmpty: Bool {
        switch reelsMode {
        case .scenes: return viewModel.scenes.isEmpty
        case .markers: return viewModel.sceneMarkers.isEmpty
        case .clips: return viewModel.clips.isEmpty
        }
    }

    var body: some View {
        premiumContent
    }


    @ViewBuilder
    private var premiumContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            let isLoading = viewModel.isLoading && isListEmpty

            if isLoading {
                loadingStateView
            } else if isListEmpty && viewModel.errorMessage != nil {
                errorStateView
            } else {
                reelsListView()
            }
        }
        .ignoresSafeArea(.all)
        .navigationTitle(viewModel.scenes.isEmpty && viewModel.errorMessage != nil ? "StashTok" : "")
        .navigationBarTitleDisplayMode(.inline)
        // Toolbar Background Logic
        .toolbarBackground(
            viewModel.scenes.isEmpty && viewModel.errorMessage != nil ? .visible : .hidden,
            for: .navigationBar
        )
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(
            viewModel.scenes.isEmpty && viewModel.errorMessage != nil ? Color.black : Color.clear,
            for: .navigationBar
        )
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            reelsToolbar
        }
        .onChange(of: reelsMode) { _, newValue in
            switch newValue {
            case .markers:
                if let defaultId = TabManager.shared.getDefaultMarkerFilterId(for: .reels),
                   let filter = viewModel.savedFilters[defaultId] {
                    applySettings(filter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                } else {
                    applySettings(filter: nil, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                }
            case .scenes:
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .reels),
                   let filter = viewModel.savedFilters[defaultId] {
                    applySettings(filter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                } else {
                    applySettings(filter: nil, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                }
            case .clips:
                if let defaultId = TabManager.shared.getDefaultClipFilterId(for: .reels),
                   let filter = viewModel.savedFilters[defaultId] {
                    selectedClipFilter = filter
                    applySettings(filter: nil, clipFilter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                } else {
                    applySettings(filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
                }
            }
        }
        .onChange(of: viewModel.scenes.first?.id) { _, _ in autoSelectFirstItem() }
        .onChange(of: viewModel.sceneMarkers.first?.id) { _, _ in autoSelectFirstItem() }
        .onChange(of: viewModel.clips.first?.id) { _, _ in autoSelectFirstItem() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            
            // Audio Optimization: Ensure session is active once for Reels
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("🎬 Reels: Audio setup error: \(error)")
            }

            // 0. Guard against rotation-triggered onAppear
            if isRotating {
                print("🔄 ReelsView: Skipping recursive onAppear during rotation")
                isRotating = false
                return
            }

            if viewModel.savedFilters.isEmpty {
                viewModel.fetchSavedFilters()
            }
            
            autoSelectFirstItem()
            
            // 1. Initialize reelsMode ONLY if current mode is disabled in settings
            let enabledTypes = tabManager.enabledReelsModes
            if !enabledTypes.contains(reelsMode.toModeType) {
                if let first = enabledTypes.first {
                    reelsMode = ReelsMode(from: first)
                }
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
                let isCurrentlyEmpty: Bool = {
                    switch reelsMode {
                    case .scenes: return viewModel.scenes.isEmpty
                    case .markers: return viewModel.sceneMarkers.isEmpty
                    case .clips: return viewModel.clips.isEmpty
                    }
                }()

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
                            selectedSortOption = savedSort
                            applySettings(sortBy: savedSort, filter: initialFilter, performer: selectedPerformer, tags: selectedTags)
                        case .markers:
                            let savedSort = StashDBViewModel.SceneMarkerSortOption(rawValue: savedSortStr ?? "") ?? .random
                            selectedMarkerSortOption = savedSort
                            applySettings(markerSortBy: savedSort, filter: initialFilter, performer: selectedPerformer, tags: selectedTags)
                        case .clips:
                            let savedSort = StashDBViewModel.ImageSortOption(rawValue: savedSortStr ?? "") ?? .random
                            selectedClipSortOption = savedSort
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
        .onChange(of: isMenuOpen) { _, _ in }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
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
            // Only apply initial load if we are empty and no specific navigation context was provided
            let isCurrentlyEmpty: Bool = {
                switch reelsMode {
                case .scenes: return viewModel.scenes.isEmpty
                case .markers: return viewModel.sceneMarkers.isEmpty
                case .clips: return viewModel.clips.isEmpty
                }
            }()

            let noCriteriaSet = (reelsMode == .clips ? selectedClipFilter == nil : selectedFilter == nil) && selectedPerformer == nil && selectedTags.isEmpty

            if noCriteriaSet && isCurrentlyEmpty && !newValue.isEmpty {
                print("✅ ReelsView: Saved filters arrived, triggering initial load...")
                let defaultId: String? = {
                    switch reelsMode {
                    case .scenes: return TabManager.shared.getDefaultFilterId(for: .reels)
                    case .markers: return TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                    case .clips: return TabManager.shared.getDefaultClipFilterId(for: .reels)
                    }
                }()

                if let defId = defaultId, let filter = newValue[defId] {
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
                    // No default filter, just load unfiltered with saved sort
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
    private func reelItemRow(index: Int, item: ReelItemData, itemCount: Int) -> some View {
        ReelItemView(
            item: item,
            isActive: item.id == currentVisibleSceneId,
            isMuted: $isMuted,
            onPerformerTap: { performer in
                applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: performer, tags: selectedTags)
            },
            onTagTap: { tag in
                applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: selectedPerformer, tags: [tag])
            },
            onRatingChanged: { rating in
                switch item {
                case .scene(let s):
                    self.viewModel.updateSceneRating(sceneId: s.id, rating100: rating, completion: { _ in })
                case .marker(let m):
                    if let sid = m.scene?.id {
                        self.viewModel.updateSceneRating(sceneId: sid, rating100: rating, completion: { _ in })
                    }
                case .clip(let c):
                    self.viewModel.updateImageRating(imageId: c.id, rating100: rating, completion: { _ in })
                }
            },
            onOCounterChanged: { _ in
                switch item {
                case .scene(let s):
                    self.viewModel.incrementOCounter(sceneId: s.id)
                case .marker(let m):
                    if let sid = m.scene?.id {
                        self.viewModel.incrementOCounter(sceneId: sid)
                    }
                case .clip(let c):
                    self.viewModel.incrementImageOCounter(imageId: c.id)
                }
            },
            viewModel: viewModel,
            isMenuOpen: $isMenuOpen,
            isZoomed: $isMediaZoomed,
            isRotating: $isRotating,
            onInteraction: { }
        )
        .scrollDisabled(isMediaZoomed)
        .containerRelativeFrame([.horizontal, .vertical])
        .background(Color.black)
        .id(item.id)
        .onAppear {
            if index == itemCount - 2 {
                switch reelsMode {
                case .scenes: viewModel.loadMoreScenes()
                case .markers: viewModel.loadMoreMarkers()
                case .clips: viewModel.loadMoreClips()
                }
            }
        }
    }

    @ViewBuilder
    private func reelsListView() -> some View {
        let items = currentReelItems
        
        ScrollView(.vertical, showsIndicators: false) {
            ScrollViewReader { proxy in
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        reelItemRow(index: index, item: item, itemCount: items.count)
                    }
                }
                .scrollTargetLayout()
            }
        }
        .focusable(false)
        .focusEffectDisabled()
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: scrollPositionBinding)
        .toolbar(.visible, for: .navigationBar)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .onScrollPhaseChange { _, _ in }
        .background(Color.black)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // Just update state for UI adjustments, no force rebuilds
            withAnimation(.easeInOut(duration: 0.3)) {
                isRotating = true
            }
            
            // Allow system rotation animation to complete before un-pausing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation {
                    isRotating = false
                }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    @ToolbarContentBuilder
    private var reelsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: {
                // Navigate back to the first visible tab (home)
                if let firstTab = TabManager.shared.visibleTabs.first {
                    coordinator.selectedTab = firstTab
                }
            }) {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.01)) // Ensure hit area is detected
                    .contentShape(Rectangle())
            }
        }
            
            if !(isListEmpty && viewModel.errorMessage != nil) {
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
                    modeMenu
                        .simultaneousGesture(TapGesture().onEnded { isMenuOpen = true })
                    sortMenu
                        .simultaneousGesture(TapGesture().onEnded { isMenuOpen = true })
                    filterMenu
                        .simultaneousGesture(TapGesture().onEnded { isMenuOpen = true })
                }
            }
        }

    private var filterColor: Color {
        selectedFilter != nil ? appearanceManager.tintColor : .white
    }

    @ViewBuilder
    private var modeMenu: some View {
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
            .foregroundColor(.white)
        }
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

        // Created
        Menu {
            Button(action: { applySettings(clipSortBy: .createdAtDesc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Newest First")
                    if selectedClipSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(clipSortBy: .createdAtAsc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Oldest First")
                    if selectedClipSortOption == .createdAtAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Created")
                if selectedClipSortOption == .createdAtAsc || selectedClipSortOption == .createdAtDesc { Image(systemName: "checkmark") }
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
    let isActive: Bool
    @State private var player: AVPlayer?
    @State private var looper: Any?
    @ObservedObject var tabManager = TabManager.shared
    
    // Playback State
    @Binding var isMuted: Bool
    var onPerformerTap: (ScenePerformer) -> Void
    var onTagTap: (Tag) -> Void
    var onRatingChanged: (Int?) -> Void
    var onOCounterChanged: (Int) -> Void
    @ObservedObject var viewModel: StashDBViewModel
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var isPlaying = true
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 1.0
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    @State private var showRatingOverlay = false
    @State private var showTagsOverlay = false
    @Binding var isMenuOpen: Bool
    @Binding var isZoomed: Bool
    @Binding var isRotating: Bool
    var onInteraction: () -> Void

    private var shouldFill: Bool {
        // Only fill if the setting is enabled
        guard tabManager.reelsFillHeight else { return false }
        
        let isPortraitDevice = UIScreen.main.bounds.height > UIScreen.main.bounds.width
        if isPortraitDevice {
            // In portrait device: fill if item is portrait
            return item.isPortrait
        } else {
            // In landscape device: fill if item is landscape (exclude GIFs which might look bad stretched too much)
            return !item.isPortrait
        }
    }

    
    
    var body: some View {
        ZStack(alignment: .bottom) {
            mediaLayer
            
            // Center Play Icon (only for videos, not GIFs)
            if !item.isGIF && !isPlaying {
                CenterPlayIcon()
            }
            
            
            bottomOverlay
        }
        .buttonStyle(.plain)
        .background(Color.black)
        .onAppear {
            setupPlayer()
            if isActive {
                onInteraction()
            }
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
        .focusable(false)
        .focusEffectDisabled()
        .onChange(of: isActive) { _, newValue in
            if newValue {
                if isPlaying && !isRotating { player?.play() }
                onInteraction()
            } else {
                player?.pause()
            }
        }
        .onChange(of: isRotating) { _, newValue in
            if !newValue && isActive && isPlaying {
                print("🔄 ReelItemView: Rotation finished, resuming playback")
                player?.play()
            } else if newValue {
                print("🔄 ReelItemView: Rotation started, pausing playback")
                player?.pause()
            }
        }
        .onChange(of: showRatingOverlay) { _, newValue in
            isMenuOpen = newValue || showTagsOverlay
        }
        .onChange(of: showTagsOverlay) { _, newValue in
            isMenuOpen = newValue || showRatingOverlay
        }
    }

    @ViewBuilder
    private var mediaLayer: some View {
        ZoomableScrollView(isZoomed: $isZoomed, onTap: handleMediaTap) {
            ZStack {
                Group {
                    if item.isGIF {
                        CustomAsyncImage(url: item.videoURL) { loader in
                            if let data = loader.imageData, isGIF(data) {
                                GIFView(data: data, fillMode: shouldFill)
                            } else if let img = loader.image {
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: shouldFill ? .fill : .fit)
                            } else if loader.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.white)
                            }
                        }
                    } else if let player = player {
                        FullScreenVideoPlayer(player: player, videoGravity: shouldFill ? .resizeAspectFill : .resizeAspect)
                    } else {
                        thumbnailPlaceholder
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .focusable(false)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private var thumbnailPlaceholder: some View {
        if let url = item.thumbnailURL {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: shouldFill ? .fill : .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } placeholder: {
                ProgressView()
                    .tint(.white)
            }
        }
    }

    private func handleMediaTap() {
        // No-op or specialized action (e.g. play/pause)
        // We no longer toggle UI visibility
        onInteraction()
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            // Tags overlay (toggled by button)
            if showTagsOverlay {
                let tags = item.tags
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tags) { tag in
                                Button(action: {
                                        let fullTag = Tag(id: tag.id, name: tag.name, imagePath: nil, sceneCount: nil, galleryCount: nil, favorite: nil, createdAt: nil, updatedAt: nil)
                                        onTagTap(fullTag)
                                        onInteraction()
                                    }) {
                                        Text("#\(tag.name)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 5)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                
                // Rating overlay (expands upward)
                if showRatingOverlay {
                    let rating = item.rating100 ?? 0
                    HStack {
                        StarRatingView(
                            rating100: rating,
                            isInteractive: true,
                            size: 28,
                            spacing: 10,
                            isVertical: false
                        ) { newRating in
                            onRatingChanged(newRating)
                            onInteraction()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showRatingOverlay = false
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Full-width progress bar
                if !item.isGIF {
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
                                onInteraction()
                            }
                        }
                    )
                    .padding(.horizontal, 0)
                }
                
                // Bottom row: Left = Performer/Title, Right = Buttons
            Spacer().frame(height: 10)
            HStack(alignment: .center, spacing: 0) {
                // Left half: Performer + Title
                VStack(alignment: .leading, spacing: 4) {
                    performerLabel(for: item)
                    titleLabel(for: item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                
                // Right half: Action buttons (horizontal)
                HStack(spacing: 8) {
                    // Tags button
                    let tags = item.tags
                    if !tags.isEmpty {
                        BottomBarButton(icon: "tag.fill", count: tags.count) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showTagsOverlay.toggle()
                                showRatingOverlay = false
                            }
                            onInteraction()
                        }
                    }
                    
                    // Rating
                    let rating = item.rating100 ?? 0
                    BottomBarButton(icon: "star", count: rating > 0 ? (rating / 20) : 0) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showRatingOverlay.toggle()
                            showTagsOverlay = false
                        }
                        onInteraction()
                    }
                    
                    // O-Counter
                    let oCounter = item.oCounter ?? 0
                    BottomBarButton(icon: AppearanceManager.shared.oCounterIcon, count: oCounter) {
                        onOCounterChanged(oCounter + 1)
                        onInteraction()
                    }
                    
                    // View Counter
                    if let playCount = item.playCount {
                        BottomBarButton(icon: "stopwatch", count: playCount) { }
                    }
                    
                    // Mute Button (only for videos)
                    if !item.isGIF {
                        BottomBarButton(
                            icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            count: 0,
                            hideCount: true
                        ) {
                            isMuted.toggle()
                            onInteraction()
                        }

                        // Play/Pause Button
                        BottomBarButton(
                            icon: isPlaying ? "pause.fill" : "play.fill",
                            count: 0,
                            hideCount: true
                        ) {
                            isPlaying.toggle()
                            if isPlaying && !isRotating {
                                player?.play()
                            } else {
                                player?.pause()
                            }
                            onInteraction()
                        }
                    }
                }
                .padding(.trailing, 16)
            }
            .frame(height: 50)
        }
        .padding(.bottom, 30) // Safe area spacing
    }
    


    @ViewBuilder
    private func performerLabel(for item: ReelsView.ReelItemData) -> some View {
        if let performer = item.performers.first {
            Button(action: { onPerformerTap(performer) }) {
                Text(performer.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func titleLabel(for item: ReelsView.ReelItemData) -> some View {
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
            if !isRotating { player?.play() }
            onInteraction()
        }
    }
    
    func setupPlayer() {
        // GIFs don't need AVPlayer
        guard !item.isGIF else { return }
        
        guard item.sceneID != nil else {
            if let url = item.videoURL { initPlayer(with: url) }
            return
        }
        
        // 1. Start with the immediate URL (legacy or cached) for instant playback
        if let url = item.videoURL {
            initPlayer(with: url)
        }
        
        // 2. Performance: Fetch best stream immediately (optimized for preloading)
        updateBestStream()
    }
    
    private func updateBestStream() {
        guard let sid = item.sceneID else { return }
        
        // Optimization: If we are already using a local file, don't bother fetching streams
        // Local files are already the "best" possible quality/performance.
        if let currentURL = item.videoURL, !currentURL.absoluteString.hasPrefix("http") {
            print("📂 Reels: Scene \(sid) is local, skipping best stream fetch.")
            return
        }
        
        // Background fetch for the "best" stream (MP4/HLS)
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
            // Smooth Upgrade: Preserve state for active items
            let wasPlaying = existingPlayer.timeControlStatus == .playing
            let currentTime = existingPlayer.currentTime()
            
            // Reuse existing player for smoothness and to prevent VideoPlayer re-renders
            if let observer = timeObserver {
                existingPlayer.removeTimeObserver(observer)
                self.timeObserver = nil
            }
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: existingPlayer.currentItem)
            
            existingPlayer.replaceCurrentItem(with: newItem)
            
            // If this is the active item and it was already playing, ensure it continues smoothly
            if isActive && wasPlaying {
                existingPlayer.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                existingPlayer.play()
            }
        } else {
            // First time player creation
            self.player = createPlayer(for: streamURL) // createPlayer handles AVAudioSession
        }
        
        guard let player = self.player else { return }
        
        player.isMuted = isMuted
        if isPlaying && isActive && !isRotating { 
            player.play() 
        } else {
            player.pause()
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
            } else if case .marker = self.item {
                let start = self.item.startTime
                player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
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
                     player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
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

struct BottomBarButton: View {
    let icon: String
    var count: Int = 0
    var hideCount: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.light()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                .overlay(alignment: .topTrailing) {
                    if !hideCount && count > 0 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.5))
                            .offset(x: 10, y: -8)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                    }
                }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
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
        .focusable(false)
        .focusEffectDisabled()
    }
}
#endif
