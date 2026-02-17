//
//  TVStudioDetailView.swift
//  stashyTV
//
//  Studio detail for tvOS — Netflix/Prime style
//

import SwiftUI

struct TVStudioDetailView: View {
    let studioId: String
    let studioName: String

    @StateObject private var viewModel = StashDBViewModel()
    @State private var studio: Studio?
    @State private var isLoadingStudio = true

    private let sceneColumns = [
        GridItem(.adaptive(minimum: 380, maximum: 420), spacing: 30)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Header
                HStack(alignment: .top, spacing: 50) {
                    // Studio thumbnail
                    CustomAsyncImage(url: studio?.thumbnailURL) { loader in
                        if loader.isLoading {
                            Rectangle()
                                .fill(Color.gray.opacity(0.08))
                                .overlay(ProgressView())
                        } else if let image = loader.image {
                            image.resizable().scaledToFit()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.08))
                                .overlay(
                                    Image(systemName: "building.2.fill")
                                        .font(.system(size: 56))
                                        .foregroundColor(.white.opacity(0.12))
                                )
                        }
                    }
                    .frame(width: 400, height: 225)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Info
                    VStack(alignment: .leading, spacing: 16) {
                        Text(studioName)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if isLoadingStudio {
                            ProgressView()
                                .scaleEffect(1.2)
                        } else if let studio = studio {
                            studioInfoSection(studio: studio)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 50)
                .padding(.top, 40)

                // Scenes
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "film.fill")
                            .font(.title3)
                            .foregroundColor(AppearanceManager.shared.tintColor)
                        Text("Scenes")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if viewModel.totalStudioScenes > 0 {
                            Text("\(viewModel.totalStudioScenes)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 50)

                    if viewModel.isLoadingStudioScenes && viewModel.studioScenes.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().scaleEffect(1.5)
                            Spacer()
                        }
                        .padding(.vertical, 60)
                    } else if viewModel.studioScenes.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 16) {
                                Image(systemName: "film")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white.opacity(0.12))
                                Text("No scenes found")
                                    .font(.title3)
                                    .foregroundColor(.white.opacity(0.4))
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
                                    if scene.id == viewModel.studioScenes.last?.id && viewModel.hasMoreStudioScenes {
                                        viewModel.fetchStudioScenes(studioId: studioId, isInitialLoad: false)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 50)
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .navigationTitle(studioName)
        .background(Color.black)
        .onAppear {
            loadStudioData()
        }
    }

    // MARK: - Studio Info

    @ViewBuilder
    private func studioInfoSection(studio: Studio) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let details = studio.details, !details.isEmpty {
                Text(details)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(6)
            }

            Divider()
                .background(Color.white.opacity(0.1))

            LazyVGrid(columns: [
                GridItem(.fixed(180), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], alignment: .leading, spacing: 12) {
                Text("Scenes").font(.title3).foregroundColor(.white.opacity(0.4))
                Text("\(studio.sceneCount)").font(.title3).foregroundColor(.white)

                if let performerCount = studio.performerCount, performerCount > 0 {
                    Text("Performers").font(.title3).foregroundColor(.white.opacity(0.4))
                    Text("\(performerCount)").font(.title3).foregroundColor(.white)
                }

                if let galleryCount = studio.galleryCount, galleryCount > 0 {
                    Text("Galleries").font(.title3).foregroundColor(.white.opacity(0.4))
                    Text("\(galleryCount)").font(.title3).foregroundColor(.white)
                }

                if let rating = studio.rating100 {
                    Text("Rating").font(.title3).foregroundColor(.white.opacity(0.4))
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill").foregroundColor(.yellow)
                        Text(String(format: "%.1f", Double(rating) / 20.0)).font(.title3).foregroundColor(.white)
                    }
                }

                if studio.favorite == true {
                    Text("Favorite").font(.title3).foregroundColor(.white.opacity(0.4))
                    Image(systemName: "heart.fill").foregroundColor(.red).font(.title3)
                }

                if let url = studio.url, !url.isEmpty {
                    Text("URL").font(.title3).foregroundColor(.white.opacity(0.4))
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
        viewModel.fetchStudio(studioId: studioId) { fetchedStudio in
            self.studio = fetchedStudio
            self.isLoadingStudio = false
        }
        viewModel.fetchStudioScenes(studioId: studioId, isInitialLoad: true)
    }
}

#Preview {
    NavigationStack {
        TVStudioDetailView(studioId: "1", studioName: "Example Studio")
    }
}
