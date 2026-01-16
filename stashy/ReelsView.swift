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
    @ObservedObject private var store = SubscriptionManager.shared
    @State private var showingPaywall = false
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getSortOption(for: .reels) ?? "") ?? .random
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var selectedPerformer: ScenePerformer?
    @State private var selectedTags: [Tag] = []
    @State private var isMuted = !isHeadphonesConnected() // Shared mute state for Reels

    private func applySettings(sortBy: StashDBViewModel.SceneSortOption, filter: StashDBViewModel.SavedFilter?, performer: ScenePerformer? = nil, tags: [Tag] = []) {
        selectedSortOption = sortBy
        TabManager.shared.setSortOption(for: .reels, option: sortBy.rawValue)
        selectedFilter = filter
        selectedPerformer = performer
        selectedTags = tags
        
        let mergedFilter = portraitMergedFilter(from: filter, performer: performer, tags: tags)
        viewModel.fetchScenes(sortBy: sortBy, filter: mergedFilter)
    }

    private func portraitMergedFilter(from filter: StashDBViewModel.SavedFilter?, performer: ScenePerformer? = nil, tags: [Tag] = []) -> StashDBViewModel.SavedFilter {
        var baseDict: [String: Any] = [:]
        
        // 1. Recover filter data
        if let filter = filter, let dict = filter.filterDict {
            baseDict = dict
        }
        
        // 2. Force Portrait
        var criteria = baseDict["c"] as? [[String: Any]] ?? []
        criteria.removeAll { ($0["id"] as? String) == "orientation" }
        criteria.append([
            "id": "orientation",
            "value": ["PORTRAIT"],
            "modifier": "EQUALS"
        ])
        
        // 3. Force Performer if selected
        criteria.removeAll { ($0["id"] as? String) == "performers" }
        if let performer = performer {
            criteria.append([
                "id": "performers",
                "value": [performer.id],
                "modifier": "INCLUDES_ALL"
            ])
        }

        // 4. Force Tags if selected
        criteria.removeAll { ($0["id"] as? String) == "tags" }
        if !tags.isEmpty {
            criteria.append([
                "id": "tags",
                "value": tags.map { $0.id },
                "modifier": "INCLUDES_ALL"
            ])
        }
        
        baseDict["c"] = criteria
        
        // 3. Serialize back to StashJSONValue
        let jsonValue: StashJSONValue? = {
            if let data = try? JSONSerialization.data(withJSONObject: baseDict),
               let decoded = try? JSONDecoder().decode(StashJSONValue.self, from: data) {
                return decoded
            }
            return nil
        }()
    
        return StashDBViewModel.SavedFilter(
            id: filter?.id ?? "reels_merged",
            name: filter?.name ?? "StashTok",
            mode: .scenes,
            filter: nil,
            object_filter: jsonValue
        )
    }

    var body: some View {
        Group {
            if !store.isPremium {
                paywallView
            } else {
                premiumContent
            }
        }
    }

    @ViewBuilder
    private var paywallView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "play.square.stack.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.appAccent)
            }
            
            VStack(spacing: 8) {
                Text("Stashtok VIP Feature")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Become stashy VIP to unlock Stashtok and offline downloads.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button {
                showingPaywall = true
            } label: {
                Text("Upgrade for 0,99€ / Month")
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.appAccent)
                    .clipShape(Capsule())
            }
            
            Button {
                Task {
                    await SubscriptionManager.shared.restorePurchases()
                }
            } label: {
                Text("Restore Purchase")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .navigationTitle("StashTok")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }

    @ViewBuilder
    private var premiumContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.isLoading && viewModel.scenes.isEmpty {
                loadingStateView
            } else if viewModel.scenes.isEmpty && viewModel.errorMessage != nil {
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
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { isMuted.toggle() }) {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundColor(.white)
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
                filterMenu
            }
        }
        .onAppear {
            viewModel.fetchSavedFilters()
            if viewModel.scenes.isEmpty {
                let savedSort = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getSortOption(for: .reels) ?? "") ?? .random
                applySettings(sortBy: savedSort, filter: nil, performer: nil, tags: []) 
            }
        }
        .onChange(of: viewModel.savedFilters) { _, newValue in
            if selectedFilter == nil, let defaultId = TabManager.shared.getDefaultFilterId(for: .reels) {
                if let filter = newValue[defaultId] {
                    applySettings(sortBy: selectedSortOption, filter: filter, performer: selectedPerformer, tags: selectedTags)
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
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.scenes.enumerated()), id: \.element.id) { index, scene in
                    ReelItemView(
                        scene: scene,
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
                            viewModel.updateSceneRating(sceneId: scene.id, rating100: newRating) { success in
                                if success {
                                    // Update scene in list
                                    if let sceneIndex = viewModel.scenes.firstIndex(where: { $0.id == scene.id }) {
                                        DispatchQueue.main.async {
                                            viewModel.scenes[sceneIndex] = viewModel.scenes[sceneIndex].withRating(newRating)
                                        }
                                    }
                                }
                            }
                        }
                    )
                    .containerRelativeFrame(.vertical)
                    .id(scene.id)
                    .onAppear {
                        if index == viewModel.scenes.count - 2 {
                            viewModel.loadMoreScenes()
                        }
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .background(Color.black)
        .background(Color.black)
        .ignoresSafeArea()
    }

    private var filterColor: Color {
        selectedFilter != nil ? appearanceManager.tintColor : .white
    }

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            // --- FILTER SECTION ---
            Section {
                Button(action: {
                    applySettings(sortBy: selectedSortOption, filter: nil, performer: selectedPerformer)
                }) {
                    HStack {
                        Text("No Filter")
                        if selectedFilter == nil { Image(systemName: "checkmark") }
                    }
                }

                let activeFilters = viewModel.savedFilters.values
                    .filter { $0.mode == .scenes && $0.id != "reels_temp" && $0.id != "reels_merged" }
                    .sorted { $0.name < $1.name }

                ForEach(activeFilters) { filter in
                    Button(action: {
                        applySettings(sortBy: selectedSortOption, filter: filter, performer: selectedPerformer)
                    }) {
                        HStack {
                            Text(filter.name)
                            if selectedFilter?.id == filter.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            } header: {
                Text("Saved Filters")
            }

            // --- SORT SECTION ---
            Section {
                ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                    Button(action: {
                        applySettings(sortBy: option, filter: selectedFilter, performer: selectedPerformer)
                    }) {
                        HStack {
                            Text(option.displayName)
                            if option == selectedSortOption {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } header: {
                Text("Sort By")
            }
        } label: {
            Image(systemName: selectedFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundColor(filterColor)
        }
    }

}

struct ReelItemView: View {
    let scene: Scene
    @State private var player: AVPlayer?
    @State private var looper: Any?
    
    // Playback State
    @Binding var isMuted: Bool
    var onPerformerTap: (ScenePerformer) -> Void
    var onTagTap: (Tag) -> Void
    var onRatingChanged: (Int?) -> Void
    @State private var isPlaying = true
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 1.0
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Video / Thumbnail layer
            Group {
                if let player = player {
                    FullScreenVideoPlayer(player: player)
                        .onTapGesture {
                            isPlaying.toggle()
                            if isPlaying { player.play() } else { player.pause() }
                        }
                } else {
                     if let url = scene.thumbnailURL {
                         AsyncImage(url: url) { image in
                             image.resizable().aspectRatio(contentMode: .fill)
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
            
            // Interaction overlay (Labels + Scrubber)
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 6) {
                    // Row 1: Performer and Rating
                    HStack(alignment: .center) {
                        if let performer = scene.performers.first {
                            Button(action: { onPerformerTap(performer) }) {
                                Text(performer.name)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Spacer()
                        
                        StarRatingView(
                            rating100: scene.rating100,
                            isInteractive: true,
                            size: 20,
                            spacing: 4,
                            isVertical: false
                        ) { newRating in
                            onRatingChanged(newRating)
                        }
                    }

                    // Row 2: Title and Studio
                    HStack(alignment: .bottom) {
                        Text(scene.title ?? "")
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if let studio = scene.studio?.name {
                            Text(studio)
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.9))
                                .shadow(radius: 2)
                                .lineLimit(1)
                        }
                    }
                    
                    // Row 3: Tags (Scrollable) in Dark Pills
                    if let tags = scene.tags, !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tags) { tag in
                                    Button(action: {
                                        let fullTag = Tag(id: tag.id, name: tag.name, imagePath: nil, sceneCount: nil, favorite: nil, createdAt: nil, updatedAt: nil)
                                        onTagTap(fullTag)
                                    }) {
                                        Text("#\(tag.name)")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white.opacity(0.9))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Scrubber (Full Width)
                Slider(value: Binding(get: { currentTime }, set: { val in
                    currentTime = val
                    seek(to: val)
                }), in: 0...duration, onEditingChanged: { editing in
                    isSeeking = editing
                    if editing {
                        player?.pause()
                    } else {
                        if isPlaying { player?.play() }
                    }
                })
                .accentColor(.white)
                .onAppear {
                     UISlider.appearance().thumbTintColor = .white
                     UISlider.appearance().maximumTrackTintColor = .white.withAlphaComponent(0.4)
                }
            }
            .padding(.bottom, 85)
        }
        .background(Color.black)
        .onAppear {
            setupPlayer()
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
        }
    }
    
    func setupPlayer() {
        guard let streamURL = scene.videoURL else { return }
         
        player = createPlayer(for: streamURL)
        
        if let player = player {
            player.isMuted = isMuted
            player.play()
            
            // Initial duration guess from metadata
            if let d = scene.duration, d > 0 {
                self.duration = d
            }
            
            // Loop
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                player.seek(to: .zero)
                player.play()
            }
            
            // Time Observer
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600) // 10fps update
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                if !self.isSeeking {
                    self.currentTime = time.seconds
                }
                
                // Update duration from REAL asset if avaiable
                if let d = player.currentItem?.duration.seconds, d > 0, !d.isNaN {
                    self.duration = d
                }
            }
        }
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
    }
}
