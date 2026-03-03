import SwiftUI

struct STVHeaderView<SortMenu: View, FilterMenu: View>: View {
    @ViewBuilder let sortMenu: () -> SortMenu
    @ViewBuilder let filterMenu: () -> FilterMenu

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            sortMenu()
            filterMenu()
            Spacer()
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 30) // Balanced vertical padding
    }
}
