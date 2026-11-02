//
//  MagazineToolsView.swift
//  stashy
//
//  Tools → Magazin: the regular gallery list (filter, sort, presets), opening `MagazineReaderView`.
//

import SwiftUI

struct MagazineToolsView: View {
    /// Filter state survives switching between tools, like the Home sub-tab lists.
    private static let filterMemory = CatalogListFilterMemory<CatalogListFilterSnapshot<StashDBViewModel.GallerySortOption>>(mode: .galleries)

    /// The default filter the remembered list state was built with.
    private static var seenDefaultFilterId = MagazineDefaultFilter.id

    @ObservedObject private var readingStore = MagazineReadingStore.shared
    @State private var openedGallery: Gallery?

    init() {
        // Changed in Settings while this list was not on screen: start over with the new default.
        if Self.seenDefaultFilterId != MagazineDefaultFilter.id {
            Self.seenDefaultFilterId = MagazineDefaultFilter.id
            Self.filterMemory.reset()
        }
    }

    var body: some View {
        GalleriesView(
            hideTitle: true,
            filterMemory: Self.filterMemory,
            host: GalleryListHost(
                onOpen: { openedGallery = $0 },
                decorateCard: { gallery, card in AnyView(decoratedCard(gallery, card)) },
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
            Self.filterMemory.reset()
        }
        .fullScreenCover(item: $openedGallery) { gallery in
            MagazineReaderView(gallery: gallery) { openedGallery = nil }
        }
    }

    private func decoratedCard(_ gallery: Gallery, _ card: AnyView) -> some View {
        let page = readingStore.entries[gallery.id]?.page ?? 1
        return card
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
