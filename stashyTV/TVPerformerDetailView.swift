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
        GridItem(.adaptive(minimum: 380, maximum: 420), spacing: 30)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Header: photo + info
                HStack(alignment: .top, spacing: 50) {
                    // Profile image
                    AsyncImage(url: performer?.thumbnailURL) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.08))
                                .overlay(ProgressView())
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Rectangle()
                                .fill(Color.gray.opacity(0.08))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 56))
                                        .foregroundColor(.white.opacity(0.12))
                                )
                        @unknown default:
                            Rectangle()
                                .fill(Color.gray.opacity(0.08))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 56))
                                        .foregroundColor(.white.opacity(0.12))
                                )
                        }
                    }
                    .aspectRatio(2/3, contentMode: .fill)
                    .frame(width: 350, height: 525)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Info
                    VStack(alignment: .leading, spacing: 16) {
                        Text(performerName)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if let disambiguation = performer?.disambiguation, !disambiguation.isEmpty {
                            Text(disambiguation)
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.4))
                        }

                        Divider()
                            .background(Color.white.opacity(0.1))
                            .padding(.vertical, 4)

                        if isLoadingPerformer {
                            ProgressView().scaleEffect(1.2)
                        } else if let performer = performer {
                            detailInfoGrid(performer: performer)
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

                        if viewModel.totalPerformerScenes > 0 {
                            Text("\(viewModel.totalPerformerScenes)")
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

                    if viewModel.isLoadingPerformerScenes && viewModel.performerScenes.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().scaleEffect(1.5)
                            Spacer()
                        }
                        .padding(.vertical, 60)
                    } else if viewModel.performerScenes.isEmpty {
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
                            ForEach(viewModel.performerScenes) { scene in
                                VStack(alignment: .leading, spacing: 10) {
                                    NavigationLink(destination: TVSceneDetailView(sceneId: scene.id)) {
                                        TVSceneCardView(scene: scene)
                                    }
                                    .buttonStyle(.card)
                                    
                                    TVSceneCardTitleView(scene: scene)
                                }
                                .frame(width: 400)
                                .onAppear {
                                    if scene.id == viewModel.performerScenes.last?.id && viewModel.hasMorePerformerScenes {
                                        viewModel.fetchPerformerScenes(performerId: performerId, isInitialLoad: false)
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
        .navigationTitle("")
        .background(Color.black)
        .onAppear {
            loadPerformerData()
        }
    }

    // MARK: - Detail Info Grid

    @ViewBuilder
    private func detailInfoGrid(performer: Performer) -> some View {
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
