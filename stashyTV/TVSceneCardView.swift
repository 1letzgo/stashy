//
//  TVSceneCardView.swift
//  stashyTV
//
//  Scene card for tvOS — sized for 4 visible in row
//

import SwiftUI

struct TVSceneCardView: View {
    let scene: Scene

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
                    colors: [.clear, .clear, .black.opacity(0.6), .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Studio label
                if let studio = scene.studio {
                    VStack {
                        HStack {
                            Text(studio.name.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AppearanceManager.shared.tintColor)
                                .tracking(1)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(10)
                }

                // Duration badge (top right)
                if let duration = scene.sceneDuration ?? scene.duration, duration > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            Text(formatDuration(duration))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        Spacer()
                    }
                    .padding(10)
                }

                // Rating badge (bottom right)
                if let rating = scene.rating100, rating > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", Double(rating) / 20.0))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    .padding(10)
                }

                // Resume progress bar
                if let resumeTime = scene.resumeTime, resumeTime > 0,
                   let duration = scene.sceneDuration ?? scene.duration, duration > 0 {
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 3)
                                Rectangle()
                                    .fill(AppearanceManager.shared.tintColor)
                                    .frame(width: geo.size.width * CGFloat(resumeTime / duration), height: 3)
                            }
                        }
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }
            }
            .frame(width: 400, height: 225)

            // Title + date below thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(scene.title ?? "Untitled Scene")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let date = scene.date {
                    Text(date)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                }
            }
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
