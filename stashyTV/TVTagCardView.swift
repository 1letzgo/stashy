//
//  TVTagCardView.swift
//  stashyTV
//

import SwiftUI

struct TVTagCardView: View {
    let tag: Tag

    // Generate a consistent color from the tag name
    private var tagColor: Color {
        let hash = abs(tag.name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.4, brightness: 0.35)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tag image or colored placeholder
            ZStack(alignment: .bottomTrailing) {
                CustomAsyncImage(url: tag.thumbnailURL) { loader in
                    if loader.isLoading {
                        Rectangle()
                            .fill(tagColor)
                            .overlay(ProgressView())
                    } else if let image = loader.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(tagColor)
                            .overlay(
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.white.opacity(0.6))
                            )
                    }
                }
                .aspectRatio(1.0, contentMode: .fill)
                .frame(minHeight: 160)
                .clipped()
                .cornerRadius(12)

                // Scene count badge
                if let sceneCount = tag.sceneCount, sceneCount > 0 {
                    Text("\(sceneCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppearanceManager.shared.tintColor.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .padding(8)
                }
            }

            // Tag name
            Text(tag.name)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
        }
        .frame(width: 180)
    }
}
