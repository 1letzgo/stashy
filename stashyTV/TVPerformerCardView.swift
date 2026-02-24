//
//  TVPerformerCardView.swift
//  stashyTV
//
//  Performer card for tvOS — Netflix style
//

import SwiftUI

struct TVPerformerCardView: View {
    let performer: Performer

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailView
                .frame(width: 200, height: 300)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if performer.sceneCount > 0 {
                Text("\(performer.sceneCount)")
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(performer.name)
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let disambiguation = performer.disambiguation, !disambiguation.isEmpty {
                        Text(disambiguation)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
        .frame(width: 200, height: 300)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailURL = performer.thumbnailURL {
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
                Image(systemName: "person.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.12))
            )
    }
}
