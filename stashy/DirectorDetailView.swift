//
//  DirectorDetailView.swift
//  stashy
//
//  All scenes credited to one director.
//

#if !os(tvOS)
import SwiftUI

extension StashDBViewModel.SavedFilter {
    /// Stash has no director entity — `director` is a free-text field on the scene,
    /// so the list is scoped with a string criterion instead of an id.
    static func scenesByDirector(_ director: String) -> StashDBViewModel.SavedFilter {
        StashDBViewModel.SavedFilter(
            id: "stashy_director_\(director)",
            name: director,
            mode: .scenes,
            filter: nil,
            object_filter: .object([
                "director": .object([
                    "value": .string(director),
                    "modifier": .string("EQUALS")
                ])
            ]),
            ui_options: nil
        )
    }
}

struct DirectorDetailView: View {
    let director: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    var body: some View {
        ScenesView(
            filter: .scenesByDirector(director),
            hideTitle: true,
            scope: .catalog,
            showsFloatingFilterButton: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .stashyCustomChromeInset { navBar }
    }

    @ViewBuilder
    private var navBar: some View {
        StashySectionChromeBar {
            HStack(spacing: 8) {
                StashyChromeBackButton { dismiss() }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                        .foregroundColor(appearanceManager.tintColor)
                    Text(director)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundColor(.white.opacity(0.9))
                }
                .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight))

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
#endif
