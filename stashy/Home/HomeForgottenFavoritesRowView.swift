#if !os(tvOS)
import SwiftUI

/// stashy+ "Forgotten Favorites" row on Home (`ForgottenFavoritesEngine`): top played or
/// O-Counted scenes not played for a while. No link in the title — the list exists only here.
/// As the first scene row it is the hero, like every other scene row.
struct HomeForgottenFavoritesRowView: View {
    let config: HomeRowConfig
    var isLarge: Bool = false
    var isFirst: Bool = false
    @ObservedObject private var engine = ForgottenFavoritesEngine.shared
    @ObservedObject private var tabManager = TabManager.shared
    @Environment(\.homeContentWidth) private var homeContentWidth
    @State private var scrollID: String?

    private var cardWidth: CGFloat {
        isLarge ? homeHeroCardWidth(screenWidth: homeContentWidth) : 125 * 16 / 9
    }
    private var cardHeight: CGFloat { isLarge ? cardWidth * 9 / 16 : 125 }
    private var onBackdrop: Bool { isLarge && isFirst && tabManager.showDashboardHeroBackground }

    var body: some View {
        // An empty row is left out by HomeView: nothing forgotten is good news, not a message.
        VStack(alignment: .leading, spacing: isLarge ? 8 : 12) {
            Text(config.title)
                .font(.headline)
                .foregroundColor(isLarge ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.top, isFirst ? 16 : 0)

            switch engine.state {
            case .idle, .loading:
                placeholder
            case .preparing:
                Text(SceneRecommendationEngine.preparingMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
            case .ready:
                cards
            }
        }
        .background {
            if onBackdrop {
                let focused = engine.items.first { $0.id == scrollID } ?? engine.items.first
                HomeDashboardHeroBackdrop(thumbnailURL: focused?.scene.thumbnailURL)
                    .equatable()
            }
        }
        .onAppear { engine.refreshIfNeeded() }
    }

    private var cards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(engine.items) { item in
                    NavigationLink(destination: LazyView { SceneDetailView(scene: item.scene) }) {
                        VStack(alignment: .leading, spacing: 6) {
                            HomeSceneCardView(scene: item.scene, isLarge: isLarge, screenWidth: homeContentWidth)
                            label(item)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: cardWidth)
                    .accessibilityHint(item.label)
                    .id(item.id)
                }
            }
            .padding(.horizontal, 12)
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollID)
        .scrollTargetBehavior(.viewAligned)
        .scrollContentBackground(.hidden)
    }

    private func label(_ item: ForgottenFavorite) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppearanceManager.shared.tintColor)
                .accessibilityHidden(true)
            Text(item.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(onBackdrop ? .white.opacity(0.8) : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
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
}
#endif
