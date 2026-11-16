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
    // Default-Filter nur einmal pro View-Lebensdauer anwenden — sonst kommt er
    // nach jedem Pop/Tab-Wechsel zurück, obwohl "No Filter" gewählt war.
    @State private var didApplyDefaultFilter = false
    @State private var focusResetToken = 0
    @FocusState private var focusedGroupID: String?

    init() {
        let defaultSort = StashDBViewModel.GroupSortOption(rawValue: TabManager.shared.getSortOption(for: .groups) ?? "") ?? .nameAsc
        _sortBy = State(initialValue: defaultSort)
    }

    private static let sortOrder: [StashDBViewModel.GroupSortOption] = [.random, .nameAsc, .nameDesc, .sceneCountDesc, .sceneCountAsc, .dateDesc, .dateAsc, .ratingDesc, .ratingAsc, .createdAtDesc, .createdAtAsc, .updatedAtDesc, .updatedAtAsc]

    private var sortOptions: [TVPickerOption<StashDBViewModel.GroupSortOption>] {
        Self.sortOrder.map { TVPickerOption($0, label(for: $0)) }
    }

    var body: some View {
        TVCatalogGrid(
            items: viewModel.groups,
            hasValidConfig: hasValidConfig,
            errorMessage: viewModel.errorMessage,
            isLoading: viewModel.isLoadingGroups,
            isLoadingMore: viewModel.isLoadingMoreGroups,
            hasMore: viewModel.hasMoreGroups,
            columnWidth: 260,
            columnCount: 6,
            emptySystemImage: "rectangle.stack",
            emptyTitle: tr("empty_groups_found"),
            loadingText: tr("loading_groups"),
            errorTitle: tr("error_loading_groups"),
            focusResetToken: focusResetToken,
            loadMore: { viewModel.loadMoreGroups() },
            reload: { reload() },
            focusedID: $focusedGroupID,
            header: {
                STVHeaderView(
                    sortMenu: {
                        TVOptionPickerButton(
                            title: tr("action_sort_by"),
                            icon: "arrow.up.arrow.down",
                            options: sortOptions,
                            selection: $sortBy
                        )
                    },
                    filterMenu: {
                        TVFilterPickerButton(filters: savedFilters, selection: $selectedFilter)
                    }
                )
            },
            card: { item in
                TVNavButton(value: TVGroupLink(id: item.id, name: item.name)) {
                    TVGroupCardView(group: item)
                }
            }
        )
        .onChange(of: sortBy) { _, newValue in
            focusResetToken += 1
            viewModel.fetchGroups(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
            focusResetToken += 1
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
            didApplyDefaultFilter = false
            viewModel.fetchGroups(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashServerInitializationFinished)) { _ in
            if hasValidConfig && viewModel.groups.isEmpty {
                viewModel.fetchGroups(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
    }

    private var hasValidConfig: Bool { configManager.activeConfig?.hasValidConfig == true }

    private var savedFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .groups }
            .sorted { $0.name < $1.name }
    }

    private func applyDefaultFilterIfNeeded() {
        guard !didApplyDefaultFilter else { return }
        didApplyDefaultFilter = true
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

    private func label(for option: StashDBViewModel.GroupSortOption) -> String {
        switch option {
        case .nameAsc: return tr("name_z")
        case .nameDesc: return tr("name_z_2")
        case .sceneCountDesc: return tr("most_scenes")
        case .sceneCountAsc: return tr("least_scenes")
        case .galleryCountDesc: return tr("most_galleries")
        case .galleryCountAsc: return tr("least_galleries")
        case .performerCountDesc: return tr("most_performers")
        case .performerCountAsc: return tr("least_performers")
        case .dateDesc: return tr("newest_first")
        case .dateAsc: return tr("oldest_first")
        case .ratingDesc: return tr("highest_rated")
        case .ratingAsc: return tr("lowest_rated")
        case .createdAtDesc: return tr("recently_added")
        case .createdAtAsc: return tr("oldest_added")
        case .updatedAtDesc: return tr("recently_updated")
        case .updatedAtAsc: return tr("least_recently_updated")
        case .random: return tr("random")
        }
    }
}

// MARK: - Group Detail View

struct TVGroupDetailView: View {
    let groupId: String
    let groupName: String

    @StateObject private var viewModel = StashDBViewModel()
    @State private var groupDetail: StashGroup?
    @State private var isLoadingGroup: Bool = false
    // Szenen nur beim ersten Erscheinen laden (Pop zurück behält Seiten/Fokus).
    @State private var didLoadScenes = false
    @State private var coverSide: CoverSide = .front

    private enum CoverSide: String, CaseIterable {
        case front = "Front"
        case back = "Back"
    }

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
            backdrop: .image(backdropURL),
            channel: .group(id: groupId, name: item.name),
            trailingActions: coverActions,
            facts: headerFacts,
            scenes: viewModel.groupScenes,
            isLoadingScenes: viewModel.isLoadingGroupScenes,
            totalScenes: viewModel.totalGroupScenes,
            hasMoreScenes: viewModel.hasMoreGroupScenes,
            loadMoreScenes: { viewModel.loadMoreGroupScenes(groupId: groupId) },
            headerAccessory: { EmptyView() }
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
            if !didLoadScenes {
                didLoadScenes = true
                viewModel.fetchGroupScenes(groupId: groupId, isInitialLoad: true)
            }
        }
    }

    /// The cover shown as backdrop; only a real one (a group without a cover has none).
    private var backdropURL: URL? {
        guard let group = groupDetail else { return nil }
        switch coverSide {
        case .front: return Self.hasImage(group.front_image_path) ? groupFrontImageURL(group) : nil
        case .back: return Self.hasImage(group.back_image_path) ? groupBackImageURL(group) : nil
        }
    }

    private static func hasImage(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        return !path.contains("default=true")
    }

    /// Switches the backdrop between front and back cover; only when the group has both.
    private var coverActions: [TVDetailHeaderAction] {
        guard let group = groupDetail,
              Self.hasImage(group.front_image_path), Self.hasImage(group.back_image_path) else { return [] }
        let showsFront = coverSide == .front
        return [
            TVDetailHeaderAction(
                id: "cover",
                icon: "arrow.left.arrow.right",
                title: showsFront ? tr("back_cover") : tr("front_cover"),
                perform: { coverSide = showsFront ? .back : .front }
            )
        ]
    }

    /// Date and studio (the scene count is in the title line); only those with a value.
    private var headerFacts: [TVDetailFact] {
        guard let group = groupDetail else { return [] }
        var facts: [TVDetailFact] = []
        if let date = group.date, !date.isEmpty {
            facts.append(TVDetailFact(id: "date", label: tr("date"), value: date))
        }
        if let studio = group.studio?.name, !studio.isEmpty {
            facts.append(TVDetailFact(id: "studio", label: tr("studio"), value: studio))
        }
        if let rating = group.rating100 {
            facts.append(TVDetailFact(id: "rating", label: tr("rating"), value: String(format: "%.1f", Double(rating) / 20.0),
                                      icon: "star.fill", iconColor: .yellow))
        }
        if let subGroups = group.sub_group_count, subGroups > 0 {
            facts.append(TVDetailFact(id: "sub_groups", label: tr("sub_groups"), value: "\(subGroups)"))
        }
        return facts
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
