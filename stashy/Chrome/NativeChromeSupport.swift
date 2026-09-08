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

struct SectionChromeModifier<Row: View>: ViewModifier {
    let showsSwitcher: Bool
    @ViewBuilder let row: () -> Row

    func body(content: Content) -> some View {
        content
            .navigationBarHidden(true)
            .stashyCustomChromeInset(spacing: DesignTokens.Chrome.contentTopGap) {
                if showsSwitcher {
                    StashySectionChromeBar {
                        row()
                            .padding(.horizontal, StashyExpandingDock.edgePadding)
                            .padding(.vertical, 6)
                    }
                }
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
