//
//  TVScenesView.swift
//  stashyTV
//
//  Created for tvOS on 08.02.26.
//

import SwiftUI

struct TVScenesView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @State private var sortBy: StashDBViewModel.SceneSortOption
    
    // Support initialization with a specific sort option
    init(sortBy: StashDBViewModel.SceneSortOption = .dateDesc) {
        _sortBy = State(initialValue: sortBy)
    }

    // 3-column grid sized for TV (roughly 350pt wide cards)
    private let columns = [
        GridItem(.adaptive(minimum: 380, maximum: 500), spacing: 48)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Content
            if viewModel.isLoadingScenes && viewModel.scenes.isEmpty {
                Spacer()
                ProgressView("Loading scenes...")
                    .font(.title2)
                Spacer()
            } else if viewModel.scenes.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    Image(systemName: "film")
                        .font(.system(size: 72))
                        .foregroundColor(.secondary)
                    Text("No scenes found")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Button("Load Scenes") {
                        viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true)
                    }
                    .font(.title3)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 48) {
                        ForEach(viewModel.scenes) { scene in
                            NavigationLink(destination: TVSceneDetailView(sceneId: scene.id)) {
                                TVSceneCardView(scene: scene)
                            }
                            .buttonStyle(.card)
                            .onAppear {
                                // Pagination: load more when the last item appears
                                if scene.id == viewModel.scenes.last?.id && viewModel.hasMoreScenes {
                                    viewModel.loadMoreScenes()
                                }
                            }
                        }

                        // Loading more indicator
                        if viewModel.isLoadingMoreScenes {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 40)
                    .padding(.bottom, 80)
                }
            }
        }
        .navigationTitle("Scenes")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort By", selection: $sortBy) {
                        Text("Released").tag(StashDBViewModel.SceneSortOption.dateDesc)
                        Text("Added").tag(StashDBViewModel.SceneSortOption.createdAtDesc)
                        Text("Played").tag(StashDBViewModel.SceneSortOption.lastPlayedAtDesc)
                        Text("Title").tag(StashDBViewModel.SceneSortOption.titleAsc)
                        Text("Rating").tag(StashDBViewModel.SceneSortOption.ratingDesc)
                    }
                } label: {
                    Label("Sort", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .onChange(of: sortBy) { _, newValue in
            viewModel.fetchScenes(sortBy: newValue, isInitialLoad: true)
        }
        .onAppear {
            if viewModel.scenes.isEmpty {
                viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true)
        }
    }
}

