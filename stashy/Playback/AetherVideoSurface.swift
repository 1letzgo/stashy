//
//  AetherVideoSurface.swift
//  stashy
//
//  The one video surface every screen draws the engine's picture with.
//  The engine swaps its own CALayer per session, so a host UIView cannot
//  move or crop it — everything positional happens in SwiftUI around
//  `AetherPlayerSurface`.
//

#if canImport(AetherEngine)

import SwiftUI
import AVFoundation
import AetherEngine

/// SwiftUI wrapper around `AetherPlayerSurface` with the layout the app's players need:
/// a video gravity, visual-only content insets, a top-aligned aspect-fill crop, and an
/// optional focus point plus zoom for a smart crop.
@MainActor
struct AetherVideoSurface: View {

    @ObservedObject var engine: AetherSceneEngine

    /// Gravity handed to the engine; it applies to whichever layer the current route mounts.
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    /// Visual-only insets: the picture is inset, the surface still fills its frame.
    var topContentInset: CGFloat = 0
    var bottomContentInset: CGFloat = 0

    /// Pins an aspect-fill picture to the top edge instead of centring the crop.
    var topAlignAspectFill: Bool = false

    /// Normalized [0, 1] point of the source that should stay visible while zoomed.
    /// nil centres the zoom.
    var focus: CGPoint?

    /// Scale applied around `focus`. 1 draws the picture untouched.
    var zoom: CGFloat = 1

    /// Fires once per session, the first time the engine reports a displayable frame.
    var onFirstFrame: (() -> Void)?

    private var alignment: Alignment {
        topAlignAspectFill ? .top : .center
    }

    /// Anchor for the zoom. UnitPoint shares the [0, 1] space `focus` is expressed in.
    private var zoomAnchor: UnitPoint {
        guard let focus else { return .center }
        return UnitPoint(x: min(max(0, focus.x), 1), y: min(max(0, focus.y), 1))
    }

    var body: some View {
        AetherPlayerSurface(engine: engine.engine)
            .padding(.top, topContentInset)
            .padding(.bottom, bottomContentInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .scaleEffect(max(zoom, 0.01), anchor: zoomAnchor)
            .clipped()
            .background(Color.black)
            .onAppear { engine.setVideoGravity(videoGravity) }
            .onChange(of: videoGravity) { _, gravity in
                engine.setVideoGravity(gravity)
            }
            .onChange(of: engine.hasFirstFrame) { _, ready in
                if ready { onFirstFrame?() }
            }
    }
}

#endif
