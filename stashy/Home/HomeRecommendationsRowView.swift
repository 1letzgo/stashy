#if !os(tvOS)
import SwiftUI

/// stashy+ "For You" row on Home: `SceneRecommendationEngine` picks, each card with the reason
/// it was picked. Rendered only while stashy+ is unlocked (`HomeView`). As the first scene row
/// it is the hero: large cards and, as the very first row, the blurred backdrop.
struct HomeRecommendationsRowView: View {
    let config: HomeRowConfig
    var isLarge: Bool = false
    var isFirst: Bool = false
    @ObservedObject private var engine = SceneRecommendationEngine.shared
    @ObservedObject private var tabManager = TabManager.shared
    @Environment(\.homeContentWidth) private var homeContentWidth
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @State private var scrollID: String?

    private var cardWidth: CGFloat {
        isLarge ? homeHeroCardWidth(screenWidth: homeContentWidth) : 125 * 16 / 9
    }
    private var cardHeight: CGFloat { isLarge ? cardWidth * 9 / 16 : 125 }

    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 8 : 12) {
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
        .background {
            if isLarge && isFirst && tabManager.showDashboardHeroBackground {
                let items = engine.homeItems
                let focused = items.first { $0.id == HomeHeroPreview.shared.focusedID(row: config.id.uuidString, current: scrollID, in: items.map(\.id)) }
                HomeDashboardHeroBackdrop(thumbnailURL: focused?.scene.thumbnailURL)
                    .equatable()
            }
        }
        .onAppear { engine.refreshIfNeeded() }
    }

    // MARK: - Header

    /// Like every scene row: "Title ›" opens Scenes, here sorted For You.
    private var header: some View {
        Button {
            coordinator.navigateToScenes(sort: .forYou)
        } label: {
            HStack(spacing: 4) {
                Text(config.title)
                    .font(.headline)
                    .foregroundColor(isLarge ? .white : .primary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isLarge ? .white.opacity(0.7) : .secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    private var cards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(engine.homeItems) { item in
                    NavigationLink(destination: LazyView { SceneDetailView(scene: item.scene) }) {
                        VStack(alignment: .leading, spacing: 6) {
                            HomeSceneCardView(scene: item.scene, isLarge: isLarge, screenWidth: homeContentWidth,
                                              autoplaysPreview: isLarge && isFirst && tabManager.dashboardHeroAutoplay
                                                  && HomeHeroPreview.shared.focusedID(row: config.id.uuidString, current: scrollID, in: engine.homeItems.map(\.id)) == item.id)
                            reasonLine(item)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: cardWidth)
                    .accessibilityHint(item.reason.label)
                    .id(item.id)
                }
            }
            .padding(.horizontal, 12)
            .scrollTargetLayout()
        }
        .homeRowPosition($scrollID, row: config.id.uuidString, ids: engine.homeItems.map(\.id))
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
                .foregroundColor(isLarge && isFirst && tabManager.showDashboardHeroBackground ? .white.opacity(0.8) : .secondary)
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
            } else {
                Spacer(minLength: 2)
            }
            // The card's own long press is the preview: adjusting lives in this menu.
            Menu {
                RecommendationAdjustMenu(scene: item.scene)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isLarge && isFirst && tabManager.showDashboardHeroBackground ? .white.opacity(0.8) : .secondary)
                    .frame(width: 28, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Adjust suggestions")
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
