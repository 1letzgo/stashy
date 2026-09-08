//
//  AetherSceneEngine.swift
//  stashy
//
//  Adapter around AetherEngine so the app's playback surfaces can talk to
//  it with the small vocabulary they already use for AVPlayer
//  (time, playing, seek, rate, mute, loop). The engine itself stays
//  reachable via `engine` for the SwiftUI surface.
//

#if !os(tvOS) && canImport(AetherEngine)

import Foundation
import Combine
import AVFoundation
import AetherEngine

@MainActor
final class AetherSceneEngine: ObservableObject {

    /// The underlying engine; the SwiftUI surface binds to this directly.
    let engine: AetherEngine

    // MARK: - Published state

    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    /// True only while playback really moves (engine phase `.playing`).
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isBuffering: Bool = false
    @Published private(set) var hasFirstFrame: Bool = false
    @Published private(set) var didEnd: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var audioTracks: [TrackInfo] = []
    @Published private(set) var activeAudioTrackIndex: Int?
    /// Non-nil only on a route that actually owns an AVPlayerLayer (PiP).
    @Published private(set) var pipPlayerLayer: AVPlayerLayer?

    // MARK: - Callbacks

    var onTime: ((Double, Double) -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?
    var onReachedEnd: (() -> Void)?
    var onFirstFrame: (() -> Void)?

    // MARK: - Host-controlled knobs

    /// Loop the current item shortly before its end instead of ending.
    var loopsAtEnd: Bool = false

    private(set) var currentURL: URL?

    private var _rate: Float = 1.0
    /// Playback speed. Never forwarded as 0 (that would be a pause on the engine).
    var rate: Float {
        get { _rate }
        set {
            let clamped = max(0.1, min(newValue, engine.maxSupportedRate))
            guard clamped != _rate else { return }
            _rate = clamped
            engine.setRate(clamped)
        }
    }

    private var unmutedVolume: Float = 1.0
    private var _isMuted: Bool = false
    /// The engine has no mute flag; this drives `volume` and remembers the level.
    var isMuted: Bool {
        get { _isMuted }
        set {
            // No early-out on an unchanged value: the software route builds its audio output
            // only after `load` returns, so a re-assert has to write through to be effective.
            if newValue, !_isMuted {
                let current = engine.volume
                if current > 0 { unmutedVolume = current }
            }
            _isMuted = newValue
            applyVolumeState()
        }
    }

    /// Writes the current mute state onto the engine. Idempotent, so it can be re-applied at
    /// every point where the audio output may have been (re)created.
    private func applyVolumeState() {
        engine.volume = _isMuted ? 0 : (unmutedVolume > 0 ? unmutedVolume : 1.0)
    }

    // MARK: - Internals

    private var cancellables = Set<AnyCancellable>()
    /// Guards against a superseded load's completion touching newer state.
    private var loadGeneration: Int = 0
    private var pendingSeek: Double?
    private var loopSeekInFlight = false
    private var isLoading = false

    // MARK: - Lifecycle

    init() throws {
        engine = try AetherEngine()
        engine.deactivatesAudioSessionOnStop = false
        engine.backgroundPlaybackEnabled = TabManager.shared.isPiPEnabled
        bind()
    }

    private func bind() {
        engine.clock.$currentTime
            .receive(on: RunLoop.main)
            .sink { [weak self] time in
                guard let self else { return }
                self.currentTime = time
                let dur = self.duration
                self.onTime?(time, dur)
                self.handleLoopIfNeeded(time: time, duration: dur)
            }
            .store(in: &cancellables)

        engine.$duration
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.duration = value }
            .store(in: &cancellables)

        engine.$playbackPhase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.handlePhase(phase) }
            .store(in: &cancellables)

        engine.$isBuffering
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.isBuffering = value }
            .store(in: &cancellables)

        engine.$hasFirstFrameReadyForDisplay
            .receive(on: RunLoop.main)
            .sink { [weak self] ready in
                guard let self else { return }
                let wasReady = self.hasFirstFrame
                self.hasFirstFrame = ready
                if ready && !wasReady {
                    self.applyVolumeState()
                    self.onFirstFrame?()
                }
            }
            .store(in: &cancellables)

        engine.$audioTracks
            .receive(on: RunLoop.main)
            .sink { [weak self] tracks in self?.audioTracks = tracks }
            .store(in: &cancellables)

        engine.$activeAudioTrackIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] index in self?.activeAudioTrackIndex = index }
            .store(in: &cancellables)

        engine.$errorInfo
            .receive(on: RunLoop.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let info { self.errorMessage = info.message }
            }
            .store(in: &cancellables)

        // PiP is only meaningful where an AVPlayerLayer actually exists.
        engine.$videoRoute
            .combineLatest(engine.$currentAVPlayer)
            .receive(on: RunLoop.main)
            .sink { [weak self] route, player in
                guard let self else { return }
                let routeSupportsPiP = (route == .loopback || route == .remoteBypass)
                self.pipPlayerLayer = (routeSupportsPiP && player != nil) ? self.engine.nativePlayerLayer : nil
            }
            .store(in: &cancellables)
    }

    private func handlePhase(_ phase: PlaybackPhase) {
        let playing: Bool
        switch phase {
        case .playing: playing = true
        default: playing = false
        }
        if playing != isPlaying {
            isPlaying = playing
            onPlayingChanged?(playing)
        }

        switch phase {
        case .loading:
            isLoading = true
        case .playing, .paused:
            isLoading = false
            didEnd = false
            applyVolumeState()
            flushPendingSeekIfNeeded()
        case .ended:
            isLoading = false
            handleEnded()
        case .error(let message):
            isLoading = false
            errorMessage = message
        default:
            break
        }
    }

    private func handleEnded() {
        guard !didEnd else { return }
        if loopsAtEnd, let url = currentURL {
            // `.ended` is terminal: loop by reloading at zero.
            Task { await self.load(url: url, startAt: nil, autoplay: true) }
            return
        }
        didEnd = true
        onReachedEnd?()
    }

    /// Near-end loop seek, so looping does not have to pass through the terminal `.ended` state.
    private func handleLoopIfNeeded(time: Double, duration: Double) {
        guard loopsAtEnd, duration > 0.5, !loopSeekInFlight else { return }
        guard duration - time < 0.25 else { return }
        loopSeekInFlight = true
        Task { [weak self] in
            guard let self else { return }
            await self.engine.seek(to: 0)
            self.loopSeekInFlight = false
        }
    }

    // MARK: - Loading

    /// Loads a URL. Never throws: a failure lands in `errorMessage`.
    func load(url: URL, startAt: Double?, autoplay: Bool) async {
        loadGeneration &+= 1
        let generation = loadGeneration

        applyPlaybackAudioSession()

        currentURL = url
        didEnd = false
        hasFirstFrame = false
        errorMessage = nil
        pendingSeek = nil
        loopSeekInFlight = false
        isLoading = true

        var options = LoadOptions()
        options.autoplay = autoplay
        if let key = ServerConfigManager.shared.activeConfig?.secureApiKey, !key.isEmpty,
           url.isFileURL == false {
            options.httpHeaders["ApiKey"] = key
        }

        do {
            _ = try await engine.load(url: signedURL(url) ?? url,
                                      startPosition: startAt,
                                      options: options)
            guard generation == loadGeneration else { return }
            if _rate != 1.0 { engine.setRate(_rate) }
            applyVolumeState()
        } catch is CancellationError {
            // A newer load superseded this one; nothing to report.
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
            AppLog.error("AetherSceneEngine load failed: \(error.localizedDescription)")
        }
        if generation == loadGeneration { isLoading = false }
    }

    // MARK: - Transport

    func play() {
        engine.play()
    }

    func pause() {
        engine.pause()
    }

    func togglePlayPause() {
        engine.togglePlayPause()
    }

    /// Seeks. `.ended` is terminal on the engine, so that case reloads instead.
    func seek(to seconds: Double) async {
        let target = max(0, seconds)
        if didEnd, let url = currentURL {
            await load(url: url, startAt: target, autoplay: true)
            return
        }
        if isLoading {
            pendingSeek = target
            return
        }
        currentTime = target
        await engine.seek(to: target)
    }

    private func flushPendingSeekIfNeeded() {
        guard let target = pendingSeek else { return }
        pendingSeek = nil
        Task { [weak self] in
            guard let self else { return }
            await self.engine.seek(to: target)
        }
    }

    // MARK: - Tracks and presentation

    func selectAudioTrack(index: Int) {
        engine.selectAudioTrack(index: index)
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        engine.videoGravity = gravity
    }

    func setPictureInPictureActive(_ active: Bool) {
        engine.pictureInPictureActive = active
    }

    /// Callers must invoke this before releasing the wrapper: `@State` release is not deterministic.
    func stop() {
        cancellables.removeAll()
        loadGeneration &+= 1
        pendingSeek = nil
        engine.stop()
        currentURL = nil
        isPlaying = false
        hasFirstFrame = false
    }
}

// MARK: - Process-wide bootstrap

enum AetherPlaybackBootstrap {
    private static var installed = false

    /// Wires the engine into the app's TLS policy and logging. Safe to call more than once.
    static func installOnce() {
        guard !installed else { return }
        installed = true

        EngineTLS.serverTrustEvaluator = { space in
            StashTrustDelegate.acceptsSelfSigned(host: space.host)
        }

        #if DEBUG
        // The engine mirrors only its `.info` lines to this handler.
        EngineLog.handler = { message in
            AppLog.debug(AetherPlaybackBootstrap.redactingAPIKeys(message))
        }
        #endif
    }

    /// Strips `apikey=` query values so no key ever reaches the log.
    static func redactingAPIKeys(_ message: String) -> String {
        guard message.lowercased().contains("apikey=") else { return message }
        let pattern = "(?i)(apikey=)[^&\\s\"']+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return message }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        return regex.stringByReplacingMatches(in: message, range: range, withTemplate: "$1<redacted>")
    }
}

#endif
