//
//  TVImageCardView.swift
//  stashyTV
//
//  Image card for tvOS
//

import SwiftUI

struct TVImageCardView: View {
    let image: StashImage
    var width: CGFloat = 300
    var height: CGFloat = 300

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            thumbnailView
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if let rating = image.rating100, rating > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", Double(rating) / 20.0))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(8)
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailURL = image.thumbnailURL {
            CustomAsyncImage(url: thumbnailURL) { loader in
                if let img = loader.image {
                    img.resizable().scaledToFill()
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
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.12))
            )
    }
}
