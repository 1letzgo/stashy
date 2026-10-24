//
//  Scene+AetherPlayback.swift
//  stashy
//
//  Source URL for the playback engine. Never a server-side transcode:
//  the engine always plays the original file.
//

import Foundation

/// Stash's server-side captions (`.en.srt` next to the file) as URLs the engine can load —
/// shared by the iOS scene detail and the tvOS player.
enum StashCaptionURL {
    static func url(for caption: VideoCaption, scene: Scene) -> URL? {
        let base = resolveBase(scene.paths?.caption) ?? fallbackBase(sceneID: scene.id)
        guard let base, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        var items = (components.queryItems ?? []).filter {
            let name = $0.name.lowercased()
            return name != "lang" && name != "type" && name != "apikey"
        }
        items.append(URLQueryItem(name: "lang", value: caption.languageCode))
        items.append(URLQueryItem(name: "type", value: caption.captionType))
        components.queryItems = items
        return signedURL(components.url)
    }

    static func resolveBase(_ path: String?) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://"), let url = URL(string: path) { return url }
        guard let config = ServerConfigManager.shared.activeConfig ?? ServerConfigManager.shared.loadConfig() else {
            return URL(string: path)
        }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "\(config.baseURL)/\(trimmed)")
    }

    static func fallbackBase(sceneID: String) -> URL? {
        guard let config = ServerConfigManager.shared.activeConfig ?? ServerConfigManager.shared.loadConfig() else { return nil }
        return URL(string: "\(config.baseURL)/scene/\(sceneID)/caption")
    }
}

#if canImport(AetherEngine)
extension AetherSceneEngine {
    /// Registers the scene's server captions as external subtitle tracks. Call after `load`;
    /// republishes `subtitleTracks`, so the automatic selection can pick one.
    func registerCaptions(for scene: Scene) {
        guard let captions = scene.captions, !captions.isEmpty else { return }
        for caption in captions {
            guard let url = StashCaptionURL.url(for: caption, scene: scene) else { continue }
            let language = caption.languageCode.isEmpty || caption.languageCode == "00" ? nil : caption.languageCode
            let name = language.flatMap { Locale.current.localizedString(forIdentifier: $0) }
                ?? language?.uppercased()
                ?? "Captions"
            _ = addExternalSubtitleTrack(url: url, name: name, language: language, formatHint: caption.captionType)
        }
    }
}
#endif

extension Scene {
    /// Original-file URL for the playback engine, or nil when no source is known.
    var aetherVideoURL: URL? {
        // 0. A finished local download wins (offline first).
        if let localURL = LocalDownloadStore.videoURL(sceneID: id) {
            return localURL
        }

        // 1. The stream path the server reported.
        if let streamPath = paths?.stream, let url = URL(string: streamPath) {
            return signedURL(url)
        }

        // 2. Constructed direct-stream endpoint.
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return signedURL(URL(string: "\(config.baseURL)/scene/\(id)/stream"))
    }
}

extension Scene {
    /// Server-side transcodes, in the order the engine should try them when the original
    /// cannot be played. Stash serves both endpoints deterministically, so no `sceneStreams`
    /// query is needed.
    ///
    /// 1. `stream.m3u8` — HLS, segments transcoded on demand (seekable).
    /// 2. `stream.mp4` — progressive transcode from a non-seekable origin; a shifted start is
    ///    requested with `?start=<seconds>`.
    ///
    /// Empty for a local download: the file is already on the device, and a server transcode
    /// would be a step backwards (and unreachable offline).
    var transcodeFallbackURLs: [URL] {
        if LocalDownloadStore.videoURL(sceneID: id) != nil { return [] }
        guard let config = ServerConfigManager.shared.activeConfig
                ?? ServerConfigManager.shared.loadConfig() else { return [] }
        let base = config.baseURL
        return [
            URL(string: "\(base)/scene/\(id)/stream.m3u8"),
            URL(string: "\(base)/scene/\(id)/stream.mp4")
        ].compactMap { signedURL($0) }
    }
}

#if !os(tvOS)
extension Scene {
    /// Markers for the player's time bar: start time plus the title, falling back to the
    /// primary tag's name.
    var timeBarMarkers: [AetherTimeBarMarker] {
        (sceneMarkers ?? []).map { marker in
            let title = marker.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return AetherTimeBarMarker(seconds: marker.seconds,
                                       title: title.isEmpty ? marker.primaryTag?.name : title)
        }
    }
}
#endif

// MARK: - Feeds playback window (shared by the iOS Feeds tab and tvOS Feeds)

/// Settings › Playback › "Feeds start position": where a Feeds › Scenes row starts (and loops
/// back to), so the feed does not open on studio intros. Worked out once per scene and feed
/// session and then kept, so a Random start stays put while the row stays and for its loop,
/// and an engine rebuild by the watchdog lands on the same spot.
@MainActor
enum ReelsSceneStartPositions {
    private static var cache: [String: Double] = [:]

    /// Videos shorter than this always start at 0.
    private static let minimumDuration: Double = 120
    /// A start this close to the end starts at 0 instead.
    private static let endMargin: Double = 5
    private static let skipSeconds: Double = 30

    static func reset() { cache.removeAll() }

    static func start(for scene: Scene) -> Double {
        let setting = TabManager.shared.feedsSceneStartPosition
        let key = "\(setting.rawValue)|\(scene.id)"
        if let cached = cache[key] { return cached }
        let value = compute(for: scene, setting: setting)
        cache[key] = value
        return value
    }

    private static func compute(for scene: Scene, setting: TabManager.FeedsSceneStartPosition) -> Double {
        guard let duration = scene.sceneDuration, duration.isFinite, duration >= minimumDuration else { return 0 }
        // Square and vertical videos are mostly short-form content that starts right away.
        if let file = scene.files?.first, let width = file.width, let height = file.height,
           width > 0, height > 0, width <= height {
            return 0
        }
        let start: Double
        switch setting {
        case .beginning:
            return 0
        case .firstMarker:
            let detailMarkers = scene.sceneMarkers?.map(\.seconds).filter { $0.isFinite && $0 >= 0 }.min()
            start = [scene.earliestMarkerSeconds, detailMarkers].compactMap { $0 }.min() ?? skipSeconds
        case .skip30:
            start = skipSeconds
        case .random:
            start = Double.random(in: 0..<(duration * 0.5))
        }
        guard start > 0, start < duration - endMargin else { return 0 }
        return start
    }
}

/// The stretch of a source file a Feeds row plays (marker rows: their part of the scene).
/// The scrubber shows it as 0…`length`; the engine keeps working in file time.
struct ReelPlaybackSegment: Equatable {
    // Markers without an end in Stash play Settings › Playback › "Marker length" (30 s default).

    let start: Double
    let end: Double

    var length: Double { max(0.1, end - start) }

    /// Segment-relative time (the scrubber's) → file time, kept inside the segment.
    func fileTime(forRelative relative: Double) -> Double {
        min(max(start, start + relative), max(start, end - 0.1))
    }

    /// File time → segment-relative time for the scrubber.
    func relativeTime(forFile time: Double) -> Double {
        min(max(0, time - start), length)
    }

    /// A marker's stretch of its scene: `seconds` to `end_seconds` when Stash has an end for
    /// it, otherwise Settings › Playback › "Marker length" from the marker on — clamped to the
    /// file's length when that is known.
    static func marker(_ m: SceneMarker) -> ReelPlaybackSegment {
        let start = max(0, m.seconds)
        var end: Double
        if let explicitEnd = m.endSeconds, explicitEnd > start + 0.1 {
            end = explicitEnd
        } else {
            end = start + TabManager.storedFeedsMarkerDefaultSeconds
        }
        if let fileDuration = m.scene?.files?.first?.duration, fileDuration > start + 0.5 {
            end = min(end, fileDuration)
        }
        return ReelPlaybackSegment(start: start, end: end)
    }

    /// The same segment with its end pulled in to a file length learnt at runtime.
    func clamped(toFileDuration duration: Double?) -> ReelPlaybackSegment {
        guard let duration, duration.isFinite, duration > start + 0.5, duration < end else { return self }
        return ReelPlaybackSegment(start: start, end: duration)
    }
}
