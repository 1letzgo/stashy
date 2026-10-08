//
//  AppDelegate.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS) && !os(watchOS)
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var backgroundSessionCompletionHandler: (() -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        _ = AppIconManager.shared
        // "Done" above every keyboard (SwiftUI's keyboard toolbar was unreliable).
        KeyboardDoneAccessory.shared.install()
        // Entitlements (lifetime IAP, paid-app grandfathering) must sync at launch,
        // not only when Settings is opened.
        _ = StoreManager.shared
        // The statistics manager listens for the server-ready notification to refresh
        // stale tag statistics; a lazy singleton nobody touches before that misses it.
        _ = AITagSuggestionManager.shared
        #if !os(tvOS) && canImport(AetherEngine)
        AetherPlaybackBootstrap.installOnce()
        #endif
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        backgroundSessionCompletionHandler = completionHandler
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    /// Orientations the app allows right now. `.all` normally; the fullscreen player narrows it
    /// to landscape for a moment so a programmatic rotation takes, then restores it (keeping it
    /// narrowed crashed UIKit with a sheet + keyboard in landscape).
    static var orientationLock: UIInterfaceOrientationMask = .all

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}
#endif
