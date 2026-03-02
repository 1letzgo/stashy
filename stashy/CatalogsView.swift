//
//  CatalogsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

#if !os(tvOS)
import SwiftUI

struct CatalogsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    
    enum CatalogsTab: String, CaseIterable {
        case dashboard = "Dashboard"
        case scenes = "Scenes"
        case images = "Images"
        case galleries = "Galleries"
        case performers = "Performers"
        case studios = "Studios"
        case tags = "Tags"
        case groups = "Groups"
        
        var icon: String {
            switch self {
            case .dashboard: return "chart.bar.fill"
            case .scenes: return "film"
            case .images: return "photo"
            case .galleries: return "photo.stack"
            case .performers: return "person.3"
            case .studios: return "building.2"
            case .tags: return "tag"
            case .groups: return "rectangle.stack.fill"
            }
        }
    }
    
    private var sortedVisibleTabs: [CatalogsTab] {
        tabManager.tabs
            .filter { ($0.id == .dashboard || $0.id == .performers || $0.id == .studios || $0.id == .tags || $0.id == .scenes || $0.id == .galleries || $0.id == .groups) && $0.isVisible }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { (config: TabConfig) -> CatalogsTab? in
                switch config.id {
                case .dashboard: return .dashboard
                case .scenes: return .scenes
                case .galleries: return .galleries
                case .performers: return .performers
                case .studios: return .studios
                case .tags: return .tags
                case .groups: return .groups
                default: return nil
                }
            }
            .flatMap { (tab: CatalogsTab) -> [CatalogsTab] in
                if tab == .galleries {
                    return [.galleries, .images]
                }
                return [tab]
            }
    }
    
    private var selectedTabBinding: Binding<CatalogsTab> {
        Binding(
            get: { effectiveTab ?? .studios },
            set: { coordinator.catalogueSubTab = $0.rawValue }
        )
    }
    
    private var showTabSwitcher: Bool {
        sortedVisibleTabs.count > 1
    }
    
    private var effectiveTab: CatalogsTab? {
        let visible = sortedVisibleTabs
        
        // If current sub-tab is in visible list, use it
        if let current = CatalogsTab(rawValue: coordinator.catalogueSubTab), visible.contains(current) {
            return current
        }
        
        // Otherwise fallback to the first visible one (respecting sortOrder)
        return visible.first
    }
    
    private var effectiveTabRaw: String {
        coordinator.catalogueSubTab
    }
    
    var body: some View {
        Group {
            if let tab = effectiveTab {
                switch tab {
                case .dashboard:
                    HomeView()
                case .scenes:
                    ScenesView()
                case .images:
                    ImagesView()
                case .galleries:
                    GalleriesView()
                case .performers:
                    PerformersView()
                case .studios:
                    StudiosView(hideTitle: false)
                case .tags:
                    TagsView(hideTitle: false)
                case .groups:
                    GroupsView(hideTitle: false)
                }
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Please enable Dashboard, Performers, Studios, Tags or Groups in Settings")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .toolbar {
            if showTabSwitcher {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Dashboard", selection: selectedTabBinding) {
                            ForEach(sortedVisibleTabs, id: \.self) { tab in
                                Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: effectiveTab?.icon ?? "square.grid.2x2")
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
                }
            }
        }
    }
}
#endif

// MARK: - Groups Support Views

#if !os(tvOS)
struct GroupsView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.GroupSortOption = StashDBViewModel.GroupSortOption(rawValue: TabManager.shared.getSortOption(for: .groups) ?? "") ?? .nameAsc
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    var hideTitle: Bool = false
    
    // Search function
    private func performSearch(isInitialLoad: Bool = true) {
        viewModel.fetchGroups(sortBy: selectedSortOption, searchQuery: searchText, isInitialLoad: isInitialLoad, filter: selectedFilter)
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.isLoadingGroups && viewModel.groups.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading groups...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.groups.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.groups.isEmpty {
                emptyStateView
            } else {
                groupsGrid
            }
        }
        .navigationTitle("Groups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // Search Pill (if active)
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            performSearch()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text(searchText)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
                            .clipShape(Capsule())
                        }
                    }

                    // Sort Menu
                    Menu {
                        // Random
                        Button(action: { changeSortOption(to: .random) }) {
                            HStack {
                                Text("Random")
                                if selectedSortOption == .random { Image(systemName: "checkmark") }
                            }
                        }
                        
                        Divider()
                        
                        // Name
                        Menu {
                            Button(action: { changeSortOption(to: .nameAsc) }) {
                                HStack {
                                    Text("A → Z")
                                    if selectedSortOption == .nameAsc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .nameDesc) }) {
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

                        // Counts
                        Menu {
                            Button(action: { changeSortOption(to: .sceneCountDesc) }) {
                                HStack {
                                    Text("Scenes (High → Low)")
                                    if selectedSortOption == .sceneCountDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .galleryCountDesc) }) {
                                HStack {
                                    Text("Galleries (High → Low)")
                                    if selectedSortOption == .galleryCountDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .performerCountDesc) }) {
                                HStack {
                                    Text("Performers (High → Low)")
                                    if selectedSortOption == .performerCountDesc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Counts")
                                if selectedSortOption == .sceneCountDesc || selectedSortOption == .galleryCountDesc || selectedSortOption == .performerCountDesc { Image(systemName: "checkmark") }
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
                                if selectedFilter == nil { Image(systemName: "checkmark") }
                            }
                        }

                        let activeFilters = viewModel.savedFilters.values
                            .filter { $0.mode == .groups }
                            .sorted { $0.name < $1.name }
                        
                        ForEach(activeFilters) { filter in
                            Button(action: {
                                selectedFilter = filter
                                performSearch()
                            }) {
                                HStack {
                                    Text(filter.name)
                                    if selectedFilter?.id == filter.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: selectedFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(appearanceManager.tintColor)
                    }
                }
            }
        }
        .onAppear {
            viewModel.fetchSavedFilters()
            
            // Initial fetch if empty
            if viewModel.groups.isEmpty {
                // If no default filter is set, fetch immediately
                if TabManager.shared.getDefaultFilterId(for: .groups) == nil {
                    performSearch()
                }
            }
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // Apply default filter if set and none selected yet
            if selectedFilter == nil {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .groups),
                   let filter = newValue[defaultId] {
                    selectedFilter = filter
                    if viewModel.groups.isEmpty {
                        performSearch()
                    }
                } else if !viewModel.isLoadingSavedFilters && viewModel.groups.isEmpty {
                    performSearch()
                }
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if newValue == self.searchText {
                    performSearch()
                }
            }
        }
    }

    private func changeSortOption(to newOption: StashDBViewModel.GroupSortOption) {
        selectedSortOption = newOption
        TabManager.shared.setSortOption(for: .groups, option: newOption.rawValue)
        performSearch()
    }

    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: "rectangle.stack.fill",
            title: "No groups found",
            buttonText: "Load Groups",
            onRetry: { performSearch() }
        )
    }

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

    private var groupsGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.groups) { group in
                        NavigationLink(destination: GroupDetailView(selectedGroup: group)) {
                            GroupCardView(group: group)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id(group.id)
                    }

                    // Loading indicator for pagination
                    if viewModel.isLoadingMoreGroups {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if viewModel.hasMoreGroups && !viewModel.groups.isEmpty {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                viewModel.loadMoreGroups()
                            }
                            .id("pagination-trigger")
                    }
                }
                .padding(16)
            }
            .refreshable { performSearch() }
        }
    }
}

struct GroupCardView: View {
    let group: StashGroup
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Image
            GeometryReader { geometry in
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))

                    if let url = group.thumbnailURL {
                        CustomAsyncImage(url: url) { loader in
                            if loader.isLoading {
                                ProgressView()
                            } else if let image = loader.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                                    .clipped()
                            } else {
                                placeholderImageContent
                            }
                        }
                    } else {
                        placeholderImageContent
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
            .frame(height: 100)
            
            // Top Badges
            VStack {
                HStack(spacing: 8) {
                    Spacer()
                    // Gallery Badge (if available)
                    if let galleryCount = group.gallery_count, galleryCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(galleryCount)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 2)
                    }

                    // Scenes Badge
                    if let count = group.scene_count {
                        HStack(spacing: 3) {
                            Image(systemName: "film")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 2)
                    }
                }
                .padding(8)
                Spacer()
            }
            
            // Info Section (Bottom Name)
            VStack(alignment: .leading, spacing: 4) {
                 HStack(alignment: .bottom, spacing: 6) {
                    Text(group.name)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
    
    private var placeholderImageContent: some View {
        Image(systemName: "rectangle.stack")
            .font(.largeTitle)
            .foregroundColor(.secondary)
    }
}

struct GroupDetailView: View {
    let selectedGroup: StashGroup
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getPersistentDetailSortOption(for: DetailViewContext.group.rawValue) ?? "") ?? .dateDesc
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
    }
    @State private var selectedDetailTab: DetailTab = .scenes

    private var columns: [GridItem] {
        if verticalSizeClass == .compact {
             return [
                 GridItem(.flexible(), spacing: 12),
                 GridItem(.flexible(), spacing: 12)
             ]
        } else if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
            return [GridItem(.flexible(), spacing: 12)]
        }
    }
    
    private var galleryColumns: [GridItem] {
        if horizontalSizeClass == .regular {
             return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
             return [
                 GridItem(.flexible(), spacing: 12),
                 GridItem(.flexible(), spacing: 12)
             ]
        }
    }

    private var effectiveGalleries: Int {
        max(viewModel.totalGroupGalleries, selectedGroup.gallery_count ?? 0)
    }
    
    private var showTabSwitcher: Bool {
        (selectedGroup.scene_count ?? 0) > 0 && effectiveGalleries > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header Section
                headerView
                
                if selectedDetailTab == .scenes {
                    if !viewModel.groupScenes.isEmpty {
                        sceneGrid
                    } else if viewModel.isLoadingGroupScenes {
                        VStack {
                            ProgressView()
                            Text("Loading scenes...").font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        Text("No scenes found").foregroundColor(.secondary).padding(.top, 40)
                    }
                } else {
                    if !viewModel.groupGalleries.isEmpty {
                        galleryGrid
                    } else if viewModel.isLoadingGroupGalleries {
                        VStack {
                            ProgressView()
                            Text("Loading galleries...").font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        Text("No galleries found").foregroundColor(.secondary).padding(.top, 40)
                    }
                }
            }
        }
        .background(Color.appBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if showTabSwitcher {
                    Picker("View", selection: $selectedDetailTab) {
                        Text("Scenes").tag(DetailTab.scenes)
                        Text("Galleries").tag(DetailTab.galleries)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                } else {
                    Text(selectedGroup.name)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedDetailTab == .scenes {
                    sceneSortMenu
                }
            }
        }
        .onAppear {
            if viewModel.groupScenes.isEmpty {
                viewModel.fetchGroupScenes(groupId: selectedGroup.id, sortBy: selectedSortOption, isInitialLoad: true)
            }
            if viewModel.groupGalleries.isEmpty {
                viewModel.fetchGroupGalleries(groupId: selectedGroup.id, isInitialLoad: true)
            }
        }
    }

    private var sceneSortMenu: some View {
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
            
            // Rating
            Menu {
                Button(action: { changeSortOption(to: .ratingDesc) }) {
                    HStack {
                        Text("Highest Rated")
                        if selectedSortOption == .ratingDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeSortOption(to: .ratingAsc) }) {
                    HStack {
                        Text("Lowest Rated")
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
                .foregroundColor(appearanceManager.tintColor)
        }
    }

    private func changeSortOption(to option: StashDBViewModel.SceneSortOption) {
        selectedSortOption = option
        TabManager.shared.setPersistentDetailSortOption(for: DetailViewContext.group.rawValue, option: option.rawValue)
        viewModel.fetchGroupScenes(groupId: selectedGroup.id, sortBy: option, isInitialLoad: true)
    }

    private var sceneGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.groupScenes) { scene in
                NavigationLink(destination: SceneDetailView(scene: scene)) {
                    SceneCardView(scene: scene)
                }
                .buttonStyle(.plain)
            }
            
            if viewModel.isLoadingGroupScenes {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.hasMoreGroupScenes {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        viewModel.loadMoreGroupScenes(groupId: selectedGroup.id)
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private var galleryGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
             ForEach(viewModel.groupGalleries) { gallery in
                 NavigationLink(destination: ImagesView(gallery: gallery)) {
                     GalleryCardView(gallery: gallery)
                 }
                 .buttonStyle(.plain)
             }
             if viewModel.isLoadingGroupGalleries {
                 VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading more galleries...").font(.caption).foregroundColor(.secondary)
                }.padding(.vertical, 20)
             } else if viewModel.hasMoreGroupGalleries {
                 Color.clear.frame(height: 1).onAppear { viewModel.loadMoreGroupGalleries(groupId: selectedGroup.id) }
             }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    @State private var isHeaderExpanded = false
    
    private var headerView: some View {
        let collapsedHeight: CGFloat = 115
        let imageWidth: CGFloat = 72
        
        return HStack(alignment: .top, spacing: 0) {
            // Thumbnail: 9:16 portrait
            ZStack(alignment: .bottom) {
                if let url = selectedGroup.thumbnailURL {
                    CustomAsyncImage(url: url) { loader in
                        if loader.isLoading {
                            Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .overlay(ProgressView().scaleEffect(0.6))
                        } else if let image = loader.image {
                            image.resizable()
                                .scaledToFill()
                                .frame(width: imageWidth)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            defaultThumbnailContent(width: imageWidth)
                        }
                    }
                } else {
                    defaultThumbnailContent(width: imageWidth)
                }
            }
            .frame(width: imageWidth)
            .frame(minHeight: collapsedHeight)
            .frame(maxHeight: isHeaderExpanded ? .infinity : collapsedHeight)
            .background(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            
            // Details Section
            VStack(alignment: .leading, spacing: 4) {
                // Header: Name
                Text(selectedGroup.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(isHeaderExpanded ? nil : 2)
                
                // Grid for Group Info
                let allDetails = getGroupDetails()
                let visibleDetails = isHeaderExpanded ? allDetails : Array(allDetails.prefix(4))
                
                if !visibleDetails.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        ForEach(visibleDetails, id: \.label) { detail in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(detail.label)
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(detail.value)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                
                if isHeaderExpanded && !(selectedGroup.synopsis ?? "").isEmpty {
                    Text("Synopsis")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 4)
                    Text(selectedGroup.synopsis ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: collapsedHeight, alignment: .topLeading)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .padding(.horizontal, 16)
        .overlay(
            Group {
                let allDetails = getGroupDetails()
                if allDetails.count > 4 || !(selectedGroup.synopsis ?? "").isEmpty {
                    Button(action: {
                        withAnimation(.spring()) {
                            isHeaderExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isHeaderExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(appearanceManager.tintColor)
                            .padding(6)
                            .background(appearanceManager.tintColor.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 8)
                }
            },
            alignment: .bottomTrailing
        )
    }

    private func defaultThumbnailContent(width: CGFloat) -> some View {
        Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .overlay(Image(systemName: "rectangle.stack").font(.system(size: 24)).foregroundColor(.appAccent.opacity(0.5)))
    }

    private func getGroupDetails() -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        list.append((label: "SCENES", value: "\(viewModel.totalGroupScenes)"))
        if effectiveGalleries > 0 {
            list.append((label: "GALLERIES", value: "\(effectiveGalleries)"))
        }
        if let studio = selectedGroup.studio {
            list.append((label: "STUDIO", value: studio.name))
        }
        if let date = selectedGroup.date {
            list.append((label: "DATE", value: date))
        }
        if let rating = selectedGroup.rating100 {
            list.append((label: "RATING", value: "\(rating)%"))
        }
        return list
    }
}
#endif
