//
//  MagazineListView.swift
//  stashy
//
//  Home → Magazin: the regular gallery list (filter, sort, presets) as magazine covers, opening
//  `MagazineReaderView`. Switched on in Settings › stashy+.
//

import SwiftUI

struct MagazineListView: View {
    let filterMemory: CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.GallerySortOption>>

    /// The default filter the remembered list state was built with.
    private static var seenDefaultFilterId = MagazineDefaultFilter.id

    @ObservedObject private var readingStore = MagazineReadingStore.shared
    @State private var openedGallery: Gallery?

    init(filterMemory: CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.GallerySortOption>>) {
        self.filterMemory = filterMemory
        // Changed in Settings while this list was not on screen: start over with the new default.
        if Self.seenDefaultFilterId != MagazineDefaultFilter.id {
            Self.seenDefaultFilterId = MagazineDefaultFilter.id
            filterMemory.reset()
        }
    }

    var body: some View {
        GalleriesView(
            filterMemory: filterMemory,
            host: GalleryListHost(
                title: "Magazin",
                onOpen: { openedGallery = $0 },
                card: { AnyView(card(for: $0)) },
                gridItems: Self.gridItems(width:),
                onGalleriesChanged: { galleries in
                    let ids = galleries.map(\.id)
                    Task { await readingStore.sync(galleryIds: ids) }
                },
                defaultFilterId: { MagazineDefaultFilter.id },
                defaultFilterChangeKey: MagazineDefaultFilter.changeKey
            )
        )
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            openedGallery = nil
        }
        .fullScreenCover(item: $openedGallery) { gallery in
            MagazineReaderView(gallery: gallery) { openedGallery = nil }
        }
    }

    /// Three covers per row, more only where three would turn into posters (iPad, Mac).
    private static func gridItems(width: CGFloat) -> [GridItem] {
        let spacing: CGFloat = 12
        let count = max(3, Int((width + spacing) / (220 + spacing)))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    private func card(for gallery: Gallery) -> some View {
        let page = readingStore.entries[gallery.id]?.page ?? 1
        return MagazineCoverCard(gallery: gallery)
            .overlay(alignment: .bottom) {
                if let fraction = readFraction(page: page, gallery: gallery) {
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            // Same bar as the scene cards.
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.2)).frame(height: 5)
                                Rectangle()
                                    .fill(AppearanceManager.shared.tintColor)
                                    .frame(width: geometry.size.width * fraction, height: 5)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    .allowsHitTesting(false)
                }
            }
            .contextMenu {
                if page > 1 {
                    Button("Reset position", systemImage: "arrow.counterclockwise") {
                        readingStore.resetPosition(galleryId: gallery.id)
                    }
                }
            }
    }

    /// Page 1 counts as not started. The saved page is the first of its spread, so the last
    /// spread (which can end one page later) fills the bar.
    private func readFraction(page: Int, gallery: Gallery) -> CGFloat? {
        guard page > 1, let total = gallery.imageCount, total > 0 else { return nil }
        return page + 1 >= total ? 1 : CGFloat(page) / CGFloat(total)
    }
}

/// A gallery as a magazine cover: portrait, the title printed over the image.
private struct MagazineCoverCard: View {
    /// A4.
    private static let coverAspectRatio: CGFloat = 210.0 / 297.0

    let gallery: Gallery

    var body: some View {
        Color.clear
            .aspectRatio(Self.coverAspectRatio, contentMode: .fit)
            .overlay {
                ZStack {
                    Color.gray.opacity(0.2)
                    CustomAsyncImage(url: gallery.coverURL) { loader in
                        if loader.isLoading {
                            ProgressView()
                        } else if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "magazine")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                Text(gallery.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.top, 20)
                    // Clear of the progress bar.
                    .padding(.bottom, 10)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .cardShadow()
    }
}
