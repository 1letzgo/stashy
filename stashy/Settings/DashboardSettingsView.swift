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
                Toggle("Compact Statistics", isOn: Binding(
                    get: { tabManager.useCompactStatistics },
                    set: { tabManager.useCompactStatistics = $0 }
                ))
                .tint(appearanceManager.tintColor)
            } footer: {
                Text("Show statistics as a single compact card with a 2-column layout instead of a horizontal scrolling row.")
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section {
                Toggle("Big Hero Layout", isOn: Binding(
                    get: { tabManager.dashboardHeroSize == .big },
                    set: { tabManager.dashboardHeroSize = $0 ? .big : .small }
                ))
                .tint(appearanceManager.tintColor)
            } footer: {
                Text("Enable Big Hero to show one item at a time with full-width paging. If disabled, a standard carousel will be shown.")
            }
            .listRowBackground(Color.secondaryAppBackground)
            
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
            } footer: {
                Text("Enable and reorder the rows shown on the Dashboard.")
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Dashboard")
        .applyAppBackground()
    }
}
#endif
