//
//  TVAetherPlayerView.swift
//  stashyTV
//
//  The tvOS transport for `AetherSceneEngine`. `AetherPlayerSurface` is a plain
//  `UIViewRepresentable` and cannot take focus, so the whole player is one
//  focusable container that translates the Siri Remote into engine calls.
//

#if canImport(AetherEngine)

import SwiftUI
import UIKit
import AetherEngine

struct TVAetherPlayerView<Panel: View>: View {

    @ObservedObject var model: TVAetherPlaybackModel

    var title: String = ""
    var subtitle: String = ""
    var posterURL: URL? = nil

    // Channel mode
    var canGoPrevious: Bool = false
    var canGoNext: Bool = false
    var onPrevious: (() -> Void)? = nil
    var onNext: (() -> Void)? = nil
    /// Extra content for the "down" panel — the channel's Up Next rail.
    @ViewBuilder var panelExtra: () -> Panel

    /// Menu button on the bare player. Defaults to dismissing the scene-detail cover.
    var onExit: (() -> Void)? = nil
    var onDisappear: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let engine = model.engine {
                TVAetherPlayerContent(
                    engine: engine,
                    title: title,
                    subtitle: subtitle,
                    posterURL: posterURL,
                    canGoPrevious: canGoPrevious,
                    canGoNext: canGoNext,
                    onPrevious: onPrevious,
                    onNext: onNext,
                    panelExtra: panelExtra,
                    onExit: exit
                )
            } else {
                TVPlayerErrorView(error: model.error, onDismiss: exit)
            }
        }
        .ignoresSafeArea()
        .onDisappear { onDisappear?() }
    }

    private func exit() {
        if let onExit {
            onExit()
        } else {
            model.isShowingPlayer = false
        }
    }
}

// MARK: - Panel environment

/// Lets `panelExtra` content (e.g. `TVMarkerRailView`) dismiss the down panel without the
/// host having to thread a closure through both the player and the extra's own API.
private struct TVPlayerClosePanelKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var tvPlayerClosePanel: () -> Void {
        get { self[TVPlayerClosePanelKey.self] }
        set { self[TVPlayerClosePanelKey.self] = newValue }
    }
}

extension TVAetherPlayerView {
    /// Single-scene player with a panel extra but no channel Prev/Next row.
    init(model: TVAetherPlaybackModel,
         title: String = "",
         subtitle: String = "",
         posterURL: URL? = nil,
         onExit: (() -> Void)? = nil,
         onDisappear: (() -> Void)? = nil,
         @ViewBuilder panelExtra: @escaping () -> Panel) {
        self.init(model: model,
                  title: title,
                  subtitle: subtitle,
                  posterURL: posterURL,
                  canGoPrevious: false,
                  canGoNext: false,
                  onPrevious: nil,
                  onNext: nil,
                  panelExtra: panelExtra,
                  onExit: onExit,
                  onDisappear: onDisappear)
    }
}

extension TVAetherPlayerView where Panel == EmptyView {
    init(model: TVAetherPlaybackModel,
         title: String = "",
         subtitle: String = "",
         posterURL: URL? = nil,
         onExit: (() -> Void)? = nil,
         onDisappear: (() -> Void)? = nil) {
        self.init(model: model,
                  title: title,
                  subtitle: subtitle,
                  posterURL: posterURL,
                  canGoPrevious: false,
                  canGoNext: false,
                  onPrevious: nil,
                  onNext: nil,
                  panelExtra: { EmptyView() },
                  onExit: onExit,
                  onDisappear: onDisappear)
    }
}

// MARK: - Content

private struct TVAetherPlayerContent<Panel: View>: View {

    @ObservedObject var engine: AetherSceneEngine

    let title: String
    let subtitle: String
    let posterURL: URL?
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: (() -> Void)?
    let onNext: (() -> Void)?
    @ViewBuilder var panelExtra: () -> Panel
    let onExit: () -> Void

    @FocusState private var isPlayerFocused: Bool
    /// Fokus-Einstieg fürs ausgeklappte Panel. Ohne ihn lässt der Fokus-Engine den
    /// Fokus beim Öffnen ins Leere laufen — der Container gibt ihn ab, das Panel
    /// nimmt ihn nicht, und die Fernbedienung tut gar nichts mehr.
    @FocusState private var panelFocus: PanelFocusTarget?
    @Namespace private var panelScope
    @State private var isPanelOpen = false
    @State private var showTransport = true
    @State private var hideWork: DispatchWorkItem?

    // Scrub mode
    @State private var isScrubbing = false
    @State private var scrubTarget: Double = 0
    @State private var scrubImage: UIImage?
    @State private var scrubCommitWork: DispatchWorkItem?
    @State private var scrubThumbGeneration = 0
    @State private var lastMove = Date.distantPast
    @State private var moveStreak = 0

    private static var autoHideDelay: Double { 4 }

    var body: some View {
        ZStack {
            AetherVideoSurface(engine: engine)
                .ignoresSafeArea()

            if !engine.hasPresentedFrame {
                posterOverlay
            }

            subtitleOverlay

            if let message = engine.errorMessage {
                errorLabel(message)
            }

            if showTransport && !isPanelOpen {
                transportOverlay
                    .transition(.opacity)
            }

            // Der Fernbedienungs-Layer ist bewusst ein **Geschwister** des Panels und
            // existiert nur, solange das Panel zu ist. Lagen `onTapGesture`,
            // `onMoveCommand` & Co. am gemeinsamen Container, hingen ihre
            // Gesten-Recognizer über den Buttons des Panels und schluckten Select
            // und die Richtungstasten — auch dann, wenn der Closure-Körper wegen
            // `guard !isPanelOpen` gar nichts tat. Genau daran scheiterte die
            // Navigation im ausgeklappten Panel.
            if !isPanelOpen {
                remoteInputLayer
            }

            if isPanelOpen {
                panelOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            isPlayerFocused = true
            scheduleAutoHide()
        }
        .onChange(of: engine.hasFirstFrame) { _, ready in
            if ready && !isPanelOpen { isPlayerFocused = true }
        }
        .onChange(of: isPanelOpen) { _, open in
            if open {
                focusPanelEntry()
            } else {
                panelFocus = nil
                restorePlayerFocus()
                reveal()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showTransport)
        .animation(.easeInOut(duration: 0.2), value: isPanelOpen)
    }

    /// Das einzige Fokus-Ziel bei geschlossenem Panel: `AetherPlayerSurface` kann
    /// selbst keinen Fokus nehmen, und ein zweites fokussierbares Element würde ihm
    /// die Transport-Kommandos wegnehmen.
    private var remoteInputLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable(true)
            .focused($isPlayerFocused)
            .onTapGesture { handleSelect() }
            .onPlayPauseCommand { handlePlayPause() }
            .onMoveCommand { handleMove($0) }
            .onExitCommand { handleExit() }
            .ignoresSafeArea()
    }

    // MARK: - Panel focus

    /// Die Reihe, die den Fokus bekommt, wenn das Panel aufgeht. `nil` heißt: es gibt
    /// weder Prev/Next noch Spuren, also übernimmt `panelExtra` per
    /// `prefersDefaultFocus`.
    private var firstPanelTarget: PanelFocusTarget? {
        if canGoPrevious || canGoNext { return .nav }
        if !engine.audioTracks.isEmpty { return .audio }
        if !engine.subtitleTracks.isEmpty { return .subtitles }
        return nil
    }

    /// Erst nach der Einblend-Animation: vorher existieren die Buttons noch nicht und
    /// die `@FocusState`-Zuweisung verpufft.
    private func focusPanelEntry() {
        guard let target = firstPanelTarget else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard isPanelOpen else { return }
            panelFocus = target
        }
    }

    /// Gegenstück: der Input-Layer wird beim Schließen neu eingesetzt, die Zuweisung
    /// muss also warten, bis er wieder im Baum ist.
    private func restorePlayerFocus() {
        isPlayerFocused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !isPanelOpen else { return }
            isPlayerFocused = true
        }
    }

    // MARK: - Poster / error

    @ViewBuilder
    private var posterOverlay: some View {
        ZStack {
            Color.black
            if let posterURL {
                CustomAsyncImage(url: posterURL) { loader in
                    if let image = loader.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .opacity(0.35)
                    } else {
                        Color.clear
                    }
                }
            }
            ProgressView()
                .scaleEffect(1.8)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func errorLabel(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 220)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Subtitles

    @ViewBuilder
    private var subtitleOverlay: some View {
        ZStack {
            if let bitmap = engine.currentSubtitleImage {
                Image(decorative: bitmap.image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 260)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, showTransport ? 260 : 90)
            }
            if let text = engine.currentSubtitleText, !text.isEmpty {
                VStack {
                    Spacer()
                    Text(text)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 80)
                        .padding(.bottom, showTransport ? 260 : 90)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Transport

    private var displayedTime: Double {
        isScrubbing ? scrubTarget : engine.currentTime
    }

    @ViewBuilder
    private var transportOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                if isScrubbing, let scrubImage {
                    Image(uiImage: scrubImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.6), lineWidth: 2)
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(title.isEmpty ? "Untitled Scene" : title)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer()
                    if engine.isUsingTranscodeFallback {
                        Text("Transcode")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.15), in: Capsule())
                    }
                    Image(systemName: engine.isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.8))
                }

                GeometryReader { geo in
                    let duration = max(engine.duration, 0.001)
                    let progress = min(max(displayedTime / duration, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule()
                            .fill(isScrubbing ? Color.white : AppearanceManager.shared.tintColor)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(timeLabel(displayedTime))
                    Spacer()
                    if canGoPrevious || canGoNext {
                        HStack(spacing: 20) {
                            if canGoPrevious {
                                Label("Prev", systemImage: "backward.end.fill")
                            }
                            if canGoNext {
                                Label("Next", systemImage: "forward.end.fill")
                            }
                            Label("Menu", systemImage: "chevron.down")
                        }
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Text(timeLabel(engine.duration))
                }
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 70)
            .padding(.top, 40)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.8)],
                               startPoint: .top,
                               endPoint: .bottom)
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - Panel (audio / subtitles / up next)

    @ViewBuilder
    private var panelOverlay: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 26) {
                if canGoPrevious || canGoNext {
                    HStack(spacing: 24) {
                        if canGoPrevious {
                            panelButton(title: "Previous",
                                        icon: "backward.end.fill",
                                        focusTarget: .nav) {
                                closePanel()
                                onPrevious?()
                            }
                        }
                        if canGoNext {
                            panelButton(title: "Next",
                                        icon: "forward.end.fill",
                                        focusTarget: canGoPrevious ? nil : .nav) {
                                closePanel()
                                onNext?()
                            }
                        }
                    }
                    .focusSection()
                }

                if !engine.audioTracks.isEmpty {
                    trackRow(heading: "Audio",
                             tracks: engine.audioTracks,
                             activeIndex: engine.activeAudioTrackIndex,
                             allowsOff: false,
                             focusTarget: firstPanelTarget == .audio ? .audio : nil) { index in
                        if let index { engine.selectAudioTrack(index: index) }
                    }
                }

                if !engine.subtitleTracks.isEmpty {
                    trackRow(heading: "Subtitles",
                             tracks: engine.subtitleTracks,
                             activeIndex: engine.activeSubtitleTrackIndex,
                             allowsOff: true,
                             focusTarget: firstPanelTarget == .subtitles ? .subtitles : nil) { index in
                        if let index {
                            engine.selectSubtitleTrack(index: index)
                        } else {
                            engine.clearSubtitle()
                        }
                    }
                }

                panelExtra()
                    .focusSection()
                    // Gibt es weder Prev/Next noch Spuren, ist der Extra-Inhalt die
                    // einzige Reihe — dann muss der Fokus-Engine ihn als Einstieg
                    // nehmen, denn `@FocusState` erreicht fremden Inhalt nicht.
                    .prefersDefaultFocus(firstPanelTarget == nil, in: panelScope)
                    .environment(\.tvPlayerClosePanel, { closePanel() })
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.9))
            .focusScope(panelScope)
        }
        .ignoresSafeArea()
        // Menu schließt das Panel. Kein `onMoveCommand` hier: dessen Recognizer läge
        // über den Buttons und würde die Richtungstasten schlucken, statt — wie der
        // frühere Kommentar annahm — nur die von keiner Reihe genommenen zu sehen.
        .onExitCommand { closePanel() }
    }

    /// Fokus-Anker des Panels. `nil` als `equals`-Wert gibt es bei `@FocusState` nicht,
    /// also wird der Modifier nur auf dem Einstiegs-Button gesetzt.
    fileprivate enum PanelFocusTarget: Hashable {
        case nav, audio, subtitles
    }

    @ViewBuilder
    private func panelButton(title: String,
                             icon: String,
                             focusTarget: PanelFocusTarget? = nil,
                             action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 24, weight: .semibold))
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
        }
        .buttonStyle(.card)

        if let focusTarget {
            button.focused($panelFocus, equals: focusTarget)
        } else {
            button
        }
    }

    @ViewBuilder
    private func trackRow(heading: String,
                          tracks: [TrackInfo],
                          activeIndex: Int?,
                          allowsOff: Bool,
                          focusTarget: PanelFocusTarget? = nil,
                          select: @escaping (Int?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    if allowsOff {
                        panelButton(title: activeIndex == nil ? "✓ Off" : "Off",
                                    icon: "captions.bubble",
                                    focusTarget: focusTarget) {
                            select(nil)
                        }
                    }
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { offset, track in
                        panelButton(title: label(for: track, isActive: track.id == activeIndex),
                                    icon: heading == "Audio" ? "speaker.wave.2.fill" : "captions.bubble.fill",
                                    focusTarget: (!allowsOff && offset == 0) ? focusTarget : nil) {
                            select(track.id)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .focusSection()
    }

    private func label(for track: TrackInfo, isActive: Bool) -> String {
        var name = track.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = track.language ?? track.codec.uppercased() }
        return isActive ? "✓ \(name)" : name
    }

    // MARK: - Remote handling

    private func handleSelect() {
        if isScrubbing {
            commitScrub()
            return
        }
        engine.togglePlayPause()
        reveal()
    }

    private func handlePlayPause() {
        if isScrubbing {
            commitScrub()
            return
        }
        engine.togglePlayPause()
        reveal()
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        // With the panel up, every move belongs to the focus engine. The ones that reach us
        // are the moves no button could take (an edge of a row, the rail's last card), and
        // treating those as seeks or as "close" made the panel feel broken.
        guard !isPanelOpen else { return }
        switch direction {
        case .down:
            cancelScrub()
            isPanelOpen = true
            cancelAutoHide()
        case .up:
            reveal()
        case .left:
            step(by: -stepSeconds())
        case .right:
            step(by: stepSeconds())
        @unknown default:
            break
        }
    }

    /// Repeated presses within 0.5 s accelerate 10 → 30 → 60 s; three quick presses also
    /// switch to a preview-first scrub that only commits on Select or after 1 s of idle.
    private func stepSeconds() -> Double {
        let now = Date()
        if now.timeIntervalSince(lastMove) < 0.5 {
            moveStreak += 1
        } else {
            moveStreak = 1
        }
        lastMove = now
        if moveStreak >= 6 { return 60 }
        if moveStreak >= 3 { return 30 }
        return 10
    }

    private func step(by delta: Double) {
        reveal()
        let duration = engine.duration
        let upperBound = duration.isFinite && duration > 0 ? duration - 0.5 : Double.greatestFiniteMagnitude

        if !isScrubbing && moveStreak >= 3 {
            isScrubbing = true
            scrubTarget = engine.currentTime
            scrubImage = nil
        }

        if isScrubbing {
            scrubTarget = min(max(0, scrubTarget + delta), upperBound)
            requestScrubThumbnail()
            scheduleScrubCommit()
        } else {
            let target = min(max(0, engine.currentTime + delta), upperBound)
            Task { await engine.seek(to: target) }
        }
    }

    private func requestScrubThumbnail() {
        scrubThumbGeneration &+= 1
        let generation = scrubThumbGeneration
        let target = scrubTarget
        Task {
            let image = await engine.scrubThumbnail(at: target, maxWidth: 320)
            guard generation == scrubThumbGeneration, let image else { return }
            scrubImage = image
        }
    }

    private func scheduleScrubCommit() {
        scrubCommitWork?.cancel()
        let work = DispatchWorkItem { commitScrub() }
        scrubCommitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func commitScrub() {
        guard isScrubbing else { return }
        scrubCommitWork?.cancel()
        scrubCommitWork = nil
        let target = scrubTarget
        isScrubbing = false
        scrubImage = nil
        moveStreak = 0
        Task { await engine.seek(to: target) }
        reveal()
    }

    private func cancelScrub() {
        scrubCommitWork?.cancel()
        scrubCommitWork = nil
        isScrubbing = false
        scrubImage = nil
        moveStreak = 0
    }

    private func closePanel() {
        isPanelOpen = false
    }

    private func handleExit() {
        if isPanelOpen {
            closePanel()
            return
        }
        if isScrubbing {
            cancelScrub()
            return
        }
        if showTransport {
            cancelAutoHide()
            showTransport = false
            return
        }
        onExit()
    }

    // MARK: - Auto hide

    private func reveal() {
        showTransport = true
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem {
            guard !isScrubbing, !isPanelOpen else { return }
            showTransport = false
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoHideDelay, execute: work)
    }

    private func cancelAutoHide() {
        hideWork?.cancel()
        hideWork = nil
    }
}

// MARK: - Player error fallback

/// Shown when the engine could not be created at all — without it the cover would be
/// empty and offer no way back.
struct TVPlayerErrorView: View {
    let error: Error?
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
                Text("Unable to play this scene")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
                if let error {
                    Text(error.localizedDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 80)
                }
                Button("Close", action: onDismiss)
                    .font(.title3)
            }
        }
        .onExitCommand { onDismiss() }
    }
}

#endif
