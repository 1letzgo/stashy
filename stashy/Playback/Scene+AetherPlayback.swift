//
//  Scene+AetherPlayback.swift
//  stashy
//
//  Source URL for the playback engine. Never a server-side transcode:
//  the engine always plays the original file.
//

import Foundation

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
