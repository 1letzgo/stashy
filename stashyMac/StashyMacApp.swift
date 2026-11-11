//
//  StashyMacApp.swift
//  stashyMac
//

import SwiftUI

@main
struct StashyMacApp: App {
    @StateObject private var navigationCoordinator = NavigationCoordinator()

    init() {
        // English by default (beta); a language picked on iPhone / Mac applies from the next start.
        AppLanguage.applyPreferredLanguages()
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
            LanguageRefreshing {
                MainTabView()
            }
                .macFullScreenCoverHost()
                .environmentObject(navigationCoordinator)
                .macIOSLikeControlStyles()
                .frame(minWidth: 900, minHeight: 600)
                .onAppear(perform: Self.applyLaunchWindowSize)
                // Auto-lock on Background: Cmd-H / hide others. Not on mere resign-active, which
                // fires on every click into another app's window.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in
                    SecurityManager.shared.lockIfAutoLockOnBackground()
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            StashyMacCommands(coordinator: navigationCoordinator)
        }
    }
}

extension StashyMacApp {
    /// `-StashyWindowSize 1440x900` (launch argument): exact window size in points, e.g. for
    /// App Store screenshots (2880×1800 on a Retina display).
    static func applyLaunchWindowSize() {
        guard let value = UserDefaults.standard.string(forKey: "StashyWindowSize") else { return }
        let parts = value.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return }
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            var frame = window.frame
            frame.origin.y += frame.height - parts[1]
            frame.size = NSSize(width: parts[0], height: parts[1])
            window.setFrame(frame, display: true)
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
            Button(tr("settings_menu")) { coordinator.selectedTab = .settings }
                .keyboardShortcut(",")
        }
        CommandGroup(after: .textEditing) {
            Button(tr("search")) { coordinator.selectedTab = .search }
                .keyboardShortcut("f")
        }
        CommandMenu(tr("action_go")) {
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
