#if !os(tvOS)
import SwiftUI

/// Menu item for top-nav strips (Feeds / Home / Tools / Settings).
struct StashyNavMenuItem: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
}

/// Abstand-style expanding dock in the top nav: inactive = circle icon, active = tinted pill with label.
/// `title` is kept for call-site / accessibility compatibility (not shown as a separate label).
struct StashyTopNavNameDropdownRow: View {
    let title: String
    let items: [StashyNavMenuItem]
    let selectionID: String
    var titleColor: Color = .primary
    var menuAccessibilityLabel: String = "Section"
    var menuAccessibilityHint: String = "Chooses which section to show"
    let onSelect: (String) -> Void

    var body: some View {
        StashyExpandingDockBrowseStrip(
            items: items,
            selectionID: selectionID,
            accessibilityLabel: menuAccessibilityLabel,
            accessibilityHint: menuAccessibilityHint,
            onSelect: onSelect
        )
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - Expanding Dock (abstand-style)

/// Shared chrome metrics for the expanding dock and Feeds control pills.
enum StashyExpandingDock {
    static let inactiveIconOpacity: CGFloat = 0.72
    static let itemSpacing: CGFloat = 10
    static let circleSize: CGFloat = 40
    static let iconSize: CGFloat = 18
    static let activeHeight: CGFloat = 40
    /// Same inset before icon and after label when expanded.
    static let activeHorizontalPadding: CGFloat = 14
    static let iconLabelSpacing: CGFloat = 8
    /// Center the strip when item count is below this (Settings has 4 sections).
    static let centerWhenFewThreshold = 5
    static let selectionAnimation = Animation.spring(response: 0.32, dampingFraction: 0.72)
    static var inactiveIconSideInset: CGFloat { (circleSize - iconSize) / 2 }
    static let inactiveBackground = Color.white.opacity(0.14)
    /// Leading/trailing inset for dock strips and matching Feeds chrome.
    static let edgePadding: CGFloat = DesignTokens.Spacing.md
}

/// Uniform capsule chrome for Feeds / dock-aligned pills.
struct StashyChromePillStyle: ViewModifier {
    var height: CGFloat = StashyExpandingDock.activeHeight
    var iconOnly: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(
                .horizontal,
                iconOnly
                    ? StashyExpandingDock.inactiveIconSideInset
                    : StashyExpandingDock.activeHorizontalPadding
            )
            .frame(height: height)
            .frame(minWidth: StashyExpandingDock.circleSize, minHeight: StashyExpandingDock.circleSize)
            .frame(width: iconOnly ? StashyExpandingDock.circleSize : nil)
            .background(StashyExpandingDock.inactiveBackground)
            .clipShape(Capsule(style: .continuous))
    }
}

/// Horizontal icon/pill strip: selected item expands into a labeled capsule.
struct StashyExpandingDockBrowseStrip: View {
    let items: [StashyNavMenuItem]
    let selectionID: String
    var accessibilityLabel: String = "Section"
    var accessibilityHint: String = "Chooses which section to show"
    let onSelect: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: StashyExpandingDock.itemSpacing) {
                    ForEach(items) { item in
                        StashyExpandingDockChip(
                            item: item,
                            isSelected: item.id == selectionID,
                            onSelect: {
                                guard item.id != selectionID else { return }
                                HapticManager.light()
                                withAnimation(reduceMotion ? nil : StashyExpandingDock.selectionAnimation) {
                                    onSelect(item.id)
                                }
                            }
                        )
                        .id(item.id)
                    }
                }
                .frame(maxWidth: items.count < StashyExpandingDock.centerWhenFewThreshold ? .infinity : nil)
                .animation(reduceMotion ? nil : StashyExpandingDock.selectionAnimation, value: selectionID)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: selectionID) { _, newID in
                withAnimation(reduceMotion ? nil : StashyExpandingDock.selectionAnimation) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(selectionID, anchor: .center)
            }
        }
        .accessibilityHint(accessibilityHint)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct StashyExpandingDockChip: View {
    let item: StashyNavMenuItem
    let isSelected: Bool
    let onSelect: () -> Void

    @ObservedObject private var appearance = AppearanceManager.shared

    private var activeBackground: Color { appearance.tintColor }
    private var activeForeground: Color { .white }
    private var inactiveBackground: Color { StashyExpandingDock.inactiveBackground }
    private var inactiveForeground: Color { Color.white }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: isSelected ? StashyExpandingDock.iconLabelSpacing : 0) {
                Image(systemName: item.systemImage)
                    .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                    .foregroundStyle(
                        isSelected
                            ? activeForeground
                            : inactiveForeground.opacity(StashyExpandingDock.inactiveIconOpacity)
                    )
                    .frame(width: StashyExpandingDock.iconSize, height: StashyExpandingDock.iconSize)

                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(activeForeground)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: isSelected ? nil : 0, alignment: .leading)
                    .clipped()
            }
            .padding(
                .horizontal,
                isSelected
                    ? StashyExpandingDock.activeHorizontalPadding
                    : StashyExpandingDock.inactiveIconSideInset
            )
            .frame(height: StashyExpandingDock.activeHeight)
            .frame(width: isSelected ? nil : StashyExpandingDock.circleSize)
            .frame(minWidth: StashyExpandingDock.circleSize, minHeight: StashyExpandingDock.circleSize)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? activeBackground : inactiveBackground)
                    .shadow(
                        color: isSelected ? activeBackground.opacity(0.35) : .clear,
                        radius: 6,
                        x: 0,
                        y: 3
                    )
            }
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(StashyExpandingDockButtonStyle())
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct StashyExpandingDockButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}
#endif
