//
//  DirectPlayPolicy.swift
//  stashy
//
//  stashy+ Direct Play: decides whether a scene plays through the native
//  AVFoundation chain (unchanged) or through the FFmpeg-backed engine.
//
//  Design rule for this whole feature: the engine is strictly ADDITIVE.
//  Everything that plays today keeps playing through exactly the same code
//  path. The engine only ever gets sources the native chain refuses, and any
//  failure falls straight back to the existing transcode path.
//

import Foundation

/// Which playback chain a scene should use.
enum DirectPlayRoute: Equatable {
    /// Today's path: `createPlayer(for:muted:)` on a server-provided stream.
    case native
    /// stashy+ Direct Play: FFmpeg demux + VideoToolbox, no server transcode.
    case engine
}

/// Gate, kill switch and codec classification for Direct Play.
///
/// Deliberately holds no engine types so it compiles (and can be reasoned
/// about) without the package linked.
enum DirectPlayPolicy {

    // MARK: - Settings / kill switch

    /// Master switch. Defaults to **off** — this ships dark and is enabled per
    /// user, so a bad release is a toggle rather than a hotfix review.
    private static let enabledKey = "stashy_direct_play_enabled"
    /// Scene IDs whose engine attempt already failed once; bounded ring.
    private static let failureMemoryKey = "stashy_direct_play_failed_scene_ids"
    private static let failureMemoryLimit = 200

    static var isEnabledBySetting: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// stashy+ entitlement plus the user setting. Both must hold.
    static var isAvailable: Bool {
        StashyPlusManager.isUnlockedNow && isEnabledBySetting
    }

    // MARK: - Codec classification

    /// Containers AVFoundation opens without help.
    private static let nativeContainers: Set<String> = ["mp4", "m4v", "mov", "qt"]

    /// Video codecs VideoToolbox decodes and AVFoundation demuxes happily.
    private static let nativeVideoCodecs: Set<String> = ["h264", "avc1", "hevc", "h265", "hvc1", "hev1"]

    /// Audio codecs AVFoundation plays inside an MP4/MOV container.
    private static let nativeAudioCodecs: Set<String> = [
        "aac", "mp4a", "alac", "ac3", "eac3", "ac-3", "e-ac-3", "mp3", "pcm_s16le", "lpcm"
    ]

    /// Codecs the engine can only serve on its software route, which this
    /// phase does not host yet (no custom transport bar). Sending them to the
    /// engine would buy a spinner over a black plane, so they stay native and
    /// keep using the server transcode.
    private static let softwareOnlyVideoCodecs: Set<String> = [
        "av1", "av01", "vp9", "vp09", "vp8", "vp08",
        "mpeg2video", "mpeg4", "msmpeg4v1", "msmpeg4v2", "msmpeg4v3",
        "vc1", "wmv1", "wmv2", "wmv3", "divx", "xvid"
    ]

    private static func normalized(_ value: String?) -> String {
        (value ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the primary file is something AVFoundation handles on its own.
    /// Unknown metadata counts as native — never take a source away from the
    /// working path on a guess.
    static func isNativelyPlayable(file: SceneFile?) -> Bool {
        guard let file else { return true }
        let container = normalized(file.format)
        let video = normalized(file.videoCodec)
        let audio = normalized(file.audioCodec)
        if container.isEmpty || video.isEmpty { return true }
        guard nativeContainers.contains(container) else { return false }
        guard nativeVideoCodecs.contains(video) else { return false }
        // An unknown audio codec inside an otherwise native container is still
        // worth letting AVFoundation try; it fails loudly rather than silently.
        if !audio.isEmpty && !nativeAudioCodecs.contains(audio) { return false }
        return true
    }

    /// True when the engine would have to fall back to its software renderer,
    /// which this phase does not present.
    static func requiresSoftwareRoute(file: SceneFile?) -> Bool {
        guard let file else { return false }
        return softwareOnlyVideoCodecs.contains(normalized(file.videoCodec))
    }

    // MARK: - Routing

    /// Decides the chain for a scene. Any doubt resolves to `.native`.
    static func route(for scene: Scene) -> DirectPlayRoute {
        guard isAvailable else { return .native }
        guard !hasFailedBefore(sceneID: scene.id) else { return .native }
        let file = scene.files?.first
        guard !isNativelyPlayable(file: file) else { return .native }
        guard !requiresSoftwareRoute(file: file) else { return .native }
        guard directStreamURL(for: scene) != nil else { return .native }
        return .engine
    }

    /// Stash's direct-stream endpoint — the untouched file, no transcode.
    /// `Scene.videoURL` deliberately refuses this URL for non-MP4 formats
    /// (see `StashDBViewModel`, "Preventing fallback to incompatible"), which
    /// is exactly the guard Direct Play exists to lift, so it is bypassed here
    /// rather than changed there.
    static func directStreamURL(for scene: Scene) -> URL? {
        if let streamPath = scene.paths?.stream, let url = URL(string: streamPath) {
            return signedURL(url)
        }
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return signedURL(URL(string: "\(config.baseURL)/scene/\(scene.id)/stream"))
    }

    /// Headers the engine must send on demux and every segment fetch.
    /// Mirrors `makeAuthenticatedAsset(for:)` so both chains authenticate alike.
    static var authHeaders: [String: String] {
        guard let config = ServerConfigManager.shared.loadConfig(),
              let apiKey = config.secureApiKey, !apiKey.isEmpty else { return [:] }
        return ["ApiKey": apiKey]
    }

    // MARK: - Failure memory

    /// One failed engine attempt per scene is enough — the next open goes
    /// straight to the working path instead of re-paying the timeout.
    static func rememberFailure(sceneID: String) {
        var ids = UserDefaults.standard.stringArray(forKey: failureMemoryKey) ?? []
        guard !ids.contains(sceneID) else { return }
        ids.append(sceneID)
        if ids.count > failureMemoryLimit { ids.removeFirst(ids.count - failureMemoryLimit) }
        UserDefaults.standard.set(ids, forKey: failureMemoryKey)
    }

    static func hasFailedBefore(sceneID: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: failureMemoryKey) ?? []).contains(sceneID)
    }

    static func clearFailureMemory() {
        UserDefaults.standard.removeObject(forKey: failureMemoryKey)
    }
}
