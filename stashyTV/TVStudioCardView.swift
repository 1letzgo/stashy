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
                CustomAsyncImage(url: studio.thumbnailURL) { loader in
                    if loader.isLoading {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(ProgressView())
                    } else if let image = loader.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.15))
                            .overlay(
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                .aspectRatio(16/9, contentMode: .fill)
                .clipped()
                .cornerRadius(12)

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
                        .padding(10)
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
