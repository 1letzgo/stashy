//
//  DefaultFilterView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

import SwiftUI

struct DefaultFilterView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var tabManager = TabManager.shared

    var body: some View {
        List {
            Section {
                filterPicker(for: .dashboard, title: "Dashboard", icon: "chart.bar.fill")
                filterPicker(for: .scenes, title: "Scenes", icon: "film")
                filterPicker(for: .galleries, title: "Galleries", icon: "photo.stack")
                filterPicker(for: .performers, title: "Performers", icon: "person.3")
                filterPicker(for: .studios, title: "Studios", icon: "building.2")
                filterPicker(for: .tags, title: "Tags", icon: "tag")
            } header: {
                Text("Default Filters")
            } footer: {
                Text("Pick a saved filter that will be applied automatically when you open the respective tab.")
            }

        }
        .listStyle(.insetGrouped)
        .navigationTitle("Default Filters")
        .toolbar {
            if viewModel.isLoadingSavedFilters {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .shimmer()
                }
            }
        }
        .onAppear {
            viewModel.fetchSavedFilters()
        }
    }

    @ViewBuilder
    private func filterPicker(for tab: AppTab, title: String, icon: String, modeOverride: StashDBViewModel.FilterMode? = nil) -> some View {
        let mode: StashDBViewModel.FilterMode? = modeOverride ?? {
            switch tab {
            case .scenes, .reels, .dashboard: return .scenes
            case .performers: return .performers
            case .studios: return .studios
            case .galleries: return .galleries
            case .tags: return .tags
            default: return nil
            }
        }()

        if let mode = mode {
            let filters = viewModel.savedFilters.values
                .filter { $0.mode == mode }
                .sorted { $0.name < $1.name }

            let currentId = tabManager.getDefaultFilterId(for: tab)

            HStack {
                Label(title, systemImage: icon)
                Spacer()

                if filters.isEmpty && !viewModel.isLoadingSavedFilters {
                    Text("No filters found")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    Picker("", selection: Binding(
                        get: { currentId ?? "" },
                        set: { newId in
                            if newId.isEmpty {
                                tabManager.setDefaultFilter(for: tab, filterId: nil, filterName: nil)
                            } else if let filter = filters.first(where: { $0.id == newId }) {
                                tabManager.setDefaultFilter(for: tab, filterId: filter.id, filterName: filter.name)
                            }
                        }
                    )) {
                        Text("None").tag("")

                        ForEach(filters) { filter in
                            Text(filter.name).tag(filter.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        }
    }

    @ViewBuilder
    private func markerFilterPicker(for tab: AppTab, title: String, icon: String) -> some View {
        let mode: StashDBViewModel.FilterMode = .sceneMarkers

        let filters = viewModel.savedFilters.values
            .filter { $0.mode == mode }
            .sorted { $0.name < $1.name }

        let currentId = tabManager.getDefaultMarkerFilterId(for: tab)

        HStack {
            Label(title, systemImage: icon)
            Spacer()

            if filters.isEmpty && !viewModel.isLoadingSavedFilters {
                Text("No filters found")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                Picker("", selection: Binding(
                    get: { currentId ?? "" },
                    set: { newId in
                        if newId.isEmpty {
                            tabManager.setDefaultMarkerFilter(for: tab, filterId: nil, filterName: nil)
                        } else if let filter = filters.first(where: { $0.id == newId }) {
                            tabManager.setDefaultMarkerFilter(for: tab, filterId: filter.id, filterName: filter.name)
                        }
                    }
                )) {
                    Text("None").tag("")

                    ForEach(filters) { filter in
                        Text(filter.name).tag(filter.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}
