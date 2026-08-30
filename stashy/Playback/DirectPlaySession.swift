//
//  DirectPlaySession.swift
//  stashy
//
//  Thin wrapper around AetherEngine that hands back a plain `AVPlayer`.
//
//  The whole point of this shape: on the engine's loopback route FFmpeg only
//  demuxes and re-muxes into HLS-fMP4 served on 127.0.0.1, and AVPlayer plays
//  that. So the object the app gets back is an ordinary AVPlayer, and every
//  existing consumer — AVPlayerViewController, SubtitleController,
//  SceneAudioTrackController, VideoAnalysisManager, the periodic time
//  observer, PiP — keeps working untouched.
//
//  If the engine cannot produce an AVPlayer (its software route, which this
//  phase does not present), this throws and the caller falls back to today's
//  server-transcode path.
//

import Foundation
import AVFoundation
import AetherEngine

enum DirectPlayError: LocalizedError {
    case engineUnavailable(String)
    case softwareRouteUnsupported
    case noPlayerProduced

    var errorDescription: String? {
        switch self {
        case .engineUnavailable(let reason): return "Direct Play engine unavailable: \(reason)"
        case .softwareRouteUnsupported:      return "Direct Play would need the software renderer"
        case .noPlayerProduced:              return "Direct Play produced no AVPlayer"
        }
    }
}

@MainActor
final class DirectPlaySession {

    static let shared = DirectPlaySession()

    private var engine: AetherEngine?

    /// Route the last successful `makePlayer` landed on — for diagnostics and
    /// so callers can tell an engine-backed player from a native one.
    private(set) var activeRoute: VideoRoute = .none

    /// True while an engine-produced player is in use. Callers must not swap
    /// items on that player (`replaceCurrentItem`) — the engine owns it.
    var isEngineBacked: Bool { engine != nil && activeRoute != .none }

    private init() {}

    /// Longest we wait for the engine to publish an `AVPlayer` after `load`
    /// returns. Past this we give up and let the caller use the native path;
    /// a slow open must never become a black screen.
    private static let playerHandoverDeadline: TimeInterval = 6

    /// Opens `url` through the engine and returns the AVPlayer it drives.
    /// - Throws: `DirectPlayError` — every case means "use the native path".
    func makePlayer(url: URL, startPosition: Double?, muted: Bool) async throws -> AVPlayer {
        applyPlaybackAudioSession()

        let engine: AetherEngine
        if let existing = self.engine {
            engine = existing
        } else {
            do {
                engine = try AetherEngine()
                self.engine = engine
            } catch {
                throw DirectPlayError.engineUnavailable(error.localizedDescription)
            }
        }

        // AVKit registers Now-Playing itself for the AVPlayerViewController we
        // hand this player to. Claiming it here would fight that registration.
        engine.ownsVideoNowPlayingSession = false

        var options = LoadOptions()
        options.httpHeaders = DirectPlayPolicy.authHeaders
        // The app decides when playback starts (resume seek, sync managers).
        options.autoplay = false

        do {
            _ = try await engine.load(url: url, startPosition: startPosition, options: options)
        } catch {
            teardown()
            throw DirectPlayError.engineUnavailable(error.localizedDescription)
        }

        if engine.videoRoute == .software {
            teardown()
            throw DirectPlayError.softwareRouteUnsupported
        }

        guard let player = await awaitPlayer(from: engine) else {
            teardown()
            throw engine.videoRoute == .software
                ? DirectPlayError.softwareRouteUnsupported
                : DirectPlayError.noPlayerProduced
        }

        activeRoute = engine.videoRoute
        player.isMuted = muted
        applyBackgroundPlaybackPolicy(to: player)
        AppLog.debug("🎬 Direct Play: route=\(activeRoute.rawValue) for \(redactedURLString(url))")
        return player
    }

    /// Polls `currentAVPlayer` until it appears or the deadline passes.
    /// The engine publishes it during `load`, but the exact ordering is an
    /// implementation detail — waiting is cheaper than depending on it.
    private func awaitPlayer(from engine: AetherEngine) async -> AVPlayer? {
        if let player = engine.currentAVPlayer { return player }
        let deadline = Date().addingTimeInterval(Self.playerHandoverDeadline)
        while Date() < deadline {
            if engine.videoRoute == .software { return nil }
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let player = engine.currentAVPlayer { return player }
        }
        return nil
    }

    /// Tears the engine down only if it still drives `player`.
    ///
    /// The session is a singleton, so a second scene opening while the first
    /// is still tearing down would otherwise kill the *new* session. Callers
    /// pass the player they believe they own; a stale owner is a no-op.
    func teardown(owning player: AVPlayer?) {
        guard let player, engine?.currentAVPlayer === player else { return }
        teardown()
    }

    /// Unconditional teardown. Only for callers that just created the session
    /// and are abandoning it before anyone else can have taken it over.
    func teardown() {
        engine?.stop()
        engine = nil
        activeRoute = .none
    }
}
