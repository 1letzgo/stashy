//
//  TVSceneCardView.swift
//  stashyTV
//
//  Scene card for tvOS — sized for 4 visible in row
//

import SwiftUI

struct TVSceneCardView: View {
    let scene: Scene
    var width: CGFloat = 410
    var height: CGFloat = 230
    @Environment(\.isFocused) var isFocused

    var body: some View {
        // Thumbnail with overlays
        ZStack(alignment: .bottomLeading) {
            thumbnailView
                .aspectRatio(16/9, contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Gradient
            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(isFocused ? 0.3 : 1.0) // Lighten gradient on focus for pop effect

            // Top Labels (Studio Left, Duration Right)
            VStack {
                HStack(alignment: .top) {
                    if let studio = scene.studio {
                        Text(studio.name.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                            .tracking(1)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Spacer()
                    
                    if let duration = scene.sceneDuration ?? scene.duration, duration > 0 {
                        Text(formatDuration(duration))
                            .font(.caption.weight(.bold).monospaced())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(12)
                Spacer()
            }

            // Bottom Metadata Bar (inside thumbnail) — nur noch das Rating.
            // Der Titel steht unter der Karte, siehe `TVSceneCardTitleView`.
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Spacer(minLength: 0)

                    if let rating = scene.rating100, rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", Double(rating) / 20.0))
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(12)
            }

            // Resume progress bar
            if let resumeTime = scene.resumeTime, resumeTime > 0,
               let duration = scene.sceneDuration ?? scene.duration, duration > 0,
               duration.isFinite, resumeTime.isFinite {
                let progress = max(0.0, min(1.0, resumeTime / duration))
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        let safeWidth: CGFloat = (geo.size.width.isFinite && geo.size.width > 0) ? geo.size.width : 0
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 4)
                            Rectangle()
                                .fill(AppearanceManager.shared.tintColor)
                                .frame(width: safeWidth * CGFloat(progress), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailURL = scene.thumbnailURL {
            CustomAsyncImage(url: thumbnailURL) { loader in
                if let image = loader.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else if loader.isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.08))
                        .overlay(ProgressView().scaleEffect(0.8))
                } else {
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.08))
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
            )
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

struct TVSceneCardTitleView: View {
    let scene: Scene

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // `displayTitle` fällt auf den Dateinamen zurück — dasselbe
            // Verhalten wie auf iOS (`SceneCardView`, `HomeSceneCardView`).
            Text(scene.displayTitle ?? "Untitled Scene")
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(1)

            if let date = scene.date, !date.isEmpty {
                Text(date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !scene.performers.isEmpty {
                Text(scene.performers.prefix(3).map { $0.name }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
