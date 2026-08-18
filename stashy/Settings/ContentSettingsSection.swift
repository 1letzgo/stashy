//
//  ContentSettingsSection.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI

struct ContentSettingsSection: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared

    var body: some View {
        let rowCount = stashyPlus.isUnlocked ? 3 : 2
        Section {
            stashyScrollingSectionHeader("Content & Tabs")
            NavigationLink(destination: DashboardSettingsView()) {
                Label("Dashboard", systemImage: "uiwindow.split.2x1")
            }
            .stashyGroupedBlockRow(index: 0, count: rowCount)

            NavigationLink(destination: ReelsModeSettingsView()) {
                Label("Feeds", systemImage: "play.rectangle.on.rectangle")
            }
            .stashyGroupedBlockRow(index: 1, count: rowCount)

            if stashyPlus.isUnlocked {
                NavigationLink(destination: ToolsSettingsView()) {
                    Label("Tools", systemImage: "cube.box")
                }
                .stashyGroupedBlockRow(index: 2, count: rowCount)
            }
        }
    }
}

struct ToolsSettingsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared

    private var toolsTabIsVisible: Bool {
        tabManager.tabs.first(where: { $0.id == .tools })?.isVisible ?? true
    }

    /// Tools shown in the Tools tab (Server lives under Settings → Actions).
    private var orderedTools: [ToolsItemConfig] {
        tabManager.tools
            .filter { $0.id != .server }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section {
                stashyScrollingSectionHeader("Tab")
                Toggle(isOn: Binding(
                    get: { toolsTabIsVisible },
                    set: { _ in tabManager.toggle(.tools) }
                )) {
                    Label("Show Tools Tab", systemImage: "cube.box")
                }
                .tint(appearanceManager.tintColor)
                .stashyGroupedSettingsRow()
            }

            if !orderedTools.isEmpty {
                Section {
                    stashyScrollingSectionHeader("Tools")
                    ForEach(orderedTools) { tool in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Label(tool.id.plusFeatureTitle, systemImage: tool.id.icon)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(appearanceManager.tintColor)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { tool.isEnabled },
                                    set: { _ in tabManager.toggleTool(tool.id) }
                                ))
                                .labelsHidden()
                                .tint(appearanceManager.tintColor)
                            }
                        }
                        .padding(.vertical, 6)
                        .stashySettingsCardRow()
                    }
                    .onMove { indices, newOffset in
                        var working = orderedTools
                        working.move(fromOffsets: indices, toOffset: newOffset)
                        var rebuilt = working.enumerated().map { idx, item in
                            ToolsItemConfig(id: item.id, isEnabled: item.isEnabled, sortOrder: idx)
                        }
                        // Keep tools not shown here (currently Server under Settings → Actions).
                        for hidden in tabManager.tools where !rebuilt.contains(where: { $0.id == hidden.id }) {
                            rebuilt.append(
                                ToolsItemConfig(
                                    id: hidden.id,
                                    isEnabled: hidden.isEnabled,
                                    sortOrder: rebuilt.count
                                )
                            )
                        }
                        tabManager.tools = rebuilt
                        tabManager.saveTools()
                    }
                }
            }
        }
        .stashyMovableCardsList()
        .environment(\.editMode, .constant(.active))
        .deleteDisabled(true)
        .applyAppBackground()
        .stashySettingsDetailChrome("Tools")
        .onAppear { tabManager.repairMissingToolsIfNeeded() }
    }
}
#endif
