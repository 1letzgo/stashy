//
//  TVGalleryCardView.swift
//  stashyTV
//
//  Gallery card for tvOS
//

import SwiftUI

struct TVGalleryCardView: View {
    let gallery: Gallery

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

            if let count = gallery.imageCount, count > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.caption2)
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(12)
            }

            VStack {
                Spacer()
                Text(gallery.displayName)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(width: 410, height: 230)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailURL = gallery.thumbnailURL {
            CustomAsyncImage(url: thumbnailURL) { loader in
                if let image = loader.image {
                    image.resizable().scaledToFill()
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
                Image(systemName: "photo.stack")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
            )
    }
}
