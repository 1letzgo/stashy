//
//  TVGroupsView.swift
//  stashyTV
//
//  Groups and Group Detail views for tvOS — Netflix style
//

import SwiftUI

struct TVGroupsView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @State private var sortBy: StashDBViewModel.GroupSortOption = .nameAsc
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @FocusState private var focusedGroupID: String?

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
            if viewModel.isLoadingGroups && viewModel.groups.isEmpty {
                loadingView
            } else if viewModel.groups.isEmpty {
                emptyView
            } else {
                contentGrid
            }
        }
        .navigationTitle("")
        .background(Color.black)
        .onChange(of: viewModel.groups.first?.id) { oldID, newID in
            if oldID != newID {
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
            viewModel.fetchSavedFilters()
            if viewModel.groups.isEmpty {
                viewModel.fetchGroups(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            viewModel.fetchGroups(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
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
        case .createdAtDesc: return "Recently Added"
        case .updatedAtDesc: return "Recently Updated"
        case .random: return "Random"
        default: return option.displayName
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        Spacer()
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5)
            Text("Loading groups…")
                .font(.title3)
                .foregroundColor(.white.opacity(0.4))
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
                .foregroundColor(.white.opacity(0.1))
            
            Text("No Groups Found")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.3))
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
                        NavigationLink(value: TVGroupLink(id: group.id, name: group.name)) {
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
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            Section("Sort By") {
                sortButton(option: .nameAsc)
                sortButton(option: .nameDesc)
                sortButton(option: .sceneCountDesc)
                sortButton(option: .createdAtDesc)
                sortButton(option: .updatedAtDesc)
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

    private let sceneColumns = [
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40)
    ]

    var body: some View {
        SwiftUI.Group {
            if let group = viewModel.groups.first(where: { $0.id == groupId }) {
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
            isLoading: viewModel.isLoadingGroups && viewModel.groups.isEmpty,
            heroAspectRatio: 16/9,
            placeholderSystemImage: "rectangle.stack.fill",
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
                    if viewModel.totalGroupScenes > 0 {
                        Text("Scenes").font(.title3).foregroundColor(.white.opacity(0.4))
                        Text("\(viewModel.totalGroupScenes)").font(.title3).foregroundColor(.white)
                    }
                }
            },
            additionalContent: { EmptyView() }
        )
        .onAppear {
            viewModel.fetchGroupScenes(groupId: groupId, isInitialLoad: true)
        }
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
