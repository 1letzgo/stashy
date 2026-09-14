//
//  SceneSimilarScenesCard.swift
//  stashy
//
//  stashy+ — scenes from the library that resemble the one on screen.
//

#if !os(tvOS)
import SwiftUI

struct SceneSimilarScenesCard: View {
    /// Results for this detail page. They live in the page, not in the shared finder: every
    /// pushed `SceneDetailView` has its own list, so jumping to a similar scene and back
    /// never shows (or wipes) another page's result.
    let scenes: [Scene]
    let isLoading: Bool

    @ObservedObject private var finder = SimilarScenesFinder.shared
    @ObservedObject private var suggestions = AITagSuggestionManager.shared

    var body: some View {
        Group {
            if finder.isActive, isLoading || !scenes.isEmpty {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Similar Scenes")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                if isLoading { ProgressView() }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if !scenes.isEmpty {
                // No GeometryReader and no fixed height: `HomeSceneCardView` is a fixed
                // 222×125 plus its title block when `isLarge` is false, so the row can size
                // itself. Forcing a height only left dead space under the cards.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(scenes) { similar in
                            NavigationLink(destination: SceneDetailView(scene: similar)) {
                                HomeSceneCardView(scene: similar, screenWidth: 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.bottom, 8)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }
}
#endif
