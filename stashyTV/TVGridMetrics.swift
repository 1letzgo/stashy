//
//  TVGridMetrics.swift
//  stashyTV
//
//  Breiten-adaptive Grid-Metrik.
//
//  Hintergrund: mit einer Sidebar steht dem Inhalt nicht mehr die volle
//  1920pt-Breite zur Verfügung. Wie viel die Sidebar wegnimmt, ist im SDK
//  **nirgends dokumentiert** — es gibt keinen Sidebar-Metrik-Environment-Wert,
//  und UIKits `contentLayoutGuide` („unobscured by the tab bar or sidebar")
//  existiert erst ab tvOS 26 und nicht in SwiftUI.
//
//  Deshalb wird hier nichts geraten: die Spaltenzahl kommt aus der Breite, die
//  der Container zur Laufzeit meldet. Das ist unter beiden denkbaren
//  tvOS-Verhalten korrekt — schrumpft die Sidebar den Frame, ist `size.width`
//  bereits reduziert und die Insets sind 0; setzt sie nur einen Safe-Area-Inset,
//  ziehen wir ihn ab.
//

import SwiftUI

// MARK: - Verfügbare Inhaltsbreite

private struct TVContentWidthKey: EnvironmentKey {
    /// Volle tvOS-Breite — der Wert, der ohne Sidebar gilt.
    static let defaultValue: CGFloat = 1920
}

extension EnvironmentValues {
    var tvContentWidth: CGFloat {
        get { self[TVContentWidthKey.self] }
        set { self[TVContentWidthKey.self] = newValue }
    }
}

private struct TVWidthPreference: PreferenceKey {
    static let defaultValue: CGFloat = 1920
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Misst die nutzbare Breite und legt sie als `tvContentWidth` ins Environment.
///
/// Der `GeometryReader` sitzt bewusst im `.background` statt als Wrapper —
/// als Wrapper würde er in vertikalen `ScrollView`s die Höhe vereinnahmen.
struct TVContentWidthReader: ViewModifier {
    @State private var width: CGFloat = 1920

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: TVWidthPreference.self,
                            value: max(
                                0,
                                geo.size.width
                                    - geo.safeAreaInsets.leading
                                    - geo.safeAreaInsets.trailing
                            )
                        )
                }
                // Darf niemals Fokus-Ziel werden.
                .focusable(false)
            )
            .onPreferenceChange(TVWidthPreference.self) { new in
                // Hysterese gegen die Rückkopplung Preference → State →
                // Environment → Relayout. Ohne sie kann Sub-Pixel-Jitter
                // endlos schwingen.
                if abs(new - width) > 1 { width = new }
            }
            .environment(\.tvContentWidth, width)
    }
}

extension View {
    /// Einmal pro Navigations-Stack anwenden — deckt Root-Views und alle
    /// gepushten Ziele darunter ab.
    func measuringTVContentWidth() -> some View {
        modifier(TVContentWidthReader())
    }
}

// MARK: - Grid-Spezifikation

/// Feste Kartenbreite, variable Spaltenzahl.
///
/// `maxColumns` entspricht dem bisherigen Festwert, das Layout kann also nie
/// über das heutige Design hinauswachsen. Bei 1920pt und ohne Sidebar liefert
/// `columnCount(for:)` exakt die bisherigen Werte.
struct TVGridSpec {
    let columnWidth: CGFloat
    let spacing: CGFloat
    let maxColumns: Int
    var minColumns: Int = 1
    var horizontalPadding: CGFloat = 60

    func columnCount(for availableWidth: CGFloat) -> Int {
        // +spacing, weil bei n Spalten nur (n-1) Zwischenräume anfallen.
        let usable = availableWidth - 2 * horizontalPadding + spacing
        let fitting = Int(floor(usable / (columnWidth + spacing)))
        return max(minColumns, min(maxColumns, fitting))
    }

    func columns(for availableWidth: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(columnWidth), spacing: spacing),
            count: columnCount(for: availableWidth)
        )
    }

    /// Szenen-Karten — Katalog wie Detailseiten.
    static let scenes = TVGridSpec(columnWidth: 410, spacing: 40, maxColumns: 4, minColumns: 2)
    /// Bild-Karten in Katalog und Gallery-Detail.
    static let images = TVGridSpec(columnWidth: 300, spacing: 30, maxColumns: 5, minColumns: 3)

    /// Label-/Wert-Raster der Detailseiten. Die zweite Spalte ist `.flexible()`
    /// und fängt Breitenverlust von selbst ab.
    static let infoColumns: [GridItem] = [
        GridItem(.fixed(240), alignment: .leading),
        GridItem(.flexible(), alignment: .leading)
    ]
}
