//
//  PlayerPinchZoom.swift
//  stashy
//
//  Two-finger pinch zoom for the scene player (`AetherSceneSurface`): the picture zooms around
//  the pinch point up to 4×, a one-finger drag pans it while zoomed, and a pinch back below 1×
//  springs home. Only the video layer is transformed; controls and captions stay as they are.
//
//  In fullscreen landscape the pinch also covers the fit / fill switch it replaced: a pinch from
//  fit that ends near the fill scale snaps into "fill" (the same state the fill button sets),
//  and a pinch closed while filled goes back to fit.
//
//  The scale and offset live in an `@Observable` model that the heavy surface never reads, so
//  a pinch only re-evaluates the small wrapper around the video layer (a transform, no layout).
//

#if !os(tvOS) && canImport(AetherEngine)

import SwiftUI
import Observation

@MainActor
@Observable
final class PlayerZoomModel {
    static let maximumScale: CGFloat = 4

    /// Applied to the video layer only.
    private(set) var scale: CGFloat = 1
    private(set) var offset: CGSize = .zero
    /// Stored apart from `scale` so a reader of this flag is not re-evaluated on every pinch step.
    private(set) var isZoomed = false

    /// Frames in global space: the (unscaled) video layer and the view carrying the gestures.
    @ObservationIgnored var videoFrame: CGRect = .zero
    @ObservationIgnored var gestureFrame: CGRect = .zero

    /// Picture size at 1× inside `videoFrame` for the current gravity, fixed for one gesture.
    @ObservationIgnored private var pictureSize: CGSize = .zero
    @ObservationIgnored private var pinchStartScale: CGFloat?
    @ObservationIgnored private var pinchStartOffset: CGSize = .zero
    /// Pinch point relative to the video layer's centre.
    @ObservationIgnored private var pinchAnchor: CGPoint = .zero
    @ObservationIgnored private var panStartOffset: CGSize?

    var isPinching: Bool { pinchStartScale != nil }

    func reset(animated: Bool = true) {
        pinchStartScale = nil
        panStartOffset = nil
        guard scale != 1 || offset != .zero || isZoomed else { return }
        apply(scale: 1, offset: .zero, animation: animated ? .snappy(duration: 0.25) : nil)
        isZoomed = false
    }

    // MARK: Pinch

    /// `location` is the pinch's start point in the gesture view's own space.
    func pinchChanged(magnification: CGFloat, location: CGPoint, pictureSize: CGSize) {
        if pinchStartScale == nil {
            pinchStartScale = scale
            pinchStartOffset = offset
            self.pictureSize = pictureSize
            let global = CGPoint(x: gestureFrame.minX + location.x, y: gestureFrame.minY + location.y)
            pinchAnchor = CGPoint(x: global.x - videoFrame.midX, y: global.y - videoFrame.midY)
        }
        guard let startScale = pinchStartScale, startScale > 0 else { return }
        let raw = startScale * magnification
        // Rubber band past both ends; the end of the gesture springs back into range.
        let shown: CGFloat
        if raw < 1 {
            shown = max(0.5, 1 - (1 - raw) * 0.5)
        } else if raw > Self.maximumScale {
            shown = Self.maximumScale + (raw - Self.maximumScale) * 0.3
        } else {
            shown = raw
        }
        // Keep the source point under the pinch where it is.
        let ratio = shown / startScale
        let target = CGSize(width: pinchAnchor.x - ratio * (pinchAnchor.x - pinchStartOffset.width),
                            height: pinchAnchor.y - ratio * (pinchAnchor.y - pinchStartOffset.height))
        apply(scale: shown, offset: clamped(target, scale: shown), animation: nil)
    }

    enum PinchOutcome {
        /// A pinch from fit that ended near the fill scale: switch to fill at 1×.
        case snapToFill
        /// A pinch closed from 1× while filled: back to fit.
        case backToFit
        case free
    }

    /// `fillScale` is the scale at which the fitted picture covers the layer, nil when fill is
    /// not offered (inline, portrait) or already on. `fills` is true only where fill is offered.
    func pinchEnded(fills: Bool, fillScale: CGFloat?) -> PinchOutcome {
        let startScale = pinchStartScale ?? scale
        pinchStartScale = nil
        let startedAtOne = startScale <= 1.01

        if startedAtOne, fills, scale < 0.95 {
            apply(scale: 1, offset: .zero, animation: .snappy(duration: 0.25))
            isZoomed = false
            return .backToFit
        }
        if startedAtOne, let fillScale, fillScale > 1.02, scale > 1.02,
           abs(scale / fillScale - 1) < 0.18 {
            // The gravity takes over the crop; the transform goes back at once so the picture
            // is not scaled twice for a frame.
            apply(scale: 1, offset: .zero, animation: nil)
            isZoomed = false
            return .snapToFill
        }
        if scale <= 1.05 {
            reset()
            return .free
        }
        let target = min(scale, Self.maximumScale)
        apply(scale: target, offset: clamped(offset, scale: target), animation: .snappy(duration: 0.25))
        isZoomed = true
        return .free
    }

    // MARK: Pan

    func panChanged(translation: CGSize, pictureSize: CGSize) {
        guard isZoomed, !isPinching else { return }
        if panStartOffset == nil {
            panStartOffset = offset
            self.pictureSize = pictureSize
        }
        guard let start = panStartOffset else { return }
        let target = CGSize(width: start.width + translation.width,
                            height: start.height + translation.height)
        apply(scale: scale, offset: clamped(target, scale: scale), animation: nil)
    }

    func panEnded() {
        panStartOffset = nil
    }

    // MARK: Helpers

    /// The picture never leaves a gap at an edge along an axis where it is larger than the
    /// layer; along an axis where it is smaller it stays centred.
    private func clamped(_ offset: CGSize, scale: CGFloat) -> CGSize {
        let frame = videoFrame.size
        let picture = pictureSize.width > 0 && pictureSize.height > 0 ? pictureSize : frame
        let maxX = max(0, (picture.width * scale - frame.width) / 2)
        let maxY = max(0, (picture.height * scale - frame.height) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX),
                      height: min(max(offset.height, -maxY), maxY))
    }

    private func apply(scale: CGFloat, offset: CGSize, animation: Animation?) {
        var transaction = Transaction(animation: animation)
        transaction.disablesAnimations = animation == nil
        withTransaction(transaction) {
            if self.scale != scale { self.scale = scale }
            if self.offset != offset { self.offset = offset }
        }
    }

    /// Visible picture size inside `frame` at 1× for a source aspect and the current gravity.
    static func pictureSize(in frame: CGSize, source: CGSize?, fills: Bool) -> CGSize {
        guard let source, source.width > 0, source.height > 0,
              frame.width > 0, frame.height > 0 else { return frame }
        let aspect = source.width / source.height
        // Fit: the picture spans the width when it is wider than the frame; fill the reverse.
        let spansWidth = (frame.width / frame.height < aspect) != fills
        let picture = spansWidth
            ? CGSize(width: frame.width, height: frame.width / aspect)
            : CGSize(width: frame.height * aspect, height: frame.height)
        // A filled picture is cropped to the layer: only that part can be panned to.
        return CGSize(width: min(picture.width, frame.width), height: min(picture.height, frame.height))
    }
}

/// Wraps the video layer: scale + offset and the clip, measured unscaled for the gestures.
/// The only view that reads the per-frame zoom values.
struct PlayerZoomedVideo<Content: View>: View {
    let model: PlayerZoomModel
    @ViewBuilder var content: Content

    var body: some View {
        content
            .scaleEffect(model.scale)
            .offset(model.offset)
            .clipped()
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                let old = model.videoFrame
                model.videoFrame = frame
                // A new size (rotation, fold, fullscreen) makes the zoom's bounds stale.
                if abs(old.width - frame.width) > 0.5 || abs(old.height - frame.height) > 0.5 {
                    model.reset(animated: false)
                }
            }
    }
}

/// Pinch + pan on the surface's free area (the tap regions under the controls), plus the
/// resets: new scene, fullscreen in or out, fill switched by the button.
struct PlayerPinchZoomGestures: ViewModifier {
    let model: PlayerZoomModel
    @ObservedObject var engine: AetherSceneEngine
    @Binding var fillsScreen: Bool
    /// Fullscreen landscape: the pinch may switch between fit and fill.
    let allowsFill: Bool
    let isFullscreen: Bool
    /// A pinch started (ends a hold-to-fast-forward the first finger armed).
    var onPinchBegan: () -> Void = {}
    /// The pinch switched fit / fill.
    var onFillChanged: () -> Void = {}

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                model.gestureFrame = frame
            }
            .simultaneousGesture(pinch)
            // Pan only while zoomed: unzoomed, the drag is left to the page's scroll view.
            .simultaneousGesture(pan, including: model.isZoomed ? .all : .subviews)
            .onChange(of: engine.hasPresentedFrame) { _, presented in
                // A new scene drops the picture first; a reload of the same item keeps it.
                if !presented { model.reset(animated: false) }
            }
            .onChange(of: isFullscreen) { _, _ in model.reset(animated: false) }
            .onChange(of: fillsScreen) { _, _ in
                // The fill button (or Autozoom) while zoomed: start over from the new gravity.
                if !model.isPinching { model.reset() }
            }
    }

    private var currentPictureSize: CGSize {
        PlayerZoomModel.pictureSize(in: model.videoFrame.size,
                                    source: engine.sourceSize,
                                    fills: fillsScreen)
    }

    private var pinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.02)
            .onChanged { value in
                if !model.isPinching { onPinchBegan() }
                model.pinchChanged(magnification: value.magnification,
                                   location: value.startLocation,
                                   pictureSize: currentPictureSize)
            }
            .onEnded { _ in
                let fillScale: CGFloat? = {
                    guard allowsFill, !fillsScreen else { return nil }
                    let frame = model.videoFrame.size
                    let picture = currentPictureSize
                    guard picture.width > 0, picture.height > 0 else { return nil }
                    return max(frame.width / picture.width, frame.height / picture.height)
                }()
                switch model.pinchEnded(fills: fillsScreen && allowsFill, fillScale: fillScale) {
                case .snapToFill:
                    HapticManager.light()
                    fillsScreen = true
                    onFillChanged()
                case .backToFit:
                    HapticManager.light()
                    fillsScreen = false
                    onFillChanged()
                case .free:
                    break
                }
            }
    }

    private var pan: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                model.panChanged(translation: value.translation, pictureSize: currentPictureSize)
            }
            .onEnded { _ in model.panEnded() }
    }
}

#endif
