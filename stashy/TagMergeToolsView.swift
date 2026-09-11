//
//  TagMergeToolsView.swift
//  stashy
//
//  Tools → Merge Tags: mehrere Tags auf einen einzigen zusammenführen.
//  Die Seite selbst ist `MergeToolsView` (MergeTools.swift), geteilt mit Merge Studios.
//

#if !os(tvOS)
import SwiftUI

/// Alles, was an den Quell-Tags hängt (Szenen, Bilder, Galerien, Performer und
/// Marker — Primär- wie Zusatz-Tag), zeigt danach auf den Ziel-Tag; die Quellen
/// sind weg. Die Umschreibung macht der Server (`tagsMerge`), nicht die App.
struct TagMergeToolsView: View {
    private static let repository = TagRepository()

    var body: some View {
        MergeToolsView(config: MergeToolsConfig<Tag>(
            kind: "tags",
            noun: "tag",
            nounPlural: "tags",
            loadAll: { try await Self.repository.fetchEveryTag() },
            merge: { sources, destination in
                try await Self.repository.mergeTags(sourceIds: sources, destinationId: destination)
            },
            didMerge: {
                // Gelöschte Tags dürfen in Filter-Pickern nicht weiterleben.
                FilterPickerOptionsStore.shared.invalidate()
            }
        ))
    }
}
#endif
