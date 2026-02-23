//
//  TVSceneCardView.swift
//  stashyTV
//
//  Scene card for tvOS — sized for 4 visible in row
//

import SwiftUI

struct TVSceneCardView: View {
    let scene: Scene
    @Environment(\.isFocused) var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Thumbnail with overlays
            ZStack(alignment: .bottomLeading) {
                thumbnailView
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(width: 400, height: 225)
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

                // Bottom Metadata Bar (inside thumbnail)
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        if let studio = scene.studio {
                            Text(studio.name.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(AppearanceManager.shared.tintColor)
                                .tracking(1)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            if let rating = scene.rating100, rating > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.yellow)
                                    Text(String(format: "%.1f", Double(rating) / 20.0))
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            
                            if let duration = scene.sceneDuration ?? scene.duration, duration > 0 {
                                Text(formatDuration(duration))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                    .padding(12)
                    .opacity(isFocused ? 0 : 1) // Hide metadata on focus to let image shine
                }

                // Resume progress bar
                if let resumeTime = scene.resumeTime, resumeTime > 0,
                   let duration = scene.sceneDuration ?? scene.duration, duration > 0 {
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(height: 4)
                                Rectangle()
                                    .fill(AppearanceManager.shared.tintColor)
                                    .frame(width: geo.size.width * CGFloat(resumeTime / duration), height: 4)
                            }
                        }
                        .frame(height: 4)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                    .opacity(isFocused ? 0 : 1)
                }
            }
            .frame(width: 400, height: 225)

            // Title + date below thumbnail
            VStack(alignment: .leading, spacing: 4) {
                // Marquee effect concept: use a repeating animation or standard lineLimit
                // Since true marquee in SwiftUI tvOS requires complex GeometryReaders,
                // we'll simulate the "clean" look by adjusting color/weight on focus.
                Text(scene.title ?? "Untitled Scene")
                    .font(.body)
                    .fontWeight(isFocused ? .bold : .medium)
                    .foregroundColor(isFocused ? .white : .white.opacity(0.8))
                    .lineLimit(isFocused ? 2 : 1) // Expand lines on focus

                if let date = scene.date {
                    Text(date)
                        .font(.caption)
                        .foregroundColor(isFocused ? .white.opacity(0.8) : .white.opacity(0.5))
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 400)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailURL = scene.thumbnailURL {
            AsyncImage(url: thumbnailURL) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.08))
                        .overlay(ProgressView().scaleEffect(0.8))
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderView
                @unknown default:
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
                    .foregroundColor(.white.opacity(0.12))
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
