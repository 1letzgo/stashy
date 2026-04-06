//
//  SceneDelegate.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS) && !os(watchOS)
import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var blurView: UIVisualEffectView?
    var navigationCoordinator = NavigationCoordinator()

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
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        // Remove the UIKit blur when becoming active.
        // If locked, the SwiftUI PasscodeEntryView handles content protection from here.
        hideBlurOverlay()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
        // If autoLockOnBackground is enabled, blur background to protect content 
        if SecurityManager.shared.autoLockOnBackground && SecurityManager.shared.isPasscodeSet && !SecurityManager.shared.isPiPActive {
            showBlurOverlay()
        }
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

    private func showBlurOverlay() {
        guard blurView == nil, let window = window else { return }

        let style: UIBlurEffect.Style
        switch AppearanceManager.shared.preferredTheme {
        case .light:
            style = .light
        case .dark, .darkBlue:
            style = .dark
        case .system:
            style = .regular
        }

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: style))
        blur.frame = window.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(blur)
        self.blurView = blur
    }

    private func hideBlurOverlay() {
        guard blurView != nil else { return }
        blurView?.removeFromSuperview()
        blurView = nil
    }
}
#endif
