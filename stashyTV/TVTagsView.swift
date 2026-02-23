//
//  TVTagsView.swift
//  stashyTV
//
//  Tags grid + tag detail for tvOS
//

import SwiftUI

struct TVTagsView: View {
    @StateObject private var viewModel = StashDBViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 30)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingTags && viewModel.tags.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    ProgressView().scaleEffect(1.5)
                    Text("Loading tags…")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            } else if viewModel.tags.isEmpty {
                Spacer()
                VStack(spacing: 24) {
                    Image(systemName: "tag")
                        .font(.system(size: 56))
                        .foregroundColor(.white.opacity(0.12))
                    Text("No Tags Found")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.4))
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
                                if tag.id == viewModel.tags.last?.id && viewModel.hasMoreTags {
                                    viewModel.loadMoreTags()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.top, 40)
                    .padding(.bottom, 80)

                    if viewModel.isLoadingMoreTags {
                        ProgressView()
                            .padding(.vertical, 40)
                    }
                }
            }
        }
        .navigationTitle("")
        .background(Color.black)
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

// MARK: - Tag Detail View

struct TVTagDetailView: View {
    let tagId: String
    let tagName: String

    @StateObject private var viewModel = StashDBViewModel()

    private let sceneColumns = [
        GridItem(.adaptive(minimum: 380, maximum: 420), spacing: 30)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Header
                HStack(spacing: 14) {
                    Image(systemName: "tag.fill")
                        .font(.title2)
                        .foregroundColor(AppearanceManager.shared.tintColor)

                    Text(tagName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    if viewModel.totalTagScenes > 0 {
                        Text("\(viewModel.totalTagScenes) scenes")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.4))
                    }

                    Spacer()
                }
                .padding(.horizontal, 50)
                .padding(.top, 40)

                if viewModel.isLoadingTagScenes && viewModel.tagScenes.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView().scaleEffect(1.5)
                        Spacer()
                    }
                    .padding(.vertical, 80)
                } else if viewModel.tagScenes.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "film")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.12))
                            Text("No scenes found for this tag")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.4))
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
                                if scene.id == viewModel.tagScenes.last?.id && viewModel.hasMoreTagScenes {
                                    viewModel.fetchTagScenes(tagId: tagId, isInitialLoad: false)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 50)
                }
            }
            .padding(.bottom, 80)
        }
        .navigationTitle("")
        .background(Color.black)
        .onAppear {
            viewModel.fetchTagScenes(tagId: tagId, isInitialLoad: true)
        }
    }
}
