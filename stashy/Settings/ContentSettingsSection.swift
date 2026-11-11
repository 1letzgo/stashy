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
            stashyScrollingSectionHeader(tr("content_and_tabs"))
            NavigationLink(destination: DashboardSettingsView()) {
                Label(tr("dashboard"), systemImage: "uiwindow.split.2x1")
            }
            .stashyGroupedBlockRow(index: 0, count: rowCount)

            NavigationLink(destination: ReelsModeSettingsView()) {
                Label(tr("feeds"), systemImage: "play.rectangle.on.rectangle")
            }
            .stashyGroupedBlockRow(index: 1, count: rowCount)

            if stashyPlus.isUnlocked {
                NavigationLink(destination: ToolsSettingsView()) {
                    Label(tr("tools"), systemImage: "cube.box")
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
                stashyScrollingSectionHeader(tr("tab"))
                Toggle(isOn: Binding(
                    get: { toolsTabIsVisible },
                    set: { _ in tabManager.toggle(.tools) }
                )) {
                    Label(tr("action_show_tools_tab"), systemImage: "cube.box")
                }
                .tint(appearanceManager.tintColor)
                .stashyGroupedSettingsRow()

                // Order and per-tool visibility used to live here. The Tools landing groups the
                // tools into fixed categories, so their order is part of that layout now.
                stashyScrollingSectionFooter(tr("hint_tools_are_grouped_on_tools"))
            }

        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome(tr("tools"))
        .onAppear {
            tabManager.repairMissingToolsIfNeeded()
        }
    }
}
#endif
