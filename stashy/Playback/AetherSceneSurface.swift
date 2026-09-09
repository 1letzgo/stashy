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
    @Binding var isMuted: Bool
    var onSeek: (Double) -> Void
    /// On-device live captions (AI Subs). Second source for the same overlay; an embedded or
    /// sidecar subtitle track always wins when one is selected.
    var liveCaptionText: String = ""
    /// Enters or leaves the host's own fullscreen presentation. nil hides the button.
    var onToggleFullscreen: (() -> Void)?
    /// Only drives the button's glyph — the host owns the actual presentation state.
    var isFullscreen: Bool = false

    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @StateObject private var pip = AetherPictureInPictureCoordinator()

    @State private var areControlsVisible = true
    @State private var controlsHideToken = UUID()
    @State private var isScrubbing = false
    @State private var scrubSeconds: Double = 0
    /// Last good scrub still. A nil result from the engine is transient, so it is never
    /// written back — the previous frame stays up until a better one arrives.
    @State private var scrubPreviewImage: UIImage?
    @State private var scrubPreviewTask: Task<Void, Never>?
    @State private var scrubPreviewPendingSeconds: Double?
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

            subtitleOverlay

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
        // Give the transport a few seconds once there is something to look at, so the mute and
        // PiP controls are found before the overlay hides itself.
        .onChange(of: engine.hasFirstFrame) { _, ready in
            if ready { revealControls() }
        }
        // The engine swaps its layer on every load, so the controller has to follow it.
        .onChange(of: engine.pipPlayerLayer.map(ObjectIdentifier.init)) { _, _ in
            pip.update(layer: engine.pipPlayerLayer)
        }
        .onDisappear {
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
                    Text(text)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    @ViewBuilder
    private var transportOverlay: some View {
        ZStack {
            // Left / right thirds take a double tap for -10 / +10 s (AVKit's gesture); the
            // middle third keeps a plain single tap so the most common play/pause tap never
            // waits out a double-tap window.
            HStack(spacing: 0) {
                tapRegion(doubleTapSkip: -10)
                tapRegion(doubleTapSkip: nil)
                tapRegion(doubleTapSkip: 10)
            }

            // Opacity instead of structural insertion: a conditional `if` plus a transition
            // proved unreliable over the UIKit-hosted player view (the re-inserted controls
            // never became visible), while a plain opacity change always renders.
            HStack(spacing: 26) {
                skipButton(-10)
                playPauseGlyph
                skipButton(10)
            }
            .opacity(areControlsVisible ? 1 : 0)
            .allowsHitTesting(areControlsVisible)

            VStack {
                Spacer()
                timeBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            .opacity(areControlsVisible ? 1 : 0)
            .allowsHitTesting(areControlsVisible)

            // Same auto-hiding group as play/pause and the time bar: one tap brings the whole
            // transport back, and it all leaves together.
            VStack {
                HStack(spacing: 8) {
                    // Output routes on the left (AirPlay, PiP), playback controls on the right.
                    #if os(iOS)
                    // The route picker only does anything on a route that owns an AVPlayer;
                    // the software route decodes into its own layer and cannot be mirrored.
                    if engine.pipPlayerLayer != nil {
                        airPlayButton
                    }
                    #endif
                    if pip.isAvailable, tabManager.isPiPEnabled, AVPictureInPictureController.isPictureInPictureSupported() {
                        pipButton
                    }
                    Spacer()
                    if hasTrackChoices {
                        tracksMenu
                    }
                    // Inline: enter-fullscreen sits with the other top-right controls.
                    // Fullscreen: the close button lives bottom-right (see below).
                    if onToggleFullscreen != nil, !isFullscreen {
                        fullscreenButton
                    }
                    muteButton
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                Spacer()
            }
            .opacity(areControlsVisible ? 1 : 0)
            .allowsHitTesting(areControlsVisible)

            if isFullscreen, onToggleFullscreen != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        fullscreenButton
                    }
                    .padding(.trailing, 10)
                    // Clear of the time bar (16 pt track + label row + its 10 pt bottom padding).
                    .padding(.bottom, 52)
                }
                .opacity(areControlsVisible ? 1 : 0)
                .allowsHitTesting(areControlsVisible)
            }
        }
    }

    private var hasTrackChoices: Bool {
        engine.audioTracks.count > 1 || !engine.subtitleTracks.isEmpty
    }

    /// One button for both track kinds: a flat menu with an Audio and a Subtitles section.
    @ViewBuilder
    private var tracksMenu: some View {
        Menu {
            if engine.audioTracks.count > 1 {
                Section("Audio") {
                    ForEach(engine.audioTracks) { track in
                        Button {
                            engine.selectAudioTrack(index: track.id)
                            revealControls()
                        } label: {
                            Label {
                                Text(AetherTrackLabel.audio(track))
                            } icon: {
                                if engine.activeAudioTrackIndex == track.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            if !engine.subtitleTracks.isEmpty {
                Section("Subtitles") {
                    Button {
                        engine.clearSubtitle()
                        revealControls()
                    } label: {
                        Label {
                            Text("Off")
                        } icon: {
                            if engine.activeSubtitleTrackIndex == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    ForEach(engine.subtitleTracks) { track in
                        Button {
                            engine.selectSubtitleTrack(index: track.id)
                            revealControls()
                        } label: {
                            Label {
                                Text(AetherTrackLabel.subtitle(track))
                            } icon: {
                                if engine.activeSubtitleTrackIndex == track.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "text.bubble")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel("Audio and subtitles")
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
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.black.opacity(0.4), in: Circle())
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
            .onLongPressGesture(minimumDuration: 0.6) {
                #if DEBUG
                showsDebugStats.toggle()
                #endif
                revealControls()
            }
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

    @ViewBuilder
    private func skipButton(_ delta: Double) -> some View {
        Button {
            skip(by: delta)
        } label: {
            Image(systemName: delta < 0 ? "gobackward.10" : "goforward.10")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Back 10 seconds" : "Forward 10 seconds")
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
            Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Color.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
    }

    @ViewBuilder
    private var fullscreenButton: some View {
        Button {
            HapticManager.light()
            onToggleFullscreen?()
            revealControls()
        } label: {
            Image(systemName: isFullscreen
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.black.opacity(0.4), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFullscreen ? "Exit full screen" : "Full screen")
    }

    #if os(iOS)
    @ViewBuilder
    private var airPlayButton: some View {
        AetherRoutePickerView()
            .frame(width: 31, height: 31)
            .background(Color.black.opacity(0.4), in: Circle())
            .accessibilityLabel("AirPlay")
    }
    #endif

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
                            requestScrubPreview(at: scrubSeconds)
                            revealControls()
                        }
                        .onEnded { value in
                            guard duration > 0 else { isScrubbing = false; return }
                            let seconds = Double(min(max(0, value.location.x), width) / width) * duration
                            scrubSeconds = seconds
                            isScrubbing = false
                            endScrubPreview()
                            onSeek(seconds)
                            revealControls()
                        }
                )
                .overlay(alignment: .topLeading) {
                    if isScrubbing, duration > 0 {
                        scrubPreviewOverlay(barWidth: width, progress: CGFloat(progress))
                    }
                }
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

    /// Floating still above the scrub thumb, clamped to the bar so it never leaves the surface.
    @ViewBuilder
    private func scrubPreviewOverlay(barWidth: CGFloat, progress: CGFloat) -> some View {
        let previewWidth: CGFloat = 120
        let previewHeight: CGFloat = previewWidth * 9 / 16
        let half = previewWidth / 2
        let rawCenter = barWidth * progress
        let center = barWidth > previewWidth
            ? min(max(half, rawCenter), barWidth - half)
            : barWidth / 2

        VStack(spacing: 3) {
            ZStack {
                Color.black.opacity(0.7)
                if let image = scrubPreviewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: previewWidth, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.75), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.55), radius: 6, x: 0, y: 2)

            Text(formatTime(scrubSeconds))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: previewWidth)
        .offset(x: center - half, y: -(previewHeight + 24))
        .allowsHitTesting(false)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
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
private struct AetherRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = .white
        view.tintColor = .white
        view.prioritizesVideoDevices = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
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
