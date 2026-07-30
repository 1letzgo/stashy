//
//  TVMainTabView.swift
//  stashyTV
//
//  Standard tvOS top-tab navigation using the Tab API (tvOS 18+).
//  Each tab gets its own NavigationStack with all destinations registered
//  at the stack root via withTVDestinations().
//

import SwiftUI

private enum TVRootTab: Hashable {
    case home, scenes, performers, studios, tags, groups, galleries, images, search, settings
}

/// tvOS-Tab-Layout. Reihenfolge ist fix (Apple-Konventionen oben links/oben Mitte),
/// aber jeder inhaltliche Tab kann via `TabManager.tabs` ausgeblendet werden.
/// Search + Settings sind tvOS-fixe Tabs, die immer sichtbar bleiben.
struct TVMainTabView: View {
    @ObservedObject private var tabManager = TabManager.shared
    @State private var selectedTab: TVRootTab = .home

    private func isVisible(_ tab: AppTab) -> Bool {
        // Home (catalogue) always stays on tvOS top bar — iOS sub-tab visibility must not hide it.
        if tab == .catalogue { return true }
        if let entry = tabManager.tabs.first(where: { $0.id == tab }) {
            return entry.isVisible
        }
        return true
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            if isVisible(.catalogue) {
                Tab("Home", systemImage: "house.fill", value: TVRootTab.home) {
                    TVTabStack { TVDashboardView() }
                }
            }
            if isVisible(.scenes) {
                Tab("Scenes", systemImage: "film.fill", value: TVRootTab.scenes) {
                    TVTabStack { TVScenesView() }
                }
            }
            if isVisible(.performers) {
                Tab("Performers", systemImage: "person.3.fill", value: TVRootTab.performers) {
                    TVTabStack { TVPerformersView() }
                }
            }
            if isVisible(.studios) {
                Tab("Studios", systemImage: "building.2.fill", value: TVRootTab.studios) {
                    TVTabStack { TVStudiosView() }
                }
            }
            if isVisible(.tags) {
                Tab("Tags", systemImage: "tag.fill", value: TVRootTab.tags) {
                    TVTabStack { TVTagsView() }
                }
            }
            if isVisible(.groups) {
                Tab("Groups", systemImage: "rectangle.stack.fill", value: TVRootTab.groups) {
                    TVTabStack { TVGroupsView() }
                }
            }
            if isVisible(.galleries) {
                Tab("Galleries", systemImage: "photo.stack.fill", value: TVRootTab.galleries) {
                    TVTabStack { TVGalleriesView() }
                }
            }
            if isVisible(.images) {
                Tab("Images", systemImage: "photo.fill", value: TVRootTab.images) {
                    TVTabStack { TVImagesView() }
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: TVRootTab.search, role: .search) {
                TVTabStack { TVSearchView() }
            }

            Tab("Settings", systemImage: "gear", value: TVRootTab.settings) {
                TVTabStack { TVSettingsView() }
            }
        }
    }
}
