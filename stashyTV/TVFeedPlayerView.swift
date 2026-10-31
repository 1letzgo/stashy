//
//  TVFeedPlayerView.swift
//  stashyTV
//
//  The full-screen Feeds pager. The Siri Remote maps like the macOS Feeds keys:
//  ▲ / ▼ (click or swipe) previous / next item, ◀ / ▶ seek 10 s, a horizontal pan on the
//  touch surface scrubs freely (like the scene player), holding ◀ / ▶ seeks continuously
//  (faster the longer it is held), Play/Pause toggles.
//  Select opens a small info overlay (title, performers, studio, actions, mode switcher);
//  Menu closes the overlay first, then the feed.
//

#if canImport(AetherEngine)

import SwiftUI
import AetherEngine
import AVFoundation

struct TVFeedPlayerView: View {
    @ObservedObject var session: TVFeedSession
    /// Hands a navigation target to the Feeds tab, which dismisses the feed and pushes it.
    var onNavigate: (TVFeedDestination) -> Void
    var onClose: () -> Void

    @ObservedObject private var appearance = AppearanceManager.shared
    @StateObject private var fullPlayer = TVAetherPlaybackModel()

    @FocusState private var isInputFocused: Bool
    @FocusState private var overlayFocus: OverlayFocus?
    @State private var isOverlayOpen = false
    @State private var showsInfo = true
    @State private var infoHideWork: DispatchWorkItem?
    @State private var seekFeedback: String?
    @State private var seekFeedbackWork: DispatchWorkItem?
    @State private var isClosing = false
    /// Touch-surface scrub: where it started, and when it last moved — the swipe's own move
    /// command arrives too and must not add a 10 s step on top.
    @State private var isPanning = false
    @State private var panStartTime: Double = 0
    @State private var lastPanAt = Date.distantPast
    @State private var lastPanSeekAt = Date.distantPast
    @State private var panTarget: Double = 0
    /// ◀ / ▶ clicks: a tap steps 10 s, a hold seeks continuously until released.
    @State private var sidePresses = TVRemoteSidePressTracker()
    @State private var holdSeekTask: Task<Void, Never>?

    /// The progress line only while there is something to see it for: the info strip after
    /// an item change, seeking / scrubbing, the overlay. Watching shows the video alone.
    private var showsProgress: Bool {
        (showsInfo && !isOverlayOpen) || isOverlayOpen || isPanning || holdSeekTask != nil || seekFeedback != nil
    }

    private enum OverlayFocus: Hashable {
        case primary
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let engine = session.engine {
                TVFeedVideoLayer(engine: engine,
                                 posterURL: session.currentItem?.posterURL,
                                 isSwitching: session.isSwitching,
                                 segment: session.currentItem?.segment,
                                 showsProgress: showsProgress)
                    .ignoresSafeArea()
            } else if let poster = session.currentItem?.posterURL {
                TVFeedPoster(url: poster, showsSpinner: true)
                    .ignoresSafeArea()
            }

            if session.isLoading && session.items.isEmpty {
                ProgressView()
                    .scaleEffect(1.6)
            } else if let message = session.errorMessage, session.items.isEmpty {
                emptyState(message)
            }

            if let seekFeedback {
                Text(seekFeedback)
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if showsInfo && !isOverlayOpen, let item = session.currentItem {
                infoStrip(item)
                    .transition(.opacity)
            }

            // Wie im Player: der Fernbedienungs-Layer ist ein Geschwister des Overlays und
            // existiert nur bei geschlossenem Overlay — sonst schlucken seine Recognizer
            // Select und die Richtungstasten der Overlay-Buttons.
            // Free scrubbing on the touch surface; the move commands only give 10 s steps.
            TVRemoteScrubRecognizer(
                isEnabled: !isOverlayOpen && session.engine != nil,
                onBegan: { beginPanScrub() },
                onChanged: { panScrub(translation: $0) },
                onEnded: { endPanScrub() }
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            TVRemoteSeekHoldRecognizer(
                isEnabled: !isOverlayOpen && session.engine != nil,
                tracker: sidePresses,
                onTap: { stepSeek($0) },
                onHoldBegan: { beginHoldSeek($0) },
                onHoldEnded: { endHoldSeek() }
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            if !isOverlayOpen {
                remoteInputLayer
            } else if let item = session.currentItem {
                overlay(item)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                overlayWithoutItem
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isOverlayOpen)
        .animation(.easeInOut(duration: 0.2), value: showsInfo)
        .animation(.easeInOut(duration: 0.15), value: seekFeedback)
        .onExitCommand { handleExit() }
        .onPlayPauseCommand { session.togglePlayPause() }
        .onAppear {
            isInputFocused = true
            revealInfo()
        }
        .onChange(of: session.currentItem?.id) { _, _ in revealInfo() }
        .onChange(of: isOverlayOpen) { _, open in
            if open {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard isOverlayOpen else { return }
                    overlayFocus = .primary
                }
            } else {
                overlayFocus = nil
                isInputFocused = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard !isOverlayOpen else { return }
                    isInputFocused = true
                }
            }
        }
        .fullScreenCover(isPresented: $fullPlayer.isShowingPlayer, onDismiss: {
            fullPlayer.clear()
            session.resumeAfterFullPlayer()
            isInputFocused = true
        }) {
            TVAetherPlayerView(
                model: fullPlayer,
                title: session.currentItem?.underlyingScene?.displayTitle ?? "Untitled Scene",
                subtitle: session.currentItem?.studio?.name ?? "",
                posterURL: session.currentItem?.posterURL,
                onDisappear: { fullPlayer.saveProgress() }
            )
        }
        .dismissOnAppLock { fullPlayer.isShowingPlayer = false }
    }

    // MARK: - Remote

    /// The only focus target while the overlay is closed. `AetherPlayerSurface` cannot take
    /// focus itself, and a second focusable element would take the move commands away.
    private var remoteInputLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable(true)
            .focused($isInputFocused)
            .onTapGesture { openOverlay() }
            .onMoveCommand { handleMove($0) }
            .ignoresSafeArea()
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            session.previous()
        case .down:
            session.next()
        case .left, .right:
            // A click is the seek-hold recognizer's (tap on release, hold seeks on); a swipe
            // also arrives here, and the pan already scrubbed it freely.
            guard !sidePresses.isPressing(direction), holdSeekTask == nil else { return }
            guard !isPanning, Date().timeIntervalSince(lastPanAt) > 0.4 else { return }
            stepSeek(direction == .left ? -1 : 1)
        @unknown default:
            break
        }
    }

    private func handleExit() {
        if isOverlayOpen {
            isOverlayOpen = false
            return
        }
        close()
    }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        onClose()
    }

    private func openOverlay() {
        infoHideWork?.cancel()
        showsInfo = false
        isOverlayOpen = true
    }

    private func revealInfo() {
        showsInfo = true
        infoHideWork?.cancel()
        let work = DispatchWorkItem { showsInfo = false }
        infoHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    // MARK: - ◀ / ▶ step and hold

    private func stepSeek(_ direction: Int) {
        guard !isOverlayOpen else { return }
        let step = Double(direction) * TVFeedSession.seekStepSeconds
        session.seek(by: step)
        flashSeek(direction < 0 ? "−\(Int(TVFeedSession.seekStepSeconds)) s" : "+\(Int(TVFeedSession.seekStepSeconds)) s")
    }

    /// Held ◀ / ▶: the playhead runs on (20 → 60 → 180 s per second), the label shows where.
    private func beginHoldSeek(_ direction: Int) {
        guard !isOverlayOpen, let engine = session.engine else { return }
        holdSeekTask?.cancel()
        panTarget = engine.currentTime
        holdSeekTask = Task { @MainActor in
            var elapsed: Double = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(TVHoldSeekSpeed.tick * 1_000_000_000))
                guard !Task.isCancelled, let engine = session.engine, let range = session.seekRange else { break }
                elapsed += TVHoldSeekSpeed.tick
                let delta = Double(direction) * TVHoldSeekSpeed.secondsPerSecond(heldFor: elapsed) * TVHoldSeekSpeed.tick
                panTarget = min(max(range.lowerBound, panTarget + delta), range.upperBound)
                seekFeedbackWork?.cancel()
                seekFeedback = "\(direction < 0 ? "◀◀" : "▶▶")  \(Self.clock(panTarget)) / \(Self.clock(engine.duration))"
                session.seek(to: panTarget)
            }
        }
    }

    private func endHoldSeek() {
        guard let task = holdSeekTask else { return }
        task.cancel()
        holdSeekTask = nil
        session.seek(to: panTarget)
        let work = DispatchWorkItem { seekFeedback = nil }
        seekFeedbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: - Touch-surface scrub

    private func beginPanScrub() {
        guard !isOverlayOpen, let engine = session.engine else { return }
        isPanning = true
        lastPanAt = Date()
        panStartTime = engine.currentTime
        panTarget = panStartTime
    }

    /// Same rate as the scene player: one swipe across the surface covers about 40 % of the
    /// file (at least 1 min). Seeks live, at most every 0.15 s; the label shows the target.
    private func panScrub(translation: CGFloat) {
        guard isPanning, let engine = session.engine, let range = session.seekRange else { return }
        lastPanAt = Date()
        let duration = engine.duration
        guard duration.isFinite, duration > 0 else { return }
        let secondsPerPoint = max(60, duration * 0.4) / 1920
        panTarget = min(max(range.lowerBound, panStartTime + Double(translation) * secondsPerPoint), range.upperBound)
        seekFeedbackWork?.cancel()
        seekFeedback = "\(Self.clock(panTarget)) / \(Self.clock(duration))"
        if Date().timeIntervalSince(lastPanSeekAt) > 0.15 {
            lastPanSeekAt = Date()
            session.seek(to: panTarget)
        }
    }

    private func endPanScrub() {
        guard isPanning else { return }
        isPanning = false
        lastPanAt = Date()
        session.seek(to: panTarget)
        let work = DispatchWorkItem { seekFeedback = nil }
        seekFeedbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func flashSeek(_ label: String) {
        seekFeedback = label
        seekFeedbackWork?.cancel()
        let work = DispatchWorkItem { seekFeedback = nil }
        seekFeedbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: - Info strip

    private func infoStrip(_ item: TVFeedItem) -> some View {
        VStack {
            HStack(spacing: 14) {
                Label(session.channel?.title ?? session.mode.defaultTitle,
                      systemImage: session.channel == nil ? session.mode.icon : "tv")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(appearance.tintColor)
                Spacer()
                Text(session.positionLabel)
                    .font(.system(size: 24, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 80)
            .padding(.top, 50)

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Text(item.title)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let line = performerStudioLine(item) {
                    Text(line)
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                Text("▲ ▼ Browse   ◀ ▶ Seek (hold to scan)   Swipe to scrub   Click for info")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
            .padding(.top, 60)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func performerStudioLine(_ item: TVFeedItem) -> String? {
        var parts: [String] = []
        let performers = item.performers.prefix(4).map(\.name)
        if !performers.isEmpty { parts.append(performers.joined(separator: ", ")) }
        if let studio = item.studio?.name { parts.append(studio) }
        if parts.isEmpty, let subtitle = item.subtitle { parts.append(subtitle) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    // MARK: - Overlay

    private func overlay(_ item: TVFeedItem) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    let tags = item.tagNames.prefix(6)
                    if !tags.isEmpty {
                        Text(tags.joined(separator: "  ·  "))
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        actionButtons(item)
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 6)
                }
                .scrollClipDisabled()

                modeRow
            }
            .padding(.horizontal, 80)
            .padding(.top, 50)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.85), .black.opacity(0.92)],
                               startPoint: .top, endPoint: .bottom)
            )
            .focusSection()
        }
        .ignoresSafeArea()
    }

    /// The feed is empty (or failed) — the overlay still offers the mode switch and reload.
    private var overlayWithoutItem: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 24) {
                    overlayButton("Reload", icon: "arrow.clockwise", focus: .primary) {
                        isOverlayOpen = false
                        session.reload()
                    }
                }
                modeRow
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func actionButtons(_ item: TVFeedItem) -> some View {
        if let scene = item.underlyingScene {
            overlayButton(playLabel(item), icon: "play.fill", focus: .primary) {
                playInFullPlayer(item: item, scene: scene)
            }
            overlayButton("Scene Details", icon: "info.circle") {
                onNavigate(.scene(id: scene.id))
            }
        } else {
            overlayButton(session.engine?.isPlaying == true ? "Pause" : "Play",
                          icon: session.engine?.isPlaying == true ? "pause.fill" : "play.fill",
                          focus: .primary) {
                session.togglePlayPause()
            }
        }
        overlayButton(session.isMuted ? "Unmute" : "Mute",
                      icon: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
            session.toggleMute()
        }
        ForEach(Array(item.performers.prefix(4)), id: \.id) { performer in
            overlayButton(performer.name, icon: "person.fill") {
                onNavigate(.performer(id: performer.id, name: performer.name))
            }
        }
        if let studio = item.studio {
            overlayButton(studio.name, icon: "building.2.fill") {
                onNavigate(.studio(id: studio.id, name: studio.name))
            }
        }
    }

    private func playLabel(_ item: TVFeedItem) -> String {
        if case .marker = item { return "Play from Marker" }
        return "Play from Start"
    }

    private var modeRow: some View {
        HStack(spacing: 20) {
            ForEach(ReelsModeType.tvEnabledFeedModes, id: \.self) { mode in
                Button {
                    isOverlayOpen = false
                    session.switchMode(to: mode)
                } label: {
                    Label(mode.defaultTitle, systemImage: mode.icon)
                        .font(.system(size: 24, weight: mode == session.mode ? .bold : .regular))
                        .foregroundStyle(mode == session.mode ? appearance.tintColor : .primary)
                }
                .buttonStyle(.bordered)
            }
            Spacer(minLength: 20)
            Button {
                isOverlayOpen = false
                session.reload()
            } label: {
                Label("Reshuffle", systemImage: "shuffle")
                    .font(.system(size: 24))
            }
            .buttonStyle(.bordered)
        }
    }

    private func overlayButton(_ title: String,
                               icon: String,
                               focus: OverlayFocus? = nil,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 26, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.bordered)
        .focused($overlayFocus, equals: focus)
    }

    // MARK: - Full player

    /// Scenes and previews play the whole scene from the top, markers from the marker —
    /// like the iOS Feeds title link.
    private func playInFullPlayer(item: TVFeedItem, scene: Scene) {
        guard let url = scene.aetherVideoURL else { return }
        isOverlayOpen = false
        session.suspendForFullPlayer()
        let start: Double
        if case .marker(let marker) = item { start = marker.seconds } else { start = 0 }
        fullPlayer.setup(url: url,
                         sceneId: scene.id,
                         viewModel: session.catalog,
                         startAt: start,
                         title: scene.displayTitle,
                         subtitle: item.studio?.name,
                         artworkURL: scene.thumbnailURL,
                         fallbackSources: scene.transcodeFallbackURLs,
                         fallbackDeclaredDuration: scene.sceneDuration,
                         scene: scene)
    }

    // MARK: - Empty state

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: session.mode.icon)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.title2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Click to switch modes or reload")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
        .padding(80)
        .allowsHitTesting(false)
    }
}

// MARK: - Video layer

/// Observes the engine (picture, playhead) so the pager itself does not re-render per tick.
private struct TVFeedVideoLayer: View {
    @ObservedObject var engine: AetherSceneEngine
    let posterURL: URL?
    let isSwitching: Bool
    let segment: ReelPlaybackSegment?
    var showsProgress: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            AetherVideoSurface(engine: engine, videoGravity: .resizeAspect)

            if isSwitching || !engine.hasPresentedFrame, let posterURL {
                TVFeedPoster(url: posterURL, showsSpinner: true)
            }

            if let message = engine.errorMessage, !isSwitching {
                Text(message)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(maxHeight: .infinity)
            }

            progressBar
                .opacity(showsProgress ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: showsProgress)
        }
        .allowsHitTesting(false)
    }

    /// Thin progress line, shown only on demand (`showsProgress`); markers show their
    /// segment, not the whole file.
    private var progressBar: some View {
        GeometryReader { geo in
            let progress = currentProgress
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.18))
                Rectangle()
                    .fill(AppearanceManager.shared.tintColor)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 6)
    }

    private var currentProgress: CGFloat {
        let time = engine.currentTime
        if let segment = segment?.clamped(toFileDuration: engine.duration) {
            return PlaybackFraction.cgFloat(segment.relativeTime(forFile: time), in: segment.length)
        }
        return PlaybackFraction.cgFloat(time, in: engine.duration)
    }
}

/// Poster while the next item loads: the thumbnail dimmed behind a spinner.
private struct TVFeedPoster: View {
    let url: URL
    var showsSpinner: Bool

    var body: some View {
        ZStack {
            Color.black
            CustomAsyncImage(url: url) { loader in
                if let image = loader.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .opacity(0.45)
                } else {
                    Color.clear
                }
            }
            if showsSpinner {
                ProgressView()
                    .scaleEffect(1.6)
            }
        }
        .allowsHitTesting(false)
    }
}

#endif
