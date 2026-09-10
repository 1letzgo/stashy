//
//  StudioLogo.swift
//  stashy
//
//  Studio-Logo als kleines Abzeichen auf Szenenkarten. Rasterung und Cache
//  liegen in `StudioLogoStore` (gemeinsam mit Studios View und tvOS).
//

#if !os(tvOS)
import SwiftUI
import UIKit

/// Studio-Logo statt Name auf Szenenkarten.
///
/// Zeigt den Namen, solange kein Logo da ist: während des Ladens, bei Studios ohne
/// eigenes Bild (Stash liefert dann einen Platzhalter, den wir nicht wollen), bei
/// Renderfehlern und wenn der Schalter in Settings → Dashboard → Scenes aus ist.
struct SceneStudioBadge: View {
    let studio: SceneStudio
    var logoHeight: CGFloat = 16
    var maxLogoWidth: CGFloat = 180
    var font: Font = .caption
    var fontWeight: Font.Weight = .medium
    var uppercased: Bool = false

    @ObservedObject private var tabManager = TabManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @State private var logo: UIImage?

    var body: some View {
        Group {
            if let logo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: displaySize(for: logo).width, height: displaySize(for: logo).height)
            } else {
                Text(uppercased ? studio.name.uppercased() : studio.name)
                    .font(font)
                    .fontWeight(fontWeight)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: logoHeight + 8)
        // Gleiche Glasoptik wie die Player-Elemente in der Scene-Detailansicht.
        .stashyGlass(shape: Capsule())
        .task(id: "\(studio.logoCacheKey)|\(tabManager.sceneCardsShowStudioLogo)|\(appearanceManager.studioLogoStyle.rawValue)") {
            guard tabManager.sceneCardsShowStudioLogo, studio.hasCustomImage else {
                logo = nil
                return
            }
            logo = await StudioLogoStore.shared.image(
                studioId: studio.id,
                updatedAt: studio.updatedAt,
                height: StudioLogoStore.badgeHeight,
                maxWidth: StudioLogoStore.badgeMaxWidth,
                style: appearanceManager.studioLogoStyle
            )
        }
    }

    /// Das Logo wird immer vollständig gezeigt: normal `logoHeight` hoch, nur sehr
    /// breite Schriftzüge werden an `maxLogoWidth` gedeckelt und dafür flacher.
    /// Beschneiden wäre unlesbar; die Pill-Höhe hält `minHeight`.
    private func displaySize(for logo: UIImage) -> CGSize {
        let aspect = logo.size.width / max(logo.size.height, 1)
        var height = logoHeight
        var width = height * aspect
        if width > maxLogoWidth {
            width = maxLogoWidth
            height = width / max(aspect, 0.01)
        }
        return CGSize(width: width, height: height)
    }
}

extension SceneStudio {
    /// Ändert sich mit dem Studio-Bild (`updated_at`), damit ein neues Logo den
    /// Cache nicht überlebt.
    var logoCacheKey: String {
        StudioLogoStore.cacheKey(studioId: id, updatedAt: updatedAt, height: StudioLogoStore.badgeHeight)
    }
}
#endif
