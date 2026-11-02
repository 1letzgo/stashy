//
//  StashyMacApp.swift
//  stashyMac
//

import SwiftUI

@main
struct StashyMacApp: App {
    @StateObject private var navigationCoordinator = NavigationCoordinator()

    init() {
        _ = Self.debugObservers
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
                .onAppear(perform: Self.applyLaunchWindowSize)
                .onAppear(perform: Self.debugFullscreenCycleIfRequested)
        }
        .windowToolbarStyle(.unified)
        .commands {
            StashyMacCommands(coordinator: navigationCoordinator)
        }
    }
}

extension StashyMacApp {
    // TEMP diagnostics: logs every window / app state change to ~/Downloads/stashy-fs.log.
    static let debugObservers: [NSObjectProtocol] = {
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("stashy-fs.log")
        func dump(_ tag: String) {
            var out = "\(Date()) \(tag) hidden=\(NSApp.isHidden) active=\(NSApp.isActive) windows=\(NSApp.windows.count)\n"
            for w in NSApp.windows {
                out += "   visible=\(w.isVisible) mini=\(w.isMiniaturized) onSpace=\(w.isOnActiveSpace) key=\(w.isKeyWindow) fs=\(w.styleMask.contains(.fullScreen)) frame=\(NSStringFromRect(w.frame)) screen=\(w.screen?.localizedName ?? "nil") alpha=\(w.alphaValue) class=\(type(of: w))\n"
            }
            let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (old + out).write(to: url, atomically: true, encoding: .utf8)
        }
        let c = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification,
            NSWindow.willExitFullScreenNotification, NSWindow.didExitFullScreenNotification,
            NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification,
            NSWindow.didChangeScreenNotification, NSWindow.didChangeOcclusionStateNotification,
            NSApplication.didHideNotification, NSApplication.didResignActiveNotification,
            NSApplication.didBecomeActiveNotification,
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { dump("launch") }
        return names.map { name in
            c.addObserver(forName: name, object: nil, queue: .main) { note in
                dump("\(name.rawValue) obj=\(type(of: note.object as Any))")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { dump("  +1s after \(name.rawValue)") }
            }
        }
    }()

    // TEMP diagnostics: -StashyDebugFullscreenCycle YES enters and leaves macOS full screen
    // and logs the window state afterwards.
    static func debugFullscreenCycleIfRequested() {
        guard UserDefaults.standard.bool(forKey: "StashyDebugFullscreenCycle") else { return }
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("stashy-fs.log")
        func dump(_ tag: String) {
            var out = "\(tag) hidden=\(NSApp.isHidden) active=\(NSApp.isActive) windows=\(NSApp.windows.count)\n"
            for w in NSApp.windows {
                out += "   title=\(w.title) visible=\(w.isVisible) mini=\(w.isMiniaturized) onSpace=\(w.isOnActiveSpace) key=\(w.isKeyWindow) fs=\(w.styleMask.contains(.fullScreen)) frame=\(NSStringFromRect(w.frame)) alpha=\(w.alphaValue) class=\(type(of: w))\n"
            }
            let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (old + out).write(to: url, atomically: true, encoding: .utf8)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            dump("before")
            NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })?.toggleFullScreen(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                dump("in-fullscreen")
                NSApp.windows.first(where: { $0.styleMask.contains(.fullScreen) })?.toggleFullScreen(nil)
                for delay in [1.0, 3.0, 6.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { dump("after+\(delay)") }
                }
            }
        }
    }

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
