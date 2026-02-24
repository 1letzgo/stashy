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
        ZStack(alignment: .topTrailing) {
            thumbnailView
                .frame(width: 200, height: 200)
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
                Text(tag.name)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(width: 200, height: 200)
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
