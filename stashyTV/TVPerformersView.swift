//
//  TVPerformersView.swift
//  stashyTV
//
//  Performers grid for tvOS
//

import SwiftUI

struct TVPerformersView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @State private var sortBy: StashDBViewModel.PerformerSortOption = .nameAsc
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @FocusState private var focusedPerformerID: String?

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
            if viewModel.isLoadingPerformers && viewModel.performers.isEmpty {
                loadingView
            } else if viewModel.performers.isEmpty {
                emptyView
            } else {
                contentGrid
            }
        }
        .background(Color.appBackground)
        .onChange(of: viewModel.performers.first?.id) { oldID, newID in
            if oldID != newID {
                focusedPerformerID = newID
            }
        }
        .onChange(of: sortBy) { _, newValue in
            viewModel.fetchPerformers(sortBy: newValue, isInitialLoad: true, filter: selectedFilter)
        }
        .onChange(of: selectedFilter) { _, newValue in
            viewModel.fetchPerformers(sortBy: sortBy, isInitialLoad: true, filter: newValue)
        }
        .onAppear {
            viewModel.fetchSavedFilters()
            if viewModel.performers.isEmpty {
                viewModel.fetchPerformers(sortBy: sortBy, isInitialLoad: true, filter: selectedFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            viewModel.fetchPerformers(sortBy: sortBy, isInitialLoad: true, filter: nil)
        }
    }


    private func sortButton(option: StashDBViewModel.PerformerSortOption) -> some View {
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

    private func label(for option: StashDBViewModel.PerformerSortOption) -> String {
        switch option {
        case .nameAsc: return "Name (A-Z)"
        case .nameDesc: return "Name (Z-A)"
        case .sceneCountDesc: return "Most Scenes"
        case .createdAtDesc: return "Recently Added"
        case .updatedAtDesc: return "Recently Updated"
        case .birthdateDesc: return "Birthday"
        case .random: return "Random"
        default: return option.displayName
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        Spacer()
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5)
            Text("Loading performers…")
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
            Image(systemName: "person.3")
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.1))
            
            Text("No Performers Found")
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
                    ForEach(viewModel.performers) { performer in
                        NavigationLink(value: TVPerformerLink(id: performer.id, name: performer.name)) {
                            TVPerformerCardView(performer: performer)
                        }
                        .buttonStyle(.card)
                        .focused($focusedPerformerID, equals: performer.id)
                        .frame(width: 260) // Fixed width for item container
                        .onAppear {
                            if performer.id == viewModel.performers.last?.id && viewModel.hasMorePerformers {
                                viewModel.loadMorePerformers()
                            }
                        }
                    }

                    if viewModel.isLoadingMorePerformers {
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
                sortButton(option: .birthdateDesc)
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
            
            let performerFilters = viewModel.savedFilters.values
                .filter { $0.mode == .performers }
                .sorted { $0.name < $1.name }
            
            if !performerFilters.isEmpty {
                Divider()
                ForEach(performerFilters) { filter in
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
