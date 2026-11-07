//
//  StashyDetailToolbar.swift
//  stashy
//
//  Shared detail chrome: the screen's custom chrome bar plus the embedded list's
//  floating action bar slots, behind one call site.
//

#if !os(tvOS)
import SwiftUI

// MARK: - Configuration

struct StashyDetailChromeConfig {
    /// Per-tab filter / columns / contextual slots for the embedded list.
    var listSlots: CatalogSlotSet? = nil
    /// Spacing passed to `stashyCustomChromeInset`.
    var insetSpacing: CGFloat = 0
}

extension View {
    /// Detail screen chrome. `bar` is the screen's custom chrome bar.
    func stashyDetailChrome<Bar: View>(
        _ config: StashyDetailChromeConfig,
        @ViewBuilder bar: @escaping () -> Bar
    ) -> some View {
        modifier(DetailChromeModifier(config: config, bar: bar))
    }
}

// MARK: - Implementation

struct DetailChromeModifier<Bar: View>: ViewModifier {
    let config: StashyDetailChromeConfig
    @ViewBuilder let bar: () -> Bar

    func body(content: Content) -> some View {
        content
            .hideSystemNavigationBarForCustomChrome()
            .enableSwipeBackWhenNavBarHidden()
            .stashyCustomChromeInset(spacing: config.insetSpacing) {
                bar()
            }
            .modifier(DetailSlotBar(slots: config.listSlots))
    }
}

private struct DetailSlotBar: ViewModifier {
    let slots: CatalogSlotSet?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let slots {
            // An empty list with an error hides the list's actions, never the page's own
            // (Edit, Favorite): a group without scenes could not be edited otherwise, since a
            // failing side fetch (galleries, images) sets the shared error.
            let listActionsVisible = slots.visibility.floatingBarVisible(isPresented: slots.isPresented)
            let shown = listActionsVisible
                ? slots
                : CatalogSlotSet(visibility: slots.visibility, entityActions: slots.entityActions)
            let showBar = slots.isPresented && slots.visibility.hasActiveServerConfig && shown.hasAnySlot
            content.floatingActionBar(isPresented: showBar) {
                CatalogSlotBar(slots: shown)
            }
        } else {
            content
        }
    }
}

#endif
