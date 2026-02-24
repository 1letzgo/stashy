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
                .frame(width: 320, height: 180)
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
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
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", Double(rating) / 20.0))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 320, height: 180)
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
