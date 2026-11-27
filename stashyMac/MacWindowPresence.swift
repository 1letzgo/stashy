import AppKit
import SwiftUI

/// Tells a view when its own window leaves the screen and when it is back: minimized, closed,
/// the app hidden (⌘H), the Mac or its screens asleep, the screen locked or a user switch. Not
/// when the app merely stops being the active one (another app's window in front, maybe on
/// another display): the window is still on screen then.
///
/// Feeds use it for "Keep playing in background" (`TabManager.feedsKeepPlayingInBackground`).
/// `onReturn` only fires once the window really is on screen again; several "left" events in a
/// row (hide, then sleep) may each call `onLeave`, the caller keeps its own state.
struct MacWindowPresenceModifier: ViewModifier {
    let onLeave: () -> Void
    let onReturn: () -> Void

    @State private var host = MacHostWindowBox()

    func body(content: Content) -> some View {
        content
            .background(MacHostWindowReader(box: host).frame(width: 0, height: 0))
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willHideNotification)) { _ in
                onLeave()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in
                returnIfOnScreen()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willMiniaturizeNotification)) { note in
                guard isOwnWindow(note) else { return }
                onLeave()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { note in
                guard isOwnWindow(note) else { return }
                returnIfOnScreen()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                guard isOwnWindow(note) else { return }
                onLeave()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                onLeave()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in
                onLeave()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in
                onLeave()
            }
            .onReceive(DistributedNotificationCenter.default().publisher(for: Self.screenLocked)) { _ in
                onLeave()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                returnIfOnScreen()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)) { _ in
                returnIfOnScreen()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)) { _ in
                returnIfOnScreen()
            }
            .onReceive(DistributedNotificationCenter.default().publisher(for: Self.screenUnlocked)) { _ in
                returnIfOnScreen()
            }
    }

    private static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    private func isOwnWindow(_ note: Notification) -> Bool {
        guard let window = note.object as? NSWindow, let own = host.window else { return false }
        return window === own
    }

    /// A wake can come while the app is still hidden, the window still minimized or the screen
    /// still locked; the matching unhide / deminiaturize / unlock brings it back later.
    private func returnIfOnScreen() {
        // The distributed notifications arrive slightly before the session state settles.
        DispatchQueue.main.async {
            guard !NSApp.isHidden, !Self.screenIsLocked else { return }
            guard let window = host.window, window.isVisible, !window.isMiniaturized else { return }
            onReturn()
        }
    }

    private static var screenIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) == true
            || (session["kCGSSessionOnConsoleKey"] as? Bool) == false
    }
}

/// Reference box, so finding the window never causes a SwiftUI update.
final class MacHostWindowBox {
    weak var window: NSWindow?
}

/// Reads the `NSWindow` its SwiftUI view sits in.
private struct MacHostWindowReader: NSViewRepresentable {
    let box: MacHostWindowBox

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.box = box
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.box = box
        if let window = nsView.window { box.window = window }
    }

    final class ReaderView: NSView {
        var box: MacHostWindowBox?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { box?.window = window }
        }
    }
}

extension View {
    /// See ``MacWindowPresenceModifier``.
    func macWindowPresence(onLeave: @escaping () -> Void, onReturn: @escaping () -> Void) -> some View {
        modifier(MacWindowPresenceModifier(onLeave: onLeave, onReturn: onReturn))
    }
}
