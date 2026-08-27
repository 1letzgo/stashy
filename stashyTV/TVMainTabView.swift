//
//  TVMainTabView.swift
//  stashyTV
//
//  Sidebar-Navigation (tvOS 18+). `.sidebarAdaptable` heißt auf iPadOS
//  „Leiste, die zur Sidebar werden kann" — auf tvOS ist es laut Apples eigener
//  Doku immer eine Sidebar, wie bei Apple TV, Netflix und Disney+.
//
//  Jeder Eintrag bekommt seinen eigenen NavigationStack; die Pfade liegen im
//  `TVNavigationStore` außerhalb des View-Baums (siehe TVNavigationTypes).
//

import SwiftUI

private struct TVContentTab: Identifiable {
    let id: TVRootTab
    let appTab: AppTab
    let title: String
    let systemImage: String
}

struct TVMainTabView: View {
    @ObservedObject private var tabManager = TabManager.shared
    /// Bewusst `@State`, nicht `@StateObject`: die View soll den Store **besitzen**,
    /// ihn aber nicht beobachten. Als `@StateObject` löste jeder Navigations-Push
    /// ein Neuzeichnen der gesamten TabView samt Sidebar aus — Pushes kamen dann
    /// gar nicht erst an. Beobachtet wird er nur dort, wo er gebraucht wird:
    /// im jeweiligen `TVTabStack`.
    @State private var navigationStore = TVNavigationStore()
    @State private var selectedTab: TVRootTab = .home

    /// Rückfalltür auf die alte obere Leiste. Das Sidebar-Verhalten lässt sich
    /// ohne Gerät nicht verifizieren — bleibt sie unbrauchbar, kommt der Nutzer
    /// hierüber zurück, ohne dass neu gebaut werden muss.
    @AppStorage("tvUseSidebar") private var useSidebar = true

    /// Home ist ein eigener Eintrag über der Library-Sektion.
    private let homeTab = TVContentTab(
        id: .home, appTab: .catalogue, title: "Home", systemImage: "house.fill"
    )

    /// Inhaltliche Bereiche, gruppiert unter „Library".
    private let libraryTabs: [TVContentTab] = [
        TVContentTab(id: .scenes, appTab: .scenes, title: "Scenes", systemImage: "film.fill"),
        TVContentTab(id: .performers, appTab: .performers, title: "Performers", systemImage: "person.3.fill"),
        TVContentTab(id: .studios, appTab: .studios, title: "Studios", systemImage: "building.2.fill"),
        TVContentTab(id: .tags, appTab: .tags, title: "Tags", systemImage: "tag.fill"),
        TVContentTab(id: .groups, appTab: .groups, title: "Groups", systemImage: "rectangle.stack.fill"),
        TVContentTab(id: .galleries, appTab: .galleries, title: "Galleries", systemImage: "photo.stack.fill"),
        TVContentTab(id: .images, appTab: .images, title: "Images", systemImage: "photo.fill")
    ]

    private func isVisible(_ tab: AppTab) -> Bool {
        // Home (catalogue) bleibt immer sichtbar — die iOS-Sub-Tab-Sichtbarkeit
        // darf es nicht ausblenden.
        if tab == .catalogue { return true }
        if let entry = tabManager.tabs.first(where: { $0.id == tab }) {
            return entry.isVisible
        }
        return true
    }

    private var visibleLibraryTabs: [TVContentTab] {
        libraryTabs.filter { isVisible($0.appTab) }
    }

    /// Erneutes Wählen des aktiven Eintrags springt zurück zur Wurzel — das
    /// gewohnte Sidebar-Verhalten.
    private var tabSelection: Binding<TVRootTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    navigationStore.popToRoot(newValue)
                } else {
                    selectedTab = newValue
                }
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            // Search zuerst: pinnt tvOS die Search-Rolle an den Kopf der
            // Sidebar, passt es; pinnt es sie nicht, steht sie durch die
            // Reihenfolge trotzdem oben. Der frühere Zwang, Settings *vor*
            // Search zu deklarieren, galt nur für die obere Leiste, wo die
            // Rolle an den rechten Rand gepinnt wurde.
            Tab("Search", systemImage: "magnifyingglass", value: TVRootTab.search, role: .search) {
                TVTabStack(tab: .search) { TVSearchView() }
            }

            Tab(homeTab.title, systemImage: homeTab.systemImage, value: homeTab.id) {
                TVTabStack(tab: .home) { TVDashboardView() }
            }

            // Ohne die Prüfung entstünde bei komplett ausgeblendeter Library
            // eine Sektion mit Überschrift und ohne Zeilen.
            if !visibleLibraryTabs.isEmpty {
                TabSection("Library") {
                    ForEach(visibleLibraryTabs) { item in
                        Tab(item.title, systemImage: item.systemImage, value: item.id) {
                            tabContent(item.id)
                        }
                    }
                }
            }

            // Settings zuletzt. Einen Footer-Slot gibt es auf tvOS nicht
            // (`tabViewSidebarFooter` ist dort nicht verfügbar), die
            // Deklarationsreihenfolge ist der einzige Hebel.
            Tab("Settings", systemImage: "gear", value: TVRootTab.settings) {
                TVTabStack(tab: .settings) { TVSettingsView() }
            }
        }
        .modifier(TVTabPresentationStyle(sidebar: useSidebar))
        .environmentObject(navigationStore)
        .onChange(of: tabManager.tabs) { _, _ in
            // Blendet der Nutzer den gerade aktiven Bereich aus, zeigt der
            // Inhaltsbereich sonst nichts mehr an.
            var live: Set<TVRootTab> = [.home, .search, .settings]
            live.formUnion(visibleLibraryTabs.map(\.id))
            if !live.contains(selectedTab) {
                selectedTab = .home
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: TVRootTab) -> some View {
        switch tab {
        case .scenes:
            TVTabStack(tab: .scenes) { TVScenesView() }
        case .performers:
            TVTabStack(tab: .performers) { TVPerformersView() }
        case .studios:
            TVTabStack(tab: .studios) { TVStudiosView() }
        case .tags:
            TVTabStack(tab: .tags) { TVTagsView() }
        case .groups:
            TVTabStack(tab: .groups) { TVGroupsView() }
        case .galleries:
            TVTabStack(tab: .galleries) { TVGalleriesView() }
        case .images:
            TVTabStack(tab: .images) { TVImagesView() }
        case .home, .search, .settings:
            // Diese drei werden oben direkt deklariert.
            EmptyView()
        }
    }
}

/// Sidebar oder klassische obere Leiste. `.tabBarOnly` ist Apples dokumentierte
/// Rückfalltür; im Fallback stimmt die Deklarationsreihenfolge für eine obere
/// Leiste nicht mehr ganz (Search wird wieder nach rechts gepinnt), das ist
/// kosmetisch schief, aber funktionsfähig.
private struct TVTabPresentationStyle: ViewModifier {
    let sidebar: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if sidebar {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content.tabViewStyle(.tabBarOnly)
        }
    }
}
