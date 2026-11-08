//
//  NativeChromeSupport.swift
//  stashy
//
//  Section root chrome (Home / Settings / Tools): hidden system nav bar plus the
//  expanding dock strip in a top `StashySectionChromeBar`.
//

#if !os(tvOS)
import SwiftUI

// MARK: - Section roots (Home / Settings / Tools)

/// How section chrome leaves while scrolling: the same fade and short slide in Feeds and in the
/// catalog lists. Opacity and offset only, so no list ever relays out because of it.
enum StashyChromeAutoHide {
    static let slideDistance: CGFloat = 36

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.4)
    }
}

/// Top chrome takes about a fifth of an iPhone before any content shows. Catalog lists report
/// their scrolling here. As in Feeds, a finger dragging the list hides the section strip and the
/// quick bar; lists have no empty media to tap, so scrolling back up or reaching the top returns
/// them. Only flips publish, so scrolling does not rebuild anything.
@MainActor
final class CatalogChromeCollapse: ObservableObject {
    static let shared = CatalogChromeCollapse()

    @Published private(set) var isCollapsed = false
    /// Only a drag hides, as in Feeds: scroll restoration and programmatic scrolls must not.
    var isDragging = false {
        didSet {
            guard isDragging != oldValue else { return }
            #if os(iOS)
            // A swipe that starts on an open chrome menu (Home views, sort) closes the menu and
            // scrolls at once. Hiding the bar then sends the menu's closing animation back to a
            // button that is already sliding away, and it hangs under the status bar.
            dragStartedWithMenuOpen = isDragging && ContextMenuPresence.isMenuOpen
            #endif
        }
    }
    private var dragStartedWithMenuOpen = false
    private var anchor: CGFloat = 0
    /// The list the finger last dragged. Lists kept alive off screen (other Home sections)
    /// report their geometry too; loading a page re-lays them out at offset 0, which read as
    /// "back at the top" and brought the bar back on every page load.
    private var owner: AnyHashable?
    /// What the scrolling decided; `isCollapsed` follows it one run loop later.
    private var targetCollapsed = false

    private static let hideDistance: CGFloat = 12
    private static let showDistance: CGFloat = 20
    private static let minimumHidePosition: CGFloat = 40

    func update(offset: CGFloat, scrollRange: CGFloat, source: AnyHashable? = nil) {
        #if os(iOS)
        if let owner, let source, owner != source { return }
        // VoiceOver reads the screen in order; chrome that moves away would lose its place.
        guard !UIAccessibility.isVoiceOverRunning else {
            reset()
            return
        }
        // Rubber-banding at either end is not a scroll direction.
        let position = min(max(offset, 0), max(scrollRange, 0))
        guard !dragStartedWithMenuOpen else {
            anchor = position
            return
        }

        if position <= Self.showDistance {
            anchor = position
            setCollapsed(false)
        } else if position > anchor {
            if targetCollapsed {
                anchor = position
            } else if position - anchor >= Self.hideDistance {
                if !isDragging {
                    anchor = position
                } else if position >= Self.minimumHidePosition {
                    // The anchor stays put below the minimum: a short list has no second
                    // `hideDistance` left to travel once it got there.
                    anchor = position
                    setCollapsed(true)
                }
            }
        } else if targetCollapsed {
            if anchor - position >= Self.showDistance {
                anchor = position
                setCollapsed(false)
            }
        } else {
            anchor = position
        }
        #endif
    }

    /// Scroll phase of one list; a drag makes it the list that drives the chrome.
    func setDragging(_ dragging: Bool, source: AnyHashable) {
        if dragging { owner = source }
        guard owner == source else { return }
        isDragging = dragging
    }

    /// A list leaving the screen resets only if it was driving the chrome.
    func reset(source: AnyHashable) {
        guard owner == nil || owner == source else { return }
        reset()
    }

    func reset() {
        owner = nil
        anchor = 0
        isDragging = false
        setCollapsed(false)
    }

    private func setCollapsed(_ value: Bool) {
        guard targetCollapsed != value else { return }
        targetCollapsed = value
        // Not from inside the scroll update: published there, the chrome jumps in a single frame
        // and its animation never runs.
        DispatchQueue.main.async { [weak self] in
            self?.isCollapsed = value
        }
    }
}

#if os(iOS)
/// Whether a UIKit context menu (what a SwiftUI `Menu` presents) is on screen, including while
/// it animates closed. Only checked when a drag starts, so the shallow view walk is cheap.
enum ContextMenuPresence {
    static var isMenuOpen: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { containsMenu($0, depth: 0) }
    }

    private static func containsMenu(_ view: UIView, depth: Int) -> Bool {
        if String(describing: type(of: view)).contains("ContextMenu") { return true }
        guard depth < 4 else { return false }
        return view.subviews.contains { containsMenu($0, depth: depth + 1) }
    }
}
#endif

/// Hides top chrome together with `CatalogChromeCollapse`, the way Feeds hides its own.
struct CatalogChromeCollapsible: ViewModifier {
    var enabled = true

    @ObservedObject private var collapse = CatalogChromeCollapse.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let collapsed = enabled && collapse.isCollapsed
        content
            .opacity(collapsed ? 0 : 1)
            .offset(y: collapsed && !reduceMotion ? -StashyChromeAutoHide.slideDistance : 0)
            .allowsHitTesting(!collapsed)
            .accessibilityHidden(collapsed)
            .animation(StashyChromeAutoHide.animation(reduceMotion: reduceMotion), value: collapsed)
    }
}

/// Keeps the status bar readable once the section bar, whose material reaches behind it, is gone.
private struct CatalogStatusBarScrim: View {
    @ObservedObject private var collapse = CatalogChromeCollapse.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(height: 0)
            .background(.bar)
            .colorScheme(.dark)
            .opacity(collapse.isCollapsed ? 1 : 0)
            .animation(StashyChromeAutoHide.animation(reduceMotion: reduceMotion), value: collapse.isCollapsed)
            .allowsHitTesting(false)
    }
}

private struct CatalogScrollMetrics: Equatable {
    var offset: CGFloat
    var range: CGFloat
}

#if os(iOS)
/// Reports one list's scrolling to `CatalogChromeCollapse`, tagged so only the list being
/// scrolled moves the chrome.
private struct CatalogChromeScrollReporter: ViewModifier {
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CatalogScrollMetrics.self) { geometry in
                CatalogScrollMetrics(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top,
                    // The container already excludes the insets; adding them again overstates the
                    // range, and the bounce back from the list's end reads as scrolling up.
                    range: geometry.contentSize.height - geometry.containerSize.height
                )
            } action: { _, metrics in
                CatalogChromeCollapse.shared.update(offset: metrics.offset, scrollRange: metrics.range, source: id)
            }
            .onScrollPhaseChange { _, phase in
                // `.tracking` too: a quick drag on a short list can reach its end in the first
                // geometry update, before the phase turns `.interacting`.
                CatalogChromeCollapse.shared.setDragging(phase == .tracking || phase == .interacting, source: id)
            }
            .onDisappear { CatalogChromeCollapse.shared.reset(source: id) }
    }
}
#endif

extension View {
    /// Pins the quick bar over a catalog list. The list scrolls underneath, so the bar can slide
    /// away without changing the list's layout.
    func catalogPinnedQuickBar<Bar: View>(@ViewBuilder _ bar: @escaping () -> Bar) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            bar()
        }
    }

    /// Goes on the vertical scroll view of a catalog list whose chrome is pinned above it.
    /// `enabled: false` for lists embedded in a detail page, whose bar scrolls with the content.
    @ViewBuilder
    func collapsesCatalogChrome(enabled: Bool = true) -> some View {
        #if os(iOS)
        if enabled {
            modifier(CatalogChromeScrollReporter())
        } else {
            self
        }
        #else
        self
        #endif
    }
}

struct SectionChromeModifier<Row: View>: ViewModifier {
    let showsSwitcher: Bool
    @ViewBuilder let row: () -> Row

    func body(content: Content) -> some View {
        content
            .navigationBarHidden(true)
            // No gap without a bar: a hidden Home bar (Performers draws its own breadcrumb)
            // would otherwise push the list's bar down, and the Home button would jump.
            .stashyCustomChromeInset(spacing: showsSwitcher ? DesignTokens.Chrome.contentTopGap : 0) {
                if showsSwitcher {
                    StashySectionChromeBar {
                        row()
                            .padding(.horizontal, StashyExpandingDock.edgePadding)
                            .padding(.vertical, 6)
                    }
                    .modifier(CatalogChromeCollapsible())
                }
            }
            .overlay(alignment: .top) {
                if showsSwitcher { CatalogStatusBarScrim() }
            }
    }
}

extension View {
    /// Section root chrome (Home / Settings / Tools): the dock strip above the content.
    func stashySectionChrome<Row: View>(
        showsSwitcher: Bool = true,
        @ViewBuilder row: @escaping () -> Row
    ) -> some View {
        modifier(SectionChromeModifier(showsSwitcher: showsSwitcher, row: row))
    }
}

#endif
