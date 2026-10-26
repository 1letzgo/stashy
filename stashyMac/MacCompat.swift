//
//  MacCompat.swift
//  stashyMac
//
//  Thin UIKit-shaped layer over AppKit so the shared iOS SwiftUI files compile on
//  macOS mostly unchanged. Only what the shared code actually touches lives here;
//  anything with real iOS-only behaviour stays behind `#if os(iOS)` at the call site.
//

#if os(macOS)
import AppKit
import SwiftUI
import IOKit.pwr_mgt

// MARK: - Images & colors

typealias UIImage = NSImage
typealias UIColor = NSColor
typealias UIFont = NSFont

extension NSImage {
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    convenience init?(systemName: String) {
        self.init(systemSymbolName: systemName, accessibilityDescription: nil)
    }

    /// Point scale of the bitmap (1 for images built from pixel sizes, as above).
    var scale: CGFloat {
        guard let cg = cgImage, size.width > 0 else { return 1 }
        return CGFloat(cg.width) / size.width
    }

    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    func pngData() -> Data? {
        guard let cg = cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let cg = cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg)
            .representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}

extension Image {
    init(uiImage: NSImage) { self.init(nsImage: uiImage) }
}

extension Color {
    init(uiColor: NSColor) { self.init(nsColor: uiColor) }
}

// MARK: - Device & screen

enum UIUserInterfaceIdiom { case unspecified, phone, pad, tv, carPlay, mac, vision }

final class UIDevice {
    static let current = UIDevice()
    let userInterfaceIdiom: UIUserInterfaceIdiom = .mac
    /// Macs never rotate; nothing posts this name.
    static let orientationDidChangeNotification = Notification.Name("stashy.mac.orientationDidChange")
}

final class UIScreen {
    static let main = UIScreen()
    var bounds: CGRect { NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900) }
    var scale: CGFloat { NSScreen.main?.backingScaleFactor ?? 2 }
}

// MARK: - Application

final class UIApplication {
    enum State { case active, inactive, background }

    static let shared = UIApplication()

    static let didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
    static let willResignActiveNotification = NSApplication.willResignActiveNotification
    static let willEnterForegroundNotification = NSApplication.willBecomeActiveNotification
    static let didEnterBackgroundNotification = NSApplication.didHideNotification

    var applicationState: State { NSApp.isActive ? .active : .inactive }

    private var sleepAssertion: IOPMAssertionID = 0

    /// Mirrors iOS: keep the display awake while video plays.
    var isIdleTimerDisabled: Bool = false {
        didSet {
            guard isIdleTimerDisabled != oldValue else { return }
            if isIdleTimerDisabled {
                IOPMAssertionCreateWithName(
                    kIOPMAssertionTypeNoDisplaySleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    "stashy video playback" as CFString,
                    &sleepAssertion)
            } else if sleepAssertion != 0 {
                IOPMAssertionRelease(sleepAssertion)
                sleepAssertion = 0
            }
        }
    }

    func open(_ url: URL, options: [AnyHashable: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {
        completionHandler?(NSWorkspace.shared.open(url))
    }

    func canOpenURL(_ url: URL) -> Bool { NSWorkspace.shared.urlForApplication(toOpen: url) != nil }

    /// Only used to dismiss the keyboard (`resignFirstResponder`).
    @discardableResult
    func sendAction(_ action: Selector, to target: Any?, from sender: Any?, for event: Any?) -> Bool {
        NSApp.keyWindow?.makeFirstResponder(nil)
        return true
    }
}

// MARK: - SwiftUI modifiers that only exist on iOS

enum MacNavigationBarTitleDisplayMode { case automatic, inline, large }

extension View {
    func navigationBarTitleDisplayMode(_ mode: MacNavigationBarTitleDisplayMode) -> some View { self }
    func navigationBarHidden(_ hidden: Bool) -> some View { self }
    func statusBarHidden(_ hidden: Bool = true) -> some View { self }
    func listSectionSpacing(_ spacing: CGFloat) -> some View { self }
    func listRowSpacing(_ spacing: CGFloat?) -> some View { self }

    /// No full-screen modal style on macOS. The cover is handed up the view tree as a preference
    /// and drawn by `macFullScreenCoverHost()` over the whole window (sidebar included), so a
    /// fullscreen player fills the app window instead of opening as a small sheet.
    func fullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(MacFullScreenCoverModifier(isPresented: isPresented, onDismiss: onDismiss, cover: content))
    }

    /// Root of the window: draws whichever `fullScreenCover` below it is presented.
    func macFullScreenCoverHost() -> some View {
        modifier(MacFullScreenCoverHost())
    }
}

extension ListStyle where Self == InsetListStyle {
    static var insetGrouped: InsetListStyle { .inset }
}
#endif

#if os(macOS)
typealias UIResponder = NSResponder

extension NSFont {
    var lineHeight: CGFloat { ceil(ascender - descender + leading) }
}

/// iOS semantic colors used by the shared views, mapped to their AppKit counterparts.
extension NSColor {
    static var systemBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    static var tertiarySystemBackground: NSColor { .underPageBackgroundColor }
    static var systemGroupedBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemGroupedBackground: NSColor { .controlBackgroundColor }
    static var tertiarySystemGroupedBackground: NSColor { .underPageBackgroundColor }
    static var label: NSColor { .labelColor }
    static var secondaryLabel: NSColor { .secondaryLabelColor }
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }
    static var quaternaryLabel: NSColor { .quaternaryLabelColor }
    static var separator: NSColor { .separatorColor }
    static var systemFill: NSColor { .quaternaryLabelColor }
    static var secondarySystemFill: NSColor { .quaternaryLabelColor }
    static var tertiarySystemFill: NSColor { .quaternaryLabelColor }
    static var systemGray2: NSColor { .systemGray }
    static var systemGray3: NSColor { .systemGray }
    static var systemGray4: NSColor { .systemGray }
    static var systemGray5: NSColor { .systemGray }
    static var systemGray6: NSColor { .controlBackgroundColor }
}

// MARK: - Text input traits (no on-screen keyboard on macOS)

struct TextInputAutocapitalization {
    static let never = TextInputAutocapitalization()
    static let words = TextInputAutocapitalization()
    static let sentences = TextInputAutocapitalization()
    static let characters = TextInputAutocapitalization()
}

enum UITextAutocapitalizationType { case none, words, sentences, allCharacters }

enum UIKeyboardType {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad,
         namePhonePad, emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
}

enum UITextContentType { case username, password, newPassword, URL, oneTimeCode, emailAddress }

extension View {
    func textInputAutocapitalization(_ value: TextInputAutocapitalization?) -> some View { self }
    func autocapitalization(_ value: UITextAutocapitalizationType) -> some View { self }
    func keyboardType(_ type: UIKeyboardType) -> some View { self }
}
#endif

#if os(macOS)
import SwiftDraw

// MARK: - Image rendering

extension NSImage {
    enum Orientation { case up, down, left, right, upMirrored, downMirrored, leftMirrored, rightMirrored }

    var imageOrientation: Orientation { .up }

    /// Pixel-backed image whose point size is `pixels / scale`, like UIKit's initializer.
    convenience init(cgImage: CGImage, scale: CGFloat, orientation: Orientation) {
        let s = max(scale, 1)
        self.init(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / s, height: CGFloat(cgImage.height) / s))
    }

    func preparingForDisplay() -> NSImage? { self }
}

final class UIGraphicsImageRendererFormat {
    var scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2
    var opaque = false
    static func preferred() -> UIGraphicsImageRendererFormat { UIGraphicsImageRendererFormat() }
}

/// Minimal `UIGraphicsImageRenderer`: draws into a top-left-origin bitmap at `format.scale`.
final class UIGraphicsImageRenderer {
    private let size: CGSize
    private let format: UIGraphicsImageRendererFormat

    init(size: CGSize, format: UIGraphicsImageRendererFormat = .preferred()) {
        self.size = size
        self.format = format
    }

    func image(actions: (NSGraphicsContext) -> Void) -> NSImage {
        let scale = max(format.scale, 1)
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return NSImage(size: size)
        }
        // Flip to UIKit's top-left origin, then scale points → pixels.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        actions(gc)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { return NSImage(size: size) }
        return NSImage(cgImage: cg, scale: scale, orientation: .up)
    }
}

extension SVG {
    func rasterize(size: CGSize, scale: CGFloat) -> NSImage { rasterize(with: size, scale: scale) }
}

// MARK: - App icons (no alternate icons on macOS)

extension UIApplication {
    var alternateIconName: String? { nil }
    var supportsAlternateIcons: Bool { false }
    func setAlternateIconName(_ name: String?, completionHandler: ((Error?) -> Void)? = nil) {
        completionHandler?(nil)
    }
}

// MARK: - SwiftUI placements / styles that only exist on iOS

extension ToolbarPlacement {
    /// iOS-only bars: on macOS hiding/styling them must not touch the window toolbar,
    /// so they map to a placement with no effect here.
    static var navigationBar: ToolbarPlacement { .accessoryBar(id: "stashy.mac.navigationBar") }
    static var tabBar: ToolbarPlacement { .accessoryBar(id: "stashy.mac.tabBar") }
}

enum EditMode { case inactive, transient, active
    var isEditing: Bool { self != .inactive }
}

private struct MacEditModeKey: EnvironmentKey {
    static let defaultValue: Binding<EditMode>? = nil
}

extension EnvironmentValues {
    var editMode: Binding<EditMode>? {
        get { self[MacEditModeKey.self] }
        set { self[MacEditModeKey.self] = newValue }
    }
}
#endif

#if os(macOS)
// MARK: - NavigationView

/// On macOS `NavigationView` is a two-column split view: every sheet that wraps its content in
/// one (onboarding wizard, pickers, editors) showed it squeezed into an empty sidebar column.
/// This module-level type shadows SwiftUI's, so those call sites get a single-column stack —
/// what they are on iOS — and a usable size, since a sheet sizes itself to its content and a
/// `ScrollView` has no height of its own.
struct NavigationView<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        // The NavigationStack shim below sizes it and wires dismiss when it is in a sheet.
        NavigationStack { content }
    }
}
#endif

#if os(macOS)
// MARK: - In-window full screen cover

struct MacFullScreenCoverItem {
    let id: UUID
    let view: AnyView
}

private struct MacFullScreenCoverKey: PreferenceKey {
    static let defaultValue: MacFullScreenCoverItem? = nil
    static func reduce(value: inout MacFullScreenCoverItem?, nextValue: () -> MacFullScreenCoverItem?) {
        if let next = nextValue() { value = next }
    }
}

/// Equatable companion of the cover item, so the host can react to show / hide.
private struct MacFullScreenCoverShownKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct MacFullScreenCoverModifier<Cover: View>: ViewModifier {
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?
    var cover: () -> Cover

    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            // Re-emitted on every update of the presenting view, so the cover stays live.
            .preference(key: MacFullScreenCoverKey.self,
                        value: isPresented ? MacFullScreenCoverItem(id: id, view: AnyView(cover())) : nil)
            .preference(key: MacFullScreenCoverShownKey.self, value: isPresented)
            .onChange(of: isPresented) { wasPresented, presented in
                if wasPresented, !presented { onDismiss?() }
            }
    }
}

private struct MacFullScreenCoverHost: ViewModifier {
    @State private var isCoverShown = false

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(MacFullScreenCoverKey.self) { item in
                if let item {
                    item.view
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .onPreferenceChange(MacFullScreenCoverShownKey.self) { shown in
                if shown != isCoverShown { isCoverShown = shown }
            }
            // The title bar / toolbar would sit on top of the video; hide it while covered.
            .toolbar(isCoverShown ? .hidden : .automatic, for: .windowToolbar)
            .animation(.easeInOut(duration: 0.2), value: isCoverShown)
    }
}
#endif

#if os(macOS)
// MARK: - NavigationStack

/// Shadows SwiftUI's `NavigationStack` (only the root-closure form is used in this app).
/// Inside a sheet, `dismiss()` from the stack's root is a no-op on macOS — every Done / Close
/// button of a sheet did nothing. The dismiss read *outside* the stack closes the sheet, so it is
/// handed to the root as `\.stashyDismiss`. Pushed destinations keep the system behaviour.
struct NavigationStack<Root: View>: View {
    @Environment(\.dismiss) private var outerDismiss
    @Environment(\.isPresented) private var isPresentedOutside
    private let root: Root

    init(@ViewBuilder root: () -> Root) {
        self.root = root()
    }

    var body: some View {
        let dismiss = outerDismiss
        if isPresentedOutside {
            SwiftUI.NavigationStack {
                root
                    .environment(\.stashyDismiss, StashyDismissAction { dismiss() })
                    .environment(\.stashyInMacSheet, true)
            }
            // A sheet is its own window and does not inherit the main window's styles.
            .macIOSLikeControlStyles()
            // A sheet sizes itself to its content; scroll views and lists have no height of
            // their own, so without a floor the sheet collapses to its header.
            .frame(minWidth: 520, idealWidth: 620, minHeight: 560, idealHeight: 720)
            // Mac sheets close with esc.
            .onExitCommand { dismiss() }
        } else {
            SwiftUI.NavigationStack { root }
        }
    }
}
#endif

#if os(macOS)
// MARK: - Sheet toolbar

private struct StashyInMacSheetKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside the root of a `NavigationStack` presented as a sheet.
    var stashyInMacSheet: Bool {
        get { self[StashyInMacSheetKey.self] }
        set { self[StashyInMacSheetKey.self] = newValue }
    }
}

/// Views with their own chrome bar hide the system bar; in a sheet that bar is an empty strip
/// above the chrome. Only in sheets — in the main window the toolbar carries the tab bar.
struct MacHideSheetToolbar: ViewModifier {
    @Environment(\.stashyInMacSheet) private var inSheet

    func body(content: Content) -> some View {
        if inSheet {
            content.toolbar(.hidden, for: .automatic, .windowToolbar)
        } else {
            content
        }
    }
}
#endif

#if os(macOS)
extension View {
    /// The control looks the shared iOS views were designed with: switches, borderless buttons
    /// and grouped forms (AppKit defaults: checkboxes, bezeled push buttons, two-column forms).
    /// Applied to the window root and to every sheet, which does not inherit them.
    func macIOSLikeControlStyles() -> some View {
        self
            .toggleStyle(.switch)
            .buttonStyle(.borderless)
            .formStyle(.grouped)
    }
}
#endif
