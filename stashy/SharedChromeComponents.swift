#if !os(tvOS)
import SwiftUI
import UIKit
import ObjectiveC

// MARK: - Swipe-back with hidden system navigation bar

/// Long-lived pop-gesture delegate on the `UINavigationController` itself.
/// Avoids dangling delegates when a detail's representable is deallocated mid-gesture,
/// and rejects root-level swipes that otherwise freeze NavigationStack.
private final class StashyNavPopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}

private enum StashyNavPopGestureStorage {
    private static var key: UInt8 = 0

    static func install(on nav: UINavigationController) {
        if let existing = objc_getAssociatedObject(nav, &key) as? StashyNavPopGestureDelegate {
            existing.navigationController = nav
            nav.interactivePopGestureRecognizer?.delegate = existing
            nav.interactivePopGestureRecognizer?.isEnabled = nav.viewControllers.count > 1
            return
        }
        let delegate = StashyNavPopGestureDelegate()
        delegate.navigationController = nav
        objc_setAssociatedObject(nav, &key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        nav.interactivePopGestureRecognizer?.delegate = delegate
        nav.interactivePopGestureRecognizer?.isEnabled = nav.viewControllers.count > 1
    }
}

/// Hides the UIKit navigation bar (avoids empty bar after push from `.searchable`) and
/// re-enables `interactivePopGestureRecognizer` for custom top chrome.
/// Apply via `.enableSwipeBackWhenNavBarHidden()`.
private struct SwipeBackGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SwipeBackEnablerViewController {
        SwipeBackEnablerViewController()
    }

    func updateUIViewController(_ uiViewController: SwipeBackEnablerViewController, context: Context) {
        uiViewController.applyCustomChromeNavBar()
    }
}

private final class SwipeBackEnablerViewController: UIViewController {
    private var restoredNavigationBarHidden: Bool?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyCustomChromeNavBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyCustomChromeNavBar()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let nav = navigationController else { return }

        // Mutating bar visibility mid interactive-pop desyncs SwiftUI NavigationStack
        // (detail can stay "pushed" after the swipe animation finishes).
        if let coordinator = transitionCoordinator, coordinator.isInteractive {
            let restoreHidden = restoredNavigationBarHidden ?? false
            coordinator.notifyWhenInteractionChanges { [weak nav] context in
                guard let nav else { return }
                if context.isCancelled {
                    nav.setNavigationBarHidden(true, animated: false)
                    StashyNavPopGestureStorage.install(on: nav)
                } else {
                    nav.setNavigationBarHidden(restoreHidden, animated: false)
                    StashyNavPopGestureStorage.install(on: nav)
                }
            }
            return
        }

        if isMovingFromParent || isBeingDismissed {
            nav.setNavigationBarHidden(restoredNavigationBarHidden ?? false, animated: animated)
        } else {
            // Pushing a child (e.g. SceneDetail) — show the system bar again.
            nav.setNavigationBarHidden(false, animated: animated)
        }
        StashyNavPopGestureStorage.install(on: nav)
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent != nil {
            applyCustomChromeNavBar()
        }
    }

    func applyCustomChromeNavBar() {
        guard let nav = navigationController else { return }
        if restoredNavigationBarHidden == nil {
            restoredNavigationBarHidden = nav.isNavigationBarHidden
        }
        // UIKit hide removes the blank bar that SwiftUI `.toolbar(.hidden)` can leave
        // when pushing from a `.searchable` root.
        if !nav.isNavigationBarHidden {
            nav.setNavigationBarHidden(true, animated: false)
        }
        StashyNavPopGestureStorage.install(on: nav)
    }
}

/// Pops the enclosing `UINavigationController` to root when `trigger` changes.
/// Used by catalogue sub-tab switches so a stuck detail can't cover the new list.
private struct NavigationPopToRootOnChange: UIViewControllerRepresentable {
    let trigger: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.isHidden = true
        vc.view.isUserInteractionEnabled = false
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if context.coordinator.lastTrigger == nil {
            context.coordinator.lastTrigger = trigger
            return
        }
        guard context.coordinator.lastTrigger != trigger else { return }
        context.coordinator.lastTrigger = trigger
        // Defer so SwiftUI finishes swapping the catalogue root first.
        DispatchQueue.main.async {
            uiViewController.navigationController?.popToRootViewController(animated: false)
        }
    }

    final class Coordinator {
        var lastTrigger: String?
    }
}

/// iPad places custom chrome above the tab bar; iPhone keeps it under the status bar.
enum StashyChromePlacement {
    static var prefersBottom: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    static var edge: VerticalEdge {
        prefersBottom ? .bottom : .top
    }
}

/// Section dock (Home / Tools / Settings) with divider on the correct side for top vs bottom placement.
struct StashySectionChromeBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if StashyChromePlacement.prefersBottom {
                Divider().overlay(Color.white.opacity(0.15))
                content()
            } else {
                content()
                Divider().overlay(Color.white.opacity(0.15))
            }
        }
        .background(.bar)
        .colorScheme(.dark)
    }
}

extension View {
    /// Hides the system navigation bar for custom chrome and restores edge swipe-to-pop.
    func enableSwipeBackWhenNavBarHidden() -> some View {
        background(SwipeBackGestureEnabler())
    }

    /// SwiftUI-side hide for custom top chrome (pair with `enableSwipeBackWhenNavBarHidden()`).
    func hideSystemNavigationBarForCustomChrome() -> some View {
        self
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Custom chrome inset: top on iPhone, bottom on iPad.
    func stashyCustomChromeInset<V: View>(
        spacing: CGFloat = 0,
        @ViewBuilder content: @escaping () -> V
    ) -> some View {
        safeAreaInset(edge: StashyChromePlacement.edge, spacing: spacing, content: content)
    }

    /// Clears pushed detail screens when a catalogue / tools menu section changes.
    func popNavigationToRootOnChange(_ trigger: String) -> some View {
        background(NavigationPopToRootOnChange(trigger: trigger))
    }
}

// MARK: - Catalog FAB icons

/// Shared filter/sort control for floating catalog bars (`slider.horizontal.3` + active tint dot).
struct CatalogFilterFABButton: View {
    var isActive: Bool
    var accessibilityLabel: String = "Filter and sort"
    let action: () -> Void
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        Button(action: action) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: DesignTokens.Chrome.fabIconSize, weight: .semibold))
                .foregroundColor(isActive ? appearance.tintColor : .primary)
                .overlay(alignment: .topTrailing) {
                    if isActive {
                        Circle()
                            .fill(appearance.tintColor)
                            .frame(width: DesignTokens.Chrome.fabActiveDot, height: DesignTokens.Chrome.fabActiveDot)
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Generic equally-weighted FAB icon slot (columns toggle, select mode, etc.).
struct CatalogFABIconButton: View {
    let systemImage: String
    var tint: Color = .primary
    var isActive: Bool = false
    var accessibilityLabel: String? = nil
    var accessibilityHint: String? = nil
    let action: () -> Void
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: DesignTokens.Chrome.fabIconSize, weight: .semibold))
                .foregroundColor(isActive ? appearance.tintColor : tint)
                .overlay(alignment: .topTrailing) {
                    if isActive {
                        Circle()
                            .fill(appearance.tintColor)
                            .frame(width: DesignTokens.Chrome.fabActiveDot, height: DesignTokens.Chrome.fabActiveDot)
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

/// Quick-filter menu icon used beside the sheet slider (Galleries / Images).
struct CatalogQuickFilterFABLabel: View {
    var isActive: Bool
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        Image(systemName: "line.3.horizontal.decrease")
            .font(.system(size: DesignTokens.Chrome.fabIconSize, weight: .semibold))
            .foregroundColor(isActive ? appearance.tintColor : .primary)
    }
}

// MARK: - Spinners

enum InlineSpinnerScale {
    case compact   // 0.6 — thumbnails / overlays
    case medium    // 0.85
    case standard  // 1.0
    case large     // 2.0 — wizards

    var value: CGFloat {
        switch self {
        case .compact: return 0.6
        case .medium: return 0.85
        case .standard: return 1.0
        case .large: return 2.0
        }
    }
}

struct InlineSpinner: View {
    var scale: InlineSpinnerScale = .standard
    var tint: Color? = nil
    var label: String? = nil

    var body: some View {
        Group {
            if let label, !label.isEmpty {
                ProgressView(label)
            } else {
                ProgressView()
            }
        }
        .scaleEffect(scale.value)
        .modifier(OptionalProgressTint(tint: tint))
    }
}

private struct OptionalProgressTint: ViewModifier {
    var tint: Color?
    func body(content: Content) -> some View {
        if let tint {
            content.tint(tint)
        } else {
            content
        }
    }
}

/// Compact pagination / “load more” footer.
struct PaginationLoadingFooter: View {
    var message: String? = nil

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            InlineSpinner(scale: .standard)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.md)
    }
}

// MARK: - Circle chrome button (Dock-sized)

struct ChromeCircleButton: View {
    let systemImage: String
    var enabled: Bool = true
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                .foregroundColor(
                    enabled
                        ? .white.opacity(StashyExpandingDock.inactiveIconOpacity)
                        : .white.opacity(0.35)
                )
                .frame(width: StashyExpandingDock.circleSize, height: StashyExpandingDock.circleSize)
                .background(StashyExpandingDock.inactiveBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }
}

// MARK: - Primary CTA

struct PrimaryFilledButtonStyle: ButtonStyle {
    @ObservedObject private var appearance = AppearanceManager.shared

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .foregroundColor(.white)
            .background(appearance.tintColor.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.button, style: .continuous))
    }
}

// MARK: - Status placeholder (empty / connection error)

struct StatusPlaceholderView: View {
    @ObservedObject private var appearance = AppearanceManager.shared
    var icon: String
    var title: String
    var buttonText: String? = nil
    var isDark: Bool = false
    var fillsScreen: Bool = true
    var onAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            if fillsScreen { Spacer() }
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundColor(appearance.tintColor)

            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(isDark ? .white : .primary)
                .multilineTextAlignment(.center)

            if let buttonText, let onAction {
                Button(action: onAction) {
                    Text(buttonText)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.tintColor)
            }
            if fillsScreen { Spacer() }
        }
        .frame(maxWidth: .infinity, maxHeight: fillsScreen ? .infinity : nil)
        .padding(.top, fillsScreen ? 0 : DesignTokens.Spacing.xl)
        .background(fillsScreen ? Color.appBackground : Color.clear)
    }
}

/// Inline empty state for detail tabs (no full-screen background).
struct InlineEmptyStateView: View {
    var icon: String
    var title: String

    var body: some View {
        StatusPlaceholderView(
            icon: icon,
            title: title,
            buttonText: nil,
            fillsScreen: false,
            onAction: nil
        )
    }
}

#endif
