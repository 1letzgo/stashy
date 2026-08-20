//
//  TVScenesView.swift
//  stashyTV
//
//  Scenes grid for tvOS — 4-column layout
//

import SwiftUI

struct TVScenesView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @State private var sortBy: StashDBViewModel.SceneSortOption
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @FocusState private var focusedSceneID: String?
    
    init(sortBy: StashDBViewModel.SceneSortOption? = nil) {
        let defaultSort = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getSortOption(for: .scenes) ?? "") ?? .dateDesc
        _sortBy = State(initialValue: sortBy ?? defaultSort)
    }

    private var navigationTitle: String {
        switch sortBy {
        case .lastPlayedAtDesc: return "Recently Played"
        case .dateDesc: return "Recently Released"
        case .createdAtDesc: return "Recently Added"
        default: return "Scenes – \(sortBy.displayName)"
        }
    }
    
    private var navigationIcon: String {
        switch sortBy {
        case .lastPlayedAtDesc: return "play.circle.fill"
        case .dateDesc: return "sparkles.tv.fill"
        case .createdAtDesc: return "plus.rectangle.on.folder.fill"
        default: return "film.fill"
        }
    }

    private let columns = [
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !hasValidConfig {
                TVConnectionErrorView(title: "Server not reachable", subtitle: "Add a server in Settings.") { reload() }
            } else if viewModel.scenes.isEmpty && (viewModel.errorMessage?.isEmpty == false) {
                TVConnectionErrorView(title: "Error loading scenes", subtitle: viewModel.errorMessage) { reload() }
            } else if viewModel.isLoadingScenes && viewModel.scenes.isEmpty {
                loadingView
            } else if viewModel.scenes.isEmpty {
                emptyView
            } else {
                contentGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .onChange(of: viewModel.scenes.first?.id) { oldID, newID in
            if oldID != newID, let newID {
                focusedSceneID = newID
            }
        }
        .onChange(of: sortBy) { _, newValue in
            viewModel.fetchScenes(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
            viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true, filter: newValue)
        }
        .onAppear {
            guard hasValidConfig else { return }
            viewModel.fetchSavedFilters { _ in
                applyDefaultFilterIfNeeded()
            }
            if viewModel.scenes.isEmpty {
                viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashServerInitializationFinished)) { _ in
            if hasValidConfig && viewModel.scenes.isEmpty {
                viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
    }

    private var hasValidConfig: Bool { configManager.activeConfig?.hasValidConfig == true }

    private func applyDefaultFilterIfNeeded() {
        guard selectedFilter == nil,
              let filterId = tabManager.getDefaultFilterId(for: .scenes),
              let filter = viewModel.savedFilters[filterId] else { return }
        selectedFilter = filter
    }

    private func reload() {
        guard hasValidConfig else { return }
        viewModel.testConnection()
        viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
    }


    private func sortButton(option: StashDBViewModel.SceneSortOption) -> some View {
        Button {
            sortBy = option
        } label: {
            HStack {
                Text(label(for: option))
                if sortBy == option {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func label(for option: StashDBViewModel.SceneSortOption) -> String {
        switch option {
        case .dateDesc: return "Recently Released"
        case .dateAsc: return "Oldest First"
        case .createdAtDesc: return "Recently Added"
        case .createdAtAsc: return "Oldest Added"
        case .lastPlayedAtDesc: return "Recently Played"
        case .lastPlayedAtAsc: return "Least Recently Played"
        case .titleAsc: return "Title (A-Z)"
        case .titleDesc: return "Title (Z-A)"
        case .durationDesc: return "Longest First"
        case .durationAsc: return "Shortest First"
        case .playCountDesc: return "Most Viewed"
        case .playCountAsc: return "Least Viewed"
        case .playDurationDesc: return "Most Watch Time"
        case .playDurationAsc: return "Least Watch Time"
        case .oCounterDesc: return "O Count (High-Low)"
        case .oCounterAsc: return "O Count (Low-High)"
        case .ratingDesc: return "Highest Rated"
        case .ratingAsc: return "Lowest Rated"
        case .random: return "Random"
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        Spacer()
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading scenes…")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        Spacer()
    }

    @ViewBuilder
    private var emptyView: some View {
        Spacer()
        VStack(spacing: 24) {
            Image(systemName: "film")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("No scenes found")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Button {
                viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.title3)
            }
        }
        Spacer()
    }

    @ViewBuilder
    private var contentGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                STVHeaderView(
                    sortMenu: { sortMenu },
                    filterMenu: { filterMenu },
                    onRefresh: { reload() }
                )

                LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
                    ForEach(viewModel.scenes) { scene in
                        VStack(alignment: .leading, spacing: 10) {
                            TVNavButton(value: TVSceneLink(sceneId: scene.id)) {
                                TVSceneCardView(scene: scene)
                            }
                            .focused($focusedSceneID, equals: scene.id)
                            .onAppear {
                                if scene.id == viewModel.scenes.last?.id && viewModel.hasMoreScenes {
                                    viewModel.loadMoreScenes()
                                }
                            }
                            
                            TVSceneCardTitleView(scene: scene)
                        }
                        .frame(width: 410)
                    }

                    if viewModel.isLoadingMoreScenes {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 80)
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 60).focusable(false) }
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            Section("Sort By") {
                sortButton(option: .random)
                Divider()
                sortButton(option: .dateDesc)
                sortButton(option: .dateAsc)
                sortButton(option: .createdAtDesc)
                sortButton(option: .createdAtAsc)
                sortButton(option: .lastPlayedAtDesc)
                sortButton(option: .lastPlayedAtAsc)
                sortButton(option: .titleAsc)
                sortButton(option: .titleDesc)
                sortButton(option: .durationDesc)
                sortButton(option: .durationAsc)
                sortButton(option: .playCountDesc)
                sortButton(option: .playCountAsc)
                sortButton(option: .oCounterDesc)
                sortButton(option: .oCounterAsc)
                sortButton(option: .ratingDesc)
                sortButton(option: .ratingAsc)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.arrow.down")
                Text(label(for: sortBy))
            }
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .buttonStyle(.card)
    }

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            Button {
                selectedFilter = nil
            } label: {
                HStack {
                    Text("No Filter")
                    if selectedFilter == nil {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            let sceneFilters = viewModel.savedFilters.values
                .filter { $0.mode == .scenes }
                .sorted { $0.name < $1.name }
            
            if !sceneFilters.isEmpty {
                Divider()
                ForEach(sceneFilters) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        HStack {
                            Text(filter.name)
                            if selectedFilter?.id == filter.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                Text(selectedFilter?.name ?? "No Filter")
            }
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .buttonStyle(.card)
    }
}
