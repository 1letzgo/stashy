//
//  TVMainTabView.swift
//  stashyTV
//
//  Standard tvOS top-tab navigation using the Tab API (tvOS 18+).
//  Each tab gets its own NavigationStack with all destinations registered
//  at the stack root via withTVDestinations().
//

import SwiftUI

/// tvOS-Tab-Layout. Reihenfolge ist fix (Apple-Konventionen oben links/oben Mitte),
/// aber jeder inhaltliche Tab kann via `TabManager.tabs` ausgeblendet werden.
/// Search + Settings sind tvOS-fixe Tabs, die immer sichtbar bleiben.
struct TVMainTabView: View {
    @ObservedObject private var tabManager = TabManager.shared

    private func isVisible(_ tab: AppTab) -> Bool {
        // Wenn der Tab gar nicht im TabManager registriert ist, betrachten wir ihn als sichtbar
        // (z. B. weil die iOS-Konfiguration ihn nicht kennt). Sonst dem User-Wunsch folgen.
        if let entry = tabManager.tabs.first(where: { $0.id == tab }) {
            return entry.isVisible
        }
        return true
    }

    var body: some View {
        TabView {
            if isVisible(.catalogue) {
                Tab("Home", systemImage: "house.fill") {
                    NavigationStack { TVDashboardView() }
                        .withTVDestinations()
                }
            }
            if isVisible(.scenes) {
                Tab("Scenes", systemImage: "film.fill") {
                    NavigationStack { TVScenesView() }
                        .withTVDestinations()
                }
            }
            if isVisible(.performers) {
                Tab("Performers", systemImage: "person.3.fill") {
                    NavigationStack { TVPerformersView() }
                        .withTVDestinations()
                }
            }
            if isVisible(.studios) {
                Tab("Studios", systemImage: "building.2.fill") {
                    NavigationStack { TVStudiosView() }
                        .withTVDestinations()
                }
            }
            if isVisible(.tags) {
                Tab("Tags", systemImage: "tag.fill") {
                    NavigationStack { TVTagsView() }
                        .withTVDestinations()
                }
            }
            if isVisible(.groups) {
                Tab("Groups", systemImage: "rectangle.stack.fill") {
                    NavigationStack { TVGroupsView() }
                        .withTVDestinations()
                }
            }
            Tab("Search", systemImage: "magnifyingglass") {
                NavigationStack { TVSearchView() }
                    .withTVDestinations()
            }

            Tab("Settings", systemImage: "gear") {
                NavigationStack { TVSettingsView() }
                    .withTVDestinations()
            }
        }
    }
}
