//
//  StashyMacApp.swift
//  stashyMac
//

import SwiftUI

@main
struct StashyMacApp: App {
    @StateObject private var navigationCoordinator = NavigationCoordinator()

    init() {
        // Entitlements (lifetime IAP, paid-app grandfathering) must sync at launch,
        // not only when Settings is opened.
        _ = StoreManager.shared
        // The statistics manager listens for the server-ready notification to refresh
        // stale tag statistics; a lazy singleton nobody touches before that misses it.
        _ = AITagSuggestionManager.shared
        #if canImport(AetherEngine)
        AetherPlaybackBootstrap.installOnce()
        #endif
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            MainTabView()
                .macFullScreenCoverHost()
                .environmentObject(navigationCoordinator)
                .macIOSLikeControlStyles()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .commands {
            StashyMacCommands(coordinator: navigationCoordinator)
        }
    }
}

/// Menu bar: Settings (⌘,) and search (⌘F) jump to their tabs, the Go menu lists the
/// visible tabs with ⌘1…⌘9 — the same order as the sidebar.
private struct StashyMacCommands: Commands {
    @ObservedObject var coordinator: NavigationCoordinator
    @ObservedObject private var tabManager = TabManager.shared

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { coordinator.selectedTab = .settings }
                .keyboardShortcut(",")
        }
        CommandGroup(after: .textEditing) {
            Button("Search") { coordinator.selectedTab = .search }
                .keyboardShortcut("f")
        }
        CommandMenu("Go") {
            ForEach(Array(tabManager.visibleTabs.enumerated()), id: \.element) { index, tab in
                if index < 9 {
                    Button(tab.title) { coordinator.selectedTab = tab }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                } else {
                    Button(tab.title) { coordinator.selectedTab = tab }
                }
            }
        }
    }
}
