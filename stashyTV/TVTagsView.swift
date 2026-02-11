//
//  TVTagsView.swift
//  stashyTV
//
//  Created for tvOS on 08.02.26.
//

import SwiftUI

struct TVTagsView: View {
    @StateObject private var viewModel = StashDBViewModel()

    private let columns = Array(
        repeating: GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 36),
        count: 6
    )

    var body: some View {
        VStack(spacing: 0) {
                // Content
                if viewModel.isLoadingTags && viewModel.tags.isEmpty {
                    Spacer()
                    ProgressView("Loading tags...")
                        .font(.title2)
                    Spacer()
                } else if viewModel.tags.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "tag")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        Text("No Tags Found")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 36) {
                            ForEach(viewModel.tags) { tag in
                                NavigationLink(destination: TVTagDetailView(tagId: tag.id, tagName: tag.name)) {
                                    TVTagCardView(tag: tag)
                                }
                                .buttonStyle(.card)
                                .onAppear {
                                    // Pagination: load more when last item appears
                                    if tag.id == viewModel.tags.last?.id && viewModel.hasMoreTags {
                                        viewModel.loadMoreTags()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.top, 30)
                        .padding(.bottom, 60)

                        // Loading more indicator
                        if viewModel.isLoadingMoreTags {
                            ProgressView()
                                .padding(.vertical, 40)
                        }
                    }
                }
            }
            .onAppear {
                if viewModel.tags.isEmpty {
                    viewModel.fetchTags(sortBy: .nameAsc, isInitialLoad: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
                viewModel.fetchTags(sortBy: .nameAsc, isInitialLoad: true)
        }
    }
}

#Preview {
    TVTagsView()
}

// MARK: - Tag Detail View

struct TVTagDetailView: View {
    let tagId: String
    let tagName: String

    @StateObject private var viewModel = StashDBViewModel()

    private let sceneColumns = Array(
        repeating: GridItem(.adaptive(minimum: 380, maximum: 400), spacing: 40),
        count: 4
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Tag header
                HStack(spacing: 16) {
                    Image(systemName: "tag.fill")
                        .font(.title)
                        .foregroundColor(AppearanceManager.shared.tintColor)

                    Text(tagName)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    if viewModel.totalTagScenes > 0 {
                        Text("\(viewModel.totalTagScenes) scenes")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 60)
                .padding(.top, 40)

                // Scenes grid
                if viewModel.isLoadingTagScenes && viewModel.tagScenes.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Loading scenes...")
                            .font(.title3)
                        Spacer()
                    }
                    .padding(.vertical, 80)
                } else if viewModel.tagScenes.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "film")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No scenes found for this tag")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 80)
                } else {
                    LazyVGrid(columns: sceneColumns, spacing: 40) {
                        ForEach(viewModel.tagScenes) { scene in
                            NavigationLink(destination: TVSceneDetailView(sceneId: scene.id)) {
                                TVSceneCardView(scene: scene)
                            }
                            .buttonStyle(.card)
                            .onAppear {
                                // Pagination
                                if scene.id == viewModel.tagScenes.last?.id && viewModel.hasMoreTagScenes {
                                    viewModel.fetchTagScenes(tagId: tagId, isInitialLoad: false)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                }
            }
            .padding(.bottom, 60)
        }
        .navigationTitle(tagName)
        .onAppear {
            viewModel.fetchTagScenes(tagId: tagId, isInitialLoad: true)
        }
    }
}

#Preview {
    TVTagsView()
}
