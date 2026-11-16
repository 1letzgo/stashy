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
    @Environment(\.isFocused) private var isFocused

    private var tagColor: Color {
        let hash = abs(tag.name.hashValue)
        let hue = Double(hash % 360) / 360.0
        // Fokussiert heller: die Fläche ist deckend, die Aufhellung der `.card`-Plattform
        // (bei Studio-Karten durch den transparenten Grund sichtbar) kommt hier nicht durch.
        return Color(hue: hue, saturation: 0.35, brightness: isFocused ? 0.48 : 0.3)
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
            // Wie TVSceneCardView den Verlauf bei Fokus aufhellen, aber weniger: der Name
            // unten bleibt auch auf hellen Tag-/Gruppenbildern lesbar.
            .opacity(isFocused ? 0.55 : 1.0)

            if let sceneCount = tag.sceneCount, sceneCount > 0 {
                Text("\(sceneCount)")
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
        .animation(.easeOut(duration: 0.15), value: isFocused)
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
                    .foregroundStyle(isFocused ? .primary : .secondary)
            )
    }
}
