//
//  TVPerformersView.swift
//  stashyTV
//
//  Created for tvOS on 08.02.26.
//

import SwiftUI

struct TVPerformersView: View {
    @StateObject private var viewModel = StashDBViewModel()

    private let columns = Array(
        repeating: GridItem(.adaptive(minimum: 250, maximum: 300), spacing: 48),
        count: 5
    )

    var body: some View {
        VStack(spacing: 0) {
                // Content
                if viewModel.isLoadingPerformers && viewModel.performers.isEmpty {
                    Spacer()
                    ProgressView("Loading performers...")
                        .font(.title2)
                    Spacer()
                } else if viewModel.performers.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "person.3")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        Text("No Performers Found")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 48) {
                            ForEach(viewModel.performers) { performer in
                                NavigationLink(destination: TVPerformerDetailView(performerId: performer.id, performerName: performer.name)) {
                                    TVPerformerCardView(performer: performer)
                                }
                                .buttonStyle(.card)
                                .onAppear {
                                    // Pagination: load more when last item appears
                                    if performer.id == viewModel.performers.last?.id && viewModel.hasMorePerformers {
                                        viewModel.loadMorePerformers()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.top, 40)
                        .padding(.bottom, 60)

                        // Loading more indicator
                        if viewModel.isLoadingMorePerformers {
                            ProgressView()
                                .padding(.vertical, 40)
                        }
                    }
                }
            }
            .onAppear {
                if viewModel.performers.isEmpty {
                    viewModel.fetchPerformers(sortBy: .nameAsc, isInitialLoad: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
                viewModel.fetchPerformers(sortBy: .nameAsc, isInitialLoad: true)
            }
    }
}

#Preview {
    TVPerformersView()
}
