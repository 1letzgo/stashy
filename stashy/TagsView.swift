//
//  TagsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI

struct TagsView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.TagSortOption = StashDBViewModel.TagSortOption(rawValue: TabManager.shared.getSortOption(for: .tags) ?? "") ?? .sceneCountDesc
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil
    @State private var isChangingSort = false
    @State private var searchText = ""
    @State private var isSearchVisible = false
    var hideTitle: Bool = false
    
    // Grid Setup: Flexible Columns
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 12)
    ]

    // Search function
    private func performSearch(isInitialLoad: Bool = true) {
        viewModel.fetchTags(sortBy: selectedSortOption, searchQuery: searchText, isInitialLoad: isInitialLoad, filter: selectedFilter)
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if (viewModel.isLoading && viewModel.tags.isEmpty) || (viewModel.isLoadingSavedFilters && viewModel.savedFilters.isEmpty) {
                VStack {
                    Spacer()
                    ProgressView("Loading tags...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.tags.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.tags.isEmpty {
                emptyStateView
            } else {
                tagsList
            }
        }
        .navigationTitle(hideTitle ? "" : "Tags")
#if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .conditionalSearchable(isVisible: isSearchVisible, text: $searchText, prompt: "Search tags...")
        .onChange(of: searchText) { oldValue, newValue in
            // Debounce
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if newValue == self.searchText {
                    self.performSearch()
                }
            }
        }
        .toolbar {
            if !searchText.isEmpty {
                ToolbarItem(placement: .principal) {
                    Button(action: {
                        searchText = ""
                        performSearch()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                            Text(searchText)
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
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // Sort Menu with grouped options
                    Menu {
                        // Random
                        Button(action: {
                            selectedSortOption = .random
                            TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.random.rawValue)
                            performSearch()
                        }) {
                            HStack {
                                Text("Random")
                                if selectedSortOption == .random { Image(systemName: "checkmark") }
                            }
                        }
                        
                        Divider()
                        
                        // Name
                        Menu {
                            Button(action: {
                                selectedSortOption = .nameAsc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.nameAsc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("A → Z")
                                    if selectedSortOption == .nameAsc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: {
                                selectedSortOption = .nameDesc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.nameDesc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("Z → A")
                                    if selectedSortOption == .nameDesc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Name")
                                if selectedSortOption == .nameAsc || selectedSortOption == .nameDesc { Image(systemName: "checkmark") }
                            }
                        }
                        
                        // Scene Count
                        Menu {
                            Button(action: {
                                selectedSortOption = .sceneCountDesc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.sceneCountDesc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("High → Low")
                                    if selectedSortOption == .sceneCountDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: {
                                selectedSortOption = .sceneCountAsc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.sceneCountAsc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("Low → High")
                                    if selectedSortOption == .sceneCountAsc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Scene Count")
                                if selectedSortOption == .sceneCountAsc || selectedSortOption == .sceneCountDesc { Image(systemName: "checkmark") }
                            }
                        }
                        
                        // Updated
                        Menu {
                            Button(action: {
                                selectedSortOption = .updatedAtDesc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.updatedAtDesc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("Newest First")
                                    if selectedSortOption == .updatedAtDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: {
                                selectedSortOption = .updatedAtAsc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.updatedAtAsc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("Oldest First")
                                    if selectedSortOption == .updatedAtAsc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Updated")
                                if selectedSortOption == .updatedAtAsc || selectedSortOption == .updatedAtDesc { Image(systemName: "checkmark") }
                            }
                        }
                        
                        // Created
                        Menu {
                            Button(action: {
                                selectedSortOption = .createdAtDesc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.createdAtDesc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("Newest First")
                                    if selectedSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: {
                                selectedSortOption = .createdAtAsc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.createdAtAsc.rawValue)
                                performSearch()
                            }) {
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
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .foregroundColor(appearanceManager.tintColor)
                    }

                    // Filter Menu
                    Menu {
                        Button(action: {
                            selectedFilter = nil
                            performSearch()
                        }) {
                            HStack {
                                Text("No Filter")
                                if selectedFilter == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        let tagFilters = viewModel.savedFilters.values
                            .filter { $0.mode == .tags }
                            .sorted { $0.name < $1.name }
                        
                        ForEach(tagFilters) { filter in
                            Button(action: {
                                selectedFilter = filter
                                performSearch()
                            }) {
                                HStack {
                                    Text(filter.name)
                                    if selectedFilter?.id == filter.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: selectedFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(selectedFilter != nil ? appearanceManager.tintColor : .primary)
                    }
                }
            }
        }
        .onAppear {
            // Check for search text from navigation
            if !coordinator.activeSearchText.isEmpty {
                searchText = coordinator.activeSearchText
                isSearchVisible = true
                coordinator.activeSearchText = ""
                performSearch()
                viewModel.fetchSavedFilters()
                return
            }
            
            if TabManager.shared.getDefaultFilterId(for: .tags) == nil || !viewModel.savedFilters.isEmpty {
                if viewModel.tags.isEmpty {
                    performSearch()
                }
            }
            viewModel.fetchSavedFilters()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.tags.rawValue {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .tags),
                   let newFilter = viewModel.savedFilters[defaultId] {
                    selectedFilter = newFilter
                } else {
                    selectedFilter = nil
                }
                performSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            performSearch()
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // Apply default filter if set and none selected yet
            if selectedFilter == nil {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .tags),
                   let filter = newValue[defaultId] {
                    selectedFilter = filter
                    performSearch()
                } else if !viewModel.isLoadingSavedFilters {
                    // Default filter was set but not found, or filters finished loading and none match
                    performSearch()
                }
            }
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading tags...")
            Spacer()
        }
    }

    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: "tag.fill",
            title: "No tags found",
            buttonText: "Load Tags",
            onRetry: { performSearch() }
        )
    }

    private var tagsList: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.tags) { tag in
                    NavigationLink(destination: TagDetailView(selectedTag: tag)) {
                        TagCardView(tag: tag)
                    }
                    .buttonStyle(.plain)
                }
                
                // Loading indicator for pagination
                if viewModel.isLoadingMoreTags {
                    ProgressView("Loading more tags...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if viewModel.hasMoreTags && !viewModel.tags.isEmpty {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            viewModel.loadMoreTags()
                        }
                }
            }
            .padding(16)
            .padding(.bottom, 70) // Leave space for floating bar
        }

    }
}

// Simple Card View for a Tag
struct TagCardView: View {
    let tag: Tag
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Count Box (Square, flush left, top, bottom)
            if let count = tag.sceneCount {
                 ZStack {
                     appearanceManager.tintColor
                     
                     Text("\(count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .minimumScaleFactor(0.5)
                 }
                 .frame(width: 48, height: 48)
            } else {
                // Small margin if no count box to prevent text from sticking to the edge
                Spacer().frame(width: 0)
            }
            
            // Name
            Text(tag.name)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 4)
            
            Spacer()
        } // Closing HStack
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 48) // Optimized height for two lines of subheadline
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct TagDetailView: View {
    let selectedTag: Tag
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getDetailSortOption(for: "tag_detail") ?? "") ?? .dateDesc
    @State private var isChangingSort = false
    @State private var isFavorite: Bool = false
    @State private var isUpdatingFavorite: Bool = false

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.SceneSortOption) {
        guard !isChangingSort else { return }

        isChangingSort = true
        selectedSortOption = newOption

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            TabManager.shared.setDetailSortOption(for: "tag_detail", option: newOption.rawValue)
            
            // Use existing filter if we have one loaded in viewModel, but we can't access it easily outside.
            // However, fetchTagScenes will use the internal `currentTagDetailFilter` if isInitialLoad is false?
            // No, fetchTagScenes takes `filter` arg. Only if isInitialLoad is TRUE does it store it.
            // If isInitialLoad is TRUE, I MUST pass the filter again if I want to persist it?
            // Yes, my implementation overwrite `currentTagDetailFilter = filter` on initial load.
            
            // But wait, here I am calling with isInitialLoad: true to reset pagination/sort.
            // So I need to retrieve the filter again.
            
            self.viewModel.fetchTagScenes(tagId: self.selectedTag.id, sortBy: newOption, isInitialLoad: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.isChangingSort = false
            }
        }
    }
    
    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            // iPad: 4 columns
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
            // iPhone: 1 column
            return [
                GridItem(.flexible(), spacing: 12)
            ]
        }
    }

    var body: some View {
        Group {
            if viewModel.isLoadingTagScenes && viewModel.tagScenes.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading scenes for tag...")
                    Spacer()
                }
            } else if viewModel.tagScenes.isEmpty && !viewModel.isLoadingTagScenes {
                VStack(spacing: 16) {
                    Image(systemName: "film")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)

                    Text("No scenes found for this tag")
                        .font(.title3)
                        .foregroundColor(.secondary)

                    Button(action: {
                        viewModel.fetchTagScenes(tagId: selectedTag.id, sortBy: selectedSortOption, isInitialLoad: true)
                    }) {
                        Text("Retry")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appearanceManager.tintColor)
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        // Header
                        VStack(spacing: 0) {
                            HStack(alignment: .top, spacing: 16) {
                                // Brown square with #
                                Rectangle()
                                    .fill(appearanceManager.tintColor)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        Image(systemName: "number")
                                            .font(.system(size: 32, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(selectedTag.name)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.primary)
                                            .lineLimit(2)
                                        
                                        Spacer()
                                        
                                        // StashTok Button (Top Right)
                                        Button(action: {
                                            coordinator.navigateToReels(tags: [selectedTag])
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "play.square.stack")
                                                    .font(.system(size: 10, weight: .bold))
                                                Text("StashTok")
                                                    .font(.system(size: 8, weight: .bold))
                                            }
                                            .foregroundColor(configManager.activeConfig != nil ? appearanceManager.tintColor : .white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(appearanceManager.tintColor.opacity(0.1))
                                            .clipShape(Capsule())
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    
                                    HStack(spacing: 16) {
                                        let sceneCount = selectedTag.sceneCount ?? viewModel.tagScenes.count
                                        if sceneCount > 0 {
                                            HStack(spacing: 6) {
                                                Image(systemName: "film")
                                                    .font(.caption)
                                                    .foregroundColor(appearanceManager.tintColor)
                                                
                                                Text("\(sceneCount) Scenes")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        let gCount = selectedTag.galleryCount ?? 0
                                        if gCount > 0 {
                                            HStack(spacing: 6) {
                                                Image(systemName: "photo.stack")
                                                    .font(.caption)
                                                    .foregroundColor(appearanceManager.tintColor)
                                                
                                                Text("\(gCount) Galleries")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                        }
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        
                        // Scenes Grid
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(viewModel.tagScenes) { scene in
                                NavigationLink(destination: SceneDetailView(scene: scene)) {
                                    SceneCardView(scene: scene)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if viewModel.isLoadingTagScenes {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else if viewModel.hasMoreTagScenes {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        viewModel.loadMoreTagScenes(tagId: selectedTag.id)
                                    }
                            }
                        }
                    }
                    .padding(16)
                }
                .background(Color.appBackground)
            }
        }
        .navigationTitle(selectedTag.name)
#if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button {
                        guard !isUpdatingFavorite else { return }
                        isUpdatingFavorite = true
                        let newState = !isFavorite
                        isFavorite = newState
                        
                        viewModel.toggleTagFavorite(tagId: selectedTag.id, favorite: newState) { success in
                            DispatchQueue.main.async {
                                if !success {
                                    isFavorite = !newState
                                }
                                isUpdatingFavorite = false
                            }
                        }
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(isFavorite ? .red : appearanceManager.tintColor)
                    }

                    Menu {
                        // Random
                        Button(action: { changeSortOption(to: .random) }) {
                            HStack {
                                Text("Random")
                                if selectedSortOption == .random { Image(systemName: "checkmark") }
                            }
                        }
                        
                        Divider()
                        
                        // Date
                        Menu {
                            Button(action: { changeSortOption(to: .dateDesc) }) {
                                HStack {
                                    Text("Newest First")
                                    if selectedSortOption == .dateDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .dateAsc) }) {
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
                            Button(action: { changeSortOption(to: .titleAsc) }) {
                                HStack {
                                    Text("A → Z")
                                    if selectedSortOption == .titleAsc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .titleDesc) }) {
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
                            Button(action: { changeSortOption(to: .durationDesc) }) {
                                HStack {
                                    Text("Longest First")
                                    if selectedSortOption == .durationDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .durationAsc) }) {
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
                        
                        // Rating
                        Menu {
                            Button(action: { changeSortOption(to: .ratingDesc) }) {
                                HStack {
                                    Text("High → Low")
                                    if selectedSortOption == .ratingDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .ratingAsc) }) {
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
                        
                        // Counter
                        Menu {
                            Button(action: { changeSortOption(to: .oCounterDesc) }) {
                                HStack {
                                    Text("High → Low")
                                    if selectedSortOption == .oCounterDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .oCounterAsc) }) {
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
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(appearanceManager.tintColor)
                    }
                }
            }
        }
        .onAppear {
            if viewModel.tagScenes.isEmpty && !viewModel.isLoadingTagScenes {
                viewModel.fetchTagScenes(tagId: selectedTag.id, sortBy: selectedSortOption, isInitialLoad: true)
            }
            
            // Initial fetch to get favorite status
            viewModel.fetchTag(tagId: selectedTag.id) { updatedTag in
                if let tag = updatedTag {
                    self.isFavorite = tag.favorite ?? false
                } else {
                    self.isFavorite = selectedTag.favorite ?? false
                }
            }
        }
    }
}
