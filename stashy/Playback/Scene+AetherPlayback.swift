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
