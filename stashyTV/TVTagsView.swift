//
//  TVTagsView.swift
//  stashyTV
//
//  Tags grid + tag detail for tvOS
//

import SwiftUI

struct TVTagsView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @State private var sortBy: StashDBViewModel.TagSortOption = .nameAsc
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @FocusState private var focusedTagID: String?

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
            if viewModel.isLoadingTags && viewModel.tags.isEmpty {
                loadingView
            } else if viewModel.tags.isEmpty {
                emptyView
            } else {
                contentGrid
            }
        }
        .background(Color.appBackground)
        .onChange(of: viewModel.tags.first?.id) { oldID, newID in
            if oldID != newID {
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
            viewModel.fetchSavedFilters()
            if viewModel.tags.isEmpty {
                viewModel.fetchTags(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            viewModel.fetchTags(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
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
            Text("Loading tags…")
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
            Image(systemName: "tag")
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.1))
            
            Text("No Tags Found")
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
                    ForEach(viewModel.tags) { tag in
                        NavigationLink(value: TVTagLink(id: tag.id, name: tag.name)) {
                            TVTagCardView(tag: tag)
                        }
                        .buttonStyle(.card)
                        .focused($focusedTagID, equals: tag.id)
                        .frame(width: 260) // Fixed width for item container
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

    private var tagColor: Color {
        let hash = abs(tagName.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.35, brightness: 0.3)
    }

    private let sceneColumns = [
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40)
    ]

    var body: some View {
        Group {
            if let tag = viewModel.tags.first(where: { $0.id == tagId }) {
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
            isLoading: viewModel.isLoadingTags && viewModel.tags.isEmpty,
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
                        Text("Scenes").font(.title3).foregroundColor(.white.opacity(0.4))
                        Text("\(viewModel.totalTagScenes)").font(.title3).foregroundColor(.white)
                    }
                }
            },
            additionalContent: { EmptyView() }
        )
        .onAppear {
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
