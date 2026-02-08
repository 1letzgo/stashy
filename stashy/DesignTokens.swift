//
//  DesignTokens.swift
//  stashy
//
//  Created by Daniel Goletz on 07.02.26.
//

import SwiftUI

// MARK: - Design Tokens

enum DesignTokens {

    // MARK: - Corner Radius

    enum CornerRadius {
        /// Primary card radius (12pt)
        static let card: CGFloat = 12
        /// Button/CTA radius (14pt)
        static let button: CGFloat = 14
        /// Small elements like settings rows (10pt)
        static let small: CGFloat = 10
        /// Tiny elements like progress bars (4pt)
        static let tiny: CGFloat = 4
    }

    // MARK: - Shadows

    enum Shadow {
        /// Standard card shadow
        static let card = ShadowStyle(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        /// Subtle shadow for list items
        static let subtle = ShadowStyle(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        /// Strong shadow for floating elements
        static let floating = ShadowStyle(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }

    // MARK: - Spacing

    enum Spacing {
        /// 4pt
        static let xxs: CGFloat = 4
        /// 8pt
        static let xs: CGFloat = 8
        /// 12pt - grid spacing, card internal
        static let sm: CGFloat = 12
        /// 16pt - standard padding
        static let md: CGFloat = 16
        /// 20pt
        static let lg: CGFloat = 20
        /// 24pt
        static let xl: CGFloat = 24
    }

    // MARK: - Overlay Opacity

    enum Opacity {
        /// Placeholder backgrounds (0.1)
        static let placeholder: Double = 0.1
        /// Disabled states (0.3)
        static let disabled: Double = 0.3
        /// Medium overlay (0.4)
        static let medium: Double = 0.4
        /// Badge/overlay background (0.6)
        static let badge: Double = 0.6
        /// Strong overlay (0.8)
        static let strong: Double = 0.8
    }

    // MARK: - Badge Padding

    enum BadgePadding {
        static let horizontal: CGFloat = 8
        static let vertical: CGFloat = 4
    }

    // MARK: - Grid

    enum Grid {
        /// Standard grid spacing between items
        static let spacing: CGFloat = 12
        /// Content padding around grids
        static let contentPadding: CGFloat = 16
    }

    // MARK: - Animation

    enum Animation {
        /// Quick fade (0.2s)
        static let quick: SwiftUI.Animation = .easeInOut(duration: 0.2)
        /// Standard transition (0.3s)
        static let standard: SwiftUI.Animation = .easeInOut(duration: 0.3)
        /// Spring for interactive elements
        static let spring: SwiftUI.Animation = .spring(response: 0.3, dampingFraction: 0.7)
    }
}

// MARK: - Shadow Style Helper

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func cardShadow() -> some View {
        let s = DesignTokens.Shadow.card
        return self.shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }

    func subtleShadow() -> some View {
        let s = DesignTokens.Shadow.subtle
        return self.shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }

    func floatingShadow() -> some View {
        let s = DesignTokens.Shadow.floating
        return self.shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }
}
