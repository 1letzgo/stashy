//
//  TVStudioCardView.swift
//  stashyTV
//
//  Studio card for tvOS — Netflix style
//

import SwiftUI

struct TVStudioCardView: View {
    let studio: Studio

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailView
                .frame(width: 410, height: 230)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if studio.sceneCount > 0 {
                Text("\(studio.sceneCount)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(12)
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Text(studio.name)
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer(minLength: 12)

                    if let rating = studio.rating100 {
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
        }
        .frame(width: 410, height: 230)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        // Match iOS behaviour: show the full studio image (no crop),
        // with subtle padding inside a neutral background.
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.08))

            TVStudioImageView(studioId: studio.id, studioName: studio.name, contentMode: .fit)
                .padding(24)
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.08))
            .overlay(
                Image(systemName: "building.2.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
            )
    }
}
