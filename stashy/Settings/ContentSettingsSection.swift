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

                // Order and per-tool visibility used to live here. The Tools landing groups the
                // tools into fixed categories, so their order is part of that layout now.
                stashyScrollingSectionFooter("Tools are grouped on the Tools page.")
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome("Tools")
        .onAppear { tabManager.repairMissingToolsIfNeeded() }
    }
}
#endif
