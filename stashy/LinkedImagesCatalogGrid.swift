//
//  LinkedImagesCatalogGrid.swift
//  stashy
//
//  Shared Images grid for catalog + Performer/Tag detail (1/row feed vs multi-column).
//

#if !os(tvOS)
import SwiftUI
import UIKit

/// Images list that respects `CatalogCardColumnScope.images` (1/row with set grouping, or multi-column).
struct LinkedImagesCatalogGrid: View {
    @Binding var images: [StashImage]
    var sortOption: StashDBViewModel.ImageSortOption
    var isLoading: Bool
    var hasMore: Bool
    var onLoadMore: () -> Void
    /// Used when not in 1/row mode (e.g. phone 2-col / iPad 4-col).
    var multiColumnGridItems: [GridItem]
    /// Parent ScrollView drag/decelerate state (same gate as Images catalog).
    var isFeedScrolling: Bool = false

    @ObservedObject private var tabManager = TabManager.shared
    @AppStorage("stashline_group_sets") private var groupIntoSets = true
    @AppStorage("stashline_group_fallback") private var groupFallbackRaw = StashImageSetGroupingPolicy.sessionThenMeta.rawValue
    @AppStorage("images_feed_video_autoplay") private var imagesFeedVideoAutoplay = true
    @State private var sessionKeyCache: [String: String] = [:]
    /// Only updated while idle — avoids SwiftUI invalidation on every scroll frame.
    @State private var videoCardFrames: [String: CGRect] = [:]
    @State private var autoplayVideoImageId: String?

    private var cardColumns: CatalogCardColumns {
        tabManager.catalogCardColumns(for: CatalogCardColumnScope.images)
    }

    private var usesOneColumnFeedLayout: Bool {
        cardColumns == .one
    }

    private var feedAutoplayGateOpen: Bool {
        imagesFeedVideoAutoplay && usesOneColumnFeedLayout && !isFeedScrolling
    }

    /// Geometry probing is expensive; only while idle and autoplay can run.
    private var shouldProbeVideoFrames: Bool {
        feedAutoplayGateOpen
    }

    private var groupingPolicy: StashImageSetGroupingPolicy {
        StashImageSetGroupingPolicy(rawValue: groupFallbackRaw) ?? .sessionThenMeta
    }

    private var oneColumnPosts: [(id: String, images: [StashImage])] {
        if groupIntoSets {
            return StashImageFilenameKeys.buildPosts(
                from: images,
                sort: sortOption,
                policy: groupingPolicy,
                groupEnabled: true,
                sessionCache: &sessionKeyCache
            )
        }
        return images.map { (id: "single|\($0.id)", images: [$0]) }
    }

    private var fullscreenSwipeImages: [StashImage] {
        if usesOneColumnFeedLayout {
            return oneColumnPosts.flatMap(\.images)
        }
        return images
    }

    private var imagesBinding: Binding<[StashImage]> {
        Binding(
            get: { fullscreenSwipeImages },
            set: { newImages in
                let byId = Dictionary(uniqueKeysWithValues: newImages.map { ($0.id, $0) })
                let remainingIds = Set(byId.keys)
                images = images.compactMap { img -> StashImage? in
                    guard remainingIds.contains(img.id) else { return nil }
                    return byId[img.id] ?? img
                }
            }
        )
    }

    private var gridColumns: [GridItem] {
        usesOneColumnFeedLayout
            ? [GridItem(.flexible(), spacing: 12)]
            : multiColumnGridItems
    }

    private var viewportFrame: CGRect {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first {
            return window.bounds
        }
        return UIScreen.main.bounds
    }

    private func recomputeAutoplayTarget(using frames: [String: CGRect]? = nil) {
        guard feedAutoplayGateOpen else {
            if autoplayVideoImageId != nil { autoplayVideoImageId = nil }
            return
        }
        let frames = frames ?? videoCardFrames
        let viewport = viewportFrame
        guard viewport.width > 0, viewport.height > 0 else { return }
        let targetY = viewport.midY
        let best = frames
            .filter { $0.value.maxY > viewport.minY && $0.value.minY < viewport.maxY }
            .min(by: { abs($0.value.midY - targetY) < abs($1.value.midY - targetY) })
        let newId = best?.key
        if autoplayVideoImageId != newId {
            autoplayVideoImageId = newId
        }
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            if usesOneColumnFeedLayout {
                let posts = oneColumnPosts
                ForEach(posts, id: \.id) { post in
                    ImageGroupCatalogCell(
                        images: post.images,
                        imagesBinding: imagesBinding,
                        autoplayVideoImageId: feedAutoplayGateOpen ? autoplayVideoImageId : nil,
                        reportsFeedVideoFrame: shouldProbeVideoFrames,
                        onLoadMore: onLoadMore,
                        onOpened: { _ in }
                    )
                    .onAppear {
                        if post.id == posts.last?.id {
                            onLoadMore()
                        }
                    }
                }
            } else {
                ForEach(images) { image in
                    NavigationLink(
                        destination: FullScreenImageView(
                            images: imagesBinding,
                            selectedImageId: image.id,
                            onLoadMore: onLoadMore
                        )
                    ) {
                        ImageThumbnailCard(image: image)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if image.id == images.last?.id {
                            onLoadMore()
                        }
                    }
                }
            }

            if isLoading {
                ProgressView()
                    .padding()
            } else if hasMore, !images.isEmpty {
                Color.clear
                    .frame(height: 1)
                    .onAppear { onLoadMore() }
            }
        }
        .id(cardColumns)
        .onPreferenceChange(ImagesFeedVideoFrameKey.self) { frames in
            // Ignore mid-scroll probes (also disabled via reportsFeedVideoFrame).
            guard !isFeedScrolling else { return }
            videoCardFrames = frames
            recomputeAutoplayTarget(using: frames)
        }
        .onChange(of: isFeedScrolling) { _, scrolling in
            if scrolling {
                autoplayVideoImageId = nil
            }
            // Idle: frame probes re-enable; preference callback picks the target.
        }
        .onChange(of: imagesFeedVideoAutoplay) { _, _ in
            recomputeAutoplayTarget()
        }
        .onChange(of: cardColumns) { _, _ in
            autoplayVideoImageId = nil
            recomputeAutoplayTarget()
        }
        .onChange(of: sortOption) { _, _ in
            sessionKeyCache.removeAll(keepingCapacity: true)
        }
        .onChange(of: groupIntoSets) { _, _ in
            sessionKeyCache.removeAll(keepingCapacity: true)
        }
        .onChange(of: groupFallbackRaw) { _, _ in
            sessionKeyCache.removeAll(keepingCapacity: true)
        }
    }
}
#endif
