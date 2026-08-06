//
//  DefaultFilterView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI

struct DefaultFilterView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var tabManager = TabManager.shared

    // Menu-style Pickers in List rows will happily wrap long labels, inflating row height.
    // Force a single line + fixed width so the row stays compact.
    private func pickerLabelText(_ text: String) -> some View {
        Text(text)
            .foregroundColor(.secondary)
            .font(.subheadline)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: 220, alignment: .trailing)
            .minimumScaleFactor(0.85)
    }

    var body: some View {
        List {
            Section {
                filterPicker(for: .dashboard, title: "Dashboard", icon: "chart.bar.fill")
                filterPicker(for: .scenes, title: "Scenes", icon: "film")
                filterPicker(for: .galleries, title: "Galleries", icon: "photo.stack")
                filterPicker(for: .images, title: "Images", icon: "photo")
                filterPicker(for: .performers, title: "Performers", icon: "person.fill")
                filterPicker(for: .studios, title: "Studios", icon: "building.2")
                filterPicker(for: .groups, title: "Groups", icon: "rectangle.stack.fill")
                filterPicker(for: .tags, title: "Tags", icon: "tag")
                filterPicker(for: .markers, title: "Markers", icon: "bookmark.fill", modeOverride: .sceneMarkers)
            } header: {
                Text("Default Filters")
            } footer: {
                Text("Pick a saved filter that will be applied automatically when you open the respective tab.")
            }
            .listRowBackground(Color.secondaryAppBackground)

        }
        .listStyle(.insetGrouped)
        .navigationTitle("Default Filters")
        .applyAppBackground()
        .scrollContentBackground(.hidden)
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
        if tab == .markers {
            let mode = modeOverride ?? StashDBViewModel.FilterMode.sceneMarkers
            let filters = viewModel.savedFilters.values
                .filter { $0.mode == mode }
                .sorted { $0.name < $1.name }

            let currentId = tabManager.getDefaultMarkerFilterId(for: .markers)

            HStack {
                Label(title, systemImage: icon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .layoutPriority(1)
                Spacer()

                if filters.isEmpty && !viewModel.isLoadingSavedFilters {
                    Text("No filters found")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    let current = currentId ?? ""
                    Menu {
                        Button(action: { tabManager.setDefaultMarkerFilter(for: .markers, filterId: nil, filterName: nil) }) {
                            HStack { Text("None"); if current.isEmpty { Image(systemName: "checkmark") } }
                        }
                        Divider()
                        ForEach(filters) { filter in
                            Button(action: { tabManager.setDefaultMarkerFilter(for: .markers, filterId: filter.id, filterName: filter.name) }) {
                                HStack { Text(filter.name); if filter.id == current { Image(systemName: "checkmark") } }
                            }
                        }
                    } label: {
                        let currentName = filters.first(where: { $0.id == current })?.name ?? "None"
                        pickerLabelText(currentName)
                    }
                }
            }
        } else {
        let mode: StashDBViewModel.FilterMode? = modeOverride ?? {
            switch tab {
            case .scenes, .reels, .dashboard: return .scenes
            case .performers: return .performers
            case .studios: return .studios
            case .galleries: return .galleries
            case .images: return .images
            case .tags: return .tags
            case .groups: return .groups
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .layoutPriority(1)
                Spacer()

                if filters.isEmpty && !viewModel.isLoadingSavedFilters {
                    Text("No filters found")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    let current = currentId ?? ""
                    Menu {
                        Button(action: { tabManager.setDefaultFilter(for: tab, filterId: nil, filterName: nil) }) {
                            HStack { Text("None"); if current.isEmpty { Image(systemName: "checkmark") } }
                        }
                        Divider()
                        ForEach(filters) { filter in
                            Button(action: { tabManager.setDefaultFilter(for: tab, filterId: filter.id, filterName: filter.name) }) {
                                HStack { Text(filter.name); if filter.id == current { Image(systemName: "checkmark") } }
                            }
                        }
                    } label: {
                        let currentName = filters.first(where: { $0.id == current })?.name ?? "None"
                        pickerLabelText(currentName)
                    }
                }
            }
        }
        }
    }
}
#endif
