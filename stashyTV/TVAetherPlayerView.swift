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

            if !engine.hasFirstFrame {
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

            if isPanelOpen {
                panelOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // The one focus target: `AetherPlayerSurface` cannot take focus itself, and any
        // second focusable element would steal the remote's transport commands.
        .focusable(!isPanelOpen)
        .focused($isPlayerFocused)
        .onAppear {
            isPlayerFocused = true
            scheduleAutoHide()
        }
        .onChange(of: engine.hasFirstFrame) { _, ready in
            if ready && !isPanelOpen { isPlayerFocused = true }
        }
        .onChange(of: isPanelOpen) { _, open in
            if !open {
                isPlayerFocused = true
                reveal()
            }
        }
        .onTapGesture { handleSelect() }
        .onPlayPauseCommand { handlePlayPause() }
        .onMoveCommand { handleMove($0) }
        .onExitCommand { handleExit() }
        .animation(.easeInOut(duration: 0.2), value: showTransport)
        .animation(.easeInOut(duration: 0.2), value: isPanelOpen)
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
                            panelButton(title: "Previous", icon: "backward.end.fill") {
                                closePanel()
                                onPrevious?()
                            }
                        }
                        if canGoNext {
                            panelButton(title: "Next", icon: "forward.end.fill") {
                                closePanel()
                                onNext?()
                            }
                        }
                    }
                }

                if !engine.audioTracks.isEmpty {
                    trackRow(heading: "Audio",
                             tracks: engine.audioTracks,
                             activeIndex: engine.activeAudioTrackIndex,
                             allowsOff: false) { index in
                        if let index { engine.selectAudioTrack(index: index) }
                    }
                }

                if !engine.subtitleTracks.isEmpty {
                    trackRow(heading: "Subtitles",
                             tracks: engine.subtitleTracks,
                             activeIndex: engine.activeSubtitleTrackIndex,
                             allowsOff: true) { index in
                        if let index {
                            engine.selectSubtitleTrack(index: index)
                        } else {
                            engine.clearSubtitle()
                        }
                    }
                }

                panelExtra()
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.9))
        }
        .ignoresSafeArea()
        .onMoveCommand { direction in
            if direction == .up { closePanel() }
        }
    }

    @ViewBuilder
    private func panelButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 24, weight: .semibold))
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
        }
        .buttonStyle(.card)
    }

    @ViewBuilder
    private func trackRow(heading: String,
                          tracks: [TrackInfo],
                          activeIndex: Int?,
                          allowsOff: Bool,
                          select: @escaping (Int?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    if allowsOff {
                        panelButton(title: activeIndex == nil ? "✓ Off" : "Off", icon: "captions.bubble") {
                            select(nil)
                        }
                    }
                    ForEach(tracks) { track in
                        panelButton(title: label(for: track, isActive: track.id == activeIndex),
                                    icon: heading == "Audio" ? "speaker.wave.2.fill" : "captions.bubble.fill") {
                            select(track.id)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
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
        switch direction {
        case .down:
            guard !isPanelOpen else { return }
            cancelScrub()
            isPanelOpen = true
            cancelAutoHide()
        case .up:
            if isPanelOpen { closePanel() } else { reveal() }
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
