#if !os(tvOS)
import SwiftUI

/// stashy+ "For You" row on Home: `SceneRecommendationEngine` picks, each card with the reason
/// it was picked. Rendered only while stashy+ is unlocked (`HomeView`).
struct HomeRecommendationsRowView: View {
    let config: HomeRowConfig
    var isFirst: Bool = false
    @ObservedObject private var engine = SceneRecommendationEngine.shared
    @Environment(\.homeContentWidth) private var homeContentWidth

    private let cardWidth: CGFloat = 125 * 16 / 9
    private let cardHeight: CGFloat = 125

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.top, isFirst ? 16 : 0)

            switch engine.state {
            case .idle, .loading where engine.recommendations.isEmpty:
                placeholder
            case .noHistory:
                message("Watch a few scenes and stashy will suggest more like them here.")
            case .failed(let text) where engine.recommendations.isEmpty:
                message(text)
            default:
                if engine.recommendations.isEmpty {
                    message("Nothing new matches your taste right now. Try another setting in For You.")
                } else {
                    cards
                }
            }
        }
        .onAppear { engine.refreshIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text(config.title)
                .font(.headline)
                .foregroundColor(.primary)
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppearanceManager.shared.tintColor)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            NavigationLink(destination: LazyView { RecommendationSettingsView() }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("For You settings")
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Content

    private var cards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(engine.recommendations) { item in
                    NavigationLink(destination: LazyView { SceneDetailView(scene: item.scene) }) {
                        VStack(alignment: .leading, spacing: 6) {
                            HomeSceneCardView(scene: item.scene, isLarge: false, screenWidth: homeContentWidth)
                            reasonLine(item)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: cardWidth)
                    .accessibilityHint(item.reason.label)
                }
            }
            .padding(.horizontal, 12)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollContentBackground(.hidden)
    }

    /// Why this scene is here, below its card.
    private func reasonLine(_ item: SceneRecommendation) -> some View {
        HStack(spacing: 4) {
            Image(systemName: item.reason.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppearanceManager.shared.tintColor)
                .accessibilityHidden(true)
            Text(item.reason.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if item.isUnwatched {
                Spacer(minLength: 2)
                Text("NEW")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppearanceManager.shared.tintColor))
                    .foregroundColor(.onAppTint)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .padding(.horizontal, 2)
        .frame(width: cardWidth, alignment: .leading)
    }

    private var placeholder: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                        .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                        .frame(width: cardWidth, height: cardHeight)
                        .overlay(ProgressView())
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollDisabled(true)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
    }
}
#endif
