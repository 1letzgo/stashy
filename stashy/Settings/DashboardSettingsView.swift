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
            Section("Dashboard Configuration") {
                Toggle("Show Hero Background", isOn: Binding(
                    get: { tabManager.showDashboardHeroBackground },
                    set: { tabManager.showDashboardHeroBackground = $0 }
                ))
                .tint(appearanceManager.tintColor)

                Toggle("Compact Statistics", isOn: Binding(
                    get: { tabManager.useCompactStatistics },
                    set: { tabManager.useCompactStatistics = $0 }
                ))
                .tint(appearanceManager.tintColor)

                Toggle("Colored Statistics", isOn: Binding(
                    get: { tabManager.useColoredStatistics },
                    set: { tabManager.useColoredStatistics = $0 }
                ))
                .tint(appearanceManager.tintColor)
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section("Visible Dashboard Rows") {
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
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .applyAppBackground()
        .stashySettingsDetailChrome("Dashboard")
    }
}
#endif
