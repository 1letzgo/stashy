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
    @State private var focusResetToken = 0
    @FocusState private var focusedTagID: String?

    init() {
        let defaultSort = StashDBViewModel.TagSortOption(rawValue: TabManager.shared.getSortOption(for: .tags) ?? "") ?? .nameAsc
        _sortBy = State(initialValue: defaultSort)
    }

    private static let sortOptions: [TVPickerOption<StashDBViewModel.TagSortOption>] = [
        .init(.random, "Random"),
        .init(.nameAsc, "Name (A-Z)"),
        .init(.nameDesc, "Name (Z-A)"),
        .init(.sceneCountDesc, "Most Scenes"),
        .init(.sceneCountAsc, "Least Scenes"),
        .init(.createdAtDesc, "Recently Added"),
        .init(.createdAtAsc, "Oldest Added"),
        .init(.updatedAtDesc, "Recently Updated"),
        .init(.updatedAtAsc, "Least Recently Updated")
    ]

    var body: some View {
        TVCatalogGrid(
            items: viewModel.tags,
            hasValidConfig: hasValidConfig,
            errorMessage: viewModel.errorMessage,
            isLoading: viewModel.isLoadingTags,
            isLoadingMore: viewModel.isLoadingMoreTags,
            hasMore: viewModel.hasMoreTags,
            columnWidth: 400,
            emptySystemImage: "tag",
            emptyTitle: "No Tags Found",
            loadingText: "Loading tags…",
            errorTitle: "Error loading tags",
            focusResetToken: focusResetToken,
            loadMore: { viewModel.loadMoreTags() },
            reload: { reload() },
            focusedID: $focusedTagID,
            header: {
                STVHeaderView(
                    sortMenu: {
                        TVOptionPickerButton(
                            title: "Sort By",
                            icon: "arrow.up.arrow.down",
                            options: Self.sortOptions,
                            selection: $sortBy
                        )
                    },
                    filterMenu: {
                        TVFilterPickerButton(filters: savedTagFilters, selection: $selectedFilter)
                    },
                    onRefresh: { reload() }
                )
            },
            card: { tag in
                TVNavButton(value: TVTagLink(id: tag.id, name: tag.name)) {
                    TVTagCardView(tag: tag)
                }
            }
        )
        .onChange(of: sortBy) { _, newValue in
            focusResetToken += 1
            viewModel.fetchTags(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
            focusResetToken += 1
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

    private var savedTagFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .tags }
            .sorted { $0.name < $1.name }
    }

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
            channel: .tag(id: tagId, name: loadedTag?.name ?? tagName),
            scenes: viewModel.tagScenes,
            isLoadingScenes: viewModel.isLoadingTagScenes,
            totalScenes: viewModel.totalTagScenes,
            hasMoreScenes: viewModel.hasMoreTagScenes,
            loadMoreScenes: { viewModel.loadMoreTagScenes(tagId: tagId) },
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
