import SwiftUI

struct TVGenericGridView<Item: TVGridItem, Card: View, Header: View>: View {
    let items: [Item]
    let isLoading: Bool
    let isLoadingMore: Bool
    let hasMore: Bool
    let loadMore: () -> Void
    let onAppear: () -> Void
    let columns: [GridItem]
    let emptyImage: String
    let emptyText: String
    let loadingText: String
    @ViewBuilder let header: () -> Header
    @ViewBuilder let cardView: (Item) -> Card

    // Standard init for views WITH a header
    init(
        items: [Item],
        isLoading: Bool,
        isLoadingMore: Bool,
        hasMore: Bool,
        loadMore: @escaping () -> Void,
        onAppear: @escaping () -> Void,
        columns: [GridItem],
        emptyImage: String,
        emptyText: String,
        loadingText: String,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder cardView: @escaping (Item) -> Card
    ) {
        self.items = items
        self.isLoading = isLoading
        self.isLoadingMore = isLoadingMore
        self.hasMore = hasMore
        self.loadMore = loadMore
        self.onAppear = onAppear
        self.columns = columns
        self.emptyImage = emptyImage
        self.emptyText = emptyText
        self.loadingText = loadingText
        self.header = header
        self.cardView = cardView
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && items.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    ProgressView().scaleEffect(1.5)
                    Text(loadingText)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                    .frame(height: 100)
                Spacer()
            } else {
                header()
                
                if items.isEmpty {
                    Spacer()
                    VStack(spacing: 32) {
                        Image(systemName: emptyImage)
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.1))
                        
                        Text(emptyText)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.3))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
                            ForEach(items) { item in
                                cardView(item)
                                    .onAppear {
                                        if item.id == items.last?.id && hasMore {
                                            loadMore()
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.top, 20)
                        .padding(.bottom, 80)

                        if isLoadingMore {
                            ProgressView()
                                .padding(.vertical, 40)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .navigationTitle("")
        .onAppear {
            onAppear()
        }
    }
}

extension TVGenericGridView where Header == EmptyView {
    // Convenience init for views WITHOUT a header
    init(
        items: [Item],
        isLoading: Bool,
        isLoadingMore: Bool,
        hasMore: Bool,
        loadMore: @escaping () -> Void,
        onAppear: @escaping () -> Void,
        columns: [GridItem],
        emptyImage: String,
        emptyText: String,
        loadingText: String,
        @ViewBuilder cardView: @escaping (Item) -> Card
    ) {
        self.items = items
        self.isLoading = isLoading
        self.isLoadingMore = isLoadingMore
        self.hasMore = hasMore
        self.loadMore = loadMore
        self.onAppear = onAppear
        self.columns = columns
        self.emptyImage = emptyImage
        self.emptyText = emptyText
        self.loadingText = loadingText
        self.header = { EmptyView() }
        self.cardView = cardView
    }
}

