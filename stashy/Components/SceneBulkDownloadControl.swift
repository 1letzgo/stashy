//
//  SceneBulkDownloadControl.swift
//  stashy
//
//  The "download this object's scenes" control shared by the performer, studio, tag and
//  group detail screens. Mirrors the gallery / tag image download: pick newest N or all.
//

#if !os(tvOS)
import SwiftUI

/// Alert buttons for a "newest N or all" download that never promise more than exist.
/// A known count of at most `batch` items gets one "Download all N" button; otherwise
/// "Newest {batch}" plus "All N". An unknown count (nil, or 0 from a not-yet-loaded model)
/// keeps both buttons without a number. Android: `newestOrAllOptions`.
enum DownloadBatchOptions {
    @ViewBuilder
    static func buttons(
        count: Int?,
        batch: Int,
        singular: String,
        plural: String,
        download: @escaping (_ limit: Int?) -> Void
    ) -> some View {
        let known = count.flatMap { $0 > 0 ? $0 : nil }
        if known == 1 {
            Button("Download 1 \(singular)") { download(nil) }
        } else if let known, known <= batch {
            Button("Download all \(known) \(plural)") { download(nil) }
        } else {
            Button("Newest \(batch) \(plural)") { download(batch) }
            Button(known.map { "All \($0) \(plural)" } ?? "All \(plural)") { download(nil) }
        }
    }
}

extension View {
    /// Newest-N / all picker for a bulk scene download. `scopeName` names the object in the
    /// toast, e.g. the performer's name. `sceneCount` (the object's `scene_count`) collapses
    /// the choice to "Download all N" when there are no more than the batch size.
    func sceneBulkDownloadDialog(
        isPresented: Binding<Bool>,
        scope: DownloadManager.SceneDownloadScope,
        scopeName: String,
        sceneCount: Int? = nil,
        downloadManager: DownloadManager = .shared
    ) -> some View {
        let batch = DownloadManager.sceneNewestBatchSize
        // Alert, not a confirmation dialog — the gallery and tag image downloads ask this way.
        return alert("Download scenes", isPresented: isPresented) {
            DownloadBatchOptions.buttons(count: sceneCount, batch: batch, singular: "scene", plural: "scenes") { limit in
                downloadManager.downloadScenes(for: scope, limit: limit, scopeName: scopeName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scenes already downloaded are skipped.")
        }
    }
}

/// Chrome slot for the scenes tab of a detail screen.
enum SceneBulkDownloadChrome {
    static func slot(action: @escaping () -> Void) -> CatalogChromeSlot {
        CatalogChromeSlot(
            systemImage: "arrow.down.doc",
            accessibilityLabel: "Download scenes",
            accessibilityHint: "Downloads the newest scenes, or all of them"
        ) {
            HapticManager.light()
            action()
        }
    }
}
#endif
