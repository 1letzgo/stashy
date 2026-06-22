//
//  TVTagCardView.swift
//  stashyTV
//
//  Tag card for tvOS — 16:9 landscape thumbnails
//

import SwiftUI

struct TVTagCardView: View {
    let tag: Tag
    var width: CGFloat = 400
    var height: CGFloat = 225  // 16:9 aspect ratio

    private var tagColor: Color {
        let hash = abs(tag.name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.35, brightness: 0.3)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailView
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if let sceneCount = tag.sceneCount, sceneCount > 0 {
                Text("\(sceneCount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(12)
            }

            VStack {
                Spacer()
                Text(tag.name)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailURL = tag.thumbnailURL {
            CustomAsyncImage(url: thumbnailURL) { loader in
                if let image = loader.image {
                    image.resizable().scaledToFill()
                } else if loader.isLoading {
                    Rectangle().fill(tagColor).overlay(ProgressView().scaleEffect(0.8))
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
            .fill(tagColor)
            .overlay(
                Image(systemName: "tag.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.4))
            )
    }
}
