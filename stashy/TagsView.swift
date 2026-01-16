//
//  TagsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI

struct TagsView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var configManager = ServerConfigManager.shared
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
        .navigationBarTitleDisplayMode(.inline)
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
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 0) {
                    Button(action: {
                        withAnimation {
                            isSearchVisible.toggle()
                            if !isSearchVisible {
                                searchText = ""
                            }
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.appAccent)
                    }
                    .padding(.trailing, 8)

                    Menu {
                        Section {
                            let tagFilters = viewModel.savedFilters.values
                                .filter { $0.mode == .tags }
                                .sorted { $0.name < $1.name }
                            
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
                        } header: {
                            Text("Saved Filters")
                        }

                        Section {
                            ForEach(StashDBViewModel.TagSortOption.allCases, id: \.self) { option in
                                Button(action: {
                                    selectedSortOption = option
                                    TabManager.shared.setSortOption(for: .tags, option: option.rawValue)
                                    performSearch()
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
                            .foregroundColor(selectedFilter != nil ? .appAccent : .primary)
                    }
                }
            }
        }
        .onAppear {
            if TabManager.shared.getDefaultFilterId(for: .tags) == nil || !viewModel.savedFilters.isEmpty {
                if viewModel.tags.isEmpty {
                    performSearch()
                }
            }
            viewModel.fetchSavedFilters()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            performSearch()
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // Apply default filter if set and none selected yet
            if selectedFilter == nil, let defaultId = TabManager.shared.getDefaultFilterId(for: .tags) {
                if let filter = newValue[defaultId] {
                    selectedFilter = filter
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
    
    var body: some View {
        HStack(spacing: 12) {
            // Count Box (Square, flush left, top, bottom)
            if let count = tag.sceneCount {
                 ZStack {
                     Color.appAccent
                     
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
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
    }
}

struct TagDetailView: View {
    let selectedTag: Tag
    @StateObject private var viewModel = StashDBViewModel()
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
                    .tint(.appAccent)
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        // Header
                        VStack(spacing: 0) {
                            HStack(alignment: .top, spacing: 16) {
                                // Brown square with #
                                Rectangle()
                                    .fill(Color.appAccent)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        Image(systemName: "number")
                                            .font(.system(size: 32, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(selectedTag.name)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    HStack(spacing: 6) {
                                        Image(systemName: "film")
                                            .font(.subheadline)
                                            .foregroundColor(.appAccent)
                                        
                                        Text("\(selectedTag.sceneCount ?? viewModel.tagScenes.count) Scenes")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                        }
                        .background(Color(UIColor.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .navigationBarTitleDisplayMode(.inline)
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
                            .foregroundColor(isFavorite ? .red : .appAccent)
                    }

                    Menu {
                        ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                            Button(action: {
                                changeSortOption(to: option)
                            }) {
                                HStack {
                                    Text(option.displayName)
                                    if option == selectedSortOption {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.appAccent)
                    }
                }
            }
        }
        .onAppear {
            viewModel.fetchTagScenes(tagId: selectedTag.id, sortBy: selectedSortOption, isInitialLoad: true)
            
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
