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
    @State private var currentVisibleSceneId: String?
    @State private var showDeleteConfirmation = false
    @State private var sceneToDelete: Scene?

    private func applySettings(sortBy: StashDBViewModel.SceneSortOption, filter: StashDBViewModel.SavedFilter?, performer: ScenePerformer? = nil, tags: [Tag] = []) {
        selectedSortOption = sortBy
        TabManager.shared.setSortOption(for: .reels, option: sortBy.rawValue)
        selectedFilter = filter
        selectedPerformer = performer
        selectedTags = tags
        
        // Merge performer and tags into filter if needed
        let mergedFilter = viewModel.mergeFilterWithCriteria(filter: filter, performer: performer, tags: tags)
        viewModel.fetchScenes(sortBy: sortBy, filter: mergedFilter)
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
                Text(store.vipPriceDisplay)
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
            if let currentId = currentVisibleSceneId, let scene = viewModel.scenes.first(where: { $0.id == currentId }) {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(role: .destructive) {
                        sceneToDelete = scene
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
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
        .alert("Really delete scene and files?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                if let scene = sceneToDelete {
                    viewModel.deleteSceneWithFiles(scene: scene) { success in
                        if success {
                            // Scene is removed from viewModel.scenes via notification or manual filter
                            viewModel.scenes.removeAll { $0.id == scene.id }
                        }
                    }
                }
            }
        } message: {
            if let scene = sceneToDelete {
                Text("The scene '\(scene.title ?? "Unknown Title")' and all associated files will be permanently deleted. This action cannot be undone.")
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
                            // Optimistic Update
                            if let sceneIndex = viewModel.scenes.firstIndex(where: { $0.id == scene.id }) {
                                let originalRating = viewModel.scenes[sceneIndex].rating100
                                viewModel.scenes[sceneIndex] = viewModel.scenes[sceneIndex].withRating(newRating)
                                
                                viewModel.updateSceneRating(sceneId: scene.id, rating100: newRating) { success in
                                    if !success {
                                        // Rollback on failure
                                        DispatchQueue.main.async {
                                            viewModel.scenes[sceneIndex] = viewModel.scenes[sceneIndex].withRating(originalRating)
                                        }
                                    }
                                }
                            }
                        },
                        viewModel: viewModel
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

    private var filterColor: Color {
        selectedFilter != nil ? appearanceManager.tintColor : .white
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
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
                    Text("Counter")
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
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
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
    @ObservedObject var viewModel: StashDBViewModel
    @State private var isPlaying = true
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 1.0
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    @State private var showRatingOverlay = false
    @State private var showTags = false
    @State private var showUI = true
    @State private var uiHideTask: Task<Void, Never>? = nil
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Video / Thumbnail layer
            Group {
                if let player = player {
                    FullScreenVideoPlayer(player: player, videoGravity: scene.isPortrait ? .resizeAspectFill : .resizeAspect)
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
                     if let url = scene.thumbnailURL {
                         AsyncImage(url: url) { image in
                             image
                                 .resizable()
                                 .aspectRatio(contentMode: scene.isPortrait ? .fill : .fit)
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
                
                // Rating Button (TikTok style)
                SidebarButton(
                    icon: (scene.rating100 ?? 0) > 0 ? "star" : "star", // Outlined
                    label: "Rating",
                    count: (scene.rating100 ?? 0) > 0 ? (scene.rating100! / 20) : 0,
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
                                rating100: scene.rating100,
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
                        .offset(y: -220) // Moved even higher
                        .transition(.scale(scale: 0, anchor: .top).combined(with: .opacity))
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

                // O-Counter (Manual)
                SidebarButton(
                    icon: "heart", // Outlined
                    label: "Counter",
                    count: scene.oCounter ?? 0,
                    color: .white
                ) {
                    // Optimistic update
                    if let index = viewModel.scenes.firstIndex(where: { $0.id == scene.id }) {
                        let originalCount = viewModel.scenes[index].oCounter ?? 0
                        viewModel.scenes[index] = viewModel.scenes[index].withOCounter(originalCount + 1)
                        
                        viewModel.incrementOCounter(sceneId: scene.id) { newCount in
                            if let count = newCount {
                                DispatchQueue.main.async {
                                    viewModel.scenes[index] = viewModel.scenes[index].withOCounter(count)
                                }
                            } else {
                                // Rollback on failure
                                DispatchQueue.main.async {
                                    viewModel.scenes[index] = viewModel.scenes[index].withOCounter(originalCount)
                                }
                            }
                        }
                    }
                    resetUITimer()
                }
                
                // View Counter
                SidebarButton(
                    icon: "stopwatch",
                    label: "Views",
                    count: scene.playCount ?? 0,
                    color: .white
                ) {
                    // Views are automatic
                }

                // Tag Toggle
                SidebarButton(
                    icon: "number",
                    label: "Tags",
                    count: scene.tags?.count ?? 0,
                    color: (scene.tags?.count ?? 0) > 0 ? .white : .white.opacity(0.3)
                ) {
                    if (scene.tags?.count ?? 0) > 0 {
                        withAnimation(.spring()) {
                            showTags.toggle()
                        }
                        resetUITimer()
                    }
                }
                .disabled((scene.tags?.count ?? 0) == 0)
                
                Spacer()
                    .frame(height: 0)
            }
            .frame(maxWidth: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 12)
            .padding(.bottom, 145)
            .opacity(showUI ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: showUI)
            
            // Interaction overlay (Labels + Scrubber)
            VStack(alignment: .leading, spacing: 12) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 6) {
                    // Row 1: Performer - Title (Combined)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let performer = scene.performers.first {
                            Button(action: { onPerformerTap(performer) }) {
                                Text(performer.name)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            .buttonStyle(.plain)
                            
                            Text("-")
                                .font(.headline)
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                        
                        Text(scene.title ?? "")
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                            .lineLimit(1)
                    }
                    
                    // Row 2: Tags (Scrollable) in Dark Pills - Toggleable
                    if showTags, let tags = scene.tags, !tags.isEmpty {
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
                
                Slider(value: Binding(get: { currentTime }, set: { val in
                    currentTime = val
                    seek(to: val)
                }), in: 0...duration, onEditingChanged: { editing in
                    isSeeking = editing
                    if editing {
                        player?.pause()
                    } else {
                        if isPlaying { player?.play() }
                        resetUITimer()
                    }
                })
            .accentColor(.white)
            .onAppear {
                 UISlider.appearance().thumbTintColor = .white
                 UISlider.appearance().maximumTrackTintColor = .white.withAlphaComponent(0.4)
            }
        }
        .padding(.bottom, 85)
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
                incrementPlayCount()
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
            
            // Increment play count after 3 seconds of viewing
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                incrementPlayCount()
            }
        }
    }
    
    private func incrementPlayCount() {
        viewModel.addScenePlay(sceneId: scene.id) { newCount in
            if let count = newCount {
                // Update scene in viewModel.scenes array
                if let index = viewModel.scenes.firstIndex(where: { $0.id == scene.id }) {
                    DispatchQueue.main.async {
                        viewModel.scenes[index] = viewModel.scenes[index].withPlayCount(count)
                    }
                }
            }
        }
    }
    
    private func resetUITimer() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showUI = true
        }
        
        uiHideTask?.cancel()
        uiHideTask = Task {
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            
            // Don't hide if specific overlays are visible
            if !showRatingOverlay && !isSeeking {
                withAnimation(.easeInOut(duration: 0.8)) {
                    showUI = false
                }
            } else if !Task.isCancelled {
                // If we can't hide now, try again in 2 seconds
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
