//
//  DashboardSettingsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI

struct DashboardSettingsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        List {
            Section {
                ForEach(tabManager.homeRows) { row in
                    Toggle(isOn: Binding(
                        get: { row.isEnabled },
                        set: { _ in tabManager.toggleHomeRow(row.id) }
                    )) {
                        Text(row.title)
                    }
                    .tint(appearanceManager.tintColor)
                }
                .onMove { indices, newOffset in
                    tabManager.moveHomeRow(from: indices, to: newOffset)
                }
            } header: {
                Text("Dashboard Rows")
            } footer: {
                Text("Enable and reorder the rows shown on the Dashboard.")
            }

            Section {
                // Anchored Dashboard item
                if let dashTab = tabManager.tabs.first(where: { $0.id == .dashboard }) {
                    HStack {
                        Text(dashTab.id.title)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("Always Visible")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                ForEach(tabManager.tabs.filter { 
                    $0.id == .scenes || $0.id == .galleries || $0.id == .performers || 
                    $0.id == .studios || $0.id == .tags || $0.id == .images
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
            } header: {
                Text("Statistic Card & Menu")
            } footer: {
                Text("Reorder cards. Dashboard is anchored at the top.")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Dashboard Settings")
    }
}
#endif
