//
//  TVAetherPlaybackModel.swift
//  stashyTV
//
//  Playback state for tvOS on top of `AetherSceneEngine`. Replaces the old
//  `TVPlayerViewModel` (the old KVO-based route): one long-lived engine per session,
//  resume persistence, Now-Playing metadata and the channel's item hand-over.
//

#if canImport(AetherEngine)

import Foundation
import Combine
import SwiftUI
import UIKit
import MediaPlayer

@MainActor
final class TVAetherPlaybackModel: ObservableObject {

    /// Drives the scene detail `fullScreenCover`. The channel presents its player itself.
    @Published var isShowingPlayer = false
    /// Only set when the engine itself could not be created; playback errors live on the engine.
    @Published var error: Error?

    /// Called when the current item finishes. Used by channel continuous play.
    var onPlaybackEnded: (() -> Void)?

    /// The one engine for this session. Rebuilt after `clear()`.
    @Published private(set) var engine: AetherSceneEngine?

    var hasEngine: Bool { engine != nil }

    private var cancellables = Set<AnyCancellable>()
    private var engineCancellables = Set<AnyCancellable>()
    /// Resume position and play duration, synced like the phone player (`SceneDetailView`):
    /// `sceneSaveActivity` every 10 s of real watching, on pause and when leaving. Before, tvOS
    /// sent the resume point only (`playDuration: 0`), so Stash never saw how long a scene was
    /// watched there.
    private let activityTracker = ScenePlaybackActivityTracker()
    /// Settings › Playback › "Count as played": the play is credited once the scene has been
    /// watched that long in this session (`playCreditClock`), not when playback starts.
    private var playCreditTimer: AnyCancellable?
    /// Time actually watched of the current item — resume position and seeks add nothing.
    private var playCreditClock = PlayCountWatchClock()
    private var creditedSceneIds: Set<String> = []
    private var sceneId: String?
    private var viewModel: StashDBViewModel?
    /// `saveProgress()` already ran in `suspend()` — skip the duplicate in `clear()`.
    private var isSuspended = false
    /// Guards a stale artwork download from overwriting a newer item's Now-Playing info.
    private var nowPlayingGeneration = 0
    private var nowPlayingInfo: [String: Any] = [:]
    /// Set while an item hand-over (channel Next / Up Next) is in flight. The engine keeps the
    /// outgoing item's `currentTime` until the new one ticks, so neither the play credit nor the
    /// resume save may read the playhead before the new item has shown its first frame.
    private var isAwaitingNewItem = false

    private var playheadBelongsToCurrentItem: Bool {
        guard let engine else { return false }
        return !isAwaitingNewItem && engine.hasFirstFrame
    }

    init() {
        // Combine instead of raw observer tokens: the subscriptions die with the model,
        // so there is nothing to unregister in a `deinit` on a `@MainActor` class.
        let center = NotificationCenter.default
        center.publisher(for: UIApplication.willResignActiveNotification)
            .merge(with: center.publisher(for: UIApplication.didEnterBackgroundNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.saveProgress() }
            .store(in: &cancellables)
    }

    // MARK: - Engine

    @discardableResult
    private func ensureEngine() -> AetherSceneEngine? {
        if let engine { return engine }
        do {
            let created = try AetherSceneEngine()
            // Must be set before the first `load` — the native host is built with this value.
            created.ownsNowPlaying = true
            created.audioSessionPolicy = .playback
            created.onReachedEnd = { [weak self] in
                self?.onPlaybackEnded?()
            }
            created.$currentTime
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.trackActivityPosition() }
                .store(in: &engineCancellables)
            created.$isPlaying
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak self] playing in
                    // Paused: saved right away (the exact spot, the time watched so far).
                    if !playing { self?.activityTracker.stop() }
                }
                .store(in: &engineCancellables)
            engine = created
            return created
        } catch {
            AppLog.error("TV playback: engine init failed: \(error.localizedDescription)")
            self.error = error
            return nil
        }
    }

    // MARK: - Loading

    /// First load of a session. Creates the engine, stages Now-Playing metadata and presents.
    func setup(url: URL,
               sceneId: String,
               viewModel: StashDBViewModel,
               startAt: Double = 0,
               title: String? = nil,
               subtitle: String? = nil,
               artworkURL: URL? = nil,
               fallbackSources: [URL] = [],
               fallbackDeclaredDuration: Double? = nil,
               scene: Scene? = nil) {
        AppLog.debug("🚀 TV PLAYBACK: setup \(redactedURLString(url)) at \(startAt)s")
        self.sceneId = sceneId
        self.viewModel = viewModel
        self.isSuspended = false
        self.error = nil

        guard let engine = ensureEngine() else {
            isShowingPlayer = true
            return
        }

        applyNowPlaying(title: title, subtitle: subtitle, artworkURL: artworkURL)
        isShowingPlayer = true
        configureActivityTracking(sceneId: sceneId, viewModel: viewModel)
        startPlayCreditTimer()

        engine.fallbackSources = fallbackSources
        engine.fallbackDeclaredDuration = fallbackDeclaredDuration
        // Every scene starts at 1×, as on iOS (a fresh player per scene there).
        engine.rate = 1

        let start = max(0, startAt)
        Task {
            await engine.load(url: url, startAt: start > 0.25 ? start : nil, autoplay: true)
            // Server captions (.srt sidecars) as subtitle tracks — iOS does the same.
            if let scene { engine.registerCaptions(for: scene) }
        }
    }

    /// Channel hand-over: same engine, next item. Keeps the session (and the HDMI display mode)
    /// instead of tearing the whole route down between scenes.
    func playNext(url: URL,
                  sceneId: String,
                  viewModel: StashDBViewModel,
                  title: String? = nil,
                  subtitle: String? = nil,
                  artworkURL: URL? = nil,
                  fallbackSources: [URL] = [],
                  fallbackDeclaredDuration: Double? = nil,
                  scene: Scene? = nil) {
        guard let engine else {
            setup(url: url, sceneId: sceneId, viewModel: viewModel,
                  title: title, subtitle: subtitle, artworkURL: artworkURL,
                  fallbackSources: fallbackSources,
                  fallbackDeclaredDuration: fallbackDeclaredDuration,
                  scene: scene)
            return
        }
        self.sceneId = sceneId
        self.viewModel = viewModel
        self.isSuspended = false
        self.error = nil

        applyNowPlaying(title: title, subtitle: subtitle, artworkURL: artworkURL)
        // Saves what was watched of the outgoing item, then tracks the new one.
        configureActivityTracking(sceneId: sceneId, viewModel: viewModel)
        startPlayCreditTimer()

        engine.fallbackSources = fallbackSources
        engine.fallbackDeclaredDuration = fallbackDeclaredDuration

        // The engine outlives the item here, so the speed pick would carry over; a new
        // scene starts at 1× like on iOS.
        engine.rate = 1
        isAwaitingNewItem = true
        engine.prepareForItemReplacement()
        Task {
            await engine.load(url: url, startAt: nil, autoplay: true)
            // `load` resets `hasFirstFrame` synchronously; from here the gate waits for the new frame.
            self.isAwaitingNewItem = false
            if let scene { engine.registerCaptions(for: scene) }
        }
    }

    // MARK: - Now Playing

    private func applyNowPlaying(title: String?, subtitle: String?, artworkURL: URL?) {
        nowPlayingGeneration &+= 1
        let generation = nowPlayingGeneration

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title ?? tr("untitled_scene")
        if let subtitle, !subtitle.isEmpty {
            info[MPMediaItemPropertyArtist] = subtitle
        }
        nowPlayingInfo = info
        engine?.setNowPlayingInfo(info)

        guard let artworkURL else { return }
        Task { [weak self] in
            guard let data = await Self.loadArtworkData(artworkURL),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                guard let self, self.nowPlayingGeneration == generation else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                self.engine?.setNowPlayingInfo(self.nowPlayingInfo)
            }
        }
    }

    /// Uses the app's shared session so self-signed LAN servers work here too.
    private static func loadArtworkData(_ url: URL) async -> Data? {
        let request = stashRequest(to: url, config: ServerConfigManager.shared.activeConfig)
        do {
            let (data, _) = try await StashNetworking.session.data(for: request)
            return data
        } catch {
            return nil
        }
    }

    // MARK: - Progress

    /// Points the tracker at `sceneId`. Resetting flushes the previous item with its own save
    /// closure first, so a channel hand-over keeps the outgoing scene's time.
    private func configureActivityTracking(sceneId: String, viewModel: StashDBViewModel) {
        activityTracker.reset()
        activityTracker.updatesResumeTime = true
        activityTracker.onSave = { resumeTime, playDuration in
            AppLog.debug("💾 TV PLAYBACK: activity \(sceneId) resume=\(resumeTime.map { "\($0)" } ?? "-") +\(playDuration)s")
            viewModel.updateSceneResumeTime(
                sceneId: sceneId,
                resumeTime: resumeTime,
                playDuration: playDuration
            ) { success in
                guard success, let resumeTime else { return }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SceneResumeTimeUpdated"),
                        object: nil,
                        userInfo: ["sceneId": sceneId, "resumeTime": resumeTime]
                    )
                }
            }
        }
    }

    /// Feeds the playhead to the tracker. Until the new item shows its first frame the engine
    /// still reports the old one's time, which must not count for the new scene.
    private func trackActivityPosition() {
        guard let engine, sceneId != nil, !isSuspended, playheadBelongsToCurrentItem else { return }
        activityTracker.setPosition(currentTime: engine.currentTime, duration: engine.duration)
        if engine.isPlaying { activityTracker.start() }
    }

    private func startPlayCreditTimer() {
        playCreditTimer = nil
        playCreditClock.reset()
        creditPlayIfDue()
        guard TabManager.shared.playCountPlayerSeconds > 0 else { return }
        playCreditTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.creditPlayIfDue() }
    }

    /// Credits the scene once it has been watched for the configured threshold in this session.
    /// Where playback started (resume) and seeks do not count — the same rule as the phone player.
    private func creditPlayIfDue() {
        guard let sceneId, let viewModel, !creditedSceneIds.contains(sceneId) else { return }
        let threshold = max(0, TabManager.shared.playCountPlayerSeconds)
        if threshold > 0 {
            guard let engine, playheadBelongsToCurrentItem else {
                playCreditClock.breakInterval()
                return
            }
            playCreditClock.sample(playhead: engine.currentTime, isPlaying: engine.isPlaying)
            guard playCreditClock.watchedSeconds >= threshold else { return }
        }
        creditedSceneIds.insert(sceneId)
        playCreditTimer = nil
        viewModel.addScenePlay(sceneId: sceneId)
        NotificationCenter.default.post(
            name: NSNotification.Name("ScenePlayAdded"),
            object: nil,
            userInfo: ["sceneId": sceneId]
        )
    }

    /// Sends what is pending now (app to the background, player closing). The tracker clears
    /// the resume point once ≥ 98 % is watched, like Stash's web player.
    func saveProgress() {
        activityTracker.flush()
    }

    // MARK: - Teardown

    /// Stops the clock and pauses, but keeps the engine (and its surface) alive while a
    /// cover is still on screen. `clear()` runs once the cover is gone.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        activityTracker.stop()
        playCreditTimer = nil
        engine?.pause()
    }

    func clear() {
        if !isSuspended { activityTracker.stop() }
        // Already saved: drop the closure first so the reset does not send it twice.
        activityTracker.onSave = nil
        activityTracker.reset()
        isSuspended = false
        playCreditTimer = nil
        creditedSceneIds.removeAll()
        nowPlayingGeneration &+= 1
        nowPlayingInfo = [:]
        let stopping = engine
        engineCancellables.removeAll()
        engine = nil
        stopping?.onReachedEnd = nil
        stopping?.stop()
        sceneId = nil
        viewModel = nil
    }
}

#endif
