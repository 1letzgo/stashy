//
//  DefaultSortView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

import SwiftUI

struct DefaultSortView: View {
    @ObservedObject var tabManager = TabManager.shared

    var visibleTabs: [TabConfig] {
        tabManager.tabs
            .filter { $0.id != .settings && $0.id != .catalogue && $0.id != .media && $0.id != .downloads && $0.id != .dashboard && $0.id != .reels && $0.isVisible }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section(header: Text("Default Sort Order")) {
                ForEach(visibleTabs) { tab in
                    sortPicker(for: tab.id)
                }
            }

            Section(header: Text("Detail Views Sort Order")) {
                ForEach(tabManager.detailViews) { config in
                    detailSortPicker(for: config)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Default Sorting")
    }

    @ViewBuilder
    private func sortPicker(for tab: AppTab) -> some View {
        HStack {
            Label(tab.title, systemImage: tab.icon)
            Spacer()
            switch tab {
            case .studios:
                Picker("", selection: Binding(
                    get: { StashDBViewModel.StudioSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .sceneCountDesc },
                    set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.StudioSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            case .performers:
                Picker("", selection: Binding(
                    get: { StashDBViewModel.PerformerSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .sceneCountDesc },
                    set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.PerformerSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            case .scenes:
                Picker("", selection: Binding(
                    get: { StashDBViewModel.SceneSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .dateDesc },
                    set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            case .galleries:
                Picker("", selection: Binding(
                    get: { StashDBViewModel.GallerySortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .dateDesc },
                    set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.GallerySortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            case .tags:
                Picker("", selection: Binding(
                    get: { StashDBViewModel.TagSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .sceneCountDesc },
                    set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.TagSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            case .images:
                Picker("", selection: Binding(
                    get: { StashDBViewModel.ImageSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .dateDesc },
                    set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.ImageSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func detailSortPicker(for config: DetailViewConfig) -> some View {
        HStack {
            Label(config.id.title, systemImage: config.id.icon)
            Spacer()
            if config.id == .gallery {
                Picker("", selection: Binding(
                    get: { StashDBViewModel.ImageSortOption(rawValue: tabManager.getPersistentDetailSortOption(for: config.id.rawValue) ?? "") ?? .dateDesc },
                    set: { tabManager.setPersistentDetailSortOption(for: config.id.rawValue, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.ImageSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            } else {
                Picker("", selection: Binding(
                    get: { StashDBViewModel.SceneSortOption(rawValue: tabManager.getPersistentDetailSortOption(for: config.id.rawValue) ?? "") ?? .dateDesc },
                    set: { tabManager.setPersistentDetailSortOption(for: config.id.rawValue, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}
