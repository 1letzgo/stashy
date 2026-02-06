//
//  DashboardSettingsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

import SwiftUI

struct DashboardSettingsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        List {
            Section {
                ForEach(tabManager.homeRows) { row in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { row.isEnabled },
                            set: { _ in tabManager.toggleHomeRow(row.id) }
                        )) {
                            VStack(alignment: .leading) {
                                Text(row.title)
                            }
                        }
                        .tint(appearanceManager.tintColor)
                    }
                }
                .onMove { indices, newOffset in
                    tabManager.moveHomeRow(from: indices, to: newOffset)
                }
            } header: {
                Text("Dashboard Rows")
            } footer: {
                Text("Enable and reorder the rows shown on the Dashboard.")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Dashboard Settings")
    }
}
