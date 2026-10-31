//
//  TVRemoteSeekHoldRecognizer.swift
//  stashyTV
//
//  Tap vs. hold on the Siri Remote's ◀ / ▶ clicks. A tap seeks a fixed step; holding seeks
//  continuously, faster the longer it is held, and stops where it is on release — like the
//  ▲ / ▼ hold recognizer, the clicks go through a press observer on the window, because
//  SwiftUI's `onMoveCommand` fires on press-down and cannot tell a tap from a hold.
//
//  Swipes on the touch surface produce move commands without presses; `TVRemoteSidePressTracker`
//  lets the SwiftUI side ignore the move command of a click it handles here.
//

import SwiftUI
import UIKit

/// Which ◀ / ▶ click is down right now. Read inside `onMoveCommand`, never drives a render.
final class TVRemoteSidePressTracker {
    fileprivate(set) var pressedDirections: Set<UIPress.PressType> = []

    func isPressing(_ direction: MoveCommandDirection) -> Bool {
        switch direction {
        case .left: return pressedDirections.contains(.leftArrow)
        case .right: return pressedDirections.contains(.rightArrow)
        default: return false
        }
    }
}

struct TVRemoteSeekHoldRecognizer: UIViewRepresentable {
    var isEnabled: Bool = true
    var tracker: TVRemoteSidePressTracker?
    /// A click released before the hold threshold: `-1` for ◀, `+1` for ▶.
    var onTap: (Int) -> Void
    /// Held past the threshold: continuous seeking starts in this direction.
    var onHoldBegan: (Int) -> Void
    /// The held click was released (or cancelled).
    var onHoldEnded: () -> Void

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
        coordinator.tracker = tracker
        coordinator.onTap = onTap
        coordinator.onHoldBegan = onHoldBegan
        coordinator.onHoldEnded = onHoldEnded
    }

    static func dismantleUIView(_ uiView: HostView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

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
        var isEnabled = true
        weak var tracker: TVRemoteSidePressTracker?
        var onTap: (Int) -> Void = { _ in }
        var onHoldBegan: (Int) -> Void = { _ in }
        var onHoldEnded: () -> Void = {}

        private weak var window: UIWindow?
        private var recognizer: SidePressObserver?

        func install(in window: UIWindow) {
            guard self.window !== window else { return }
            uninstall()
            self.window = window
            let observer = SidePressObserver()
            observer.onChange = { [weak self] pressed in self?.tracker?.pressedDirections = pressed }
            observer.onHoldBegan = { [weak self] type in
                guard let self, self.isEnabled else { return }
                self.onHoldBegan(type == .leftArrow ? -1 : 1)
            }
            observer.onHoldEnded = { [weak self] in self?.onHoldEnded() }
            observer.onTap = { [weak self] type in
                guard let self, self.isEnabled else { return }
                self.onTap(type == .leftArrow ? -1 : 1)
            }
            window.addGestureRecognizer(observer)
            recognizer = observer
        }

        func uninstall() {
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            tracker?.pressedDirections = []
            window = nil
        }
    }
}

/// Watches ◀ / ▶ presses without ever recognizing, so the focus engine and SwiftUI keep theirs.
private final class SidePressObserver: UIGestureRecognizer {
    var minimumPressDuration: TimeInterval = 0.4
    var onChange: ((Set<UIPress.PressType>) -> Void)?
    var onHoldBegan: ((UIPress.PressType) -> Void)?
    var onHoldEnded: (() -> Void)?
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
            NSNumber(value: UIPress.PressType.leftArrow.rawValue),
            NSNumber(value: UIPress.PressType.rightArrow.rawValue),
        ]
    }

    convenience init() { self.init(target: nil, action: nil) }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    private static func isSide(_ type: UIPress.PressType) -> Bool {
        type == .leftArrow || type == .rightArrow
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        for press in presses where Self.isSide(press.type) {
            let type = press.type
            pressed.insert(type)
            held.remove(type)
            holdTimers[type]?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.pressed.contains(type) else { return }
                self.held.insert(type)
                self.onHoldBegan?(type)
            }
            holdTimers[type] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + minimumPressDuration, execute: work)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        finish(presses, asTap: true)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        finish(presses, asTap: false)
    }

    private func finish(_ presses: Set<UIPress>, asTap: Bool) {
        for press in presses where Self.isSide(press.type) {
            let type = press.type
            holdTimers[type]?.cancel()
            holdTimers[type] = nil
            let wasHeld = held.remove(type) != nil
            pressed.remove(type)
            if wasHeld {
                onHoldEnded?()
            } else if asTap {
                onTap?(type)
            }
        }
        if pressed.isEmpty { state = .failed }
    }

    override func reset() {
        super.reset()
        if !pressed.isEmpty {
            holdTimers.values.forEach { $0.cancel() }
            holdTimers = [:]
            if !held.isEmpty { onHoldEnded?() }
            held = []
            pressed = []
        }
    }
}

/// Seconds the playhead moves per second while ◀ / ▶ is held: faster the longer it is held.
enum TVHoldSeekSpeed {
    static let tick: Double = 0.15

    static func secondsPerSecond(heldFor elapsed: Double) -> Double {
        if elapsed < 1.5 { return 20 }
        if elapsed < 4 { return 60 }
        return 180
    }
}
