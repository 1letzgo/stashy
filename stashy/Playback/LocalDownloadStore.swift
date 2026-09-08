//
//  LocalDownloadStore.swift
//  stashy
//
//  One place that answers "is this scene downloaded, and where is the file".
//  Every playback surface used to carry its own copy of the same path
//  construction; they all call in here now.
//

import Foundation

/// Lookup for finished scene downloads in `Documents/Downloads/<sceneID>/`.
///
/// Phase 1 keeps the historical layout (`video.mp4` only). The download path itself is
/// unchanged, so nothing here has to know about containers yet.
enum LocalDownloadStore {

    /// Root of the download tree, or nil when the documents directory is unreachable.
    static var downloadsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Downloads")
    }

    /// File URL of a finished download, or nil when the scene is not downloaded.
    static func videoURL(sceneID: String) -> URL? {
        guard !sceneID.isEmpty, let root = downloadsDirectory else { return nil }
        let candidate = root.appendingPathComponent("\(sceneID)/video.mp4")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// True when a finished download exists for this scene.
    static func exists(sceneID: String) -> Bool {
        videoURL(sceneID: sceneID) != nil
    }
}
