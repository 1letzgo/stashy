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
            content.floatingActionBar(isPresented: slots.isPresented, catalogChrome: slots.visibility) {
                CatalogSlotBar(slots: slots)
            }
        } else {
            content
        }
    }
}

#endif
