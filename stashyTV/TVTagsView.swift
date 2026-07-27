//
//  TVTagsView.swift
//  stashyTV
//
//  Tags grid + tag detail for tvOS
//

import SwiftUI

struct TVTagsView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @State private var sortBy: StashDBViewModel.TagSortOption
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @FocusState private var focusedTagID: String?

    init() {
        let defaultSort = StashDBViewModel.TagSortOption(rawValue: TabManager.shared.getSortOption(for: .tags) ?? "") ?? .nameAsc
        _sortBy = State(initialValue: defaultSort)
    }

    private let columns = [
        GridItem(.fixed(400), spacing: 40),
        GridItem(.fixed(400), spacing: 40),
        GridItem(.fixed(400), spacing: 40),
        GridItem(.fixed(400), spacing: 40)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !hasValidConfig {
                TVConnectionErrorView(title: "Server not reachable", subtitle: "Add a server in Settings.") { reload() }
            } else if viewModel.tags.isEmpty && (viewModel.errorMessage?.isEmpty == false) {
                TVConnectionErrorView(title: "Error loading tags", subtitle: viewModel.errorMessage) { reload() }
            } else if viewModel.isLoadingTags && viewModel.tags.isEmpty {
                loadingView
            } else if viewModel.tags.isEmpty {
                emptyView
            } else {
                contentGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .onChange(of: viewModel.tags.first?.id) { oldID, newID in
            if oldID != newID, let newID {
                focusedTagID = newID
            }
        }
        .onChange(of: sortBy) { _, newValue in
            viewModel.fetchTags(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
            viewModel.fetchTags(sortBy: sortBy, isInitialLoad: true, filter: newValue)
        }
        .onAppear {
            guard hasValidConfig else { return }
            viewModel.fetchSavedFilters { _ in
                applyDefaultFilterIfNeeded()
            }
            if viewModel.tags.isEmpty {
                viewModel.fetchTags(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            viewModel.fetchTags(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashServerInitializationFinished)) { _ in
            if hasValidConfig && viewModel.tags.isEmpty {
                viewModel.fetchTags(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
    }

    private var hasValidConfig: Bool { configManager.activeConfig?.hasValidConfig == true }

    private func applyDefaultFilterIfNeeded() {
        guard selectedFilter == nil,
              let filterId = tabManager.getDefaultFilterId(for: .tags),
              let filter = viewModel.savedFilters[filterId] else { return }
        selectedFilter = filter
    }

    private func reload() {
        guard hasValidConfig else { return }
        viewModel.testConnection()
        viewModel.fetchTags(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
    }


    private func sortButton(option: StashDBViewModel.TagSortOption) -> some View {
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

    private func label(for option: StashDBViewModel.TagSortOption) -> String {
        switch option {
        case .nameAsc: return "Name (A-Z)"
        case .nameDesc: return "Name (Z-A)"
        case .sceneCountDesc: return "Most Scenes"
        case .sceneCountAsc: return "Least Scenes"
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
            Text("Loading tags…")
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
            Image(systemName: "tag")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("No Tags Found")
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
                    ForEach(viewModel.tags) { tag in
                        NavigationLink(destination: TVTagDetailView(tagId: tag.id, tagName: tag.name).tvExitDismissable()) {
                            TVTagCardView(tag: tag)
                        }
                        .buttonStyle(.card)
                        .focused($focusedTagID, equals: tag.id)
                        .frame(width: 400) // Fixed width for item container
                        .onAppear {
                            if tag.id == viewModel.tags.last?.id && viewModel.hasMoreTags {
                                viewModel.loadMoreTags()
                            }
                        }
                    }

                    if viewModel.isLoadingMoreTags {
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
            
            let tagFilters = viewModel.savedFilters.values
                .filter { $0.mode == .tags }
                .sorted { $0.name < $1.name }
            
            if !tagFilters.isEmpty {
                Divider()
                ForEach(tagFilters) { filter in
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

// MARK: - Tag Detail View

struct TVTagDetailView: View {
    let tagId: String
    let tagName: String

    @StateObject private var viewModel = StashDBViewModel()
    @State private var loadedTag: Tag?
    @State private var isLoadingTag: Bool = false

    private let sceneColumns = [
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40)
    ]

    var body: some View {
        Group {
            if let tag = loadedTag {
                renderDetail(item: tag)
            } else {
                renderDetail(item: StubTagDetailItem(id: tagId, name: tagName))
            }
        }
    }

    @ViewBuilder
    private func renderDetail<T: TVDetailItem>(item: T) -> some View {
        TVGenericDetailView(
            item: item,
            isLoading: isLoadingTag,
            heroAspectRatio: 16/9,
            placeholderSystemImage: "tag.fill",
            scenes: viewModel.tagScenes,
            isLoadingScenes: viewModel.isLoadingTagScenes,
            totalScenes: viewModel.totalTagScenes,
            hasMoreScenes: viewModel.hasMoreTagScenes,
            loadMoreScenes: { viewModel.fetchTagScenes(tagId: tagId, isInitialLoad: false) },
            infoGrid: { _ in
                LazyVGrid(columns: [
                    GridItem(.fixed(240), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ], alignment: .leading, spacing: 12) {
                    if viewModel.totalTagScenes > 0 {
                        Text("Scenes").font(.title3).foregroundStyle(.secondary)
                        Text("\(viewModel.totalTagScenes)").font(.title3).foregroundColor(.white)
                    }
                }
            },
            additionalContent: { EmptyView() }
        )
        .onAppear {
            if loadedTag == nil && !isLoadingTag {
                isLoadingTag = true
                viewModel.fetchTag(tagId: tagId) { fetched in
                    DispatchQueue.main.async {
                        self.loadedTag = fetched
                        self.isLoadingTag = false
                    }
                }
            }
            viewModel.fetchTagScenes(tagId: tagId, isInitialLoad: true)
        }
    }
}

private struct StubTagDetailItem: TVDetailItem {
    let id: String
    let name: String
    let thumbnailURL: URL? = nil
    let sceneCountDisplay: Int = 0
    let details: String? = nil
    let favorite: Bool? = nil
    let rating100: Int? = nil
}
