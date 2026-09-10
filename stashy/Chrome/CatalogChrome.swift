//
//  CatalogChrome.swift
//  stashy
//
//  One call site per catalog list: the floating action bar and its slots live behind
//  a single config, never at the call site.
//

#if !os(tvOS)
import SwiftUI

// MARK: - Configuration

/// One equally weighted slot in the catalog chrome (columns toggle, contextual action, filter & sort).
struct CatalogChromeSlot {
    var systemImage: String
    var isActive: Bool = false
    var accessibilityLabel: String
    var accessibilityHint: String? = nil
    var action: () -> Void
}

/// Slot 2: a menu instead of a plain button (quick filter / preset picker).
struct CatalogQuickFilterMenuModel {
    var isActive: Bool = false
    var accessibilityLabel: String = "Quick filter"
    var menuContent: AnyView
}

/// Selection mode chrome (Images).
struct CatalogSelectionChrome {
    var isActive: Bool
    var count: Int
    var onDone: () -> Void
    var onSelectAll: (() -> Void)? = nil
    var onDelete: () -> Void
}

/// Search wiring. `isVisible` is the toggle target driven by the magnifier button.
struct CatalogSearchChrome {
    var text: Binding<String>
    var isVisible: Binding<Bool>
    var prompt: String = "Search"
    /// Called after the text was cleared, so the screen can refetch.
    var onClear: () -> Void
}

/// The slot payload shared by catalog lists and detail screens. Detail screens have no
/// mandatory filter & sort slot, so `filterSort` is optional here.
struct CatalogSlotSet {
    var visibility: CatalogFloatingChromeState
    var isPresented: Bool = true
    var columns: CatalogChromeSlot? = nil              // slot 1
    var quickFilter: CatalogQuickFilterMenuModel? = nil // slot 2
    var filterSort: CatalogChromeSlot? = nil            // always rendered last (far right)
    var contextual: CatalogChromeSlot? = nil            // slot 3
    var secondaryContextual: CatalogChromeSlot? = nil   // slot 4
}

struct CatalogChromeConfig {
    var title: String
    /// `false` == today's `hideTitle`: the list is embedded and the parent owns the nav bar.
    var ownsNavigationBar: Bool = true
    var visibility: CatalogFloatingChromeState
    var isPresented: Bool = true
    var columns: CatalogChromeSlot? = nil              // slot 1
    var quickFilter: CatalogQuickFilterMenuModel? = nil // slot 2
    var filterSort: CatalogChromeSlot                   // slot 3
    var contextual: CatalogChromeSlot? = nil            // slot 4
    /// Optional slot 5 for screens that legitimately carry two contextual actions
    /// (Images: select mode plus the gallery download control).
    var secondaryContextual: CatalogChromeSlot? = nil
    var selection: CatalogSelectionChrome? = nil
    var search: CatalogSearchChrome? = nil

    /// The slots this config carries, in the shape the shared renderers consume.
    var slotSet: CatalogSlotSet {
        CatalogSlotSet(
            visibility: visibility,
            isPresented: isPresented,
            columns: columns,
            quickFilter: quickFilter,
            filterSort: filterSort,
            contextual: contextual,
            secondaryContextual: secondaryContextual
        )
    }
}

extension View {
    func stashyCatalogChrome(_ config: CatalogChromeConfig) -> some View {
        modifier(CatalogChromeModifier(config: config))
    }

    /// Bottom overlay for chrome that sits below the list (selection bars, delete affordances).
    func stashyBottomOverlay<V: View>(
        alignment: Alignment = .bottom,
        @ViewBuilder _ overlay: @escaping () -> V
    ) -> some View {
        self.overlay(alignment: alignment) { overlay() }
    }
}

// MARK: - Shared glyphs

/// Filter & sort glyph (slider icon plus the active tint dot).
struct CatalogFilterGlyph: View {
    var isActive: Bool
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
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
}

/// Generic slot glyph (columns toggle, select mode, download, …) with the same active dot treatment.
struct CatalogSlotGlyph: View {
    let systemImage: String
    var tint: Color = .primary
    var isActive: Bool = false
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
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
}

/// The `.principal` chip that shows the active search term and clears it on tap.
struct SearchClearChip: View {
    let text: String
    let onClear: () -> Void

    var body: some View {
        Button(action: onClear) {
            HStack(spacing: 4) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                Text(text)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(DesignTokens.Opacity.badge))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Shared slot rendering

/// The row of equally weighted slot buttons inside the floating action bar.
/// Shared by catalog lists and detail screens; the caller owns the `floatingActionBar` wrapper.
struct CatalogSlotBar: View {
    let slots: CatalogSlotSet
    var selection: CatalogSelectionChrome? = nil

    var body: some View {
        HStack(spacing: 0) {
            if let selection, selection.isActive {
                // Selection mode owns the whole bar; the delete affordance stays in the
                // call site's bottom overlay.
                CatalogFABIconButton(
                    systemImage: "checkmark.circle.fill",
                    accessibilityLabel: "Done selecting",
                    action: selection.onDone
                )
                .frame(maxWidth: .infinity)
            } else {
                if let columns = slots.columns {
                    slotButton(columns)
                        .frame(maxWidth: .infinity)
                }
                if let quick = slots.quickFilter {
                    Menu {
                        quick.menuContent
                    } label: {
                        CatalogQuickFilterFABLabel(isActive: quick.isActive)
                    }
                    .accessibilityLabel(quick.accessibilityLabel)
                    .frame(maxWidth: .infinity)
                }
                if let contextual = slots.contextual {
                    slotButton(contextual)
                        .frame(maxWidth: .infinity)
                }
                if let secondary = slots.secondaryContextual {
                    slotButton(secondary)
                        .frame(maxWidth: .infinity)
                }
                // Filter & sort ("Settings") always sits at the far right, whatever else the screen adds.
                if let filterSort = slots.filterSort {
                    CatalogFilterFABButton(
                        isActive: filterSort.isActive,
                        accessibilityLabel: filterSort.accessibilityLabel,
                        action: filterSort.action
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func slotButton(_ slot: CatalogChromeSlot) -> some View {
        CatalogFABIconButton(
            systemImage: slot.systemImage,
            isActive: slot.isActive,
            accessibilityLabel: slot.accessibilityLabel,
            accessibilityHint: slot.accessibilityHint,
            action: slot.action
        )
    }
}

// MARK: - Implementation

/// Inline nav title, conditional searchable, `.principal` clear chip and the floating
/// action bar with the slots in fixed order.
struct CatalogChromeModifier: ViewModifier {
    let config: CatalogChromeConfig

    func body(content: Content) -> some View {
        titledContent(content)
            .floatingActionBar(isPresented: config.isPresented, catalogChrome: config.visibility) {
                CatalogSlotBar(slots: config.slotSet, selection: config.selection)
            }
    }

    @ViewBuilder
    private func titledContent(_ content: Content) -> some View {
        if config.ownsNavigationBar {
            content
                .navigationTitle(config.title)
                .navigationBarTitleDisplayMode(.inline)
                .modifier(CatalogSearchModifier(search: config.search))
                .toolbar {
                    if let search = config.search, !search.text.wrappedValue.isEmpty {
                        ToolbarItem(placement: .principal) {
                            SearchClearChip(text: search.text.wrappedValue) {
                                search.text.wrappedValue = ""
                                search.onClear()
                            }
                        }
                    }
                }
        } else {
            content.hideSystemNavigationBarForCustomChrome()
        }
    }
}

private struct CatalogSearchModifier: ViewModifier {
    let search: CatalogSearchChrome?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let search {
            content.conditionalSearchable(
                isVisible: search.isVisible.wrappedValue,
                text: search.text,
                prompt: search.prompt
            )
        } else {
            content
        }
    }
}

#endif
