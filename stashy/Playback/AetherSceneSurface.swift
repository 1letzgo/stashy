//
//  AetherSceneSurface.swift
//  stashy
//
//  SwiftUI surface for the optional playback engine in Scene Detail.
//  Deliberately minimal: the engine has no AVKit transport bar, so this
//  draws the few controls the detail screen needs (play/pause, a slim
//  time bar, and PiP where the route actually owns an AVPlayerLayer).
//

#if !os(tvOS) && canImport(AetherEngine)

import SwiftUI
import AVFoundation
import AVKit
import AetherEngine

struct AetherSceneSurface: View {
    @ObservedObject var engine: AetherSceneEngine
    let posterURL: URL?
    var onSeek: (Double) -> Void

    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @StateObject private var pip = AetherPictureInPictureCoordinator()

    @State private var areControlsVisible = true
    @State private var controlsHideToken = UUID()
    @State private var isScrubbing = false
    @State private var scrubSeconds: Double = 0
    #if DEBUG
    @State private var showsDebugStats = false
    #endif

    private var displayedTime: Double {
        isScrubbing ? scrubSeconds : engine.currentTime
    }

    var body: some View {
        ZStack {
            Color.black

            AetherPlayerSurface(engine: engine.engine)

            if !engine.hasFirstFrame {
                posterPlaceholder
            }

            if let message = engine.errorMessage {
                errorLabel(message)
            }

            transportOverlay

            #if DEBUG
            if showsDebugStats {
                debugStatsCaption
            }
            #endif
        }
        .contentShape(Rectangle())
        .onAppear {
            pip.update(layer: engine.pipPlayerLayer)
            pip.onActiveChange = { [weak engine] active in
                engine?.setPictureInPictureActive(active)
            }
            scheduleControlsHide()
        }
        // The engine swaps its layer on every load, so the controller has to follow it.
        .onChange(of: engine.pipPlayerLayer.map(ObjectIdentifier.init)) { _, _ in
            pip.update(layer: engine.pipPlayerLayer)
        }
        .onDisappear {
            pip.update(layer: nil)
        }
    }

    // MARK: - Poster / error

    @ViewBuilder
    private var posterPlaceholder: some View {
        ZStack {
            if let posterURL {
                CustomAsyncImage(url: posterURL) { @MainActor loader in
                    if let image = loader.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else {
                        Color.black
                    }
                }
            }
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    @ViewBuilder
    private func errorLabel(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.65), in: Capsule())
                .padding(.bottom, 46)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Transport

    @ViewBuilder
    private var transportOverlay: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    engine.togglePlayPause()
                    revealControls()
                }
                .onLongPressGesture(minimumDuration: 0.6) {
                    #if DEBUG
                    showsDebugStats.toggle()
                    #endif
                    revealControls()
                }

            if areControlsVisible {
                playPauseGlyph
            }

            VStack {
                Spacer()
                if areControlsVisible {
                    timeBar
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }
            }

            if pip.isAvailable, tabManager.isPiPEnabled, AVPictureInPictureController.isPictureInPictureSupported() {
                VStack {
                    HStack {
                        Spacer()
                        pipButton
                            .padding(.trailing, 10)
                            .padding(.top, 10)
                    }
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var playPauseGlyph: some View {
        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(.white)
            .padding(16)
            .background(Color.black.opacity(0.35), in: Circle())
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    @ViewBuilder
    private var pipButton: some View {
        Button {
            HapticManager.light()
            pip.toggle()
            revealControls()
        } label: {
            Image(systemName: pip.isActive ? "pip.exit" : "pip.enter")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.black.opacity(0.4), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pip.isActive ? "Stop Picture in Picture" : "Start Picture in Picture")
    }

    @ViewBuilder
    private var timeBar: some View {
        let duration = max(engine.duration, 0)
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let progress = duration > 0 ? min(1, max(0, displayedTime / duration)) : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                    Capsule()
                        .fill(appearanceManager.tintColor)
                        .frame(width: width * CGFloat(progress))
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            isScrubbing = true
                            scrubSeconds = Double(min(max(0, value.location.x), width) / width) * duration
                            revealControls()
                        }
                        .onEnded { value in
                            guard duration > 0 else { isScrubbing = false; return }
                            let seconds = Double(min(max(0, value.location.x), width) / width) * duration
                            scrubSeconds = seconds
                            isScrubbing = false
                            onSeek(seconds)
                            revealControls()
                        }
                )
            }
            .frame(height: 16)

            HStack {
                Text(formatTime(displayedTime))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    #if DEBUG
    @ViewBuilder
    private var debugStatsCaption: some View {
        VStack {
            HStack {
                Text(debugStatsText)
                    .font(.system(size: 9, weight: .medium).monospaced())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.leading, 10)
                    .padding(.top, 10)
                Spacer()
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var debugStatsText: String {
        let underlying = engine.engine
        let route = underlying.videoRoute.rawValue
        let codec = underlying.sourceVideoCodecName ?? "—"
        let decoder = underlying.activeVideoDecoder ?? "—"
        let phase = String(describing: underlying.playbackPhase)
        return "route \(route)\ncodec \(codec)\ndecoder \(decoder)\nphase \(phase)"
    }
    #endif

    // MARK: - Helpers

    private func revealControls() {
        withAnimation(.easeInOut(duration: 0.15)) {
            areControlsVisible = true
        }
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        let token = UUID()
        controlsHideToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard controlsHideToken == token, !isScrubbing else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                areControlsVisible = false
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Picture in Picture

/// Owns the `AVPictureInPictureController` for whichever layer the engine currently exposes.
/// The engine hands out a new layer per load, so the controller is rebuilt on identity changes.
private final class AetherPictureInPictureCoordinator: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {

    @Published private(set) var isAvailable = false
    @Published private(set) var isActive = false

    var onActiveChange: ((Bool) -> Void)?

    private var controller: AVPictureInPictureController?
    private weak var boundLayer: AVPlayerLayer?

    func update(layer: AVPlayerLayer?) {
        guard let layer else {
            controller = nil
            boundLayer = nil
            if isAvailable { isAvailable = false }
            if isActive { isActive = false }
            return
        }
        if boundLayer === layer, controller != nil { return }
        boundLayer = layer
        let created = AVPictureInPictureController(playerLayer: layer)
        created?.delegate = self
        controller = created
        isAvailable = created != nil
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        setActive(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        setActive(false)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        AppLog.error("PiP failed to start: \(error.localizedDescription)")
        setActive(false)
    }

    private func setActive(_ active: Bool) {
        DispatchQueue.main.async {
            self.isActive = active
            self.onActiveChange?(active)
        }
    }
}

#endif
