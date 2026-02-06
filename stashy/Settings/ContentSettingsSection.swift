//
//  ContentSettingsSection.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

import SwiftUI

struct ContentSettingsSection: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared

    // Sub-tabs that the user can reorder within the Catalogs tab
    private var catalogueSubTabs: [TabConfig] {
        tabManager.tabs
            .filter { $0.id == .performers || $0.id == .studios || $0.id == .tags || $0.id == .scenes || $0.id == .galleries }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Section("Content & Tabs") {
            NavigationLink(destination: DashboardSettingsView()) {
                Label("Configure Dashboard", systemImage: "uiwindow.split.2x1")
            }

            NavigationLink(destination: ReelsModeSettingsView()) {
                Label("Configure StashTok", systemImage: "slider.horizontal.3")
            }
        }

        Section("Tab Visibility") {
            tabToggle(for: .reels)
            tabToggle(for: .downloads)
        }

        Section(header: Text("Home Content Order"), footer: Text("Reorder the tabs shown in the Home screen. Dashboard is always first.")) {
            // Fixed Dashboard Row - always visible and at top
            HStack {
                Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.icon)
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            ForEach(catalogueSubTabs) { tab in
                HStack {
                    Label(tab.id.title, systemImage: tab.id.icon)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { tab.isVisible },
                        set: { _ in tabManager.toggle(tab.id) }
                    ))
                    .labelsHidden()
                    .tint(appearanceManager.tintColor)
                }
            }
            .onMove { indices, newOffset in
                tabManager.moveSubTab(from: indices, to: newOffset, within: .catalogue)
            }
        }
    }

    @ViewBuilder
    private func tabToggle(for tabId: AppTab) -> some View {
        if let config = tabManager.tabs.first(where: { $0.id == tabId }) {
            Toggle(isOn: Binding(
                get: { config.isVisible },
                set: { _ in tabManager.toggle(tabId) }
            )) {
                Label(tabId.title, systemImage: tabId.icon)
            }
            .tint(appearanceManager.tintColor)
        }
    }
}
