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
import MediaPlayer
import AetherEngine

struct AetherSceneSurface: View {
    @ObservedObject var engine: AetherSceneEngine
    let posterURL: URL?
    @Binding var isMuted: Bool
    var onSeek: (Double) -> Void
    /// On-device live captions (AI Subs). Second source for the same overlay; an embedded or
    /// sidecar subtitle track always wins when one is selected.
    var liveCaptionText: String = ""
    /// Enters or leaves the host's own fullscreen presentation. nil hides the button.
    var onToggleFullscreen: (() -> Void)?
    /// Only drives the button's glyph — the host owns the actual presentation state.
    var isFullscreen: Bool = false
    /// Markers (start + title) drawn on the time bar and used by the marker jumps. Empty hides them.
    var markers: [AetherTimeBarMarker] = []
    private var markerSeconds: [Double] { markers.map(\.seconds) }
    /// Opens the host's add-marker flow at the current time. nil hides the button.
    var onAddMarker: (() -> Void)? = nil
    /// Host-provided rows for the "…" menu (Set Image, AI Subtitles, AI Motion, …).
    var extraMenuItems: () -> [PlayerMenuItem] = { [] }

    @ObservedObject private var tabManager = TabManager.shared
    @StateObject private var pip = AetherPictureInPictureCoordinator()
    @State private var airPlayTrigger = AetherAirPlayTrigger()
    @State private var systemVolume = AetherSystemVolumeControl()

    @State private var areControlsVisible = true
    /// Fullscreen only: crop to fill the whole screen instead of letterboxing.
    @State private var fillsScreen = false
    @State private var controlsHideToken = UUID()
    /// True while the UIKit "…" menu is on screen — the auto-hide timer rests until it goes.
    @State private var isOptionsMenuOpen = false
    @State private var isScrubbing = false
    @State private var scrubSeconds: Double = 0
    /// Last good scrub still. A nil result from the engine is transient, so it is never
    /// written back — the previous frame stays up until a better one arrives.
    @State private var scrubPreviewImage: UIImage?
    @State private var scrubPreviewTask: Task<Void, Never>?
    @State private var scrubPreviewPendingSeconds: Double?
    /// Surface height, so the inline card can use the same layout at smaller sizes.
    @State private var surfaceHeight: CGFloat = 0
    @State private var surfaceSize: CGSize = .zero
    /// Hold anywhere on the picture: 2× while pressed (same as Feeds), previous rate after.
    @State private var isFastForwarding = false
    @State private var rateBeforeFastForward: Float = 1
    /// Mirrors of engine state that is not observable, so the slider and the speed menu redraw.
    @State private var volumeLevel: Float = 1
    @State private var playbackRate: Float = 1
    #if DEBUG
    @State private var showsDebugStats = false
    #endif

    private var displayedTime: Double {
        isScrubbing ? scrubSeconds : engine.currentTime
    }

    var body: some View {
        ZStack {
            // Picture and backdrop run edge to edge (under the notch and home indicator in
            // fullscreen); the overlays below stay inside the safe area so they remain
            // reachable. Inline the surface has no safe-area inset, so this is a no-op there.
            Color.black
                .ignoresSafeArea()

            AetherPlayerSurface(engine: engine.engine)
                .ignoresSafeArea()

            if !engine.hasPresentedFrame {
                posterPlaceholder
                    .ignoresSafeArea()
            }

            if let message = engine.errorMessage {
                errorLabel(message)
            }

            subtitleOverlay

            fastForwardOverlay

            transportOverlay
                // Fullscreen: keep the controls inside the picture. A 16:9 file in landscape
                // is pillarboxed, and controls hanging into the black bars read as clipped.
                .padding(.horizontal, videoHorizontalInset)

            #if DEBUG
            if showsDebugStats {
                debugStatsCaption
            }
            #endif
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            surfaceHeight = size.height
            surfaceSize = size
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashyHardwareVolumeChanged)) { _ in
            volumeLevel = AVAudioSession.sharedInstance().outputVolume
        }
        .onAppear {
            HardwareVolumeMonitor.shared.start()
            // This surface draws cues, so it is the one that may auto-pick a track
            // ("Show subtitles automatically"); card previews never set this.
            engine.autoSelectsPreferredSubtitleTrack = true
            // The slider is the system volume, so it follows the hardware buttons. The
            // engine's own level is left alone: writing it here cleared the host's mute
            // (the volume setter un-mutes), so a muted scene started with sound.
            volumeLevel = AVAudioSession.sharedInstance().outputVolume
            playbackRate = engine.rate
            pip.update(layer: pipLayerIfEnabled)
            pip.onActiveChange = { [weak engine] active in
                engine?.setPictureInPictureActive(active)
            }
            scheduleControlsHide()
        }
        // Give the transport a few seconds once there is something to look at, so the mute and
        // PiP controls are found before the overlay hides itself.
        .onChange(of: engine.hasFirstFrame) { _, ready in
            if ready { revealControls() }
        }
        // The engine swaps its layer on every load, so the controller has to follow it.
        .onChange(of: engine.pipPlayerLayer.map(ObjectIdentifier.init)) { _, _ in
            pip.update(layer: pipLayerIfEnabled)
        }
        // Setting off → no controller at all, so the system can never start PiP on its own
        // (it did when the app resigned active, e.g. for the share sheet).
        .onChange(of: tabManager.isPiPEnabled) { _, _ in
            pip.update(layer: pipLayerIfEnabled)
        }
        .onAppear {
            // The gravity lives on the engine and outlives this view; every surface starts
            // letterboxed, and the fill mode is opted into per fullscreen session.
            fillsScreen = false
            engine.setVideoGravity(.resizeAspect)
        }
        .onChange(of: fillsScreen) { _, fills in
            engine.setVideoGravity(fills ? .resizeAspectFill : .resizeAspect)
        }
        .onDisappear {
            if isFullscreen { engine.setVideoGravity(.resizeAspect) }
            pip.update(layer: nil)
            endScrubPreview()
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

    // MARK: - Subtitles

    /// Embedded/sidecar cue first, live ASR second — never both at once.
    private var displayedSubtitleText: String? {
        if let text = engine.currentSubtitleText, !text.isEmpty { return text }
        let live = liveCaptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return live.isEmpty ? nil : live
    }

    /// Cue size multiplier: the configured point size is meant for the inline card, fullscreen
    /// gets the same step up the rest of the chrome takes.
    private var subtitleScale: CGFloat { isFullscreen ? 1.3 : 1 }

    /// The engine draws nothing itself: the host renders the cue covering the current source time.
    @ViewBuilder
    private var subtitleOverlay: some View {
        ZStack {
            if let bitmap = engine.currentSubtitleImage {
                subtitleImage(bitmap)
            }
            if let text = displayedSubtitleText {
                VStack {
                    Spacer()
                    StashySubtitleText(text: text,
                                       scale: subtitleScale,
                                       style: tabManager.subtitleStyle)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Bitmap cues carry a [0, 1] rect against their own composition canvas, so they are mapped
    /// onto the aspect-fitted video rect. An empty rect falls back to bottom-centre.
    @ViewBuilder
    private func subtitleImage(_ cue: AetherSubtitleImageCue) -> some View {
        GeometryReader { geo in
            let aspect: CGFloat? = (cue.canvasSize.width > 0 && cue.canvasSize.height > 0)
                ? cue.canvasSize.width / cue.canvasSize.height
                : nil
            let rect = Self.videoRect(in: geo.size, aspect: aspect)
            let image = Image(decorative: cue.image, scale: 1)

            if cue.position.width > 0, cue.position.height > 0 {
                image
                    .resizable()
                    .frame(width: max(1, rect.width * cue.position.width),
                           height: max(1, rect.height * cue.position.height))
                    .position(x: rect.minX + rect.width * cue.position.midX,
                              y: rect.minY + rect.height * cue.position.midY)
            } else {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: rect.width, maxHeight: rect.height * 0.3)
                    .position(x: rect.midX, y: rect.maxY - rect.height * 0.16)
            }
        }
    }

    /// Aspect-fit rect for the video inside the surface; without a known aspect the surface itself is it.
    private static func videoRect(in size: CGSize, aspect: CGFloat?) -> CGRect {
        guard let aspect, aspect > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let containerAspect = size.width / size.height
        if containerAspect > aspect {
            let width = size.height * aspect
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        } else {
            let height = size.width / aspect
            return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
        }
    }

    // MARK: - Transport

    // MARK: Metrics
    //
    // One layout for both surfaces; the inline card is simply too short for the fullscreen
    // sizes, so the same groups shrink and the volume slider drops out (mute stays).
    /// Compact control sizes for the inline card and for fullscreen — the large set was
    /// out of proportion next to the inline player. The regular set stays for big inline
    /// surfaces (iPad).
    private var isCompact: Bool { isFullscreen || (surfaceHeight > 0 && surfaceHeight < 260) }
    private var skipButtonSize: CGFloat { isCompact ? 44 : 66 }
    private var playButtonSize: CGFloat { isCompact ? 64 : 96 }
    private var centerSpacing: CGFloat { isCompact ? 24 : 70 }
    /// Width of the pillarbox on each side in fullscreen (aspect-fit), 0 when the picture
    /// spans the surface, is cropped to fill, or inline.
    private var videoHorizontalInset: CGFloat {
        guard isFullscreen, !fillsScreen, let source = engine.sourceSize,
              source.width > 0, source.height > 0,
              surfaceSize.width > 0, surfaceSize.height > 0 else { return 0 }
        let videoWidth = min(surfaceSize.width, surfaceSize.height * source.width / source.height)
        return max(0, (surfaceSize.width - videoWidth) / 2)
    }

    private var chromeButtonSize: CGFloat { isCompact ? 34 : 42 }
    private var showsVolumeSlider: Bool { !isCompact || isFullscreen }

    @ViewBuilder
    private var transportOverlay: some View {
        ZStack {
            // Left / right thirds take a double tap for -10 / +10 s (AVKit's gesture); the
            // middle third keeps a plain single tap so the most common play/pause tap never
            // waits out a double-tap window.
            HStack(spacing: 0) {
                tapRegion(doubleTapSkip: -tabManager.playerSkipSeconds)
                tapRegion(doubleTapSkip: nil)
                tapRegion(doubleTapSkip: tabManager.playerSkipSeconds)
            }

            // Opacity instead of structural insertion: a conditional `if` plus a transition
            // proved unreliable over the UIKit-hosted player view (the re-inserted controls
            // never became visible), while a plain opacity change always renders.
            // Marker jumps flank play/pause (only when the scene has markers); ±10 s lives
            // on the double-tap regions left and right of the centre.
            // The jumps wait for the first frame: while the scene loads, `markerSeconds`
            // and the playhead settle in steps, which made the buttons blink in and out.
            HStack(spacing: centerSpacing) {
                if showsMarkerJumps { markerJumpButton(forward: false, large: true) }
                playPauseGlyph
                if showsMarkerJumps { markerJumpButton(forward: true, large: true) }
            }
            .transaction { $0.animation = nil }
            .autoHiding(areControlsVisible)

            // Top row: dismiss / expand plus the output-route capsule on the left, the volume
            // capsule on the right.
            VStack {
                HStack(alignment: .top, spacing: 10) {
                    topLeadingControls
                    Spacer(minLength: 12)
                    optionsMenu
                    volumeControls
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                Spacer()
            }
            .autoHiding(areControlsVisible)

            // Bottom: the option capsule sits above the full-width time bar.
            VStack {
                Spacer()
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        if engine.isUsingTranscodeFallback { transcodeTag }
                        bottomTrailingControls
                    }
                    // Add marker on the left of the time bar.
                    HStack(spacing: 8) {
                        if onAddMarker != nil { addMarkerButton }
                        timeBar
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .autoHiding(areControlsVisible)
        }
    }

    // MARK: Top leading

    @ViewBuilder
    private var topLeadingControls: some View {
        HStack(spacing: 10) {
            if onToggleFullscreen != nil {
                dismissOrExpandButton
            }
            if isFullscreen { rotateButton }
            routeCapsule
        }
    }

    /// Fullscreen closes with an `xmark`; inline the same slot enters fullscreen.
    @ViewBuilder
    private var dismissOrExpandButton: some View {
        Button {
            HapticManager.light()
            onToggleFullscreen?()
            revealControls()
        } label: {
            glassCircle(systemName: isFullscreen ? "xmark" : "arrow.up.left.and.arrow.down.right",
                        diameter: chromeButtonSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFullscreen ? "Close" : "Full screen")
    }

    /// The layer the PiP controller may bind to — nil while PiP is switched off in Settings.
    private var pipLayerIfEnabled: AVPlayerLayer? {
        tabManager.isPiPEnabled ? engine.pipPlayerLayer : nil
    }

    private var showsPiPButton: Bool {
        pip.isAvailable && tabManager.isPiPEnabled && AVPictureInPictureController.isPictureInPictureSupported()
    }

    /// The route picker only does anything on a route that owns an AVPlayer; the software route
    /// decodes into its own layer and cannot be mirrored. With neither control the capsule goes.
    private var showsAirPlayButton: Bool {
        engine.pipPlayerLayer != nil
    }

    @ViewBuilder
    private var routeCapsule: some View {
        if showsPiPButton {
            HStack(spacing: 2) {
                pipButton
            }
            .padding(.horizontal, 6)
            .frame(height: chromeButtonSize)
            .stashyGlass(shape: Capsule())
        }
        // Hidden MPVolumeView: the only way to set the system volume from the slider.
        AetherSystemVolumeView(control: systemVolume)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        // AirPlay is an entry in the options menu; the system picker still needs a live
        // AVRoutePickerView to present from, so one sits here invisibly.
        if showsAirPlayButton {
            AetherRoutePickerView(trigger: airPlayTrigger)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: Volume

    @ViewBuilder
    private var volumeControls: some View {
        if showsVolumeSlider {
            HStack(spacing: 12) {
                volumeSlider
                muteButton
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(width: 210, height: chromeButtonSize)
            .stashyGlass(shape: Capsule())
        } else {
            muteButton
                .frame(width: chromeButtonSize, height: chromeButtonSize)
                .stashyGlass(shape: Circle())
        }
    }

    /// Custom track rather than a `Slider`: the stock control cannot be made this thin, and the
    /// engine's volume is not observable, so the level is mirrored in `volumeLevel`.
    @ViewBuilder
    private var volumeSlider: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let level = CGFloat(isMuted ? 0 : min(max(volumeLevel, 0), 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                Capsule()
                    .fill(Color.white)
                    .frame(width: width * level)
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        setVolume(Float(min(max(0, value.location.x), width) / width))
                    }
                    .onEnded { value in
                        setVolume(Float(min(max(0, value.location.x), width) / width))
                    }
            )
        }
        .frame(height: 22)
        .accessibilityLabel("Volume")
    }

    /// Dragging the slider is an unmute: the level is what the user asked for. The level is
    /// pushed to the system volume through the hidden MPVolumeView.
    private func setVolume(_ level: Float) {
        volumeLevel = level
        if level > 0, isMuted { isMuted = false }
        systemVolume.set(level)
        revealControls()
    }

    // MARK: Bottom trailing

    // MARK: Markers

    private var showsMarkerJumps: Bool { !markerSeconds.isEmpty && engine.hasPresentedFrame }

    private var sortedMarkerSeconds: [Double] { markerSeconds.sorted() }

    /// Previous = the last marker that starts at least a second before the playhead, so
    /// repeated taps walk backwards instead of re-hitting the current one.
    private var previousMarkerSeconds: Double? {
        sortedMarkerSeconds.last { $0 < displayedTime - 1 }
    }

    private var nextMarkerSeconds: Double? {
        sortedMarkerSeconds.first { $0 > displayedTime + 0.5 }
    }

    @ViewBuilder
    private func markerJumpButton(forward: Bool, large: Bool = false) -> some View {
        let target = forward ? nextMarkerSeconds : previousMarkerSeconds
        Button {
            guard let target else { return }
            HapticManager.light()
            onSeek(target)
            revealControls()
        } label: {
            glassCircle(systemName: forward ? "forward.end.fill" : "backward.end.fill",
                        diameter: large ? skipButtonSize : chromeButtonSize,
                        glyphSize: large ? (isCompact ? 18 : 24) : nil)
                .opacity(target == nil ? 0.4 : 1)
                .animation(nil, value: target == nil)
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .accessibilityLabel(forward ? "Next marker" : "Previous marker")
    }

    @ViewBuilder
    private var addMarkerButton: some View {
        Button {
            HapticManager.light()
            onAddMarker?()
            revealControls()
        } label: {
            glassCircle(systemName: "plus.square.fill.on.square.fill", diameter: chromeButtonSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add marker")
    }

    /// Fullscreen only: flips the interface between portrait and landscape through the window
    /// scene, so it works with the device's orientation lock on — the reason it exists.
    @ViewBuilder
    private var rotateButton: some View {
        Button {
            HapticManager.light()
            toggleInterfaceOrientation()
            revealControls()
        } label: {
            glassCircle(systemName: "rotate.right", diameter: chromeButtonSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rotate")
    }

    private func toggleInterfaceOrientation() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let target: UIInterfaceOrientationMask = scene.interfaceOrientation.isLandscape ? .portrait : .landscapeRight
        // Only the geometry request: the app's supported orientations stay `.all`. Narrowing
        // them to one orientation crashed UIKit as soon as a sheet + keyboard came up in
        // landscape ("no common orientation with the application"). With the device's
        // orientation lock on there is no rotation event, so the new orientation holds anyway.
        Self.didRotateInFullscreen = true
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { error in
            AppLog.debug("Rotate request failed: \(error)")
        }
    }

    private static var didRotateInFullscreen = false

    /// Back to portrait on the phone once fullscreen goes away, if the button rotated it.
    static func releaseOrientationOverride() {
        guard didRotateInFullscreen else { return }
        didRotateInFullscreen = false
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach { $0.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in } }
    }

    /// Fullscreen only: the fill toggle. (Options live next to the volume capsule.)
    @ViewBuilder
    private var bottomTrailingControls: some View {
        if isFullscreen { fillButton }
    }

    /// Non-interactive marker: this session is not playing the original file.
    @ViewBuilder
    private var transcodeTag: some View {
        Text("Transcode")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: chromeButtonSize)
            .stashyGlass(shape: Capsule())
            .allowsHitTesting(false)
    }

    private var availableSpeedOptions: [Float] {
        let cap = min(engine.engine.maxSupportedRate, 2.0)
        return AetherSceneSurfaceConstants.speedOptions.filter { $0 <= cap + 0.001 }
    }

    /// Every special function of this player in one menu: speed, tracks and whatever the
    /// host hangs in through `extraMenuItems`.
    private var playerMenuItems: [PlayerMenuItem] {
        var items: [PlayerMenuItem] = []

        items.append(.submenu(
            id: "player.speed",
            title: abs(playbackRate - 1) > 0.001
                ? "Playback Speed (\(Self.speedLabel(playbackRate)))"
                : "Playback Speed",
            systemImage: "gauge.with.dots.needle.67percent",
            items: availableSpeedOptions.map { option in
                .action(
                    id: "player.speed.\(option)",
                    title: Self.speedLabel(option),
                    isChecked: abs(playbackRate - option) < 0.001
                ) {
                    engine.rate = option
                    playbackRate = engine.rate
                    revealControls()
                }
            }
        ))

        if engine.audioTracks.count > 1 {
            items.append(.submenu(
                id: "player.audio",
                title: "Audio",
                systemImage: "waveform",
                items: engine.audioTracks.map { track in
                    .action(
                        id: "player.audio.\(track.id)",
                        title: AetherTrackLabel.audio(track),
                        isChecked: engine.activeAudioTrackIndex == track.id
                    ) {
                        engine.selectAudioTrack(index: track.id)
                        revealControls()
                    }
                }
            ))
        }

        if !engine.subtitleTracks.isEmpty {
            var subtitleItems: [PlayerMenuItem] = [
                .action(
                    id: "player.subtitle.off",
                    title: "Off",
                    isChecked: engine.activeSubtitleTrackIndex == nil
                ) {
                    engine.clearSubtitle()
                    revealControls()
                }
            ]
            subtitleItems.append(contentsOf: engine.subtitleTracks.map { track in
                .action(
                    id: "player.subtitle.\(track.id)",
                    title: AetherTrackLabel.subtitle(track),
                    isChecked: engine.activeSubtitleTrackIndex == track.id
                ) {
                    engine.selectSubtitleTrack(index: track.id)
                    revealControls()
                }
            })
            items.append(.submenu(
                id: "player.subtitles",
                title: "Subtitles",
                systemImage: "captions.bubble",
                items: subtitleItems
            ))
        }

        if showsAirPlayButton {
            items.append(.separator(id: "player.airplay.break"))
            items.append(.action(id: "player.airplay", title: "AirPlay", systemImage: "airplayvideo") {
                airPlayTrigger.present()
            })
        }

        let extras = extraMenuItems()
        if !extras.isEmpty {
            items.append(.separator(id: "player.extras.break"))
            items.append(contentsOf: extras)
        }
        return items
    }

    /// The glass circle stays pure SwiftUI; the transparent `UIButton` on top owns the menu.
    @ViewBuilder
    private var optionsMenu: some View {
        ZStack {
            glassCircle(systemName: "slider.horizontal.3", diameter: chromeButtonSize)
                .overlay(alignment: .bottom) {
                    if abs(playbackRate - 1) > 0.001 {
                        Text(Self.speedLabel(playbackRate))
                            .font(.system(size: 8, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.bottom, 2)
                    }
                }
                .allowsHitTesting(false)

            PlayerMenuButton(
                items: playerMenuItems,
                onWillPresent: {
                    isOptionsMenuOpen = true
                    revealControls()
                },
                onDidDismiss: {
                    isOptionsMenuOpen = false
                    revealControls()
                }
            )
            .frame(width: chromeButtonSize, height: chromeButtonSize)
        }
        .frame(width: chromeButtonSize, height: chromeButtonSize)
        .accessibilityLabel("More options")
    }

    private static func speedLabel(_ rate: Float) -> String {
        let rounded = (rate * 100).rounded() / 100
        let text = rounded == rounded.rounded()
            ? String(format: "%.0f", rounded)
            : String(format: "%g", rounded)
        return "\(text)×"
    }

    @ViewBuilder
    private var muteButton: some View {
        Button {
            HapticManager.light()
            let next = !isMuted
            isMuted = next
            // Explicit user action — the only place the shared choice may be written.
            ScenePlayerMute.persist(next)
            revealControls()
        } label: {
            glyph(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
    }

    /// One third of the surface. Single tap toggles playback everywhere; the outer thirds
    /// additionally take a double tap for the ±10 s jump.
    @ViewBuilder
    private func tapRegion(doubleTapSkip: Double?) -> some View {
        let region = Color.clear
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.6, pressing: { pressing in
                setFastForwarding(pressing)
            }, perform: {})
        if let doubleTapSkip {
            region
                .onTapGesture(count: 2) { skip(by: doubleTapSkip) }
                .onTapGesture { toggleControls() }
        } else {
            region
                .onTapGesture { toggleControls() }
        }
    }

    /// A tap on free surface never changes the transport: hidden controls come up, visible
    /// controls go away. Play/pause is the glyph's job.
    private func toggleControls() {
        if isOptionsMenuOpen { return }
        if areControlsVisible {
            hideControls()
        } else {
            revealControls()
        }
    }

    private func hideControls() {
        controlsHideToken = UUID()
        withAnimation(.easeInOut(duration: 0.2)) {
            areControlsVisible = false
        }
    }

    /// Press-and-hold fast forward: 2× while the finger is down, the previous rate afterwards.
    private func setFastForwarding(_ active: Bool) {
        guard active != isFastForwarding else { return }
        if active {
            guard engine.isPlaying else { return }
            HapticManager.selection()
            rateBeforeFastForward = engine.rate
            engine.rate = 2
        } else {
            engine.rate = rateBeforeFastForward
        }
        playbackRate = engine.rate
        withAnimation(.easeInOut(duration: 0.15)) { isFastForwarding = active }
    }

    @ViewBuilder
    private var fastForwardOverlay: some View {
        if isFastForwarding {
            VStack {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: isCompact ? 22 : 32, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, isCompact ? 16 : 22)
                    .padding(.vertical, isCompact ? 10 : 14)
                    .stashyGlass(shape: Capsule())
                    // Right under the top row, clear of the centre play/pause button.
                    .padding(.top, isCompact ? 12 : 16)
                Spacer()
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Seeks through the host's `onSeek`, so the coalesced engine seek, the device sync and
    /// the activity tracker all run exactly as they do for a scrub.
    private func skip(by delta: Double) {
        HapticManager.light()
        let duration = engine.duration
        let raw = engine.currentTime + delta
        let target = duration > 0 ? min(max(0, raw), duration) : max(0, raw)
        onSeek(target)
        revealControls()
    }

    @ViewBuilder
    private var playPauseGlyph: some View {
        Button {
            HapticManager.light()
            engine.togglePlayPause()
            revealControls()
        } label: {
            glassCircle(systemName: engine.isPlaying ? "pause.fill" : "play.fill",
                        diameter: playButtonSize,
                        glyphSize: isCompact ? 26 : 38)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
    }

    @ViewBuilder
    private var fillButton: some View {
        Button {
            HapticManager.light()
            fillsScreen.toggle()
            revealControls()
        } label: {
            glassCircle(systemName: fillsScreen
                        ? "rectangle.arrowtriangle.2.inward"
                        : "rectangle.arrowtriangle.2.outward",
                        diameter: chromeButtonSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fillsScreen ? "Fit to screen" : "Fill screen")
    }


    @ViewBuilder
    private var pipButton: some View {
        Button {
            HapticManager.light()
            pip.toggle()
            revealControls()
        } label: {
            glyph(pip.isActive ? "pip.exit" : "pip.enter")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pip.isActive ? "Stop Picture in Picture" : "Start Picture in Picture")
    }

    /// Full-width glass bar: elapsed on the left, the scrub track in the middle, the remaining
    /// time (`-mm:ss`) on the right.
    @ViewBuilder
    private var timeBar: some View {
        AetherTimeBar(
            currentTime: displayedTime,
            duration: max(engine.duration, 0),
            isScrubbing: isScrubbing,
            previewImage: scrubPreviewImage,
            markers: markers,
            isCompact: isCompact,
            onScrubChanged: { seconds in
                isScrubbing = true
                scrubSeconds = seconds
                requestScrubPreview(at: seconds)
                revealControls()
            },
            onScrubEnded: { seconds in
                scrubSeconds = seconds
                isScrubbing = false
                endScrubPreview()
                onSeek(seconds)
                revealControls()
            }
        )
    }

    /// One decode in flight at a time; while it runs, the newest finger position is parked
    /// and requested as soon as the current one lands. Results are applied in order, so the
    /// preview always converges on where the finger is. A nil keeps the last good frame.
    private func requestScrubPreview(at seconds: Double) {
        if scrubPreviewTask != nil {
            scrubPreviewPendingSeconds = seconds
            return
        }
        scrubPreviewPendingSeconds = nil
        scrubPreviewTask = Task { @MainActor in
            let image = await engine.scrubThumbnail(at: seconds, maxWidth: 240)
            scrubPreviewTask = nil
            guard isScrubbing else { return }
            if let image { scrubPreviewImage = image }
            if let next = scrubPreviewPendingSeconds {
                scrubPreviewPendingSeconds = nil
                requestScrubPreview(at: next)
            }
        }
    }

    private func endScrubPreview() {
        scrubPreviewPendingSeconds = nil
        scrubPreviewTask = nil
        scrubPreviewImage = nil
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
        let source = engine.activeSourceKind.rawValue
        return "route \(route)\nsource \(source)\ncodec \(codec)\ndecoder \(decoder)\nphase \(phase)"
    }
    #endif

    // MARK: - Helpers

    /// Icon inside a capsule group — the capsule already carries the glass, so this is bare.
    @ViewBuilder
    private func glyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: isCompact ? 13 : 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: chromeButtonSize, height: chromeButtonSize)
            .contentShape(Rectangle())
    }

    /// Stand-alone round glass button.
    @ViewBuilder
    private func glassCircle(systemName: String, diameter: CGFloat, glyphSize: CGFloat? = nil) -> some View {
        Image(systemName: systemName)
            .font(.system(size: glyphSize ?? (isCompact ? 13 : 15), weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .stashyGlass(shape: Circle())
            .contentShape(Circle())
    }

    private func revealControls() {
        withAnimation(.easeInOut(duration: 0.15)) {
            areControlsVisible = true
        }
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        let token = UUID()
        controlsHideToken = token
        // While the UIKit menu is up the controls must not fade out from under it — the
        // fresh token also cancels whatever hide was already in flight.
        guard !isOptionsMenuOpen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard controlsHideToken == token, !isScrubbing, !isOptionsMenuOpen else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                areControlsVisible = false
            }
        }
    }

}

enum AetherSceneSurfaceConstants {
    static let speedOptions: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
}

// MARK: - Glass and auto-hiding

private extension View {
    /// Every transport group fades and stops taking hits together.
    func autoHiding(_ visible: Bool) -> some View {
        opacity(visible ? 1 : 0).allowsHitTesting(visible)
    }
}

// MARK: - Track labels

/// Shared naming for the engine's audio and subtitle tracks, so the transport overlay and the
/// metadata pill never disagree about what a track is called.
enum AetherTrackLabel {
    static func audio(_ track: TrackInfo) -> String {
        var parts: [String] = []
        if !track.name.isEmpty {
            parts.append(track.name)
        } else if let language = track.language, !language.isEmpty {
            parts.append(language.uppercased())
        }
        if !track.codec.isEmpty { parts.append(track.codec.uppercased()) }
        if track.channels > 0 { parts.append("\(track.channels)ch") }
        return parts.isEmpty ? "Audio" : parts.joined(separator: " · ")
    }

    static func subtitle(_ track: TrackInfo) -> String {
        var name = track.name
        if name.isEmpty, let language = track.language, !language.isEmpty {
            name = language.uppercased()
        }
        if name.isEmpty { name = "Subtitles" }
        var suffixes: [String] = []
        if track.isForced { suffixes.append("Forced") }
        if track.isHearingImpaired { suffixes.append("SDH") }
        if track.isExternal { suffixes.append("External") }
        return suffixes.isEmpty ? name : "\(name) · \(suffixes.joined(separator: " · "))"
    }

    /// Compact pill caption for the current selection.
    static func short(_ track: TrackInfo) -> String {
        if let language = track.language, !language.isEmpty { return language.uppercased() }
        if !track.name.isEmpty { return track.name }
        return "Audio"
    }
}

// MARK: - AirPlay

#if os(iOS)
/// System route picker. UIKit-only control, so it is bridged rather than redrawn.
/// Sets the system output volume through MPVolumeView's slider — the supported route
/// for apps; the hardware buttons and other apps see the same value.
final class AetherSystemVolumeControl {
    weak var slider: UISlider?
    func set(_ level: Float) {
        guard let slider else { return }
        DispatchQueue.main.async {
            slider.setValue(level, animated: false)
            slider.sendActions(for: .touchUpInside)
        }
    }
}

private struct AetherSystemVolumeView: UIViewRepresentable {
    var control: AetherSystemVolumeControl
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.showsVolumeSlider = true
        view.alpha = 0.01
        control.slider = view.subviews.compactMap { $0 as? UISlider }.first
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        if control.slider == nil {
            control.slider = uiView.subviews.compactMap { $0 as? UISlider }.first
        }
    }
}

/// Lets a menu action open the system AirPlay sheet: the picker's own button is tapped
/// programmatically, which is the only supported way to present it.
final class AetherAirPlayTrigger {
    weak var pickerView: AVRoutePickerView?

    func present() {
        guard let pickerView else { return }
        // The picker still needs the layer to be attached; a detached view presents nothing.
        DispatchQueue.main.async {
            if let button = pickerView.subviews.compactMap({ $0 as? UIButton }).first {
                button.sendActions(for: .touchUpInside)
            }
        }
    }
}

private struct AetherRoutePickerView: UIViewRepresentable {
    var trigger: AetherAirPlayTrigger

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = .white
        view.tintColor = .white
        view.prioritizesVideoDevices = true
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        trigger.pickerView = view
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}

    /// The system route sheet resigns the app active; without this the privacy blur
    /// would slide over the player behind the sheet.
    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            SceneDelegate.suppressesPrivacyBlur = true
        }

        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            SceneDelegate.suppressesPrivacyBlur = false
        }
    }
}
#endif

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
            if let controller, controller.isPictureInPictureActive {
                controller.stopPictureInPicture()
            }
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
        // PiP starts only from the button, never because the app left the foreground.
        created?.canStartPictureInPictureAutomaticallyFromInline = false
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
