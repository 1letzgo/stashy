//
//  SceneBulkDownloadControl.swift
//  stashy
//
//  The "download this object's scenes" control shared by the performer, studio, tag and
//  group detail screens. Mirrors the gallery / tag image download: pick newest N or all.
//

#if !os(tvOS)
import SwiftUI

extension View {
    /// Newest-N / all picker for a bulk scene download. `scopeName` names the object in the
    /// toast, e.g. the performer's name.
    func sceneBulkDownloadDialog(
        isPresented: Binding<Bool>,
        scope: DownloadManager.SceneDownloadScope,
        scopeName: String,
        downloadManager: DownloadManager = .shared
    ) -> some View {
        let batch = DownloadManager.sceneNewestBatchSize
        return confirmationDialog("Download scenes", isPresented: isPresented, titleVisibility: .visible) {
            Button("Newest \(batch) scenes") {
                downloadManager.downloadScenes(for: scope, limit: batch, scopeName: scopeName)
            }
            Button("All scenes") {
                downloadManager.downloadScenes(for: scope, limit: nil, scopeName: scopeName)
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
