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
                Label("Dashboard", systemImage: "uiwindow.split.2x1")
            }

            NavigationLink(destination: ReelsModeSettingsView()) {
                Label("StashTok", systemImage: "play.rectangle.on.rectangle")
            }

            NavigationLink(destination: TabSettingsView()) {
                Label("Tabs", systemImage: "square.grid.2x2")
            }
        }
        .listRowBackground(Color.secondaryAppBackground)
    }
}

struct TabSettingsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        List {
            Section {
                // Anchored Dashboard item
                if let dashTab = tabManager.tabs.first(where: { $0.id == .dashboard }) {
                    HStack {
                        Text(dashTab.id.title)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("Always Visible")
                            .font(.caption)
                    }
                }

                ForEach(tabManager.tabs.filter { 
                    $0.id == .scenes || $0.id == .galleries || $0.id == .performers || 
                    $0.id == .studios || $0.id == .tags || $0.id == .images || 
                    $0.id == .groups
                }.sorted { $0.sortOrder < $1.sortOrder }) { tab in
                    Toggle(isOn: Binding(
                        get: { tab.isVisible },
                        set: { _ in tabManager.toggle(tab.id) }
                    )) {
                        Text(tab.id.title)
                    }
                    .tint(appearanceManager.tintColor)
                }
                .onMove { indices, newOffset in
                    // Adjust indices because .dashboard is at index 0 but excluded from ForEach
                    var adjustedIndices = IndexSet()
                    for index in indices {
                        adjustedIndices.insert(index + 1)
                    }
                    tabManager.moveSubTab(from: adjustedIndices, to: newOffset + 1, within: .catalogue)
                }
            } footer: {
                Text("Reorder cards and toggle visibility. Dashboard is anchored at the top.")
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Tabs")
        .applyAppBackground()
        .scrollContentBackground(.hidden)
    }
}
#endif
