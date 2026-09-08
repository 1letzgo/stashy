//
//  AetherSceneEngine.swift
//  stashy
//
//  Adapter around AetherEngine so the app's playback surfaces can talk to
//  it with the small vocabulary they already use for AVPlayer
//  (time, playing, seek, rate, mute, loop). The engine itself stays
//  reachable via `engine` for the SwiftUI surface.
//

#if canImport(AetherEngine)

import Foundation
import Combine
import AVFoundation
import CoreGraphics
import UIKit
import AetherEngine

/// How a playback surface wants the shared audio session configured when it loads.
/// Muted previews must not take the session away from a running scene, so they ask for
/// `.ambient`; a surface that manages the session itself asks for `.none`.
enum AetherAudioSessionPolicy {
    case playback
    case ambient
    case none
}

/// A bitmap subtitle cue resolved for the current playhead. Deliberately a local value type:
/// the app already owns a `SubtitleCue` (the AVPlayer caption path), so the engine's cue type
/// never leaves this file.
struct AetherSubtitleImageCue {
    let image: CGImage
    /// Normalized [0, 1] rect against the subtitle canvas.
    let position: CGRect
    /// Coded canvas the position is normalized against; `.zero` when unknown.
    let canvasSize: CGSize
}

extension AetherSubtitleImageCue: Equatable {
    static func == (lhs: AetherSubtitleImageCue, rhs: AetherSubtitleImageCue) -> Bool {
        lhs.image === rhs.image && lhs.position == rhs.position && lhs.canvasSize == rhs.canvasSize
    }
}

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
    /// Embedded text/bitmap streams, sidecar files and live renditions in one list.
    @Published private(set) var subtitleTracks: [TrackInfo] = []
    @Published private(set) var activeSubtitleTrackIndex: Int?
    @Published private(set) var isSubtitleActive: Bool = false
    /// The text of the cue covering the current source time, already flattened from rich text.
    @Published private(set) var currentSubtitleText: String?
    /// The bitmap cue covering the current source time (PGS / DVB / DVD tracks).
    @Published private(set) var currentSubtitleImage: AetherSubtitleImageCue?
    /// Non-nil only on a route that actually owns an AVPlayerLayer (PiP).
    @Published private(set) var pipPlayerLayer: AVPlayerLayer?
    /// The item AI Motion's frame analysis can attach an `AVPlayerItemVideoOutput` to.
    /// Non-nil only on the AVPlayer-backed routes (`.loopback`, `.remoteBypass`) — the software
    /// route decodes into its own layer and never produces an `AVPlayerItem`.
    /// Re-emitted on every (re)load, because items are swapped in place under the same player.
    @Published private(set) var analysisPlayerItem: AVPlayerItem?

    // MARK: - Callbacks

    var onTime: ((Double, Double) -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?
    var onReachedEnd: (() -> Void)?
    var onFirstFrame: (() -> Void)?
    /// Fires whenever `analysisPlayerItem` changes, including to nil (software route, teardown).
    /// Hosts re-run their AI Motion setup from here — a reload swaps the item without any
    /// other signal.
    var onAnalysisItemChanged: ((AVPlayerItem?) -> Void)?

    // MARK: - Host-controlled knobs

    /// Loop the current item shortly before its end instead of ending.
    var loopsAtEnd: Bool = false

    /// Which audio session `load` installs. Previews use `.ambient` so they never steal the
    /// session from a playing scene.
    var audioSessionPolicy: AetherAudioSessionPolicy = .playback

    /// Whether the engine owns the system Now-Playing session for the native video path.
    /// Must be set before the first `load` — the native host is built with this value.
    var ownsNowPlaying: Bool {
        get { engine.ownsVideoNowPlayingSession }
        set { engine.ownsVideoNowPlayingSession = newValue }
    }

    /// Stages Now-Playing metadata. Ignored unless `ownsNowPlaying` is set.
    func setNowPlayingInfo(_ info: [String: Any]) {
        engine.setVideoNowPlayingInfo(info)
    }

    /// Presentation size of the current source, in pixels, or nil while unknown.
    /// The software route reports the settled picture size directly; the AVPlayer-backed routes
    /// only have coded dimensions, so the pixel aspect is applied to the width.
    var sourceSize: CGSize? {
        if let size = engine.softwareDisplaySize, size.width > 0, size.height > 0 { return size }
        let width = Double(engine.sourceVideoWidth)
        let height = Double(engine.sourceVideoHeight)
        guard width > 0, height > 0 else { return nil }
        let aspect = engine.sourceVideoPixelAspectRatio
        let scale = (aspect.isFinite && aspect > 0) ? aspect : 1
        return CGSize(width: width * scale, height: height)
    }

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
    /// Fallback still extractor for the software route (no SegmentCache, so no cache-backed
    /// stills). Kept for the session and torn down on `stop()` / a load of a different URL.
    private var scrubExtractor: FrameExtractor?
    private var scrubExtractorURL: URL?

    // MARK: - Lifecycle

    init() throws {
        engine = try AetherEngine()
        engine.deactivatesAudioSessionOnStop = false
        #if os(iOS)
        engine.backgroundPlaybackEnabled = TabManager.shared.isPiPEnabled
        #endif
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

        engine.$subtitleTracks
            .receive(on: RunLoop.main)
            .sink { [weak self] tracks in self?.subtitleTracks = tracks }
            .store(in: &cancellables)

        engine.$activeSubtitleTrackIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] index in
                guard let self else { return }
                self.activeSubtitleTrackIndex = index
                if index == nil {
                    self.currentSubtitleText = nil
                    self.currentSubtitleImage = nil
                }
            }
            .store(in: &cancellables)

        engine.$isSubtitleActive
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                guard let self else { return }
                self.isSubtitleActive = active
                if !active {
                    self.currentSubtitleText = nil
                    self.currentSubtitleImage = nil
                }
            }
            .store(in: &cancellables)

        // `subtitleCues` is a rolling window of decoded cues, not the visible ones, and the cues
        // carry raw source PTS — so they are resolved against `clock.sourceTime`, never `currentTime`.
        engine.$subtitleCues
            .combineLatest(engine.clock.$sourceTime)
            .receive(on: RunLoop.main)
            .sink { [weak self] cues, sourceTime in
                guard let self else { return }
                guard self.isSubtitleActive, !cues.isEmpty else {
                    if self.currentSubtitleText != nil { self.currentSubtitleText = nil }
                    if self.currentSubtitleImage != nil { self.currentSubtitleImage = nil }
                    return
                }

                var text: String?
                var image: AetherSubtitleImageCue?
                for cue in cues where cue.startTime <= sourceTime && sourceTime < cue.endTime {
                    if case .image(let bitmap) = cue.body {
                        image = AetherSubtitleImageCue(image: bitmap.cgImage,
                                                       position: bitmap.position,
                                                       canvasSize: bitmap.canvasSize)
                    } else if let cueText = cue.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !cueText.isEmpty {
                        // Overlapping text cues stack; join instead of letting the last one win.
                        text = text.map { "\($0)\n\(cueText)" } ?? cueText
                    }
                }

                if self.currentSubtitleText != text { self.currentSubtitleText = text }
                if self.currentSubtitleImage != image { self.currentSubtitleImage = image }
            }
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

        // Frame analysis (AI Motion) needs a real `AVPlayerItem`; only the AVPlayer-backed
        // routes have one. Items are swapped in place across reloads, so this follows
        // `$currentAVPlayerItem` rather than `$currentAVPlayer`.
        engine.$videoRoute
            .combineLatest(engine.$currentAVPlayerItem)
            .receive(on: RunLoop.main)
            .sink { [weak self] route, item in
                guard let self else { return }
                let routeHasItem = (route == .loopback || route == .remoteBypass)
                let next = routeHasItem ? item : nil
                guard self.analysisPlayerItem !== next else { return }
                self.analysisPlayerItem = next
                self.onAnalysisItemChanged?(next)
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
    /// `customizeOptions` runs after the defaults are filled in, so a caller can tune the
    /// `LoadOptions` (buffer window, display-criteria suppression, …) without a new parameter
    /// per knob.
    func load(url: URL,
              startAt: Double?,
              autoplay: Bool,
              customizeOptions: ((inout LoadOptions) -> Void)? = nil) async {
        loadGeneration &+= 1
        let generation = loadGeneration

        switch audioSessionPolicy {
        case .playback: applyPlaybackAudioSession()
        case .ambient: applyAmbientMixingAudioSession()
        case .none: break
        }

        if currentURL != url { shutdownScrubExtractor() }
        currentURL = url
        didEnd = false
        hasFirstFrame = false
        errorMessage = nil
        currentSubtitleText = nil
        currentSubtitleImage = nil
        pendingSeek = nil
        loopSeekInFlight = false
        isLoading = true

        var options = LoadOptions()
        options.autoplay = autoplay
        if let key = ServerConfigManager.shared.activeConfig?.secureApiKey, !key.isEmpty,
           url.isFileURL == false {
            options.httpHeaders["ApiKey"] = key
        }
        customizeOptions?(&options)

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

    // MARK: - Scrub stills

    /// A still for the scrub preview. Prefers the engine's cache-backed still (decoded from
    /// bytes the active native session already produced — no second connection); on the
    /// software route it falls back to a session-coupled `FrameExtractor` over the same
    /// signed URL playback uses. A nil result is expected and transient ("time only, no
    /// image"), so callers should keep whatever they last showed.
    func scrubThumbnail(at seconds: Double, maxWidth: CGFloat) async -> UIImage? {
        let width = Int(max(1, maxWidth.rounded()))
        let target = max(0, seconds)

        // The cache-backed still only covers bytes the session already produced (around the
        // playhead), so a nil there is the normal case when scrubbing far away: fall through
        // to the extractor, which opens its own demuxer and can reach any position.
        if engine.supportsCacheBackedStills,
           let image = await engine.scrubThumbnail(atSeconds: target, maxWidth: width) {
            return UIImage(cgImage: image)
        }

        guard let extractor = scrubExtractorForCurrentURL() else { return nil }
        guard let image = await extractor.thumbnail(at: target, maxWidth: width) else { return nil }
        return UIImage(cgImage: image)
    }

    /// A full-quality still for "Set Image" (tag image / scene cover).
    ///
    /// `FrameExtractor.snapshot` is the only Aether API that returns the frame at native
    /// resolution (capped to `maxSize`, aspect preserved, never upscaled) *and* decodes
    /// forward to the requested pts. `scrubThumbnail` is deliberately the fallback: it is
    /// keyframe-granular and its `maxWidth` is a thumbnail width, so it is only used when the
    /// extractor cannot open a second connection (single-connection sources).
    func captureFrame(at seconds: Double, maxSize: CGSize) async -> UIImage? {
        let target = max(0, seconds)

        if let extractor = scrubExtractorForCurrentURL(),
           let image = await extractor.snapshot(at: target, maxSize: maxSize) {
            return UIImage(cgImage: image)
        }

        if engine.supportsCacheBackedStills {
            let width = Int(max(1, maxSize.width.rounded()))
            if let image = await engine.scrubThumbnail(atSeconds: target, maxWidth: width) {
                return UIImage(cgImage: image)
            }
        }
        return nil
    }

    /// Lazily builds (and reuses) the fallback extractor. Same auth as `load`: the signed URL
    /// plus the ApiKey header, so a server that only honours one of the two still works.
    private func scrubExtractorForCurrentURL() -> FrameExtractor? {
        guard let url = currentURL else { return nil }
        let signed = signedURL(url) ?? url
        if let existing = scrubExtractor, scrubExtractorURL == signed { return existing }
        shutdownScrubExtractor()

        var headers: [String: String] = [:]
        if let key = ServerConfigManager.shared.activeConfig?.secureApiKey, !key.isEmpty,
           url.isFileURL == false {
            headers["ApiKey"] = key
        }
        let created = engine.makeFrameExtractor(url: signed, httpHeaders: headers)
        scrubExtractor = created
        scrubExtractorURL = signed
        return created
    }

    private func shutdownScrubExtractor() {
        if let extractor = scrubExtractor {
            Task { await extractor.shutdown() }
        }
        scrubExtractor = nil
        scrubExtractorURL = nil
    }

    // MARK: - Tracks and presentation

    func selectAudioTrack(index: Int) {
        engine.selectAudioTrack(index: index)
    }

    func selectSubtitleTrack(index: Int) {
        engine.selectSubtitleTrack(index: index)
    }

    func clearSubtitle() {
        engine.clearSubtitle()
        currentSubtitleText = nil
        currentSubtitleImage = nil
    }

    /// Registers a sidecar file (Stash's server captions) as a selectable track. Overlay-only —
    /// tracks added after `load` never become native WebVTT renditions. Nothing is auto-selected.
    @discardableResult
    func addExternalSubtitleTrack(url: URL, name: String?, language: String?, formatHint: String? = nil) -> Int? {
        var headers: [String: String]?
        if let key = ServerConfigManager.shared.activeConfig?.secureApiKey, !key.isEmpty,
           url.isFileURL == false {
            headers = ["ApiKey": key]
        }
        let track = ExternalSubtitleTrack(url: url,
                                          name: name,
                                          language: language,
                                          httpHeaders: headers,
                                          formatHint: formatHint)
        return engine.addExternalSubtitleTrack(track).id
    }

    // MARK: - Decoded audio tap

    /// Installs the engine's PCM tap and returns its buffer stream (mono Float32 48 kHz).
    /// Returns nil when the install found no delivery source (no session yet, video-only
    /// source, or a backend without a tap path) so callers fail fast instead of awaiting a
    /// stream that finishes immediately.
    ///
    /// The stream also finishes on every `load`, `stop` and session-preserving reload
    /// (audio/subtitle track switch), so consumers must re-install when it ends.
    func installAudioTap() -> AsyncStream<AudioTapBuffer>? {
        let stream = engine.installAudioTap()
        guard engine.audioTapHasDeliverySource else {
            engine.removeAudioTap()
            return nil
        }
        return stream
    }

    /// Removes the tap and finishes its stream. Safe when none is installed.
    func removeAudioTap() {
        engine.removeAudioTap()
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
        shutdownScrubExtractor()
        engine.removeAudioTap()
        engine.stop()
        currentURL = nil
        analysisPlayerItem = nil
        isPlaying = false
        hasFirstFrame = false
        currentSubtitleText = nil
        currentSubtitleImage = nil
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
