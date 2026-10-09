#if !os(tvOS)
import SwiftUI
import UIKit
import ObjectiveC

/// Line height of a tag chip's label. A symbol-only pill (the "+" in the tag rows)
/// would otherwise render shorter than the chips it sits next to.
let tagChipGlyphHeight: CGFloat = UIFont.systemFont(ofSize: 12, weight: .semibold).lineHeight

// MARK: - Glass

/// Central glass transparency (Settings › Appearance). 1 = pure glass, lower values lay a
/// wash under the glass content so less of the backdrop shows through.
enum StashyGlass {
    static var dimOpacity: Double {
        let t = AppearanceManager.shared.glassTransparency
        return max(0, min(1, 1 - t)) * 0.85
    }
}

extension View {
    /// Liquid Glass where the system has it, a material fill with a hairline everywhere else.
    /// Shared by the Aether transport surface and the Feeds overlay chrome.
    @ViewBuilder
    func stashyGlass<S: Shape>(shape: S) -> some View {
        // `contentShape` on both branches: at 100 % transparency the wash has opacity 0
        // and a fully transparent fill is not hit-testable, so taps on the chrome fell
        // through to whatever lay underneath.
        if #available(iOS 26.0, *) {
            self
                .background(shape.fill(Color.black.opacity(StashyGlass.dimOpacity)))
                .glassEffect(.regular, in: shape)
                .contentShape(shape)
        } else {
            self
                .background(shape.fill(Color.black.opacity(StashyGlass.dimOpacity)))
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                .contentShape(shape)
        }
    }

    /// Tinted glass — the same material as `stashyGlass`, coloured with `tint` (accent Back
    /// pills, selected chrome chips). Pre-26 fallback: material plus a translucent tint wash.
    @ViewBuilder
    func stashyGlass<S: Shape>(shape: S, tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            self
                .background(shape.fill(tint.opacity(StashyGlass.dimOpacity)))
                .glassEffect(.regular.tint(tint), in: shape)
                .contentShape(shape)
        } else {
            self
                .background(shape.fill(tint.opacity(0.6 + 0.4 * StashyGlass.dimOpacity)))
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                .contentShape(shape)
        }
    }

    /// Chrome chip fill: a selected chip is tinted glass, an inactive one plain glass.
    /// `activeColor == nil` means "not selected".
    @ViewBuilder
    func stashyChromeFill<S: Shape>(shape: S, activeColor: Color?) -> some View {
        if let activeColor {
            self.stashyGlass(shape: shape, tint: activeColor)
        } else {
            self.stashyGlass(shape: shape)
        }
    }
}

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

/// Custom chrome sits under the status bar on every idiom.
///
/// Bis iPadOS 17 saß die Tab-Bar unten, deshalb lag die Chrome auf iPad darüber.
/// Seit iPadOS 18 (Deployment-Target) schwebt die Tab-Bar oben; die untere Platzierung
/// war damit nicht nur optisch getrennt, sondern per `safeAreaInset` auch nicht mehr
/// antippbar (Back/Edit/FAB fielen auf den Inhalt darunter durch).
enum StashyChromePlacement {
    static var prefersBottom: Bool { false }

    static var edge: VerticalEdge {
        prefersBottom ? .bottom : .top
    }
}

/// Section dock (Home / Tools / Settings) with divider on the correct side for top vs bottom placement.
///
/// `isOpaque` adds a solid fill under the `.bar` material for sheets, where the presenting view would
/// otherwise shine through. The bar stays on the app-wide dark chrome scheme, so the fill is resolved
/// from the same environment instead of a hardcoded trait collection.
struct StashySectionChromeBar<Content: View>: View {
    var isOpaque: Bool = false
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
        .background {
            if isOpaque {
                Color(UIColor.secondarySystemGroupedBackground)
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
            .foregroundColor(.white)
            .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight, accent: true))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Modal catalog filter/sort sheet chrome (title default “Settings”) — not the system nav bar.
struct CatalogSettingsSheetChromeBar: View {
    var title: String = "Settings"
    var hasSelectedPreset: Bool
    /// Name der gewählten Vorlage für "Update ‹Name›" im Speichern-Dialog.
    var selectedPresetName: String? = nil
    var onReset: () -> Void
    var onRequestSave: () -> Void
    var onRequestSaveAs: () -> Void
    var onRequestRename: () -> Void
    var onRequestDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showSaveChoice = false

    var body: some View {
        StashySectionChromeBar(isOpaque: true) {
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

                // Ein Speichern-Dialog (Alert) wie bei Merge Tags/Studios: Update der
                // gewählten Vorlage, neu anlegen, umbenennen, löschen.
                Button {
                    showSaveChoice = true
                } label: {
                    Text("Save")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save filter")
                .alert("Save filter", isPresented: $showSaveChoice) {
                    if hasSelectedPreset {
                        Button(selectedPresetName.map { "Update \"\($0)\"" } ?? "Update") { onRequestSave() }
                    }
                    Button("Save as new") { onRequestSaveAs() }
                    if hasSelectedPreset {
                        Button("Rename") { onRequestRename() }
                        Button("Delete", role: .destructive) { onRequestDelete() }
                    }
                    Button("Cancel", role: .cancel) {}
                }

                // Closing the sheet was swipe-only, which is awkward right after tapping Done in
                // the advanced editor one level up.
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close filters")
            }
            .frame(minHeight: StashyExpandingDock.activeHeight)
            .padding(.horizontal, StashyExpandingDock.edgePadding)
            .padding(.vertical, 10)
        }
    }
}

private struct CatalogSettingsSheetChromeModifier: ViewModifier {
    var hasSelectedPreset: Bool
    var selectedPresetName: String? = nil
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
                    selectedPresetName: selectedPresetName,
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
            // Enabled = filled with the accent like the Back pill, so it never reads as greyed
            // out; disabled stays plain glass with dimmed text.
            Text(isBusy ? "…" : title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(enabled && !isBusy ? .white : .white.opacity(0.35))
                .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight,
                                                accent: enabled && !isBusy))
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
            .stashyCustomChromeInset(spacing: DesignTokens.Chrome.contentTopGap) {
                StashyDetailChromeBar(title: title, trailing: trailing)
            }
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
        selectedPresetName: String? = nil,
        onReset: @escaping () -> Void,
        onRequestSave: @escaping () -> Void,
        onRequestSaveAs: @escaping () -> Void,
        onRequestRename: @escaping () -> Void,
        onRequestDelete: @escaping () -> Void
    ) -> some View {
        modifier(
            CatalogSettingsSheetChromeModifier(
                hasSelectedPreset: hasSelectedPreset,
            selectedPresetName: selectedPresetName,
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

    var body: some View {
        Button(action: action) {
            CatalogFilterGlyph(isActive: isActive)
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

    var body: some View {
        Button(action: action) {
            CatalogSlotGlyph(systemImage: systemImage, tint: tint, isActive: isActive)
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

/// Icon-only capsule pill in the same style as the Rating / O-Counter pills (Feeds, image fullscreen).
struct ChromePillIconButton: View {
    let systemImage: String
    var enabled: Bool = true
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                .foregroundColor(enabled ? StashyExpandingDock.hashtagForeground : .white.opacity(0.35))
                .modifier(StashyChromePillStyle(height: StashyExpandingDock.stackedButtonSize, width: StashyExpandingDock.stackedButtonSize, hashtagColors: true))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }
}

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
                .stashyGlass(shape: Circle())
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

// MARK: - Keyboard dismissal

extension View {
    /// Kept for the existing call sites. The Done bar is now provided app-wide by
    /// `KeyboardDoneAccessory` (UIKit input accessory on every text field / text view):
    /// SwiftUI's `.toolbar(placement: .keyboard)` showed up only some of the time — inside
    /// sheets, lists and with several fields on one screen it regularly went missing.
    func numericKeyboardDoneBar() -> some View {
        self
    }

    /// Closes the keyboard when the user taps anywhere in this subtree. Uses a *simultaneous*
    /// gesture so buttons and rows underneath keep working.
    func dismissesKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
    }
}

#endif


#if !os(tvOS)
/// Small caps category heading — the look of Settings' `stashyScrollingSectionHeader`, for
/// screens that are not a `List`. Sits above a card, flush with its leading edge, 8 pt above it.
struct StashySectionHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The one search field every Tools screen uses — built after Tools › Filters: magnifier,
/// field, clear button, on the secondary background with the card radius.
struct ToolsSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs + 2)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }
}

/// Round tinted "+" next to a Tools search field, as in Tools › Filters.
struct ToolsAddButtonLabel: View {
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: StashyExpandingDock.circleSize, height: StashyExpandingDock.circleSize)
            .background(appearance.tintColor)
            .clipShape(Circle())
    }
}
// MARK: - O-Counter long-press menu

extension View {
    /// Long-press menu on an O-Counter pill: remove the last O, or reset all of them (confirmed).
    /// A plain tap keeps incrementing — this only adds the way back.
    func oCounterRemovalMenu(count: Int, onRemoveOne: @escaping () -> Void, onReset: @escaping () -> Void) -> some View {
        modifier(OCounterRemovalMenu(count: count, onRemoveOne: onRemoveOne, onReset: onReset))
    }
}

private struct OCounterRemovalMenu: ViewModifier {
    let count: Int
    let onRemoveOne: () -> Void
    let onReset: () -> Void

    @State private var confirmingReset = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if count > 0 {
                    Button {
                        HapticManager.light()
                        onRemoveOne()
                    } label: {
                        Label("Remove one O", systemImage: "minus.circle")
                    }
                    if count > 1 {
                        Button(role: .destructive) {
                            confirmingReset = true
                        } label: {
                            Label("Reset O-Counter (\(count))", systemImage: "arrow.counterclockwise")
                        }
                    }
                } else {
                    Text("No O recorded")
                }
            }
            // Centered warning alert, not an action sheet: this deletes history on the server.
            .alert("Reset O-Counter?", isPresented: $confirmingReset) {
                Button("Remove all \(count)", role: .destructive) {
                    HapticManager.light()
                    onReset()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All \(count) recorded O entries and their dates are permanently deleted on the server. This cannot be undone.")
            }
    }
}
// MARK: - App-wide keyboard Done bar

/// Puts a "Done" bar above the keyboard for every `UITextField` / `UITextView` the moment it
/// starts editing (SwiftUI `TextField`, `SecureField`, `TextEditor` are backed by these).
/// Search fields are left alone — they have their own Search key and native look.
/// Installed once at launch from `AppDelegate`.
@MainActor
final class KeyboardDoneAccessory: NSObject {
    static let shared = KeyboardDoneAccessory()
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(didBeginEditing(_:)),
                           name: UITextField.textDidBeginEditingNotification, object: nil)
        center.addObserver(self, selector: #selector(didBeginEditing(_:)),
                           name: UITextView.textDidBeginEditingNotification, object: nil)
    }

    @objc private func didBeginEditing(_ note: Notification) {
        if let field = note.object as? UITextField {
            guard !(field is UISearchTextField), needsBar(field.inputAccessoryView) else { return }
            field.inputAccessoryView = makeBar()
            field.reloadInputViews()
        } else if let textView = note.object as? UITextView {
            guard textView.isEditable, needsBar(textView.inputAccessoryView) else { return }
            textView.inputAccessoryView = makeBar()
            textView.reloadInputViews()
        }
    }

    /// SwiftUI gives every text field an accessory host of its own (`InputAccessoryGenerator`,
    /// zero height unless a `.keyboard` toolbar fills it) — so "is nil" never matched. Replace
    /// that empty host; leave our own bar and any real accessory with content alone.
    private func needsBar(_ current: UIView?) -> Bool {
        guard let current else { return true }
        if current.tag == Self.barTag { return false }
        return current.bounds.height < 1 && current.subviews.allSatisfy { $0.bounds.height < 1 }
    }

    private static let barTag = 0x6B6264 // "kbd"

    /// One bar per field: an input accessory can only live in one view hierarchy at a time.
    private func makeBar() -> UIToolbar {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let done = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
        bar.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
        bar.tag = Self.barTag
        bar.sizeToFit()
        return bar
    }

    @objc private func done() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Detail hero card

/// One label/value cell of a `DetailHeroCard` info grid.
struct DetailHeroItem: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

/// Header card shared by the opened gallery, tag and studio detail screens.
///
/// With an image: a compact band (fixed height, also in landscape) showing the image as a
/// blurred backdrop (dashboard hero technique: scaled + 40pt blur), a sharp circular avatar
/// of the same image with the tinted ring used by the Feeds overlay, and the name in white
/// next to it. The uppercase label/value grid, `footer` and description (two lines, chevron
/// expands) sit below the band on the solid card background in normal text colours.
/// Without an image the band is skipped; the name moves into the solid section, optionally
/// behind a placeholder circle (`placeholderSystemImage`).
///
/// `backdrop` fills the band (blurred by the card), `avatar` fills the circle (clipped by
/// the card). `onHeroTap` (e.g. fullscreen) makes the band a button. `accessory` sits
/// top-trailing on the band, or next to the name on the plain card (`onImage` says which).
struct DetailHeroCard<Backdrop: View, Avatar: View, Accessory: View, Footer: View>: View {
    let title: String
    let items: [DetailHeroItem]
    let description: String?
    let showsHero: Bool
    var heroAccessibilityLabel: String = "Open image"
    var onHeroTap: (() -> Void)? = nil
    @Binding var isExpanded: Bool
    /// Collapsed cell count; the rest appears when expanded.
    var collapsedItemLimit: Int = 4
    /// SF Symbol for the circle when there is no image; `nil` shows no circle.
    var placeholderSystemImage: String? = nil
    @ViewBuilder var backdrop: () -> Backdrop
    @ViewBuilder var avatar: () -> Avatar
    @ViewBuilder var accessory: (_ onImage: Bool) -> Accessory
    @ViewBuilder var footer: () -> Footer

    @ObservedObject private var appearanceManager = AppearanceManager.shared

    private static var bandHeight: CGFloat { 150 }
    private static var avatarSize: CGFloat { 76 }
    private static var placeholderSize: CGFloat { 52 }

    private var trimmedDescription: String {
        (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasExpandableContent: Bool {
        !trimmedDescription.isEmpty || items.count > collapsedItemLimit
    }

    /// Without a description the chevron sits on the info block; keep text clear of it.
    private var chevronInset: CGFloat {
        trimmedDescription.isEmpty && hasExpandableContent ? 28 : 0
    }

    /// Whether the solid section shows anything above the description.
    private var hasInfoSection: Bool {
        !showsHero || !items.isEmpty
    }

    var body: some View {
        let desc = trimmedDescription
        VStack(alignment: .leading, spacing: 0) {
            if showsHero {
                heroBand
                if !items.isEmpty {
                    infoGrid
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .padding(.trailing, chevronInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    if let placeholderSystemImage {
                        placeholderCircle(systemImage: placeholderSystemImage)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(isExpanded ? nil : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        infoGrid
                    }
                    .padding(.trailing, chevronInset)
                    accessory(false)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            footer()

            if !desc.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if hasInfoSection { Divider() }
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 28) // keep clear of the chevron
                }
                .padding(.horizontal, 12)
                .padding(.top, hasInfoSection ? 0 : 10)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .overlay(alignment: .bottomTrailing) {
            if hasExpandableContent {
                Button {
                    withAnimation(.spring()) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.pillAccent)
                        .padding(6)
                        .background(appearanceManager.tintColor.opacity(0.15))
                        .clipShape(Circle())
                }
                .padding(8)
                .accessibilityLabel(isExpanded ? "Show less" : "Show more")
            }
        }
    }

    // MARK: Band

    /// Blurred backdrop + sharp avatar circle + name. The whole band (minus the accessory)
    /// is the tap target when `onHeroTap` is set.
    private var heroBand: some View {
        let content = ZStack(alignment: .leading) {
            Color.black
                .frame(maxWidth: .infinity)
                .frame(height: Self.bandHeight)
                .overlay {
                    backdrop()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(1.3)
                        .blur(radius: 40, opaque: true)
                        .accessibilityHidden(true)
                }
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.15), .black.opacity(0.45)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipped()

            HStack(spacing: 14) {
                avatarCircle
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(isExpanded ? 4 : 2)
                    .minimumScaleFactor(0.8)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 16)
            // Clear of the top-trailing accessory.
            .padding(.trailing, 72)
        }
        .frame(height: Self.bandHeight)
        .contentShape(Rectangle())

        return Group {
            if let onHeroTap {
                Button {
                    HapticManager.light()
                    onHeroTap()
                } label: {
                    content
                }
                .buttonStyle(.plain)
                .accessibilityLabel(heroAccessibilityLabel)
            } else {
                content
            }
        }
        .overlay(alignment: .topTrailing) {
            accessory(true)
                .padding(8)
        }
    }

    /// Sharp copy of the image in a circle with the Feeds overlay's tinted ring.
    private var avatarCircle: some View {
        Circle()
            .fill(Color.black.opacity(0.3))
            .frame(width: Self.avatarSize, height: Self.avatarSize)
            .overlay {
                avatar()
                    .frame(width: Self.avatarSize, height: Self.avatarSize)
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(appearanceManager.tintColor, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    private func placeholderCircle(systemImage: String) -> some View {
        Circle()
            .fill(appearanceManager.tintColor.opacity(0.15))
            .frame(width: Self.placeholderSize, height: Self.placeholderSize)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color.pillAccent)
            )
            .overlay(Circle().stroke(appearanceManager.tintColor, lineWidth: 2))
            .accessibilityHidden(true)
    }

    // MARK: Info

    /// Uppercase label/value grid in the studio-header type scale (8pt labels, 11pt values).
    @ViewBuilder
    private var infoGrid: some View {
        let visible = isExpanded ? items : Array(items.prefix(collapsedItemLimit))
        if !visible.isEmpty {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: min(max(visible.count, 2), 4)),
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(visible) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.label)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Text(item.value)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

extension DetailHeroCard where Backdrop == Avatar, Accessory == EmptyView, Footer == EmptyView {
    /// Same image as blurred backdrop and in the circle (centre-cropped by the caller).
    init(
        title: String,
        items: [DetailHeroItem],
        description: String?,
        showsHero: Bool,
        heroAccessibilityLabel: String = "Open image",
        onHeroTap: (() -> Void)? = nil,
        isExpanded: Binding<Bool>,
        placeholderSystemImage: String? = nil,
        @ViewBuilder hero: @escaping () -> Avatar
    ) {
        self.init(
            title: title, items: items, description: description, showsHero: showsHero,
            heroAccessibilityLabel: heroAccessibilityLabel, onHeroTap: onHeroTap,
            isExpanded: isExpanded, placeholderSystemImage: placeholderSystemImage,
            backdrop: hero, avatar: hero,
            accessory: { _ in EmptyView() }, footer: { EmptyView() }
        )
    }
}

/// "Feeds" pill for detail hero cards: tinted on the plain card, dark glass on the hero.
struct DetailHeroFeedsButton: View {
    let onImage: Bool
    let action: () -> Void
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: AppTab.reels.icon)
                    .font(.system(size: 12, weight: .bold))
                Text("Feeds")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(onImage ? .white : Color.pillAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(onImage ? Color.black.opacity(0.45) : appearanceManager.tintColor.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open in Feeds")
    }
}

/// Minimal fullscreen viewer for a single hero image (pinch to zoom, tap or X to close).
struct DetailHeroFullscreenViewer<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    @State private var isZoomed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ZoomableScrollView(isZoomed: $isZoomed, onTap: { _ in dismiss() }) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel("Close")
        }
    }
}

#endif
