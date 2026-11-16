//
//  TVFocusRow.swift
//  stashyTV
//
//  tvOS moves focus only to an element that lies in the pressed direction. A row of
//  buttons narrower than the row above or below it (hero buttons over a card row, a
//  header over a grid) then has no target from the outer columns: Up does nothing until
//  the user moves sideways first. `tvFocusRow()` stretches the row's frame across the
//  full width (leading-aligned, so nothing moves visually) and makes it a focus section,
//  so Up/Down from anywhere in the neighbouring row reaches it.
//

import SwiftUI

extension View {
    func tvFocusRow() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
    }
}
