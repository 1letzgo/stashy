//
//  TVGroupsView.swift
//  stashyTV
//
//  Groups and Group Detail views for tvOS — Netflix style
//

import SwiftUI

struct TVGroupsView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @State private var sortBy: StashDBViewModel.GroupSortOption
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @FocusState private var focusedGroupID: String?

    init() {
        let defaultSort = StashDBViewModel.GroupSortOption(rawValue: TabManager.shared.getSortOption(for: .groups) ?? "") ?? .nameAsc
        _sortBy = State(initialValue: defaultSort)
    }

    private let columns = [
        GridItem(.fixed(260), spacing: 40),
        GridItem(.fixed(260), spacing: 40),
        GridItem(.fixed(260), spacing: 40),
        GridItem(.fixed(260), spacing: 40),
        GridItem(.fixed(260), spacing: 40),
        GridItem(.fixed(260), spacing: 40)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !hasValidConfig {
                TVConnectionErrorView(title: "Server not reachable", subtitle: "Add a server in Settings.") { reload() }
            } else if viewModel.groups.isEmpty && (viewModel.errorMessage?.isEmpty == false) {
                TVConnectionErrorView(title: "Error loading groups", subtitle: viewModel.errorMessage) { reload() }
            } else if viewModel.isLoadingGroups && viewModel.groups.isEmpty {
                loadingView
            } else if viewModel.groups.isEmpty {
                emptyView
            } else {
                contentGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .onChange(of: viewModel.groups.first?.id) { oldID, newID in
            if oldID != newID, let newID {
                focusedGroupID = newID
            }
        }
        .onChange(of: sortBy) { _, newValue in
            viewModel.fetchGroups(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
            viewModel.fetchGroups(sortBy: sortBy, isInitialLoad: true, filter: newValue)
        }
        .onAppear {
            guard hasValidConfig else { return }
            viewModel.fetchSavedFilters { _ in
                applyDefaultFilterIfNeeded()
            }
            if viewModel.groups.isEmpty {
                viewModel.fetchGroups(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            viewModel.fetchGroups(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashServerInitializationFinished)) { _ in
            if hasValidConfig && viewModel.groups.isEmpty {
                viewModel.fetchGroups(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
    }

    private var hasValidConfig: Bool { configManager.activeConfig?.hasValidConfig == true }

    private func applyDefaultFilterIfNeeded() {
        guard selectedFilter == nil,
              let filterId = tabManager.getDefaultFilterId(for: .groups),
              let filter = viewModel.savedFilters[filterId] else { return }
        selectedFilter = filter
    }

    private func reload() {
        guard hasValidConfig else { return }
        viewModel.testConnection()
        viewModel.fetchGroups(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
    }


    private func sortButton(option: StashDBViewModel.GroupSortOption) -> some View {
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

    private func label(for option: StashDBViewModel.GroupSortOption) -> String {
        switch option {
        case .nameAsc: return "Name (A-Z)"
        case .nameDesc: return "Name (Z-A)"
        case .sceneCountDesc: return "Most Scenes"
        case .sceneCountAsc: return "Least Scenes"
        case .galleryCountDesc: return "Most Galleries"
        case .galleryCountAsc: return "Least Galleries"
        case .performerCountDesc: return "Most Performers"
        case .performerCountAsc: return "Least Performers"
        case .dateDesc: return "Newest First"
        case .dateAsc: return "Oldest First"
        case .ratingDesc: return "Highest Rated"
        case .ratingAsc: return "Lowest Rated"
        case .createdAtDesc: return "Recently Added"
        case .createdAtAsc: return "Oldest Added"
        case .updatedAtDesc: return "Recently Updated"
        case .updatedAtAsc: return "Least Recently Updated"
        case .random: return "Random"
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        Spacer()
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5)
            Text("Loading groups…")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        Spacer()
    }

    @ViewBuilder
    private var emptyView: some View {
        Spacer()
        VStack(spacing: 32) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("No Groups Found")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
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
                    ForEach(viewModel.groups) { group in
                        NavigationLink(destination: TVGroupDetailView(groupId: group.id, groupName: group.name).tvExitDismissable()) {
                            TVGroupCardView(group: group)
                        }
                        .buttonStyle(.card)
                        .focused($focusedGroupID, equals: group.id)
                        .frame(width: 260) // Fixed width for item container
                        .onAppear {
                            if group.id == viewModel.groups.last?.id && viewModel.hasMoreGroups {
                                viewModel.loadMoreGroups()
                            }
                        }
                    }

                    if viewModel.isLoadingMoreGroups {
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
                sortButton(option: .nameAsc)
                sortButton(option: .nameDesc)
                sortButton(option: .sceneCountDesc)
                sortButton(option: .sceneCountAsc)
                sortButton(option: .dateDesc)
                sortButton(option: .dateAsc)
                sortButton(option: .ratingDesc)
                sortButton(option: .ratingAsc)
                sortButton(option: .createdAtDesc)
                sortButton(option: .createdAtAsc)
                sortButton(option: .updatedAtDesc)
                sortButton(option: .updatedAtAsc)
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
            
            let groupFilters = viewModel.savedFilters.values
                .filter { $0.mode == .groups }
                .sorted { $0.name < $1.name }
            
            if !groupFilters.isEmpty {
                Divider()
                ForEach(groupFilters) { filter in
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

// MARK: - Group Detail View

struct TVGroupDetailView: View {
    let groupId: String
    let groupName: String

    @StateObject private var viewModel = StashDBViewModel()
    @State private var groupDetail: StashGroup?
    @State private var isLoadingGroup: Bool = false
    @State private var coverSide: CoverSide = .front

    private enum CoverSide: String, CaseIterable {
        case front = "Front"
        case back = "Back"
    }

    private let sceneColumns = [
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40)
    ]

    var body: some View {
        SwiftUI.Group {
            if let group = groupDetail ?? viewModel.groups.first(where: { $0.id == groupId }) {
                renderDetail(item: group)
            } else {
                renderDetail(item: StubGroupDetailItem(id: groupId, name: groupName))
            }
        }
    }

    @ViewBuilder
    private func renderDetail<T: TVDetailItem>(item: T) -> some View {
        TVGenericDetailView(
            item: item,
            isLoading: isLoadingGroup,
            heroAspectRatio: 16/9,
            placeholderSystemImage: "rectangle.stack.fill",
            heroImageOverride: AnyView(groupHeroImage()),
            scenes: viewModel.groupScenes,
            isLoadingScenes: viewModel.isLoadingGroupScenes,
            totalScenes: viewModel.totalGroupScenes,
            hasMoreScenes: viewModel.hasMoreGroupScenes,
            loadMoreScenes: { viewModel.fetchGroupScenes(groupId: groupId, isInitialLoad: false) },
            infoGrid: { _ in
                LazyVGrid(columns: [
                    GridItem(.fixed(240), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ], alignment: .leading, spacing: 12) {
                    if groupDetail != nil {
                        Text("Cover").font(.title3).foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            ForEach(CoverSide.allCases, id: \.self) { side in
                                Button {
                                    coverSide = side
                                } label: {
                                    Text(side.rawValue)
                                        .font(.headline)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                    if viewModel.totalGroupScenes > 0 {
                        Text("Scenes").font(.title3).foregroundStyle(.secondary)
                        Text("\(viewModel.totalGroupScenes)").font(.title3).foregroundColor(.white)
                    }
                }
            },
            additionalContent: { EmptyView() }
        )
        .onAppear {
            if groupDetail == nil && !isLoadingGroup {
                isLoadingGroup = true
                viewModel.fetchGroup(groupId: groupId) { group in
                    self.groupDetail = group
                    self.isLoadingGroup = false
                    // Wenn die gewählte Cover-Seite kein Bild hat, zur anderen wechseln.
                    if coverSide == .back && group?.back_image_path == nil {
                        coverSide = .front
                    } else if coverSide == .front && group?.front_image_path == nil {
                        coverSide = .back
                    }
                }
            }
            viewModel.fetchGroupScenes(groupId: groupId, isInitialLoad: true)
        }
    }

    @ViewBuilder
    private func groupHeroImage() -> some View {
        if let group = groupDetail {
            let url = coverSide == .back ? groupBackImageURL(group) : groupFrontImageURL(group)
            ZStack {
                if let url {
                    CustomAsyncImage(url: url) { loader in
                        if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.12))
                        } else {
                            Color.appBackground
                                .overlay(ProgressView().scaleEffect(1.2))
                        }
                    }
                } else {
                    Color.appBackground
                }
            }
        } else {
            EmptyView()
        }
    }

    private func groupFrontImageURL(_ group: StashGroup) -> URL? {
        if let path = group.front_image_path, let url = URL(string: path) {
            if path.starts(with: "http") { return signedURL(url) }
            guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
            return signedURL(URL(string: config.baseURL + path))
        }
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return signedURL(URL(string: "\(config.baseURL)/group/\(group.id)/frontimage"))
    }

    private func groupBackImageURL(_ group: StashGroup) -> URL? {
        if let path = group.back_image_path, let url = URL(string: path) {
            if path.starts(with: "http") { return signedURL(url) }
            guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
            return signedURL(URL(string: config.baseURL + path))
        }
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        // Stash uses /group/<id>/backimage for the back cover when available.
        return signedURL(URL(string: "\(config.baseURL)/group/\(group.id)/backimage"))
    }
}

private struct StubGroupDetailItem: TVDetailItem {
    let id: String
    let name: String
    let thumbnailURL: URL? = nil
    let sceneCountDisplay: Int = 0
    let details: String? = nil
    let favorite: Bool? = nil
    let rating100: Int? = nil
}
