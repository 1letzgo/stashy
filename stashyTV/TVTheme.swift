//
//  TVTheme.swift
//  stashyTV
//
//  App-Theme auf tvOS: gleiche `AppearanceManager.preferredTheme`-Einstellung
//  (Key `kPreferredTheme`) wie iOS, aber nur die dunklen Themes
//  (`AppTheme.tvOSThemes`).
//

import SwiftUI

/// Theme-Fläche, die selbst `AppearanceManager` beobachtet. `Color.appBackground`
/// liest das Theme nur beim Body-Aufbau des umgebenden Views — Seiten, die
/// AppearanceManager nicht beobachten (gepushte Details in anderen Tabs), blieben
/// nach einem Theme-Wechsel sonst in der alten Farbe stehen.
struct TVThemeFill: View {
    enum Role { case app, secondary }
    var role: Role = .app
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        switch role {
        case .app:
            Color.appBackground(for: appearance.currentTheme)
        case .secondary:
            Color.secondaryAppBackground(for: appearance.currentTheme)
        }
    }
}

extension AppTheme {
    /// Name in the tvOS theme picker.
    var tvDisplayName: String {
        switch self {
        case .darkBlue: return "Dark Blue"
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "System"
        }
    }
}

/// Theme-Karte im Appearance-Screen: Mini-Vorschau (Hintergrund, zwei Karten,
/// Akzent-Balken) plus Name; Haken beim aktiven Theme.
struct TVThemePreviewCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let tint: Color
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            swatch
                .frame(width: 300, height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? Color.white : (isFocused ? Color.white.opacity(0.5) : Color.white.opacity(0.12)),
                                lineWidth: isSelected ? 4 : 2)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, tint)
                            .padding(10)
                    }
                }
                .scaleEffect(isFocused ? 1.08 : 1.0)
                .shadow(color: .black.opacity(isFocused ? 0.6 : 0), radius: isFocused ? 18 : 0, y: isFocused ? 8 : 0)

            Text(theme.tvDisplayName)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isFocused || isSelected ? .primary : .secondary)
        }
        .padding(20) // Platz für Scale + Schatten
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var swatch: some View {
        let background = Color.appBackground(for: theme)
        let card = Color.secondaryAppBackground(for: theme)
        return ZStack(alignment: .topLeading) {
            background
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.85))
                    .frame(width: 110, height: 12)
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(card)
                            .overlay(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(index == 0 ? tint : Color.white.opacity(0.35))
                                    .frame(width: 40, height: 6)
                                    .padding(8)
                            }
                    }
                }
                .frame(height: 96)
            }
            .padding(18)
        }
    }
}
