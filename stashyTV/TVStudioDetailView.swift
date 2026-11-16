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
    @ObservedObject private var studioCounts = StudioCountsStore.shared
    @AppStorage(StudioCountsStore.includeSubStudiosKey) private var includeSubStudios = false
    // Nur beim ersten Erscheinen laden — ein Pop zurück darf die nachgeladenen
    // Seiten (und damit Scroll-Position/Fokus) nicht auf Seite 1 zurücksetzen.
    @State private var didLoad = false
    @State private var isUpdatingFavorite = false
    @State private var showingRatingPicker = false

    var body: some View {
        TVGenericDetailView(
            item: studio,
            isLoading: isLoadingStudio,
            // A logo is no backdrop: small, in the title line, no placeholder without one.
            titleLogo: AnyView(
                TVStudioImageView(studioId: studioId, studioName: studioName, imagePath: studio?.imagePath,
                                  titleLogoHeight: 72)
            ),
            channel: .studio(id: studioId, name: studio?.name ?? studioName),
            headerActions: headerActions,
            facts: studio.map(headerFacts) ?? [],
            sheetFacts: studio.map(sheetFacts) ?? [],
            scenes: viewModel.studioScenes,
            isLoadingScenes: viewModel.isLoadingStudioScenes,
            totalScenes: viewModel.totalStudioScenes,
            hasMoreScenes: viewModel.hasMoreStudioScenes,
            loadMoreScenes: { viewModel.loadMoreStudioScenes(studioId: studioId) },
            headerAccessory: { EmptyView() }
        )
        .task(id: studio?.id) {
            if let id = studio?.id { studioCounts.request(id, refresh: true) }
        }
        .tvRatingDialog(isPresented: $showingRatingPicker, current: studio?.rating100) { value in
            setRating(value)
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            loadStudioData()
        }
    }

    // MARK: - Facts

    private func headerFacts(_ studio: Studio) -> [TVDetailFact] {
        let counts = studioCounts.display(for: studio, includeSubStudios: includeSubStudios)
        var facts: [TVDetailFact] = []
        if let oCount = counts.oCount, oCount > 0 {
            facts.append(TVDetailFact(id: "o_count", label: tr("o_count"), value: "\(oCount)",
                                      icon: "heart.circle", iconColor: AppearanceManager.shared.tintColor))
        }
        if let performerCount = counts.performers, performerCount > 0 {
            facts.append(TVDetailFact(id: "performers", label: tr("performers"), value: "\(performerCount)"))
        }
        if let galleryCount = counts.galleries, galleryCount > 0 {
            facts.append(TVDetailFact(id: "galleries", label: tr("galleries"), value: "\(galleryCount)"))
        }
        // No rating fact: the Rating button shows it.
        if let url = studio.url, !url.isEmpty {
            facts.append(TVDetailFact(id: "url", label: "URL", value: url))
        }
        return facts
    }

    /// Facts only the Details sheet lists (the scene count is in the title line).
    private func sheetFacts(_ studio: Studio) -> [TVDetailFact] {
        let counts = studioCounts.display(for: studio, includeSubStudios: includeSubStudios)
        var facts = [TVDetailFact(id: "scenes", label: tr("scenes"), value: "\(counts.scenes)")]
        // The header's Rating button shows it too; the sheet lists everything.
        if let rating = studio.rating100 {
            facts.append(TVDetailFact(id: "rating", label: tr("rating"), value: String(format: "%.1f", Double(rating) / 20.0),
                                      icon: "star.fill", iconColor: .yellow))
        }
        if studio.favorite == true {
            facts.append(TVDetailFact(id: "favorite", label: tr("favourite"), value: "",
                                      icon: "heart.fill", iconColor: .red))
        }
        return facts
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
                title: isFavorite ? tr("favourite") : tr("action_add_favorite"),
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
        TVStudioDetailView(studioId: "1", studioName: tr("example_studio"))
    }
}
