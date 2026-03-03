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
            AsyncImage(url: thumbnailURL) { phase in
                switch phase {
                case .empty:
                    Rectangle().fill(groupColor).overlay(ProgressView().scaleEffect(0.8))
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
            .fill(groupColor)
            .overlay(
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.4))
            )
    }
}
