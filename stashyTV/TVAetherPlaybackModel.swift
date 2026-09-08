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
    private var progressTimer: AnyCancellable?
    private var sceneId: String?
    private var viewModel: StashDBViewModel?
    /// `saveProgress()` already ran in `suspend()` — skip the duplicate in `clear()`.
    private var isSuspended = false
    /// Guards a stale artwork download from overwriting a newer item's Now-Playing info.
    private var nowPlayingGeneration = 0
    private var nowPlayingInfo: [String: Any] = [:]

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
               artworkURL: URL? = nil) {
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
        startProgressTimer()

        let start = max(0, startAt)
        Task { await engine.load(url: url, startAt: start > 0.25 ? start : nil, autoplay: true) }
    }

    /// Channel hand-over: same engine, next item. Keeps the session (and the HDMI display mode)
    /// instead of tearing the whole route down between scenes.
    func playNext(url: URL,
                  sceneId: String,
                  viewModel: StashDBViewModel,
                  title: String? = nil,
                  subtitle: String? = nil,
                  artworkURL: URL? = nil) {
        guard let engine else {
            setup(url: url, sceneId: sceneId, viewModel: viewModel,
                  title: title, subtitle: subtitle, artworkURL: artworkURL)
            return
        }
        saveProgress()
        self.sceneId = sceneId
        self.viewModel = viewModel
        self.isSuspended = false
        self.error = nil

        applyNowPlaying(title: title, subtitle: subtitle, artworkURL: artworkURL)
        startProgressTimer()

        engine.prepareForItemReplacement()
        Task { await engine.load(url: url, startAt: nil, autoplay: true) }
    }

    // MARK: - Now Playing

    private func applyNowPlaying(title: String?, subtitle: String?, artworkURL: URL?) {
        nowPlayingGeneration &+= 1
        let generation = nowPlayingGeneration

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title ?? "Untitled Scene"
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

    private func startProgressTimer() {
        progressTimer = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.saveProgress() }
    }

    func saveProgress() {
        guard let engine,
              let sceneId,
              let viewModel else { return }

        let currentTime = engine.currentTime
        guard currentTime > 0 else { return }

        let duration = engine.duration
        var resume = currentTime
        if duration.isFinite, duration > 0, (100.0 / duration) * currentTime >= 98 {
            resume = 0
        }
        AppLog.debug("💾 TV PLAYBACK: saving resume \(resume)s for \(sceneId)")
        viewModel.updateSceneResumeTime(sceneId: sceneId, resumeTime: resume, playDuration: 0)
        NotificationCenter.default.post(
            name: NSNotification.Name("SceneResumeTimeUpdated"),
            object: nil,
            userInfo: ["sceneId": sceneId, "resumeTime": resume]
        )
    }

    // MARK: - Teardown

    /// Stops the clock and pauses, but keeps the engine (and its surface) alive while a
    /// cover is still on screen. `clear()` runs once the cover is gone.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        saveProgress()
        progressTimer = nil
        engine?.pause()
    }

    func clear() {
        if !isSuspended { saveProgress() }
        isSuspended = false
        progressTimer = nil
        nowPlayingGeneration &+= 1
        nowPlayingInfo = [:]
        let stopping = engine
        engine = nil
        stopping?.onReachedEnd = nil
        stopping?.stop()
        sceneId = nil
        viewModel = nil
    }
}

#endif
