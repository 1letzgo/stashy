//
//  PerformersView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

import SwiftUI


struct PerformersView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var configManager = ServerConfigManager.shared
    @State private var scrollPosition: String? = nil
    @State private var shouldRestoreScroll = false
    @State private var selectedSortOption: StashDBViewModel.PerformerSortOption = StashDBViewModel.PerformerSortOption(rawValue: TabManager.shared.getSortOption(for: .performers) ?? "") ?? .sceneCountDesc
    @State private var isChangingSort = false
    @State private var searchText = ""
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil
    @State private var navigationPath = [Performer]()
    @State private var isSearchVisible = false
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            // iPad: 4 columns
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
            // iPhone: 2 columns
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
    }

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.PerformerSortOption) {
        selectedSortOption = newOption
        scrollPosition = nil
        shouldRestoreScroll = false
        
        // Save to TabManager
        TabManager.shared.setSortOption(for: .performers, option: newOption.rawValue)

        // Fetch new data immediately
        viewModel.fetchPerformers(sortBy: newOption, searchQuery: searchText, filter: selectedFilter)
    }
    
    // Search function with debouncing
    private func performSearch() {
        scrollPosition = nil
        shouldRestoreScroll = false
        viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: selectedFilter)
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.isLoading && viewModel.performers.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading performers...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.performers.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.performers.isEmpty {
                emptyStateView
            } else {
                performersGrid
            }
        }
        .navigationTitle("Performers")
        .navigationBarTitleDisplayMode(.inline)
        .conditionalSearchable(isVisible: isSearchVisible, text: $searchText, prompt: "Search performers...")
        .onChange(of: searchText) { oldValue, newValue in
            // Debounce: Nur suchen wenn Nutzer aufhört zu tippen (0.5s Delay)
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
                        // Saved Filters Section
                        Section {
                            let performerFilters = viewModel.savedFilters.values
                                .filter { $0.mode == .performers }
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
                            
                            ForEach(performerFilters) { filter in
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
                        
                        // Sort Options Section
                        Section {
                            ForEach(StashDBViewModel.PerformerSortOption.allCases, id: \.self) { option in
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
            // Only search if we don't have a default filter to wait for, or if filters are already loaded
            if TabManager.shared.getDefaultFilterId(for: .performers) == nil || !viewModel.savedFilters.isEmpty {
                performSearch()
            }
            viewModel.fetchSavedFilters()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            performSearch()
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // Apply default filter if set and none selected yet
            if selectedFilter == nil, let defaultId = TabManager.shared.getDefaultFilterId(for: .performers) {
                if let filter = newValue[defaultId] {
                    selectedFilter = filter
                    viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: filter)
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { coordinator.performerToOpen != nil },
            set: { if !$0 { coordinator.performerToOpen = nil } }
        )) {
            if let performer = coordinator.performerToOpen {
                PerformerDetailView(performer: performer)
            }
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading performers...")
            Spacer()
        }
    }

    private var emptyStateView: some View {
         SharedEmptyStateView(
             icon: "person.3",
             title: "No performers found",
             buttonText: "Load Performers",
             onRetry: { performSearch() }
         )
    }

    private var performersGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.performers) { performer in
                        NavigationLink(destination: PerformerDetailView(performer: performer)) {
                            PerformerCardView(performer: performer)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id(performer.id)
                    }

                    // Loading indicator for pagination
                    if viewModel.isLoadingMorePerformers {
                        ProgressView("Loading more performers...")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .id("loading-indicator")
                    } else if viewModel.hasMorePerformers && !viewModel.performers.isEmpty {
                        // Invisible element to trigger loading more performers
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                // Save scroll position before loading - use element around 3/4 of current list
                                let currentCount = viewModel.performers.count
                                if currentCount > 4 {
                                    let targetIndex = currentCount * 3 / 4
                                    if targetIndex < currentCount {
                                        scrollPosition = viewModel.performers[targetIndex].id
                                        shouldRestoreScroll = true
                                    }
                                } else if let lastPerformer = viewModel.performers.last {
                                    scrollPosition = lastPerformer.id
                                    shouldRestoreScroll = true
                                }
                                viewModel.loadMorePerformers()
                            }
                            .id("pagination-trigger")
                    }
                }
                .padding(16)
            }

            .onChange(of: viewModel.isLoadingMorePerformers) { oldValue, isLoading in
                if !isLoading && shouldRestoreScroll {
                    // Loading completed, restore scroll position
                    if let scrollPosition = scrollPosition {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(scrollPosition, anchor: .top)
                            }
                            shouldRestoreScroll = false
                        }
                    }
                }
            }
        }
    }
}


struct PerformerCardView: View {
    let performer: Performer

    var body: some View {

        ZStack(alignment: .bottomLeading) {
            // Image
            GeometryReader { geometry in
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))

                    if let thumbnailURL = performer.thumbnailURL {
                        CustomAsyncImage(url: thumbnailURL) { loader in
                            if loader.isLoading {
                                ProgressView()
                            } else if let image = loader.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                                    .clipped()
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Image(systemName: "person.fill")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .aspectRatio(9/12, contentMode: .fit) 
            
            // Gradient Overlay
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            
            // Top Badges
            VStack {
                HStack {
                    // Gallery Badge (Top Left)
                    if let galleryCount = performer.galleryCount, galleryCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(galleryCount)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 2)
                    }
                    
                    Spacer()
                    
                    // Scenes Badge (Top Right)
                    HStack(spacing: 3) {
                        Image(systemName: "film")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(performer.sceneCount)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 2)
                }
                .padding(8)
                Spacer()
            }
            
            // Info Section (Bottom Name)
            VStack(alignment: .leading, spacing: 4) {
                 HStack(alignment: .bottom, spacing: 6) {
                    Text(performer.name)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// Keep old row view for compatibility
struct PerformerRowView: View {
    let performer: Performer

    var body: some View {
        PerformerCardView(performer: performer)
    }
}

#Preview {
    PerformersView()
}
