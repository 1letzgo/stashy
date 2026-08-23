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
        // Keep a little air toward content: below when top-placed, above when bottom-placed (iPad).
        .padding(StashyChromePlacement.prefersBottom ? .top : .bottom, 4)
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

/// Color treatment for expanding-dock chips.
enum StashyExpandingDockPalette {
    /// Dark chrome bar: translucent white circles, white icons.
    case chrome
    /// Content background: secondary fill, primary icons.
    case surface

    var inactiveBackground: Color {
        switch self {
        case .chrome: return StashyExpandingDock.inactiveBackground
        case .surface: return Color.secondary.opacity(0.15)
        }
    }

    var inactiveForeground: Color {
        switch self {
        case .chrome: return Color.white
        case .surface: return Color.primary
        }
    }

    var inactiveForegroundOpacity: CGFloat {
        switch self {
        case .chrome: return StashyExpandingDock.inactiveIconOpacity
        case .surface: return 0.85
        }
    }
}

/// Horizontal icon/pill strip: selected item expands into a labeled capsule.
struct StashyExpandingDockBrowseStrip: View {
    let items: [StashyNavMenuItem]
    let selectionID: String
    var accessibilityLabel: String = "Section"
    var accessibilityHint: String = "Chooses which section to show"
    var palette: StashyExpandingDockPalette = .chrome
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
                            palette: palette,
                            onSelect: {
                                guard item.id != selectionID else { return }
                                HapticManager.light()
                                // Do not wrap `onSelect` in `withAnimation` — that fades the catalog root
                                // (Scenes / Images). Chip expand is driven by `.animation(..., value:)` below.
                                onSelect(item.id)
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
                proxy.scrollTo(newID, anchor: .center)
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
    var palette: StashyExpandingDockPalette = .chrome
    let onSelect: () -> Void

    @ObservedObject private var appearance = AppearanceManager.shared

    private var activeBackground: Color { appearance.tintColor }
    private var activeForeground: Color { .white }
    private var inactiveBackground: Color { palette.inactiveBackground }
    private var inactiveForeground: Color { palette.inactiveForeground }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: isSelected ? StashyExpandingDock.iconLabelSpacing : 0) {
                Image(systemName: item.systemImage)
                    .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                    .foregroundStyle(
                        isSelected
                            ? activeForeground
                            : inactiveForeground.opacity(palette.inactiveForegroundOpacity)
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

/// Equal-width tinted pills for Tools section menus (Match, RateMe, Top).
struct ToolsPillMenuRow: View {
    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
    }

    let items: [Item]
    let selectionID: String
    var accessibilityLabel: String = "Section"
    let onSelect: (String) -> Void

    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        HStack(spacing: StashyExpandingDock.itemSpacing) {
            ForEach(items) { item in
                let selected = item.id == selectionID
                Button {
                    guard item.id != selectionID else { return }
                    HapticManager.selection()
                    onSelect(item.id)
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity)
                        .frame(height: StashyExpandingDock.activeHeight)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selected ? appearance.tintColor : Color.secondary.opacity(0.15))
                                .shadow(
                                    color: selected ? appearance.tintColor.opacity(0.35) : .clear,
                                    radius: 6,
                                    x: 0,
                                    y: 3
                                )
                        )
                        .clipShape(Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title)\(selected ? ", selected" : "")")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, DesignTokens.Tools.contentPadding)
        .padding(.top, DesignTokens.Tools.menuTopPadding)
        .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct StashyExpandingDockButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}
#endif
