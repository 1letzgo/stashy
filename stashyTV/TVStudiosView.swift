//
//  TVStudiosView.swift
//  stashyTV
//
//  Studios grid for tvOS
//

import SwiftUI

struct TVStudiosView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @State private var sortBy: StashDBViewModel.StudioSortOption = .nameAsc
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @FocusState private var focusedStudioID: String?

    private let columns = [
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingStudios && viewModel.studios.isEmpty {
                loadingView
            } else if viewModel.studios.isEmpty {
                emptyView
            } else {
                contentGrid
            }
        }
        .background(Color.appBackground)
        .onChange(of: viewModel.studios.first?.id) { oldID, newID in
            if oldID != newID {
                focusedStudioID = newID
            }
        }
        .onChange(of: sortBy) { _, newValue in
            viewModel.fetchStudios(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
            viewModel.fetchStudios(sortBy: sortBy, isInitialLoad: true, filter: newValue)
        }
        .onAppear {
            viewModel.fetchSavedFilters()
            if viewModel.studios.isEmpty {
                viewModel.fetchStudios(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            viewModel.fetchStudios(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
    }


    private func sortButton(option: StashDBViewModel.StudioSortOption) -> some View {
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

    private func label(for option: StashDBViewModel.StudioSortOption) -> String {
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
            Text("Loading studios…")
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
            Image(systemName: "building.2")
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.1))
            
            Text("No Studios Found")
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
                    ForEach(viewModel.studios) { studio in
                        NavigationLink(value: TVStudioLink(id: studio.id, name: studio.name)) {
                            TVStudioCardView(studio: studio)
                        }
                        .buttonStyle(.card)
                        .focused($focusedStudioID, equals: studio.id)
                        .frame(width: 410) // Fixed width for item container
                        .onAppear {
                            if studio.id == viewModel.studios.last?.id && viewModel.hasMoreStudios {
                                viewModel.loadMoreStudios()
                            }
                        }
                    }

                    if viewModel.isLoadingMoreStudios {
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
            
            let studioFilters = viewModel.savedFilters.values
                .filter { $0.mode == .studios }
                .sorted { $0.name < $1.name }
            
            if !studioFilters.isEmpty {
                Divider()
                ForEach(studioFilters) { filter in
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
