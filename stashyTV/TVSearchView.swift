//
//  TVSearchView.swift
//  stashyTV
//
//  Created for stashy tvOS.
//

import SwiftUI

@MainActor
struct TVSearchView: View {
    @StateObject private var viewModel = StashDBViewModel()

    @State private var searchQuery: String = ""
    @State private var hasSearched: Bool = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
                // Search Field
                HStack(spacing: 20) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    TextField("Search scenes, performers...", text: $searchQuery)
                        .focused($isSearchFieldFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            performSearch()
                        }

                    if !searchQuery.isEmpty {
                        Button("Clear") {
                            searchQuery = ""
                            viewModel.clearSearchResults()
                            hasSearched = false
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.top, 20)

                // Results
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Searching...")
                            .font(.title3)
                        Spacer()
                    }
                    .padding(.top, 60)
                } else if hasSearched && viewModel.scenes.isEmpty && viewModel.performers.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundStyle(.tertiary)
                            Text("No results found for \"\(searchQuery)\"")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.top, 60)
                } else if hasSearched {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 50) {
                            // Scenes Results
                            if !viewModel.scenes.isEmpty {
                                scenesResultSection
                            }

                            // Performers Results
                            if !viewModel.performers.isEmpty {
                                performersResultSection
                            }
                        }
                        .padding(.vertical, 60)
                    }
                } else {
                    // Empty state
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundStyle(.tertiary)
                            Text("Search your Stash library")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("Type a query and press Return to search.")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.top, 80)
                }

                Spacer()
            }
            .navigationTitle("Search")
            .onAppear {
                isSearchFieldFocused = true
            }
        }

    // MARK: - Search

    private func performSearch() {
        guard !searchQuery.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty else { return }
        hasSearched = true
        viewModel.fetchScenes(sortBy: StashDBViewModel.SceneSortOption.dateDesc, searchQuery: searchQuery)
        viewModel.fetchPerformers(sortBy: StashDBViewModel.PerformerSortOption.nameAsc, searchQuery: searchQuery)
    }

    // MARK: - Scenes Results

    private var scenesResultSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Scenes")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("(\(viewModel.scenes.count))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 60) // Align title with content

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 40) {
                    ForEach(viewModel.scenes) { scene in
                        NavigationLink(destination: TVSceneDetailView(sceneId: scene.id)) {
                            TVSceneCardView(scene: scene)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 60) // Add padding inside ScrollView
                .padding(.vertical, 30)   // Increased padding for focus expansion
            }
        }
    }

    // MARK: - Performers Results

    private var performersResultSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Performers")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("(\(viewModel.performers.count))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 60) // Align title with content

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 40) {
                    ForEach(viewModel.performers) { performer in
                        NavigationLink(destination: TVPerformerDetailView(performerId: performer.id, performerName: performer.name)) {
                            TVPerformerCardView(performer: performer)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 60) // Add padding inside ScrollView
                .padding(.vertical, 30)   // Increased padding for focus expansion
            }
        }
    }
}

// MARK: - Previews

#Preview {
    TVSearchView()
}
