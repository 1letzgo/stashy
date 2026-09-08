//
//  PlayerEnginePreference.swift
//  stashy
//
//  User preference for the optional AetherEngine playback path, plus the
//  resolver that decides per scene whether that path is used.
//  Deliberately free of any AetherEngine import so it compiles on tvOS,
//  where TabManager lives too.
//

import Foundation

/// Three-way switch for the optional playback engine.
enum PlayerEnginePreference: String, CaseIterable, Identifiable {
    /// Kill switch: the AVPlayer path stays byte-identical to before.
    case off
    /// Only for files iOS cannot play natively.
    case automatic
    /// Always, whenever a scene has a usable source.
    case always

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .automatic: return "Automatic"
        case .always: return "Always"
        }
    }
}

/// Decides whether a given scene should play through the optional engine.
enum PlayerEngineResolver {
    /// Containers AVFoundation demuxes natively.
    static let nativeContainers: Set<String> = ["mp4", "m4v", "mov"]
    /// Video codecs AVFoundation decodes natively (AV1 deliberately excluded).
    static let nativeCodecs: Set<String> = ["h264", "avc", "avc1", "hevc", "h265", "hvc1", "hev1"]

    static func isNativelyPlayable(format: String?, videoCodec: String?) -> Bool {
        guard let format, let videoCodec else { return false }
        let container = format.lowercased()
        let codec = videoCodec.lowercased()
        return nativeContainers.contains(container) && nativeCodecs.contains(codec)
    }

    /// True when this scene should be handed to the optional engine instead of AVPlayer.
    static func shouldUseAether(for scene: Scene) -> Bool {
        guard StashyPlusManager.isUnlockedNow else { return false }
        switch TabManager.shared.playerEnginePreference {
        case .off:
            return false
        case .always:
            return true
        case .automatic:
            // A finished local download is always an mp4 remux: AVPlayer handles it.
            if hasLocalDownload(sceneID: scene.id) { return false }
            guard let file = scene.files?.first else { return false }
            guard file.format != nil || file.videoCodec != nil else { return false }
            return !isNativelyPlayable(format: file.format, videoCodec: file.videoCodec)
        }
    }

    static func hasLocalDownload(sceneID: String) -> Bool {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        let localURL = docs.appendingPathComponent("Downloads/\(sceneID)/video.mp4")
        return fileManager.fileExists(atPath: localURL.path)
    }
}
