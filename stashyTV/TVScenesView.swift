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
    @State private var sortBy: StashDBViewModel.SceneSortOption
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @FocusState private var focusedSceneID: String?
    
    init(sortBy: StashDBViewModel.SceneSortOption = .dateDesc) {
        _sortBy = State(initialValue: sortBy)
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
            if viewModel.isLoadingScenes && viewModel.scenes.isEmpty {
                loadingView
            } else if viewModel.scenes.isEmpty {
                emptyView
            } else {
                contentGrid
            }
        }
        .navigationTitle("")
        .background(Color.black)
        .onChange(of: viewModel.scenes.first?.id) { oldID, newID in
            if oldID != newID {
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
            viewModel.fetchSavedFilters()
            if viewModel.scenes.isEmpty {
                viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
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
        case .createdAtDesc: return "Recently Added"
        case .lastPlayedAtDesc: return "Recently Played"
        case .titleAsc: return "Title (A-Z)"
        case .durationDesc: return "Longest First"
        case .playCountDesc: return "Most Viewed"
        case .ratingDesc: return "Highest Rated"
        case .random: return "Random"
        default: return option.displayName
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
                .foregroundColor(.white.opacity(0.4))
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
                .foregroundColor(.white.opacity(0.12))
            Text("No scenes found")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.4))
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
                    filterMenu: { filterMenu }
                )

                LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
                    ForEach(viewModel.scenes) { scene in
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink(destination: TVSceneDetailView(sceneId: scene.id)) {
                                TVSceneCardView(scene: scene)
                            }
                            .buttonStyle(.card)
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
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            Section("Sort By") {
                sortButton(option: .dateDesc)
                sortButton(option: .createdAtDesc)
                sortButton(option: .lastPlayedAtDesc)
                sortButton(option: .titleAsc)
                sortButton(option: .durationDesc)
                sortButton(option: .playCountDesc)
                sortButton(option: .ratingDesc)
                sortButton(option: .random)
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
