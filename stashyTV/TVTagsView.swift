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
    // Default-Filter nur einmal pro View-Lebensdauer anwenden — sonst kommt er
    // nach jedem Pop/Tab-Wechsel zurück, obwohl "No Filter" gewählt war.
    @State private var didApplyDefaultFilter = false
    @State private var focusResetToken = 0
    @FocusState private var focusedTagID: String?

    init() {
        let defaultSort = StashDBViewModel.TagSortOption(rawValue: TabManager.shared.getSortOption(for: .tags) ?? "") ?? .nameAsc
        _sortBy = State(initialValue: defaultSort)
    }

    private static var sortOptions: [TVPickerOption<StashDBViewModel.TagSortOption>] {
[
        .init(.random, tr("random")),
        .init(.nameAsc, tr("name_z")),
        .init(.nameDesc, tr("name_z_2")),
        .init(.sceneCountDesc, tr("most_scenes")),
        .init(.sceneCountAsc, tr("least_scenes")),
        .init(.createdAtDesc, tr("recently_added")),
        .init(.createdAtAsc, tr("oldest_added")),
        .init(.updatedAtDesc, tr("recently_updated")),
        .init(.updatedAtAsc, tr("least_recently_updated"))
    ]
    }

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
            emptyTitle: tr("empty_tags_found"),
            loadingText: tr("loading_tags"),
            errorTitle: tr("error_loading_tags"),
            focusResetToken: focusResetToken,
            loadMore: { viewModel.loadMoreTags() },
            reload: { reload() },
            focusedID: $focusedTagID,
            header: {
                STVHeaderView(
                    sortMenu: {
                        TVOptionPickerButton(
                            title: tr("action_sort_by"),
                            icon: "arrow.up.arrow.down",
                            options: Self.sortOptions,
                            selection: $sortBy
                        )
                    },
                    filterMenu: {
                        TVFilterPickerButton(filters: savedTagFilters, selection: $selectedFilter)
                    }
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
            didApplyDefaultFilter = false
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
        guard !didApplyDefaultFilter else { return }
        didApplyDefaultFilter = true
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
    // Szenen nur beim ersten Erscheinen laden (Pop zurück behält Seiten/Fokus).
    @State private var didLoadScenes = false

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
            backdrop: .image(backdropURL),
            channel: .tag(id: tagId, name: loadedTag?.name ?? tagName),
            facts: headerFacts,
            scenes: viewModel.tagScenes,
            isLoadingScenes: viewModel.isLoadingTagScenes,
            totalScenes: viewModel.totalTagScenes,
            hasMoreScenes: viewModel.hasMoreTagScenes,
            loadMoreScenes: { viewModel.loadMoreTagScenes(tagId: tagId) },
            headerAccessory: { EmptyView() }
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
            if !didLoadScenes {
                didLoadScenes = true
                viewModel.fetchTagScenes(tagId: tagId, isInitialLoad: true)
            }
        }
    }
}

extension TVTagDetailView {
    /// The tag's own image as backdrop; none for Stash's default tag image.
    fileprivate var backdropURL: URL? {
        guard let tag = loadedTag, let path = tag.imagePath, !path.isEmpty,
              !path.contains("default=true") else { return nil }
        return tag.thumbnailURL
    }

    /// The tag's other counts (the scene count is in the title line), only those above 0, and its aliases.
    fileprivate var headerFacts: [TVDetailFact] {
        guard let tag = loadedTag else { return [] }
        let counts: [(id: String, label: String, value: Int?)] = [
            ("performers", tr("performers"), tag.performerCount),
            ("markers", tr("markers"), tag.sceneMarkerCount),
            ("galleries", tr("galleries"), tag.galleryCount),
            ("images", tr("images"), tag.imageCount)
        ]
        var facts: [TVDetailFact] = counts.compactMap { entry in
            guard let value = entry.value, value > 0 else { return nil }
            return TVDetailFact(id: entry.id, label: entry.label, value: "\(value)")
        }
        let aliases = (tag.aliases ?? []).filter { !$0.isEmpty }
        if !aliases.isEmpty {
            facts.append(TVDetailFact(id: "aliases", label: tr("aliases"), value: aliases.joined(separator: ", ")))
        }
        return facts
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
