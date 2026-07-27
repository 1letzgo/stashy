//
//  TVGroupCardView.swift
//  stashyTV
//
//  Group card for tvOS — Unified style
//

import SwiftUI

struct TVGroupCardView: View {
    let group: StashGroup

    private var groupColor: Color {
        let hash = abs(group.name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.35, brightness: 0.3)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailView
                .frame(width: 260, height: 390)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if group.sceneCountDisplay > 0 {
                Text("\(group.sceneCountDisplay)")
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
                Text(group.name)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(width: 260, height: 390)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailURL = group.thumbnailURL {
            CustomAsyncImage(url: thumbnailURL) { loader in
                if let image = loader.image {
                    image.resizable().scaledToFill()
                } else if loader.isLoading {
                    Rectangle().fill(groupColor).overlay(ProgressView().scaleEffect(0.8))
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
            .fill(groupColor)
            .overlay(
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            )
    }
}
