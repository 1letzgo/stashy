//
//  TVStudioDetailView.swift
//  stashyTV
//
//  Created for tvOS on 08.02.26.
//

import SwiftUI

struct TVStudioDetailView: View {
    let studioId: String
    let studioName: String

    @StateObject private var viewModel = StashDBViewModel()
    @State private var studio: Studio?
    @State private var isLoadingStudio = true

    private let sceneColumns = Array(
        repeating: GridItem(.adaptive(minimum: 380, maximum: 400), spacing: 40),
        count: 4
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Header section
                HStack(alignment: .top, spacing: 60) {
                    // Studio image/logo
                    CustomAsyncImage(url: studio?.thumbnailURL) { loader in
                        if loader.isLoading {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .overlay(ProgressView())
                        } else if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFit()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .overlay(
                                    Image(systemName: "building.2.fill")
                                        .font(.system(size: 72))
                                        .foregroundColor(.secondary)
                                )
                        }
                    }
                    .frame(width: 400, height: 225)
                    .background(Color.gray.opacity(0.1))
                    .clipped()
                    .cornerRadius(16)

                    // Info section
                    VStack(alignment: .leading, spacing: 20) {
                        Text(studioName)
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        if isLoadingStudio {
                            ProgressView("Loading details...")
                                .font(.title3)
                        } else if let studio = studio {
                            studioInfoSection(studio: studio)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 60)
                .padding(.top, 40)

                // Scenes section
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Scenes")
                            .font(.title2)
                            .fontWeight(.bold)

                        if viewModel.totalStudioScenes > 0 {
                            Text("(\(viewModel.totalStudioScenes))")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 60)

                    if viewModel.isLoadingStudioScenes && viewModel.studioScenes.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Loading scenes...")
                                .font(.title3)
                            Spacer()
                        }
                        .padding(.vertical, 60)
                    } else if viewModel.studioScenes.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                Image(systemName: "film")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("No scenes found")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 60)
                    } else {
                        LazyVGrid(columns: sceneColumns, spacing: 40) {
                            ForEach(viewModel.studioScenes) { scene in
                                NavigationLink(destination: TVSceneDetailView(sceneId: scene.id)) {
                                    TVSceneCardView(scene: scene)
                                }
                                .buttonStyle(.card)
                                .onAppear {
                                    // Pagination
                                    if scene.id == viewModel.studioScenes.last?.id && viewModel.hasMoreStudioScenes {
                                        viewModel.fetchStudioScenes(studioId: studioId, isInitialLoad: false)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 60)
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .navigationTitle(studioName)
        .onAppear {
            loadStudioData()
        }
    }

    // MARK: - Studio Info Section

    @ViewBuilder
    private func studioInfoSection(studio: Studio) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Details / description
            if let details = studio.details, !details.isEmpty {
                Text(details)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(6)
                    .padding(.bottom, 4)
            }

            Divider()

            LazyVGrid(columns: [
                GridItem(.fixed(200), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], alignment: .leading, spacing: 14) {
                Text("Scenes")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("\(studio.sceneCount)")
                    .font(.title3)

                if let performerCount = studio.performerCount, performerCount > 0 {
                    Text("Performers")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("\(performerCount)")
                        .font(.title3)
                }

                if let galleryCount = studio.galleryCount, galleryCount > 0 {
                    Text("Galleries")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("\(galleryCount)")
                        .font(.title3)
                }

                if let rating = studio.rating100 {
                    Text("Rating")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", Double(rating) / 20.0))
                            .font(.title3)
                    }
                }

                if studio.favorite == true {
                    Text("Favorite")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }

                if let url = studio.url, !url.isEmpty {
                    Text("URL")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text(url)
                        .font(.callout)
                        .foregroundColor(AppearanceManager.shared.tintColor)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadStudioData() {
        // Fetch full studio details
        viewModel.fetchStudio(studioId: studioId) { fetchedStudio in
            self.studio = fetchedStudio
            self.isLoadingStudio = false
        }

        // Fetch studio's scenes
        viewModel.fetchStudioScenes(studioId: studioId, isInitialLoad: true)
    }
}

#Preview {
    NavigationStack {
        TVStudioDetailView(studioId: "1", studioName: "Example Studio")
    }
}
