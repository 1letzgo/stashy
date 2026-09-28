//
//  TVRemoteHoldRecognizer.swift
//  stashyTV
//
//  Tap vs. hold on the Siri Remote's Up/Down clicks. SwiftUI's `onMoveCommand` fires on
//  press-down and cannot tell the two apart, so the clicks go through UIKit: a press
//  observer on the window, which sits above every focused view in the responder chain and
//  therefore sees the presses no matter which SwiftUI element holds focus.
//
//  Why taps are reported here too (and only on release): acting on press-down (the player
//  opened its panel) removed the focused view under the finger, UIKit cancelled the press,
//  and a hold could never complete — "hold ▼ for next" only worked with the panel already
//  open, "hold ▲" never. Now nothing changes until the press is released or held long enough.
//
//  Swipes on the touch surface produce move commands without presses; `TVRemotePressTracker`
//  lets the SwiftUI side tell those apart and keep handling them itself.
//

import SwiftUI
import UIKit

/// Shared between the recognizer and the SwiftUI view: which Up/Down click is currently down.
/// A plain class on purpose — it is read inside `onMoveCommand`, never drives a render.
final class TVRemotePressTracker {
    fileprivate(set) var pressedDirections: Set<UIPress.PressType> = []

    func isPressing(_ direction: MoveCommandDirection) -> Bool {
        switch direction {
        case .up: return pressedDirections.contains(.upArrow)
        case .down: return pressedDirections.contains(.downArrow)
        default: return false
        }
    }
}

struct TVRemoteHoldRecognizer: UIViewRepresentable {
    var minimumPressDuration: TimeInterval = 0.7
    var tracker: TVRemotePressTracker?
    var onHoldUp: (() -> Void)?
    var onHoldDown: (() -> Void)?
    /// A click released before `minimumPressDuration`.
    var onTapUp: (() -> Void)?
    var onTapDown: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        context.coordinator.minimumPressDuration = minimumPressDuration
        update(context.coordinator)
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        update(context.coordinator)
    }

    private func update(_ coordinator: Coordinator) {
        coordinator.tracker = tracker
        coordinator.onHoldUp = onHoldUp
        coordinator.onHoldDown = onHoldDown
        coordinator.onTapUp = onTapUp
        coordinator.onTapDown = onTapDown
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

    final class Coordinator: NSObject {
        var minimumPressDuration: TimeInterval = 0.7
        weak var tracker: TVRemotePressTracker?
        var onHoldUp: (() -> Void)?
        var onHoldDown: (() -> Void)?
        var onTapUp: (() -> Void)?
        var onTapDown: (() -> Void)?

        private weak var window: UIWindow?
        private var recognizer: DirectionalPressObserver?

        func install(in window: UIWindow) {
            guard self.window !== window else { return }
            uninstall()
            self.window = window
            let observer = DirectionalPressObserver()
            observer.minimumPressDuration = minimumPressDuration
            observer.onChange = { [weak self] pressed in self?.tracker?.pressedDirections = pressed }
            observer.onHold = { [weak self] type in
                (type == .upArrow ? self?.onHoldUp : self?.onHoldDown)?()
            }
            observer.onTap = { [weak self] type in
                (type == .upArrow ? self?.onTapUp : self?.onTapDown)?()
            }
            window.addGestureRecognizer(observer)
            recognizer = observer
        }

        func uninstall() {
            recognizer?.view?.removeGestureRecognizer(recognizer!)
            recognizer = nil
            tracker?.pressedDirections = []
            window = nil
        }
    }
}

/// Watches Up/Down presses without ever recognizing: it stays in `.possible`, so it never
/// cancels or delays the presses the focus engine and SwiftUI receive.
private final class DirectionalPressObserver: UIGestureRecognizer {
    var minimumPressDuration: TimeInterval = 0.7
    var onChange: ((Set<UIPress.PressType>) -> Void)?
    var onHold: ((UIPress.PressType) -> Void)?
    var onTap: ((UIPress.PressType) -> Void)?

    private var pressed: Set<UIPress.PressType> = [] {
        didSet { onChange?(pressed) }
    }
    private var holdTimers: [UIPress.PressType: DispatchWorkItem] = [:]
    private var held: Set<UIPress.PressType> = []

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        allowedPressTypes = [
            NSNumber(value: UIPress.PressType.upArrow.rawValue),
            NSNumber(value: UIPress.PressType.downArrow.rawValue),
        ]
    }

    convenience init() { self.init(target: nil, action: nil) }

    // SwiftUI's own press handling (move commands, focus) recognizes the same click. Without
    // these, UIKit failed and reset this observer mid-press, so the hold timer never saw the
    // press still down — the reason "hold ▲/▼" did nothing whenever the player itself had focus.
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        for press in presses where press.type == .upArrow || press.type == .downArrow {
            let type = press.type
            pressed.insert(type)
            held.remove(type)
            holdTimers[type]?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.pressed.contains(type) else { return }
                self.held.insert(type)
                self.onHold?(type)
            }
            holdTimers[type] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + minimumPressDuration, execute: work)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        finish(presses, asTap: true)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        // A cancelled press is not a tap: something else already took it.
        finish(presses, asTap: false)
    }

    private func finish(_ presses: Set<UIPress>, asTap: Bool) {
        for press in presses where press.type == .upArrow || press.type == .downArrow {
            let type = press.type
            holdTimers[type]?.cancel()
            holdTimers[type] = nil
            let wasHeld = held.remove(type) != nil
            pressed.remove(type)
            if asTap, !wasHeld { onTap?(type) }
        }
        if pressed.isEmpty { state = .failed }
    }

    override func reset() {
        super.reset()
        // Keep `pressed` in sync if UIKit resets mid-press.
        if !pressed.isEmpty {
            holdTimers.values.forEach { $0.cancel() }
            holdTimers = [:]
            held = []
            pressed = []
        }
    }
}
