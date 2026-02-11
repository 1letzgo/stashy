//
//  TVPerformerDetailView.swift
//  stashyTV
//
//  Created for tvOS on 08.02.26.
//

import SwiftUI

struct TVPerformerDetailView: View {
    let performerId: String
    let performerName: String

    @StateObject private var viewModel = StashDBViewModel()
    @State private var performer: Performer?
    @State private var isLoadingPerformer = true

    private let sceneColumns = Array(
        repeating: GridItem(.adaptive(minimum: 380, maximum: 400), spacing: 40),
        count: 4
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Header section: image on left, info on right
                HStack(alignment: .top, spacing: 60) {
                    // Profile image
                    CustomAsyncImage(url: performer?.thumbnailURL) { loader in
                        if loader.isLoading {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .overlay(ProgressView())
                        } else if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 72))
                                        .foregroundColor(.secondary)
                                )
                        }
                    }
                    .aspectRatio(2/3, contentMode: .fill)
                    .frame(width: 350, height: 525)
                    .clipped()
                    .cornerRadius(16)

                    // Info section
                    VStack(alignment: .leading, spacing: 20) {
                        Text(performerName)
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        if let disambiguation = performer?.disambiguation, !disambiguation.isEmpty {
                            Text(disambiguation)
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // Detail rows
                        if isLoadingPerformer {
                            ProgressView("Loading details...")
                                .font(.title3)
                        } else if let performer = performer {
                            detailInfoGrid(performer: performer)
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

                        if viewModel.totalPerformerScenes > 0 {
                            Text("(\(viewModel.totalPerformerScenes))")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 60)

                    if viewModel.isLoadingPerformerScenes && viewModel.performerScenes.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Loading scenes...")
                                .font(.title3)
                            Spacer()
                        }
                        .padding(.vertical, 60)
                    } else if viewModel.performerScenes.isEmpty {
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
                            ForEach(viewModel.performerScenes) { scene in
                                NavigationLink(destination: TVSceneDetailView(sceneId: scene.id)) {
                                    TVSceneCardView(scene: scene)
                                }
                                .buttonStyle(.card)
                                .onAppear {
                                    // Pagination
                                    if scene.id == viewModel.performerScenes.last?.id && viewModel.hasMorePerformerScenes {
                                        viewModel.fetchPerformerScenes(performerId: performerId, isInitialLoad: false)
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
        .navigationTitle(performerName)
        .onAppear {
            loadPerformerData()
        }
    }

    // MARK: - Detail Info Grid

    @ViewBuilder
    private func detailInfoGrid(performer: Performer) -> some View {
        LazyVGrid(columns: [
            GridItem(.fixed(200), alignment: .leading),
            GridItem(.flexible(), alignment: .leading)
        ], alignment: .leading, spacing: 16) {
            if let gender = performer.gender, !gender.isEmpty {
                Text("Gender")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text(gender.capitalized)
                    .font(.title3)
            }

            if let country = performer.country, !country.isEmpty {
                Text("Country")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text(country)
                    .font(.title3)
            }

            if let ethnicity = performer.ethnicity, !ethnicity.isEmpty {
                Text("Ethnicity")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text(ethnicity.capitalized)
                    .font(.title3)
            }

            if let birthdate = performer.birthdate, !birthdate.isEmpty {
                Text("Birthdate")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text(birthdate)
                    .font(.title3)
            }

            Text("Scenes")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("\(performer.sceneCount)")
                .font(.title3)

            if let rating = performer.rating100 {
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

            if performer.favorite == true {
                Text("Favorite")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.title3)
            }
        }
    }

    // MARK: - Data Loading

    private func loadPerformerData() {
        // Fetch full performer details
        viewModel.fetchPerformer(performerId: performerId) { fetchedPerformer in
            self.performer = fetchedPerformer
            self.isLoadingPerformer = false
        }

        // Fetch performer's scenes
        viewModel.fetchPerformerScenes(performerId: performerId, isInitialLoad: true)
    }
}

// Note: TVSceneCardView is now in its own file TVSceneCardView.swift

#Preview {
    NavigationStack {
        TVPerformerDetailView(performerId: "1", performerName: "Example Performer")
    }
}
