//
//  StarRatingView.swift
//  stashy
//
//  Created by Antigravity on 16.01.26.
//

import SwiftUI

struct StarRatingView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    
    let rating100: Int?
    let isInteractive: Bool
    let size: CGFloat
    let spacing: CGFloat
    let isVertical: Bool
    let onRatingChanged: ((Int?) -> Void)?
    
    init(
        rating100: Int?,
        isInteractive: Bool = true,
        size: CGFloat = 20,
        spacing: CGFloat = 4,
        isVertical: Bool = false,
        onRatingChanged: ((Int?) -> Void)? = nil
    ) {
        self.rating100 = rating100
        self.isInteractive = isInteractive
        self.size = size
        self.spacing = spacing
        self.isVertical = isVertical
        self.onRatingChanged = onRatingChanged
    }
    
    private var stars: Int {
        guard let rating = rating100 else { return 0 }
        // Convert rating100 (0-100) to stars (0-5)
        // 100 = 5, 80 = 4, 60 = 3, 40 = 2, 20 = 1, 0 = 0
        return min(5, max(0, Int(round(Double(rating) / 20.0))))
    }
    
    private func rating100FromStars(_ starCount: Int) -> Int? {
        guard starCount > 0 else { return nil }
        return starCount * 20
    }
    
    
    var body: some View {
        Group {
            if isVertical {
                VStack(spacing: spacing) {
                    starsContent
                }
            } else {
                HStack(spacing: spacing) {
                    starsContent
                }
            }
        }
    }
    
    @ViewBuilder
    private var starsContent: some View {
        // Reverse order for vertical layout (5 on top, 1 on bottom)
        let range = isVertical ? Array((1...5).reversed()) : Array(1...5)
        ForEach(range, id: \.self) { index in
            Image(systemName: index <= stars ? "star.fill" : "star")
                .font(.system(size: size))
                .foregroundColor(index <= stars ? appearanceManager.tintColor : Color.gray.opacity(0.3))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isInteractive else { return }
                    // Tapping the same star clears the rating
                    if index == stars {
                        onRatingChanged?(nil)
                    } else {
                        onRatingChanged?(rating100FromStars(index))
                    }
                }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StarRatingView(rating100: nil, isInteractive: false)
        StarRatingView(rating100: 20)
        StarRatingView(rating100: 40)
        StarRatingView(rating100: 60)
        StarRatingView(rating100: 80)
        StarRatingView(rating100: 100)
    }
}
