//
//  TVPerformerCardView.swift
//  stashyTV
//

import SwiftUI

struct TVPerformerCardView: View {
    let performer: Performer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Profile image (portrait 2:3)
            ZStack(alignment: .bottomTrailing) {
                CustomAsyncImage(url: performer.thumbnailURL) { loader in
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
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                .aspectRatio(2/3, contentMode: .fill)
                .frame(width: 200)
                .clipped()
                .cornerRadius(12)

                // Scene count badge
                if performer.sceneCount > 0 {
                    Text("\(performer.sceneCount)")
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

            // Name
            VStack(alignment: .leading, spacing: 4) {
                Text(performer.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                if let disambiguation = performer.disambiguation, !disambiguation.isEmpty {
                    Text(disambiguation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 200)
    }
}
