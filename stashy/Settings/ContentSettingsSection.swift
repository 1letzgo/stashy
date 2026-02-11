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
#endif
