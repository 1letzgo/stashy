//
//  DirectorDetailView.swift
//  stashy
//
//  All scenes credited to one director.
//

#if !os(tvOS)
import SwiftUI

/// Stash keeps `director` as one free-text field, so a scene with two directors reads
/// "Director A, Director B". The UI shows one entry per name.
enum SceneDirectors {
    static func names(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        var seen = Set<String>()
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Matches `name` as one entry of the comma-separated field (RE2 syntax, as Stash uses Go regexp).
    static func regex(for name: String) -> String {
        let special = Set("\\.+*?()|[]{}^$")
        let escaped = name.map { special.contains($0) ? "\\\($0)" : String($0) }.joined()
        return "(^|,)\\s*" + escaped + "\\s*(,|$)"
    }
}

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
                    "value": .string(SceneDirectors.regex(for: director)),
                    "modifier": .string("MATCHES_REGEX")
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
    @StateObject private var viewModel = StashDBViewModel()

    var body: some View {
        ScenesView(
            filter: .scenesByDirector(director),
            hideTitle: true,
            scope: .catalog,
            sharedViewModel: viewModel,
            showsFloatingFilterButton: true,
            scrollHeader: AnyView(
                heroHeader
                    .padding(.horizontal, 16)
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .stashyDetailChrome(directorChromeConfig) { navBar }
    }

    private var directorChromeConfig: StashyDetailChromeConfig {
        StashyDetailChromeConfig(insetSpacing: 0)
    }

    // Hero modeled after PerformerDetailView.headerView.
    private var heroHeader: some View {
        let collapsedHeight: CGFloat = 115
        let iconWidth: CGFloat = 72

        return HStack(alignment: .top, spacing: 0) {
            ZStack {
                appearanceManager.tintColor.opacity(0.12)
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(appearanceManager.tintColor)
            }
            .frame(width: iconWidth, alignment: .center)
            .frame(minHeight: collapsedHeight)

            VStack(alignment: .leading, spacing: 4) {
                Text(director)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Scenes")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Text("\(viewModel.totalScenes)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: collapsedHeight, alignment: .topLeading)
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var navBar: some View {
        StashySectionChromeBar {
            HStack(spacing: 8) {
                StashyChromeBackButton { dismiss() }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
#endif
