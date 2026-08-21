//
//  TVPlayback.swift
//  stashyTV
//
//  Shared stream URL resolution for scene detail and channel continuous play.
//

import Foundation

func tvPlaybackURL(for scene: Scene, streams: [SceneStream], quality: StreamingQuality) -> URL? {
    let compatible = ["mp4", "m4v", "mov"]
    let fileFormat = scene.files?.first?.format?.lowercased() ?? ""
    let isNativelyCompatible = compatible.contains(fileFormat)

    // bestStream() respects quality; for MP4 + Original it returns nil → direct stream.
    let sceneWithStreams = scene.withStreams(streams)
    if let streamURL = sceneWithStreams.bestStream(for: quality) {
        return streamURL
    }

    if !isNativelyCompatible {
        if let hlsStream = streams.first(where: { $0.mime_type == "application/vnd.apple.mpegurl" }),
           let url = URL(string: hlsStream.url) {
            return url
        }
        if let mp4Stream = streams.first(where: { $0.mime_type == "video/mp4" }),
           let url = URL(string: mp4Stream.url) {
            return url
        }
    }

    if let directPath = scene.paths?.stream {
        if directPath.starts(with: "http://") || directPath.starts(with: "https://") {
            return URL(string: directPath)
        }
        if let config = ServerConfigManager.shared.activeConfig {
            return URL(string: "\(config.baseURL)\(directPath)")
        }
    }
    return nil
}
