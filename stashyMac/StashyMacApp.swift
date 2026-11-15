//
//  StashyMacApp.swift
//  stashyMac
//

import SwiftUI
import AppKit

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
        // Reads the passcode now: with one set the app is locked before the first frame.
        _ = SecurityManager.shared
        MacAppLockMonitor.shared.start()
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            LanguageRefreshing {
                MainTabView()
            }
                .macFullScreenCoverHost()
                // Above the cover host, so the player and image covers stay under it too.
                .modifier(MacAppLockOverlay())
                .environmentObject(navigationCoordinator)
                .macIOSLikeControlStyles()
                .frame(minWidth: 900, minHeight: 600)
                .onAppear(perform: Self.applyLaunchWindowSize)
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

// MARK: - App lock

/// The passcode screen over the whole window: sidebar, page, full-screen covers. Every window
/// of the app carries its own, so a second window (⌘N) is locked too. Drawn from the first
/// frame: `SecurityManager` locks in its init when a passcode is stored.
private struct MacAppLockOverlay: ViewModifier {
    @ObservedObject private var security = SecurityManager.shared

    /// `-stashyDebugShowLock YES` (DEBUG): shows the passcode screen for layout checks.
    private var locked: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "stashyDebugShowLock") { return true }
        #endif
        return security.isAppLocked
    }

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(locked)
            .overlay {
                if locked {
                    PasscodeEntryView()
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .animation(.snappy(duration: 0.3, extraBounce: 0), value: locked)
    }
}

/// When the Mac app locks. At launch `SecurityManager` does it; with "Auto-Lock on Background"
/// also whenever the app leaves the screen: hidden (⌘H, Hide Others), the Mac sleeps or its
/// screen sleeps / locks, a user switch, or the last window is closed or minimized (the app
/// keeps running; Dock and ⌘N open a new window). Not on resign-active, which fires on every
/// click into another app's window. A running PiP window keeps the app unlocked, as on iOS.
@MainActor
final class MacAppLockMonitor {
    static let shared = MacAppLockMonitor()
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        guard tokens.isEmpty else { return }
        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observe(app, NSApplication.didHideNotification)
        observe(workspace, NSWorkspace.willSleepNotification)
        observe(workspace, NSWorkspace.screensDidSleepNotification)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification)
        observe(distributed, Notification.Name("com.apple.screenIsLocked"))

        // Minimizing: lock before the Dock takes its snapshot of the window.
        observe(app, NSWindow.willMiniaturizeNotification) { note in
            Self.lockIfNoWindowLeft(besides: note.object as? NSWindow)
        }
        observe(app, NSWindow.willCloseNotification) { note in
            Self.lockIfNoWindowLeft(besides: note.object as? NSWindow)
        }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ handler: @escaping @MainActor (Notification) -> Void = { _ in MacAppLockMonitor.lockForBackground() }
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { handler(note) }
        }
        tokens.append((center, token))
    }

    private static func lockForBackground() {
        SecurityManager.shared.lockIfAutoLockOnBackground()
    }

    /// `leaving` is still on screen while its close / minimize notification runs.
    private static func lockIfNoWindowLeft(besides leaving: NSWindow?) {
        guard let leaving, isContentWindow(leaving) else { return }
        let others = NSApp.windows.filter { $0 !== leaving && isContentWindow($0) }
        guard others.isEmpty else { return }
        lockForBackground()
        // Render the passcode screen into the window now, before the minimize animation
        // captures it for the Dock.
        if SecurityManager.shared.isAppLocked {
            leaving.contentView?.layoutSubtreeIfNeeded()
            leaving.displayIfNeeded()
            CATransaction.flush()
        }
    }

    /// An app window on screen: not a sheet, panel, popover, menu or minimized window.
    private static func isContentWindow(_ window: NSWindow) -> Bool {
        window.isVisible && !window.isMiniaturized && window.sheetParent == nil
            && !(window is NSPanel) && window.canBecomeMain
    }
}

/// Menu bar: Settings (⌘,) and search (⌘F) jump to their tabs, the Go menu lists the
/// visible tabs with ⌘1…⌘9 — the same order as the sidebar.
private struct StashyMacCommands: Commands {
    @ObservedObject var coordinator: NavigationCoordinator
    @ObservedObject private var tabManager = TabManager.shared
    /// Under the passcode screen the menu must not move the app around behind it.
    @ObservedObject private var security = SecurityManager.shared

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(tr("settings_menu")) { coordinator.selectedTab = .settings }
                .keyboardShortcut(",")
                .disabled(security.isAppLocked)
        }
        CommandGroup(after: .textEditing) {
            Button(tr("search")) { coordinator.selectedTab = .search }
                .keyboardShortcut("f")
                .disabled(security.isAppLocked)
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
            .disabled(security.isAppLocked)
        }
    }
}
