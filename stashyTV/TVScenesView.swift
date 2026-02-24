//
//  TVScenesView.swift
//  stashyTV
//
//  Scenes grid for tvOS — 4-column layout
//

import SwiftUI

struct TVScenesView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @State private var sortBy: StashDBViewModel.SceneSortOption
    
    init(sortBy: StashDBViewModel.SceneSortOption = .dateDesc) {
        _sortBy = State(initialValue: sortBy)
    }

    private var navigationTitle: String {
        switch sortBy {
        case .lastPlayedAtDesc: return "Recently Played"
        case .dateDesc: return "Recently Released"
        case .createdAtDesc: return "Recently Added"
        default: return "Scenes – \(sortBy.displayName)"
        }
    }
    
    private var navigationIcon: String {
        switch sortBy {
        case .lastPlayedAtDesc: return "play.circle.fill"
        case .dateDesc: return "sparkles.tv.fill"
        case .createdAtDesc: return "plus.rectangle.on.folder.fill"
        default: return "film.fill"
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 380, maximum: 420), spacing: 30)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingScenes && viewModel.scenes.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading scenes…")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            } else if viewModel.scenes.isEmpty {
                Spacer()
                VStack(spacing: 24) {
                    Image(systemName: "film")
                        .font(.system(size: 56))
                        .foregroundColor(.white.opacity(0.12))
                    Text("No scenes found")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.4))
                    Button {
                        viewModel.fetchScenes(sortBy: sortBy, isInitialLoad: true)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.title3)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(viewModel.scenes) { scene in
                            VStack(alignment: .leading, spacing: 10) {
                                NavigationLink(destination: TVSceneDetailView(sceneId: scene.id)) {
                                    TVSceneCardView(scene: scene)
                                }
                                .buttonStyle(.card)
                                .onAppear {
                                    if scene.id == viewModel.scenes.last?.id && viewModel.hasMoreScenes {
                                        viewModel.loadMoreScenes()
                                    }
                                }
                                
                                TVSceneCardTitleView(scene: scene)
                            }
                            .frame(width: 400)
                        }

                        if viewModel.isLoadingMoreScenes {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.top, 40)
                    .padding(.bottom, 80)
                }
            }
        }
        .navigationTitle("")
        .background(Color.black)
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
