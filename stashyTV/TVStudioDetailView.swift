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
    // Nur beim ersten Erscheinen laden — ein Pop zurück darf die nachgeladenen
    // Seiten (und damit Scroll-Position/Fokus) nicht auf Seite 1 zurücksetzen.
    @State private var didLoad = false
    @State private var isUpdatingFavorite = false
    @State private var showingRatingPicker = false

    var body: some View {
        TVGenericDetailView(
            item: studio,
            isLoading: isLoadingStudio,
            heroAspectRatio: 16/9,
            placeholderSystemImage: "building.2.fill",
            heroImageOverride: AnyView(
                TVStudioImageView(studioId: studioId, studioName: studioName, contentMode: .fit)
            ),
            channel: .studio(id: studioId, name: studio?.name ?? studioName),
            headerActions: headerActions,
            scenes: viewModel.studioScenes,
            isLoadingScenes: viewModel.isLoadingStudioScenes,
            totalScenes: viewModel.totalStudioScenes,
            hasMoreScenes: viewModel.hasMoreStudioScenes,
            loadMoreScenes: { viewModel.loadMoreStudioScenes(studioId: studioId) },
            infoGrid: { studio in
                LazyVGrid(columns: TVGridSpec.infoColumns, alignment: .leading, spacing: 12) {
                    Text("Scenes").font(.title3).foregroundStyle(.secondary)
                    Text("\(studio.sceneCount)").font(.title3).foregroundColor(.white)

                    if let performerCount = studio.performerCount, performerCount > 0 {
                        Text("Performers").font(.title3).foregroundStyle(.secondary)
                        Text("\(performerCount)").font(.title3).foregroundColor(.white)
                    }

                    if let galleryCount = studio.galleryCount, galleryCount > 0 {
                        Text("Galleries").font(.title3).foregroundStyle(.secondary)
                        Text("\(galleryCount)").font(.title3).foregroundColor(.white)
                    }

                    if let rating = studio.rating100 {
                        Text("Rating").font(.title3).foregroundStyle(.secondary)
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill").foregroundColor(.yellow)
                            Text(String(format: "%.1f", Double(rating) / 20.0)).font(.title3).foregroundColor(.white)
                        }
                    }

                    if studio.favorite == true {
                        Text("Favorite").font(.title3).foregroundStyle(.secondary)
                        Image(systemName: "heart.fill").foregroundColor(.red).font(.title3)
                    }

                    if let url = studio.url, !url.isEmpty {
                        Text("URL").font(.title3).foregroundStyle(.secondary)
                        Text(url)
                            .font(.callout)
                            .foregroundColor(AppearanceManager.shared.tintColor)
                            .lineLimit(1)
                    }
                }
            },
            additionalContent: { EmptyView() }
        )
        .tvRatingDialog(isPresented: $showingRatingPicker, current: studio?.rating100) { value in
            setRating(value)
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            loadStudioData()
        }
    }

    // MARK: - Actions

    /// Favorite and rating, like the iOS detail page. Present from the first frame (they
    /// no-op until the studio is loaded): the first one is the header's focus anchor, and
    /// swapping the anchor out mid-load let tvOS move focus into the scene grid.
    private var headerActions: [TVDetailHeaderAction] {
        let isFavorite = studio?.favorite == true
        return [
            TVDetailHeaderAction(
                id: "favorite",
                icon: isFavorite ? "heart.fill" : "heart",
                title: isFavorite ? "Favorite" : "Add Favorite",
                perform: toggleFavorite
            ),
            TVDetailHeaderAction(
                id: "rating",
                icon: "star.fill",
                title: TVEntityRating.buttonTitle(studio?.rating100),
                perform: { if studio != nil { showingRatingPicker = true } }
            )
        ]
    }

    /// Optimistic like iOS: flip first, roll back if the server refuses.
    private func toggleFavorite() {
        guard var current = studio, !isUpdatingFavorite else { return }
        isUpdatingFavorite = true
        let newState = !(current.favorite == true)
        current.favorite = newState
        studio = current
        viewModel.toggleStudioFavorite(studioId: current.id, favorite: newState) { success in
            DispatchQueue.main.async {
                if !success, var latest = studio {
                    latest.favorite = !newState
                    studio = latest
                }
                isUpdatingFavorite = false
            }
        }
    }

    private func setRating(_ value: Int?) {
        guard var current = studio else { return }
        let previous = current.rating100
        current.rating100 = value
        studio = current
        Task {
            let ok = await TVEntityRating.setStudioRating(id: current.id, rating100: value)
            if !ok, var latest = studio {
                latest.rating100 = previous
                studio = latest
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
