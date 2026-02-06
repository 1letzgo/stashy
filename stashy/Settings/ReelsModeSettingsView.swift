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

    var body: some View {
        List {
            Section {
                ForEach(tabManager.reelsModes) { modeConfig in
                    DisclosureGroup {
                        if modeConfig.isEnabled {
                            HStack {
                                Text("Default Sort")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()

                                switch modeConfig.type {
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
                                }
                            }
                            .padding(.vertical, 4)
                        } else {
                            Text("Enable this mode to configure sorting.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } label: {
                        HStack {
                            Label(modeConfig.type.defaultTitle, systemImage: modeConfig.type.icon)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { modeConfig.isEnabled },
                                set: { _ in tabManager.toggleReelsMode(modeConfig.type) }
                            ))
                            .labelsHidden()
                            .tint(appearanceManager.tintColor)
                        }
                    }
                }
                .onMove { indices, newOffset in
                    tabManager.moveReelsMode(from: indices, to: newOffset)
                }
            } header: {
                Text("Reels Modes Order")
            } footer: {
                Text("The first enabled mode will be shown by default. Reorder to change the sequence in the switcher.")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("StashTok Modes")
    }
}
