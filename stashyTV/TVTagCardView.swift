//
//  TVTagCardView.swift
//  stashyTV
//
//  Tag card for tvOS — Netflix style
//

import SwiftUI

struct TVTagCardView: View {
    let tag: Tag

    private var tagColor: Color {
        let hash = abs(tag.name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.35, brightness: 0.3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                thumbnailView
                    .frame(width: 200, height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if let sceneCount = tag.sceneCount, sceneCount > 0 {
                    Text("\(sceneCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(8)
                }
            }

            Text(tag.name)
                .font(.callout)
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundColor(.white)
        }
        .frame(width: 200)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailURL = tag.thumbnailURL {
            AsyncImage(url: thumbnailURL) { phase in
                switch phase {
                case .empty:
                    Rectangle().fill(tagColor).overlay(ProgressView().scaleEffect(0.8))
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
            .fill(tagColor)
            .overlay(
                Image(systemName: "tag.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.4))
            )
    }
}
