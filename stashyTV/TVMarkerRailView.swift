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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Markers")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 30) {
                    ForEach(sorted) { marker in
                        card(for: marker, isActive: marker.id == activeMarkerID)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 24)
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
        return "Marker"
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
