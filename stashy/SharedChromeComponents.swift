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
        // Always leave the recognizer enabled — gating belongs in shouldBegin.
        // Toggling `isEnabled` from embedded root hosts (Feeds/Pics) races with
        // pushed details and can permanently disable swipe-back.
        if let existing = objc_getAssociatedObject(nav, &key) as? StashyNavPopGestureDelegate {
            existing.navigationController = nav
            nav.interactivePopGestureRecognizer?.delegate = existing
            nav.interactivePopGestureRecognizer?.isEnabled = true
            return
        }
        let delegate = StashyNavPopGestureDelegate()
        delegate.navigationController = nav
        objc_setAssociatedObject(nav, &key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        nav.interactivePopGestureRecognizer?.delegate = delegate
        nav.interactivePopGestureRecognizer?.isEnabled = true
    }

    static func nearestNavigationController(from start: UIViewController?) -> UINavigationController? {
        var current = start
        while let vc = current {
            if let nav = vc as? UINavigationController { return nav }
            if let nav = vc.navigationController { return nav }
            current = vc.parent
        }
        return nil
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

/// Reliable back for pushed details: `Environment.dismiss` is often a no-op when the
/// screen uses `safeAreaInset` chrome. Falls back to UIKit `popViewController`.
struct StashyNavigationBackTrigger: UIViewControllerRepresentable {
    @Binding var trigger: UUID?
    var dismissFallback: () -> Void

    final class Host: UIViewController {}

    final class Coordinator {
        var lastHandled: UUID?
        var dismissFallback: () -> Void

        init(dismissFallback: @escaping () -> Void) {
            self.dismissFallback = dismissFallback
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(dismissFallback: dismissFallback)
    }

    func makeUIViewController(context: Context) -> Host {
        let host = Host()
        host.view.isHidden = true
        host.view.isUserInteractionEnabled = false
        return host
    }

    func updateUIViewController(_ uiViewController: Host, context: Context) {
        context.coordinator.dismissFallback = dismissFallback
        if let nav = StashyNavPopGestureStorage.nearestNavigationController(from: uiViewController) {
            StashyNavPopGestureStorage.install(on: nav)
        }
        guard let token = trigger, context.coordinator.lastHandled != token else { return }
        context.coordinator.lastHandled = token
        // Consume once; defer so we run after the current SwiftUI update cycle.
        DispatchQueue.main.async {
            self.trigger = nil
            if let nav = StashyNavPopGestureStorage.nearestNavigationController(from: uiViewController),
               nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                context.coordinator.dismissFallback()
            }
        }
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        enforceHiddenNavigationBar()
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

    /// Sheet present/dismiss über einem gepushten Detail (z. B. Filter-Sheet im Profil,
    /// gepusht aus der Suche) blendet die System-Bar wieder ein — ohne Lifecycle-Callback,
    /// den `applyCustomChromeNavBar` abfangen könnte → leere Zeile über dem Custom-Chrome.
    /// Layout-Passes laufen beim Sheet-Auf/-Zu Abbau trotzdem; außerhalb von Push/Pop-
    /// Transitionen erzwingen wir den Hidden-Zustand daher hier erneut — aber nur, solange
    /// DIESES Detail Stack-Top ist, sonst würde die Bar gepushter Kinder (Szene-Detail etc.)
    /// weggeräumt.
    private func enforceHiddenNavigationBar() {
        guard let nav = navigationController else { return }
        guard transitionCoordinator == nil, nav.transitionCoordinator == nil else { return }
        if let top = nav.topViewController, isContained(in: top), !nav.isNavigationBarHidden {
            nav.setNavigationBarHidden(true, animated: false)
        }
    }

    private func isContained(in ancestor: UIViewController) -> Bool {
        var current: UIViewController? = self
        while let vc = current {
            if vc === ancestor { return true }
            current = vc.parent
        }
        return false
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

/// Shared Back pill used by detail / settings chrome bars.
struct StashyChromeBackButton: View {
    var title: String = "Back"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                Image(systemName: "chevron.left")
                    .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
            .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Modal catalog filter/sort sheet chrome (title default “Settings”) — not the system nav bar.
struct CatalogSettingsSheetChromeBar: View {
    var title: String = "Settings"
    var hasSelectedPreset: Bool
    var onReset: () -> Void
    var onRequestSave: () -> Void
    var onRequestSaveAs: () -> Void
    var onRequestRename: () -> Void
    var onRequestDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onReset) {
                    Text("Reset")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                        .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset")

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button { onRequestSave() } label: {
                        Label("Save", systemImage: "arrow.down.doc")
                    }
                    .disabled(!hasSelectedPreset)
                    Button { onRequestSaveAs() } label: {
                        Label("Save As", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                        .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                        .frame(width: StashyExpandingDock.circleSize, height: StashyExpandingDock.circleSize)
                        .background(StashyExpandingDock.inactiveBackground)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Save")

                ChromeCircleButton(
                    systemImage: "pencil",
                    enabled: hasSelectedPreset,
                    accessibilityLabel: "Rename",
                    action: onRequestRename
                )
                ChromeCircleButton(
                    systemImage: "trash",
                    enabled: hasSelectedPreset,
                    accessibilityLabel: "Delete",
                    action: onRequestDelete
                )
            }
            .frame(minHeight: StashyExpandingDock.activeHeight)
            .padding(.horizontal, StashyExpandingDock.edgePadding)
            .padding(.vertical, 10)

            Divider().overlay(Color.white.opacity(0.15))
        }
        // Opaque + extend into status-bar safe area so the presenter never shows through.
        .background {
            Color(
                UIColor.secondarySystemGroupedBackground.resolvedColor(
                    with: UITraitCollection(userInterfaceStyle: .dark)
                )
            )
            .ignoresSafeArea(edges: .top)
        }
        .colorScheme(.dark)
    }
}

private struct CatalogSettingsSheetChromeModifier: ViewModifier {
    var hasSelectedPreset: Bool
    var onReset: () -> Void
    var onRequestSave: () -> Void
    var onRequestSaveAs: () -> Void
    var onRequestRename: () -> Void
    var onRequestDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .hideSystemNavigationBarForCustomChrome()
            // Modal sheets always pin chrome to the top (unlike tab-root chrome on iPad).
            .safeAreaInset(edge: .top, spacing: 16) {
                CatalogSettingsSheetChromeBar(
                    hasSelectedPreset: hasSelectedPreset,
                    onReset: onReset,
                    onRequestSave: onRequestSave,
                    onRequestSaveAs: onRequestSaveAs,
                    onRequestRename: onRequestRename,
                    onRequestDelete: onRequestDelete
                )
            }
    }
}

/// Trailing text action in modal/detail chrome (Save / Done / Apply / …).
struct StashyChromeTrailingTextButton: View {
    let title: String
    var enabled: Bool = true
    var isBusy: Bool = false
    let action: () -> Void
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        Button(action: action) {
            Text(isBusy ? "…" : title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(enabled && !isBusy ? appearance.tintColor : .white.opacity(0.35))
                .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isBusy)
        .accessibilityLabel(title)
    }
}

/// Settings / simple pushed-detail chrome: Back · title · optional trailing.
struct StashyDetailChromeBar<Trailing: View>: View {
    let title: String
    /// Prefer for modal sheets: `safeAreaInset` + `NavigationView` can make env `dismiss` a no-op.
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing
    }

    var body: some View {
        StashySectionChromeBar {
            HStack(spacing: 8) {
                StashyChromeBackButton {
                    if let onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                trailing()
            }
            .frame(minHeight: StashyExpandingDock.activeHeight)
            .padding(.horizontal, StashyExpandingDock.edgePadding)
            .padding(.vertical, 8)
        }
    }
}

private struct StashySettingsDetailChromeModifier<Trailing: View>: ViewModifier {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    func body(content: Content) -> some View {
        content
            .hideSystemNavigationBarForCustomChrome()
            .enableSwipeBackWhenNavBarHidden()
            .stashyCustomChromeInset(spacing: 0) {
                StashyDetailChromeBar(title: title, trailing: trailing)
            }
    }
}

/// Shared sheet presentation: opaque background (iOS 26 glass) without `presentationSizing(.page)`,
/// which collapses `ScrollView` content to an empty sheet.
struct StashyEdgePinnedSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationBackground(Color(UIColor.systemGroupedBackground))
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

    /// Catalog filter/sort modal: custom “Settings” chrome instead of the system nav bar.
    func catalogSettingsSheetChrome(
        hasSelectedPreset: Bool,
        onReset: @escaping () -> Void,
        onRequestSave: @escaping () -> Void,
        onRequestSaveAs: @escaping () -> Void,
        onRequestRename: @escaping () -> Void,
        onRequestDelete: @escaping () -> Void
    ) -> some View {
        modifier(
            CatalogSettingsSheetChromeModifier(
                hasSelectedPreset: hasSelectedPreset,
                onReset: onReset,
                onRequestSave: onRequestSave,
                onRequestSaveAs: onRequestSaveAs,
                onRequestRename: onRequestRename,
                onRequestDelete: onRequestDelete
            )
        )
    }

    /// Modal sheet chrome pinned to the top (Back · title · trailing). Prefer over system nav bars.
    func stashyModalSheetChrome(
        _ title: String,
        onBack: (() -> Void)? = nil
    ) -> some View {
        stashyModalSheetChrome(title, onBack: onBack) { EmptyView() }
    }

    /// Modal sheet chrome with trailing action (Save / Done / Apply / …).
    func stashyModalSheetChrome<Trailing: View>(
        _ title: String,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        self
            .hideSystemNavigationBarForCustomChrome()
            .safeAreaInset(edge: .top, spacing: 16) {
                StashyDetailChromeBar(title: title, onBack: onBack, trailing: trailing)
            }
    }

    /// Pushed Settings detail: custom chrome (Back + title) instead of the system nav bar.
    func stashySettingsDetailChrome(
        _ title: String
    ) -> some View {
        modifier(StashySettingsDetailChromeModifier(title: title, trailing: { EmptyView() }))
    }

    /// Pushed Settings detail with trailing chrome accessory (status, loading, …).
    func stashySettingsDetailChrome<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        modifier(StashySettingsDetailChromeModifier(title: title, trailing: trailing))
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
    var accessibilityLabel: String = "Settings"
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
