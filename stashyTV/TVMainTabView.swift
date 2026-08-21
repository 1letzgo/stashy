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

private struct TVContentTab: Identifiable {
    let id: TVRootTab
    let appTab: AppTab
    let title: String
    let systemImage: String
}

/// tvOS-Tab-Layout. Reihenfolge ist fix (Apple-Konventionen oben links/oben Mitte),
/// aber jeder inhaltliche Tab kann via `TabManager.tabs` ausgeblendet werden.
/// Search + Settings sind tvOS-fixe Tabs, die immer sichtbar bleiben.
struct TVMainTabView: View {
    @ObservedObject private var tabManager = TabManager.shared
    @State private var selectedTab: TVRootTab = .home

    private let allContentTabs: [TVContentTab] = [
        TVContentTab(id: .home, appTab: .catalogue, title: "Home", systemImage: "house.fill"),
        TVContentTab(id: .scenes, appTab: .scenes, title: "Scenes", systemImage: "film.fill"),
        TVContentTab(id: .performers, appTab: .performers, title: "Performers", systemImage: "person.3.fill"),
        TVContentTab(id: .studios, appTab: .studios, title: "Studios", systemImage: "building.2.fill"),
        TVContentTab(id: .tags, appTab: .tags, title: "Tags", systemImage: "tag.fill"),
        TVContentTab(id: .groups, appTab: .groups, title: "Groups", systemImage: "rectangle.stack.fill"),
        TVContentTab(id: .galleries, appTab: .galleries, title: "Galleries", systemImage: "photo.stack.fill"),
        TVContentTab(id: .images, appTab: .images, title: "Images", systemImage: "photo.fill")
    ]

    private func isVisible(_ tab: AppTab) -> Bool {
        // Home (catalogue) always stays on tvOS top bar — iOS sub-tab visibility must not hide it.
        if tab == .catalogue { return true }
        if let entry = tabManager.tabs.first(where: { $0.id == tab }) {
            return entry.isVisible
        }
        return true
    }

    private var visibleContentTabs: [TVContentTab] {
        allContentTabs.filter { isVisible($0.appTab) }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(visibleContentTabs) { item in
                Tab(item.title, systemImage: item.systemImage, value: item.id) {
                    tabContent(item.id)
                }
            }
            // Settings stays ahead of the search-role tab: tvOS pins that role to the
            // trailing edge, which pushed Settings out of the visible top bar.
            Tab("Settings", systemImage: "gear", value: TVRootTab.settings) {
                TVTabStack { TVSettingsView() }
            }
            Tab("Search", systemImage: "magnifyingglass", value: TVRootTab.search, role: .search) {
                TVTabStack { TVSearchView() }
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: TVRootTab) -> some View {
        switch tab {
        case .home:
            TVTabStack { TVDashboardView() }
        case .scenes:
            TVTabStack { TVScenesView() }
        case .performers:
            TVTabStack { TVPerformersView() }
        case .studios:
            TVTabStack { TVStudiosView() }
        case .tags:
            TVTabStack { TVTagsView() }
        case .groups:
            TVTabStack { TVGroupsView() }
        case .galleries:
            TVTabStack { TVGalleriesView() }
        case .images:
            TVTabStack { TVImagesView() }
        case .search, .settings:
            EmptyView()
        }
    }
}
