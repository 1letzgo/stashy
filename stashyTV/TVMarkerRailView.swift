//
//  TVMarkerRailView.swift
//  stashyTV
//
//  The single-scene counterpart to the channel's "Up Next" rail: while the down panel
//  is open, this lists the scene's markers so the remote can jump to one instead of
//  scrubbing there by hand. Sits in the same slot (`panelExtra`) as Up Next.
//

#if canImport(AetherEngine)

import SwiftUI

struct TVMarkerRailView: View {

    let markers: [SceneMarker]
    /// Live playhead — used to mark the marker whose range contains it.
    let currentTime: Double
    let onSelect: (SceneMarker) -> Void

    /// Injected by `TVAetherPlayerView`'s panel so a pick can dismiss it.
    @Environment(\.tvPlayerClosePanel) private var closePanel

    private static let cardWidth: CGFloat = 300
    private static let cardHeight: CGFloat = 169   // 16:9

    private var sorted: [SceneMarker] {
        markers.sorted { $0.seconds < $1.seconds }
    }

    /// `seconds ≤ currentTime < next marker's seconds` — the last marker owns everything after it.
    private var activeMarkerID: String? {
        let list = sorted
        guard !list.isEmpty else { return nil }
        var result: String?
        for (index, marker) in list.enumerated() {
            let upper = index + 1 < list.count ? list[index + 1].seconds : Double.greatestFiniteMagnitude
            if currentTime >= marker.seconds && currentTime < upper {
                result = marker.id
                break
            }
        }
        return result
    }

    /// The card focus lands on when it enters the rail: the marker at or before the playhead
    /// (the first one before every marker) — never simply the leftmost card.
    private var entryMarkerID: String? {
        let list = sorted
        guard let index = TVMarkerNavigation.entryIndex(starts: list.map(\.seconds), time: currentTime) else { return nil }
        return list[index].id
    }

    @FocusState private var focusedMarkerID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("markers"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    // Lazy for the same reason as the channel's Up Next rail: it opens over playback.
                    LazyHStack(alignment: .top, spacing: 30) {
                        ForEach(sorted) { marker in
                            card(for: marker, isActive: marker.id == activeMarkerID)
                                .id(marker.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 24)
                }
                .onAppear {
                    // Opens scrolled to the current marker, so its card exists (lazy stack)
                    // and is the one in view when focus comes down into the rail. No anchor:
                    // the row only scrolls as far as needed. `.leading` put the card on the
                    // scroll view's edge, past the row's leading inset, and cut the first card.
                    if let entry = entryMarkerID, entry != sorted.first?.id { proxy.scrollTo(entry) }
                }
                .onChange(of: focusedMarkerID) { old, new in
                    // Focus just came into the rail from another row: the focus engine picks
                    // the geometrically nearest card, so move it to the current marker.
                    guard old == nil, let new, let entry = entryMarkerID, new != entry else { return }
                    proxy.scrollTo(entry)
                    focusedMarkerID = entry
                }
            }
        }
        .focusSection()
    }

    @ViewBuilder
    private func card(for marker: SceneMarker, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onSelect(marker)
                closePanel()
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    thumbnail(for: marker)

                    Text(timeLabel(marker.seconds))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(10)
                }
                .frame(width: Self.cardWidth, height: Self.cardHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppearanceManager.shared.tintColor.opacity(isActive ? 0.9 : 0),
                                lineWidth: isActive ? 4 : 0)
                )
            }
            .buttonStyle(.card)
            .focused($focusedMarkerID, equals: marker.id)

            Text(displayTitle(for: marker))
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(isActive ? 0.95 : 0.7))
                .lineLimit(1)
                .frame(width: Self.cardWidth, alignment: .leading)
        }
        .frame(width: Self.cardWidth)
    }

    @ViewBuilder
    private func thumbnail(for marker: SceneMarker) -> some View {
        if let url = marker.thumbnailURL {
            CustomAsyncImage(url: url) { loader in
                if let image = loader.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.cardWidth, height: Self.cardHeight)
                        .clipped()
                } else {
                    placeholder.overlay(ProgressView().scaleEffect(0.8))
                }
            }
        } else {
            placeholder.overlay(
                Image(systemName: "bookmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            )
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: Self.cardWidth, height: Self.cardHeight)
    }

    private func displayTitle(for marker: SceneMarker) -> String {
        if let title = marker.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let tag = marker.primaryTag?.name.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
            return tag
        }
        return tr("marker")
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

#endif
