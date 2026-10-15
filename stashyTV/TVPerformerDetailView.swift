//
//  TVPerformerDetailView.swift
//  stashyTV
//
//  Performer detail for tvOS — Netflix/Prime style
//

import SwiftUI

struct TVPerformerDetailView: View {
    let performerId: String
    let performerName: String

    @StateObject private var viewModel = StashDBViewModel()
    @State private var performer: Performer?
    @State private var isLoadingPerformer = true
    // Nur beim ersten Erscheinen laden — ein Pop zurück darf die nachgeladenen
    // Seiten (und damit Scroll-Position/Fokus) nicht auf Seite 1 zurücksetzen.
    @State private var didLoad = false
    @State private var isUpdatingFavorite = false
    @State private var showingRatingPicker = false
    /// Match rank "rank/total" in the Match pool (same line as iOS), nil when not ranked.
    @State private var battleLine: String?

    var body: some View {
        TVGenericDetailView(
            item: performer,
            isLoading: isLoadingPerformer,
            heroAspectRatio: 2/3,
            placeholderSystemImage: "person.fill",
            channel: .performer(id: performerId, name: performer?.name ?? performerName),
            headerActions: headerActions,
            scenes: viewModel.performerScenes,
            isLoadingScenes: viewModel.isLoadingPerformerScenes,
            totalScenes: viewModel.totalPerformerScenes,
            hasMoreScenes: viewModel.hasMorePerformerScenes,
            loadMoreScenes: { viewModel.loadMorePerformerScenes(performerId: performerId) },
            infoGrid: { performer in
                LazyVGrid(columns: TVGridSpec.infoColumns, alignment: .leading, spacing: 12) {
                    if let gender = performer.gender, !gender.isEmpty {
                        Text("Gender").font(.title3).foregroundStyle(.secondary)
                        Text(gender.capitalized).font(.title3).foregroundColor(.white)
                    }

                    if let country = performer.country, !country.isEmpty {
                        Text("Country").font(.title3).foregroundStyle(.secondary)
                        Text(country).font(.title3).foregroundColor(.white)
                    }

                    if let ethnicity = performer.ethnicity, !ethnicity.isEmpty {
                        Text("Ethnicity").font(.title3).foregroundStyle(.secondary)
                        Text(ethnicity.capitalized).font(.title3).foregroundColor(.white)
                    }

                    if let birthdate = performer.birthdate, !birthdate.isEmpty {
                        Text("Birthdate").font(.title3).foregroundStyle(.secondary)
                        Text(birthdate).font(.title3).foregroundColor(.white)
                    }

                    Text("Scenes").font(.title3).foregroundStyle(.secondary)
                    Text("\(performer.sceneCount)").font(.title3).foregroundColor(.white)

                    if let rating = performer.rating100 {
                        Text("Rating").font(.title3).foregroundStyle(.secondary)
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill").foregroundColor(.yellow)
                            Text(String(format: "%.1f", Double(rating) / 20.0)).font(.title3).foregroundColor(.white)
                        }
                    }

                    // Summed over the performer's scenes by Stash — read-only, the
                    // counter itself lives on the scenes.
                    if let oCounter = performer.oCounter, oCounter > 0 {
                        Text("O-Count").font(.title3).foregroundStyle(.secondary)
                        HStack(spacing: 5) {
                            Image(systemName: "heart.circle").foregroundColor(AppearanceManager.shared.tintColor)
                            Text("\(oCounter)").font(.title3).foregroundColor(.white)
                        }
                    }

                    if performer.favorite == true {
                        Text("Favorite").font(.title3).foregroundStyle(.secondary)
                        Image(systemName: "heart.fill").foregroundColor(.red).font(.title3)
                    }

                    if let battleLine {
                        Text("Battle").font(.title3).foregroundStyle(.secondary)
                        Text(battleLine).font(.title3).foregroundColor(.white)
                    }
                }
            },
            additionalContent: { EmptyView() }
        )
        .tvRatingDialog(isPresented: $showingRatingPicker, current: performer?.rating100) { value in
            setRating(value)
        }
        .task(id: performerId) {
            battleLine = await HotOrNotBattleDisplay.fetchRankSlashTotal(performerId: performerId)
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            loadPerformerData()
        }
    }

    // MARK: - Actions

    /// Favorite and rating, like the iOS detail page. Present from the first frame (they
    /// no-op until the performer is loaded): the first one is the header's focus anchor, and
    /// swapping the anchor out mid-load let tvOS move focus into the scene grid.
    private var headerActions: [TVDetailHeaderAction] {
        let isFavorite = performer?.favorite == true
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
                title: TVEntityRating.buttonTitle(performer?.rating100),
                perform: { if performer != nil { showingRatingPicker = true } }
            )
        ]
    }

    /// Optimistic like iOS: flip first, roll back if the server refuses.
    private func toggleFavorite() {
        guard let current = performer, !isUpdatingFavorite else { return }
        isUpdatingFavorite = true
        let newState = !(current.favorite == true)
        performer = current.withFavorite(newState)
        viewModel.togglePerformerFavorite(performerId: current.id, favorite: newState) { success in
            DispatchQueue.main.async {
                if !success, let latest = performer {
                    performer = latest.withFavorite(!newState)
                }
                isUpdatingFavorite = false
            }
        }
    }

    private func setRating(_ value: Int?) {
        guard let current = performer else { return }
        let previous = current.rating100
        var updated = current
        updated.rating100 = value
        performer = updated
        Task {
            let ok = await TVEntityRating.setPerformerRating(id: current.id, rating100: value)
            if !ok, var latest = performer {
                latest.rating100 = previous
                performer = latest
            }
        }
    }

    // MARK: - Data Loading

    private func loadPerformerData() {
        viewModel.fetchPerformer(performerId: performerId) { fetchedPerformer in
            self.performer = fetchedPerformer
            self.isLoadingPerformer = false
        }
        viewModel.fetchPerformerScenes(performerId: performerId, isInitialLoad: true)
    }
}

private extension Performer {
    /// `favorite` is a `let`, so a toggle needs a full copy.
    func withFavorite(_ newValue: Bool) -> Performer {
        Performer(
            id: id, name: name, disambiguation: disambiguation, birthdate: birthdate,
            country: country, imagePath: imagePath, sceneCount: sceneCount,
            imageCount: imageCount, galleryCount: galleryCount, gender: gender,
            ethnicity: ethnicity, height: height, weight: weight, measurements: measurements,
            fakeTits: fakeTits, penis_length: penis_length, careerLength: careerLength,
            tattoos: tattoos, piercings: piercings, aliasList: aliasList,
            favorite: newValue, rating100: rating100, createdAt: createdAt,
            updatedAt: updatedAt, oCounter: oCounter
        )
    }
}

#Preview {
    NavigationStack {
        TVPerformerDetailView(performerId: "1", performerName: "Example Performer")
    }
}
