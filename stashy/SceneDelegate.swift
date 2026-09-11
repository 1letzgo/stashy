//
//  SceneDelegate.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS) && !os(watchOS)
import UIKit
import SwiftUI
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    var navigationCoordinator = NavigationCoordinator()
    private var privacyBlurView: UIVisualEffectView?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).

        // Create the SwiftUI view that provides the window contents.
        let contentView = MainTabView()
            .environmentObject(navigationCoordinator)

        // Use a UIHostingController as window root view controller.
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: contentView)
            self.window = window
            window.makeKeyAndVisible()
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        privacyBlurView?.removeFromSuperview()
        privacyBlurView = nil
    }

    /// Set while a system picker (AirPlay routes) is up: presenting it resigns the app
    /// active, but it belongs to the app's own flow — covering the player with the
    /// privacy blur there is wrong.
    static var suppressesPrivacyBlur = false

    func sceneWillResignActive(_ scene: UIScene) {
        guard !Self.suppressesPrivacyBlur else { return }
        guard privacyBlurView == nil, let window else { return }
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        blur.frame = window.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let bgColor = UIColor(Color.appBackground)
        let tintOverlay = UIView(frame: blur.bounds)
        tintOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tintOverlay.backgroundColor = bgColor
        blur.contentView.addSubview(tintOverlay)
        window.addSubview(blur)
        privacyBlurView = blur
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        if SecurityManager.shared.autoLockOnBackground && !SecurityManager.shared.isPiPActive {
            SecurityManager.shared.lock()
        }
    }
}
#endif

