//
//  TVSceneCardView.swift
//  stashyTV
//
//  Created for tvOS on 08.02.26.
//

import SwiftUI

struct TVSceneCardView: View {
    let scene: Scene

    var body: some View {
        // Thumbnail Card (16:9)
        ZStack(alignment: .bottomLeading) {
            CustomAsyncImage(url: scene.thumbnailURL) { loader in
                if loader.isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(ProgressView())
                } else if let image = loader.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 380)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                        )
                }
            }
            .frame(width: 380, height: 213.75) // Standard 16:9 for 380 width
            .clipped()

            // Gradient for text readability
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 120)

            // Info overlay
            VStack(alignment: .leading, spacing: 2) {
                Text(scene.title ?? "Untitled Scene")
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .foregroundColor(.white)

                if let studio = scene.studio {
                    Text(studio.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // Duration badge
            VStack {
                HStack(alignment: .top) {
                    Spacer()

                    if let duration = scene.sceneDuration ?? scene.duration, duration > 0 {
                        Text(formatDuration(duration))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                            .padding(12)
                    }
                }
                Spacer()
            }

            // Progress Bar
            if let resumeTime = scene.resumeTime, resumeTime > 0, let duration = scene.sceneDuration ?? scene.duration, duration > 0 {
                VStack {
                    Spacer()
                    ProgressView(value: resumeTime, total: duration)
                        .progressViewStyle(LinearProgressViewStyle(tint: AppearanceManager.shared.tintColor))
                        .frame(height: 4)
                }
            }
        }
        .frame(width: 380, height: 213.75)
        .cornerRadius(12)
    }

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
