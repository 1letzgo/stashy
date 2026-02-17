//
//  TVPerformersView.swift
//  stashyTV
//
//  Performers grid for tvOS
//

import SwiftUI

struct TVPerformersView: View {
    @StateObject private var viewModel = StashDBViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 36)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingPerformers && viewModel.performers.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    ProgressView().scaleEffect(1.5)
                    Text("Loading performers…")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            } else if viewModel.performers.isEmpty {
                Spacer()
                VStack(spacing: 24) {
                    Image(systemName: "person.3")
                        .font(.system(size: 56))
                        .foregroundColor(.white.opacity(0.12))
                    Text("No Performers Found")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(viewModel.performers) { performer in
                            NavigationLink(destination: TVPerformerDetailView(performerId: performer.id, performerName: performer.name)) {
                                TVPerformerCardView(performer: performer)
                            }
                            .buttonStyle(.card)
                            .onAppear {
                                if performer.id == viewModel.performers.last?.id && viewModel.hasMorePerformers {
                                    viewModel.loadMorePerformers()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.top, 40)
                    .padding(.bottom, 80)

                    if viewModel.isLoadingMorePerformers {
                        ProgressView()
                            .padding(.vertical, 40)
                    }
                }
            }
        }
        .navigationTitle("Performers")
        .background(Color.black)
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
