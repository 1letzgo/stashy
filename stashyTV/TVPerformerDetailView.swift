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

    private let sceneColumns = [
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40)
    ]

    var body: some View {
        TVGenericDetailView(
            item: performer,
            isLoading: isLoadingPerformer,
            heroAspectRatio: 2/3,
            placeholderSystemImage: "person.fill",
            scenes: viewModel.performerScenes,
            isLoadingScenes: viewModel.isLoadingPerformerScenes,
            totalScenes: viewModel.totalPerformerScenes,
            hasMoreScenes: viewModel.hasMorePerformerScenes,
            loadMoreScenes: { viewModel.fetchPerformerScenes(performerId: performerId, isInitialLoad: false) },
            infoGrid: { performer in
                LazyVGrid(columns: [
                    GridItem(.fixed(240), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ], alignment: .leading, spacing: 12) {
                    if let gender = performer.gender, !gender.isEmpty {
                        Text("Gender").font(.title3).foregroundColor(.white.opacity(0.4))
                        Text(gender.capitalized).font(.title3).foregroundColor(.white)
                    }

                    if let country = performer.country, !country.isEmpty {
                        Text("Country").font(.title3).foregroundColor(.white.opacity(0.4))
                        Text(country).font(.title3).foregroundColor(.white)
                    }

                    if let ethnicity = performer.ethnicity, !ethnicity.isEmpty {
                        Text("Ethnicity").font(.title3).foregroundColor(.white.opacity(0.4))
                        Text(ethnicity.capitalized).font(.title3).foregroundColor(.white)
                    }

                    if let birthdate = performer.birthdate, !birthdate.isEmpty {
                        Text("Birthdate").font(.title3).foregroundColor(.white.opacity(0.4))
                        Text(birthdate).font(.title3).foregroundColor(.white)
                    }

                    Text("Scenes").font(.title3).foregroundColor(.white.opacity(0.4))
                    Text("\(performer.sceneCount)").font(.title3).foregroundColor(.white)

                    if let rating = performer.rating100 {
                        Text("Rating").font(.title3).foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill").foregroundColor(.yellow)
                            Text(String(format: "%.1f", Double(rating) / 20.0)).font(.title3).foregroundColor(.white)
                        }
                    }

                    if performer.favorite == true {
                        Text("Favorite").font(.title3).foregroundColor(.white.opacity(0.4))
                        Image(systemName: "heart.fill").foregroundColor(.red).font(.title3)
                    }
                }
            },
            additionalContent: { EmptyView() }
        )
        .onAppear {
            loadPerformerData()
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

#Preview {
    NavigationStack {
        TVPerformerDetailView(performerId: "1", performerName: "Example Performer")
    }
}
