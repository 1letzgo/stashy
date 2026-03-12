//
//  TVSearchView.swift
//  stashyTV
//
//  Search for tvOS — Netflix style
//

import SwiftUI

@MainActor
struct TVSearchView: View {
    @StateObject private var viewModel = StashDBViewModel()

    @State private var searchQuery: String = ""
    @State private var hasSearched: Bool = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 50) {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            ProgressView().scaleEffect(1.5)
                            Text("Searching…")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.4))
                        }
                        Spacer()
                    }
                    .padding(.top, 80)
                } else if hasSearched && viewModel.scenes.isEmpty && viewModel.performers.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 20) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 56))
                                .foregroundColor(.white.opacity(0.12))
                            Text("No results for \"\(searchQuery)\"")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.4))
                        }
                        Spacer()
                    }
                    .padding(.top, 80)
                } else if hasSearched {
                    if !viewModel.scenes.isEmpty {
                        scenesResultSection
                    }
                    if !viewModel.performers.isEmpty {
                        performersResultSection
                    }
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 56))
                                .foregroundColor(.white.opacity(0.12))
                            Text("Search your Stash library")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.4))
                            Text("Use the remote to type or dictate your search.")
                                .font(.callout)
                                .foregroundColor(.white.opacity(0.25))
                        }
                        Spacer()
                    }
                    .padding(.top, 100)
                }
            }
            .padding(.vertical, 60)
        }
        .background(Color.appBackground)
        .searchable(text: $searchQuery, placement: .automatic, prompt: "Search scenes, performers…")
        .onChange(of: searchQuery) { _, newValue in
            let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.count < 2 {
                viewModel.clearSearchResults()
                hasSearched = false
            } else {
                performSearch()
            }
        }
        .onSubmit(of: .search) {
            performSearch()
        }
    }

    // MARK: - Search

    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            viewModel.clearSearchResults()
            hasSearched = false
            return
        }
        hasSearched = true
        viewModel.fetchScenes(sortBy: StashDBViewModel.SceneSortOption.dateDesc, searchQuery: query)
        viewModel.fetchPerformers(sortBy: StashDBViewModel.PerformerSortOption.nameAsc, searchQuery: query)
    }

    // MARK: - Scenes Results

    private var scenesResultSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "film.fill")
                    .font(.title3)
                    .foregroundColor(AppearanceManager.shared.tintColor)
                Text("Scenes")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("\(viewModel.scenes.count)")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(viewModel.scenes) { scene in
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink(value: TVSceneLink(sceneId: scene.id)) {
                                TVSceneCardView(scene: scene)
                            }
                            .buttonStyle(.card)
                            
                            TVSceneCardTitleView(scene: scene)
                        }
                        .frame(width: 400)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Performers Results

    private var performersResultSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundColor(AppearanceManager.shared.tintColor)
                Text("Performers")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("\(viewModel.performers.count)")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(viewModel.performers) { performer in
                        NavigationLink(value: TVPerformerLink(id: performer.id, name: performer.name)) {
                            TVPerformerCardView(performer: performer)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }
}
