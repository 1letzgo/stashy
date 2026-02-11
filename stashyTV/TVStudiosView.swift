//
//  TVStudiosView.swift
//  stashyTV
//
//  Created for tvOS on 08.02.26.
//

import SwiftUI

struct TVStudiosView: View {
    @StateObject private var viewModel = StashDBViewModel()

    private let columns = Array(
        repeating: GridItem(.adaptive(minimum: 250, maximum: 300), spacing: 48),
        count: 5
    )

    var body: some View {
        VStack(spacing: 0) {
                // Content
                if viewModel.isLoadingStudios && viewModel.studios.isEmpty {
                    Spacer()
                    ProgressView("Loading studios...")
                        .font(.title2)
                    Spacer()
                } else if viewModel.studios.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "building.2")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        Text("No Studios Found")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 48) {
                            ForEach(viewModel.studios) { studio in
                                NavigationLink(destination: TVStudioDetailView(studioId: studio.id, studioName: studio.name)) {
                                    TVStudioCardView(studio: studio)
                                }
                                .buttonStyle(.card)
                                .onAppear {
                                    // Pagination: load more when last item appears
                                    if studio.id == viewModel.studios.last?.id && viewModel.hasMoreStudios {
                                        viewModel.loadMoreStudios()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.top, 40)
                        .padding(.bottom, 60)

                        // Loading more indicator
                        if viewModel.isLoadingMoreStudios {
                            ProgressView()
                                .padding(.vertical, 40)
                        }
                    }
                }
            }
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

#Preview {
    TVStudiosView()
}
