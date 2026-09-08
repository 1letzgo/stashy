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
/// Downloads keep the original container, so the file is `video.<ext>`. The download
/// metadata is the authoritative answer; the directory scan is the fallback for entries
/// written before the metadata existed (`video.mp4`) or repaired by hand.
enum LocalDownloadStore {

    /// Root of the download tree, or nil when the documents directory is unreachable.
    static var downloadsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Downloads")
    }

    /// File URL of a finished download, or nil when the scene is not downloaded.
    static func videoURL(sceneID: String) -> URL? {
        guard !sceneID.isEmpty, let root = downloadsDirectory else { return nil }

        if let fromMetadata = metadataVideoURL(sceneID: sceneID, root: root) { return fromMetadata }

        // Fallback glob: any `video.*` in the scene folder (legacy `video.mp4` included).
        let folder = root.appendingPathComponent(sceneID, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return entries.first { $0.deletingPathExtension().lastPathComponent == "video" }
    }

    /// True when a finished download exists for this scene.
    static func exists(sceneID: String) -> Bool {
        videoURL(sceneID: sceneID) != nil
    }

    // MARK: - Metadata

    /// The path the download manager recorded, when the file is actually there.
    /// `DownloadManager` is main-actor isolated and this is called from nonisolated
    /// computed properties, so off the main thread the directory scan takes over.
    private static func metadataVideoURL(sceneID: String, root: URL) -> URL? {
        guard Thread.isMainThread else { return nil }
        return MainActor.assumeIsolated {
            guard let entry = DownloadManager.shared.downloads.first(where: { $0.id == sceneID }),
                  !entry.localVideoPath.isEmpty else { return nil }
            let candidate = root.appendingPathComponent(entry.localVideoPath)
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }
    }
}
