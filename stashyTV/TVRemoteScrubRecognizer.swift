//
//  TVRemoteScrubRecognizer.swift
//  stashyTV
//
//  Free scrubbing on the Siri Remote's touch surface, like Apple's player: a horizontal pan
//  moves the playhead continuously. SwiftUI only sees swipes as discrete move commands (the
//  10 s steps), so the pan goes through UIKit: an observer on the window, which receives the
//  indirect touches no matter which SwiftUI element holds focus.
//
//  It never recognizes in a way that blocks anything: the focus engine and SwiftUI keep their
//  own handling, and the player ignores the move command a swipe also produces while (or right
//  after) this pan reported it.
//

import SwiftUI
import UIKit

struct TVRemoteScrubRecognizer: UIViewRepresentable {
    var isEnabled: Bool = true
    var onBegan: () -> Void
    /// Horizontal translation since the pan began, in touch-surface points.
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        update(context.coordinator)
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        update(context.coordinator)
    }

    private func update(_ coordinator: Coordinator) {
        coordinator.isEnabled = isEnabled
        coordinator.onBegan = onBegan
        coordinator.onChanged = onChanged
        coordinator.onEnded = onEnded
    }

    static func dismantleUIView(_ uiView: HostView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    /// Installs the observer once it is in a window, removes it when it leaves.
    final class HostView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window {
                coordinator?.install(in: window)
            } else {
                coordinator?.uninstall()
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = true
        var onBegan: () -> Void = {}
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: () -> Void = {}

        private var recognizer: UIPanGestureRecognizer?
        /// A pan that started vertical (panel / channel gestures) is not a scrub.
        private var isScrubbing = false

        func install(in window: UIWindow) {
            guard recognizer?.view !== window else { return }
            uninstall()
            let pan = ScrubPanObserver(target: self, action: #selector(handle(_:)))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            window.addGestureRecognizer(pan)
            recognizer = pan
        }

        func uninstall() {
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            isScrubbing = false
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            let translation = pan.translation(in: pan.view)
            switch pan.state {
            case .began:
                isScrubbing = isEnabled && abs(translation.x) >= abs(translation.y)
                if isScrubbing { onBegan() }
            case .changed:
                if isScrubbing { onChanged(translation.x) }
            case .ended, .cancelled, .failed:
                if isScrubbing { onEnded() }
                isScrubbing = false
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// A pan that never blocks the focus engine's or SwiftUI's own recognizers.
private final class ScrubPanObserver: UIPanGestureRecognizer {
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
