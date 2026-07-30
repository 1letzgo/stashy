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
    }
}
