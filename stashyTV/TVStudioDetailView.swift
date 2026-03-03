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

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = StashDBViewModel()
    @State private var studio: Studio?
    @State private var isLoadingStudio = true

    private let sceneColumns = [
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40)
    ]

    var body: some View {
        TVGenericDetailView(
            item: studio,
            isLoading: isLoadingStudio,
            heroAspectRatio: 16/9,
            placeholderSystemImage: "building.2.fill",
            scenes: viewModel.studioScenes,
            isLoadingScenes: viewModel.isLoadingStudioScenes,
            totalScenes: viewModel.totalStudioScenes,
            hasMoreScenes: viewModel.hasMoreStudioScenes,
            loadMoreScenes: { viewModel.fetchStudioScenes(studioId: studioId, isInitialLoad: false) },
            infoGrid: { studio in
                LazyVGrid(columns: [
                    GridItem(.fixed(240), alignment: .leading),
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
            },
            additionalContent: { EmptyView() }
        )
        .onAppear {
            loadStudioData()
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
