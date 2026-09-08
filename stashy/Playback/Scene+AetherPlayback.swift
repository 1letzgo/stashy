//
//  Scene+AetherPlayback.swift
//  stashy
//
//  Source URL for the optional playback engine. Unlike `Scene.videoURL`
//  this never resolves to a server-side transcode: the whole point of the
//  engine is to play the original file.
//

import Foundation

extension Scene {
    /// Original-file URL for the optional playback engine, or nil when no source is known.
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
