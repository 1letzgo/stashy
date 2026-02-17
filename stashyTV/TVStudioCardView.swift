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
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                thumbnailView
                    .frame(width: 320, height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if studio.sceneCount > 0 {
                    Text("\(studio.sceneCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(studio.name)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundColor(.white)

                if let rating = studio.rating100 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", Double(rating) / 20.0))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
        .frame(width: 320)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailURL = studio.thumbnailURL {
            AsyncImage(url: thumbnailURL) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.08))
                        .overlay(ProgressView().scaleEffect(0.8))
                case .success(let image):
                    image.resizable().scaledToFill()
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
                Image(systemName: "building.2.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.12))
            )
    }
}
