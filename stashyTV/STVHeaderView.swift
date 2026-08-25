import SwiftUI

struct STVHeaderView<SortMenu: View, FilterMenu: View>: View {
    @ViewBuilder let sortMenu: () -> SortMenu
    @ViewBuilder let filterMenu: () -> FilterMenu
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            sortMenu()
            filterMenu()
            Spacer()
            if let onRefresh {
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 30)
        // Ohne focusSection springt der Fokus zwischen Grid und Header rein
        // geometrisch — aus mittleren Spalten liegt nichts über dem Spacer.
        .focusSection()
    }
}
