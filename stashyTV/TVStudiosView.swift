//
//  TVStudiosView.swift
//  stashyTV
//
//  Studios grid for tvOS
//

import SwiftUI

struct TVStudiosView: View {
    @StateObject private var viewModel = StashDBViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 340), spacing: 36)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingStudios && viewModel.studios.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    ProgressView().scaleEffect(1.5)
                    Text("Loading studios…")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            } else if viewModel.studios.isEmpty {
                Spacer()
                VStack(spacing: 24) {
                    Image(systemName: "building.2")
                        .font(.system(size: 56))
                        .foregroundColor(.white.opacity(0.12))
                    Text("No Studios Found")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(viewModel.studios) { studio in
                            NavigationLink(destination: TVStudioDetailView(studioId: studio.id, studioName: studio.name)) {
                                TVStudioCardView(studio: studio)
                            }
                            .buttonStyle(.card)
                            .onAppear {
                                if studio.id == viewModel.studios.last?.id && viewModel.hasMoreStudios {
                                    viewModel.loadMoreStudios()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.top, 40)
                    .padding(.bottom, 80)

                    if viewModel.isLoadingMoreStudios {
                        ProgressView()
                            .padding(.vertical, 40)
                    }
                }
            }
        }
        .navigationTitle("")
        .background(Color.black)
        .onAppear {
            if viewModel.studios.isEmpty {
                viewModel.fetchStudios(sortBy: .nameAsc, isInitialLoad: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            viewModel.fetchStudios(sortBy: .nameAsc, isInitialLoad: true)
        }
    }
}
