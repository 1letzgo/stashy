//
//  ReelsModeSettingsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI

struct ReelsModeSettingsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()

    @ViewBuilder
    private func reelsSettingRow(title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .foregroundColor(.secondary)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: 36)
    }

    private var isEnabled: Bool {
        tabManager.tabs.first(where: { $0.id == .reels })?.isVisible ?? true
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { isEnabled },
                    set: { _ in tabManager.toggle(.reels) }
                )) {
                    Label("Show Feeds Tab", systemImage: "play.rectangle.on.rectangle")
                }
                .tint(appearanceManager.tintColor)
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section {
                ForEach(tabManager.configurableReelsModes) { modeConfig in
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
                            reelsSettingRow(title: "Default Sort") {
                                sortPicker(for: modeConfig.type)
                            }

                            // Default Filter
                            reelsSettingRow(title: "Default Filter") {
                                filterPicker(for: modeConfig.type)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                            .fill(Color.secondaryAppBackground)
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
        .applyAppBackground()
        .stashySettingsDetailChrome("Feeds")
        .onAppear {
            viewModel.fetchSavedFilters()
        }
    }

    @ViewBuilder
    private func sortPicker(for type: ReelsModeType) -> some View {
        switch type {
        case .scenes:
            let current = StashDBViewModel.SceneSortOption(rawValue: tabManager.getReelsDefaultSort(for: .scenes) ?? "") ?? .random
            Menu {
                ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                    Button(action: { tabManager.setReelsDefaultSort(for: .scenes, option: option.rawValue) }) {
                        HStack { Text(option.displayName); if option == current { Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                pickerLabelText(current.displayName)
            }

        case .markers:
            let current = StashDBViewModel.SceneMarkerSortOption(rawValue: tabManager.getReelsDefaultSort(for: .markers) ?? "") ?? .random
            Menu {
                ForEach(StashDBViewModel.SceneMarkerSortOption.allCases, id: \.self) { option in
                    Button(action: { tabManager.setReelsDefaultSort(for: .markers, option: option.rawValue) }) {
                        HStack { Text(option.displayName); if option == current { Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                pickerLabelText(current.displayName)
            }

        case .clips:
            let current = StashDBViewModel.ImageSortOption(rawValue: tabManager.getReelsDefaultSort(for: .clips) ?? "") ?? .random
            Menu {
                ForEach(StashDBViewModel.ImageSortOption.allCases, id: \.self) { option in
                    Button(action: { tabManager.setReelsDefaultSort(for: .clips, option: option.rawValue) }) {
                        HStack { Text(option.displayName); if option == current { Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                pickerLabelText(current.displayName)
            }

        case .previews:
            let current = StashDBViewModel.SceneSortOption(rawValue: tabManager.getReelsDefaultSort(for: .previews) ?? "") ?? .random
            Menu {
                ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                    Button(action: { tabManager.setReelsDefaultSort(for: .previews, option: option.rawValue) }) {
                        HStack { Text(option.displayName); if option == current { Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                pickerLabelText(current.displayName)
            }

        case .pics:
            EmptyView()
        }
    }

    // Menu-style Pickers tend to wrap the label in tight HStacks (List rows).
    // Provide an explicit label view with single-line truncation + min width.
    private func pickerLabelText(_ text: String) -> some View {
        Text(text)
            .foregroundColor(.secondary)
            .font(.subheadline)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func filterPicker(for type: ReelsModeType) -> some View {
        let sceneFilters = viewModel.savedFilters.values
            .filter { $0.mode == .scenes }
            .sorted { $0.name < $1.name }
        let markerFilters = viewModel.savedFilters.values
            .filter { $0.mode == .sceneMarkers }
            .sorted { $0.name < $1.name }

        switch type {
        case .scenes:
            if sceneFilters.isEmpty && !viewModel.isLoadingSavedFilters {
                Text("No filters found")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                Picker("", selection: Binding(
                    get: { tabManager.getDefaultFilterId(for: .reels) ?? "" },
                    set: { newId in
                        if newId.isEmpty {
                            tabManager.setDefaultFilter(for: .reels, filterId: nil, filterName: nil)
                        } else if let filter = sceneFilters.first(where: { $0.id == newId }) {
                            tabManager.setDefaultFilter(for: .reels, filterId: filter.id, filterName: filter.name)
                        }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(sceneFilters) { filter in
                        Text(filter.name).tag(filter.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

        case .markers:
            if markerFilters.isEmpty && !viewModel.isLoadingSavedFilters {
                Text("No filters found")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                Picker("", selection: Binding(
                    get: { tabManager.getDefaultMarkerFilterId(for: .reels) ?? "" },
                    set: { newId in
                        if newId.isEmpty {
                            tabManager.setDefaultMarkerFilter(for: .reels, filterId: nil, filterName: nil)
                        } else if let filter = markerFilters.first(where: { $0.id == newId }) {
                            tabManager.setDefaultMarkerFilter(for: .reels, filterId: filter.id, filterName: filter.name)
                        }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(markerFilters) { filter in
                        Text(filter.name).tag(filter.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

        case .clips:
            let filters = viewModel.savedFilters.values
                .filter { $0.mode == .images }
                .sorted { $0.name < $1.name }
            if filters.isEmpty && !viewModel.isLoadingSavedFilters {
                Text("No filters found")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
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

        case .previews:
            if sceneFilters.isEmpty && !viewModel.isLoadingSavedFilters {
                Text("No filters found")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                Picker("", selection: Binding(
                    get: { tabManager.getDefaultPreviewFilterId(for: .reels) ?? "" },
                    set: { newId in
                        if newId.isEmpty {
                            tabManager.setDefaultPreviewFilter(for: .reels, filterId: nil, filterName: nil)
                        } else if let filter = sceneFilters.first(where: { $0.id == newId }) {
                            tabManager.setDefaultPreviewFilter(for: .reels, filterId: filter.id, filterName: filter.name)
                        }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(sceneFilters) { filter in
                        Text(filter.name).tag(filter.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

        case .pics:
            EmptyView()
        }
    }
}
#endif
