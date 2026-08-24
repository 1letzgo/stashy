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
        .stashyCustomChromeInset { navBar }
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
