//
//  TVFocusStyle.swift
//  stashyTV
//
//  Custom focus style for tvOS with scale effect and shadow
//

import SwiftUI

struct TVCardFocusStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .shadow(
                color: configuration.isPressed ? .clear : .black.opacity(0.3),
                radius: configuration.isPressed ? 0 : 8,
                x: 0,
                y: configuration.isPressed ? 0 : 4
            )
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct TVCardViewModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0)
            .shadow(
                color: .black.opacity(0.2),
                radius: 4,
                x: 0,
                y: 2
            )
            .animation(.easeInOut(duration: 0.15), value: false)
    }
}

extension ButtonStyle where Self == TVCardFocusStyle {
    static var tvCard: TVCardFocusStyle {
        TVCardFocusStyle()
    }
}

extension View {
    func tvCardStyle() -> some View {
        modifier(TVCardViewModifier())
    }
}
