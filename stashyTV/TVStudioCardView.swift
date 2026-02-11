//
//  TVStudioCardView.swift
//  stashyTV
//

import SwiftUI

struct TVStudioCardView: View {
    let studio: Studio

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Studio thumbnail
            ZStack(alignment: .bottomTrailing) {
                // Background for the inset
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)

                CustomAsyncImage(url: studio.thumbnailURL) { loader in
                    if loader.isLoading {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .overlay(ProgressView())
                    } else if let image = loader.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .overlay(
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                .frame(width: 320 - 16, height: 180 - 16) // 16:9 aspect with 8pt inset each side
                .cornerRadius(8)
                .padding(8)
                .clipped()

                // Scene count badge
                if studio.sceneCount > 0 {
                    Text("\(studio.sceneCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppearanceManager.shared.tintColor.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(14) // Offset for inset
                }
            }

            // Studio name
            VStack(alignment: .leading, spacing: 4) {
                Text(studio.name)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                if let rating = studio.rating100 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", Double(rating) / 20.0))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 320)
    }
}
