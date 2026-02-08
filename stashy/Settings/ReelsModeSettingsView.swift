//
//  ReelsModeSettingsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

import SwiftUI

struct ReelsModeSettingsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()

    var body: some View {
        List {
            Section {
                ForEach(tabManager.reelsModes) { modeConfig in
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        HStack {
                            Label(modeConfig.type.defaultTitle, systemImage: modeConfig.type.icon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(appearanceManager.tintColor)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { modeConfig.isEnabled },
                                set: { _ in tabManager.toggleReelsMode(modeConfig.type) }
                            ))
                            .labelsHidden()
                            .tint(appearanceManager.tintColor)
                        }

                        if modeConfig.isEnabled {
                            Divider()
                                .padding(.vertical, 8)

                            // Default Sort
                            HStack {
                                Text("Default Sort")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                                Spacer()
                                sortPicker(for: modeConfig.type)
                            }

                            // Default Filter
                            HStack {
                                Text("Default Filter")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                                Spacer()
                                filterPicker(for: modeConfig.type)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                            .padding(.vertical, 4)
                    )
                }
                .onMove { indices, newOffset in
                    tabManager.moveReelsMode(from: indices, to: newOffset)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .deleteDisabled(true)
        .navigationTitle("StashTok Modes")
        .onAppear {
            viewModel.fetchSavedFilters()
        }
    }

    @ViewBuilder
    private func sortPicker(for type: ReelsModeType) -> some View {
        switch type {
        case .scenes:
            Picker("", selection: Binding(
                get: { StashDBViewModel.SceneSortOption(rawValue: tabManager.getReelsDefaultSort(for: .scenes) ?? "") ?? .random },
                set: { tabManager.setReelsDefaultSort(for: .scenes, option: $0.rawValue) }
            )) {
                ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

        case .markers:
            Picker("", selection: Binding(
                get: { StashDBViewModel.SceneMarkerSortOption(rawValue: tabManager.getReelsDefaultSort(for: .markers) ?? "") ?? .random },
                set: { tabManager.setReelsDefaultSort(for: .markers, option: $0.rawValue) }
            )) {
                ForEach(StashDBViewModel.SceneMarkerSortOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

        case .clips:
            Picker("", selection: Binding(
                get: { StashDBViewModel.ImageSortOption(rawValue: tabManager.getReelsDefaultSort(for: .clips) ?? "") ?? .random },
                set: { tabManager.setReelsDefaultSort(for: .clips, option: $0.rawValue) }
            )) {
                ForEach(StashDBViewModel.ImageSortOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func filterPicker(for type: ReelsModeType) -> some View {
        let filterMode: StashDBViewModel.FilterMode = {
            switch type {
            case .scenes: return .scenes
            case .markers: return .sceneMarkers
            case .clips: return .images
            }
        }()

        let filters = viewModel.savedFilters.values
            .filter { $0.mode == filterMode }
            .sorted { $0.name < $1.name }

        if filters.isEmpty && !viewModel.isLoadingSavedFilters {
            Text("No filters found")
                .foregroundColor(.secondary)
                .font(.subheadline)
        } else {
            switch type {
            case .scenes:
                Picker("", selection: Binding(
                    get: { tabManager.getDefaultFilterId(for: .reels) ?? "" },
                    set: { newId in
                        if newId.isEmpty {
                            tabManager.setDefaultFilter(for: .reels, filterId: nil, filterName: nil)
                        } else if let filter = filters.first(where: { $0.id == newId }) {
                            tabManager.setDefaultFilter(for: .reels, filterId: filter.id, filterName: filter.name)
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

            case .markers:
                Picker("", selection: Binding(
                    get: { tabManager.getDefaultMarkerFilterId(for: .reels) ?? "" },
                    set: { newId in
                        if newId.isEmpty {
                            tabManager.setDefaultMarkerFilter(for: .reels, filterId: nil, filterName: nil)
                        } else if let filter = filters.first(where: { $0.id == newId }) {
                            tabManager.setDefaultMarkerFilter(for: .reels, filterId: filter.id, filterName: filter.name)
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

            case .clips:
                Picker("", selection: Binding(
                    get: { tabManager.getDefaultClipFilterId(for: .reels) ?? "" },
                    set: { newId in
                        if newId.isEmpty {
                            tabManager.setDefaultClipFilter(for: .reels, filterId: nil, filterName: nil)
                        } else if let filter = filters.first(where: { $0.id == newId }) {
                            tabManager.setDefaultClipFilter(for: .reels, filterId: filter.id, filterName: filter.name)
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
