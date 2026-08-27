
#if !os(tvOS)
import SwiftUI

struct HomeStatisticsRowView: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    var isFirst: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.top, isFirst ? 16 : 0)

            if let stats = viewModel.statistics {
                let sortedTabs = tabManager.tabs
                    .filter { [.scenes, .galleries, .images, .performers, .studios, .tags, .groups, .markers].contains($0.id) && $0.isVisible }
                    .sorted { $0.sortOrder < $1.sortOrder }

                if tabManager.useCompactStatistics {
                    compactCard(sortedTabs: sortedTabs, stats: stats)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(sortedTabs) { tab in
                                statCard(for: tab, stats: stats)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            } else if viewModel.isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                                .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .frame(width: homeSquareCardSide, height: homeSquareCardSide)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundColor(.secondary)
                    Text("Stats unavailable").font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: - Stat card builders (single source of truth for both layouts)

    @ViewBuilder
    private func statCard(for tab: TabConfig, stats: Statistics) -> some View {
        switch tab.id {
        case .scenes:
            StatCard(title: "Scenes", value: formatCount(stats.sceneCount), icon: "film", color: tabManager.useColoredStatistics ? .blue : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToScenes() }
        case .galleries:
            StatCard(title: "Galleries", value: formatCount(stats.galleryCount), icon: "photo.stack", color: tabManager.useColoredStatistics ? .green : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToGalleries() }
        case .images:
            StatCard(title: "Images", value: formatCount(stats.imageCount), icon: "photo", color: tabManager.useColoredStatistics ? .teal : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToImages() }
        case .performers:
            StatCard(title: "Performers", value: formatCount(stats.performerCount), icon: "person.2", color: tabManager.useColoredStatistics ? .purple : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToPerformers() }
        case .studios:
            StatCard(title: "Studios", value: formatCount(stats.studioCount), icon: "building.2", color: tabManager.useColoredStatistics ? .orange : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToStudios() }
        case .tags:
            StatCard(title: "Tags", value: formatCount(stats.tagCount), icon: "tag", color: tabManager.useColoredStatistics ? .pink : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToTags() }
        case .groups:
            StatCard(title: "Groups", value: formatCount(stats.groupCount), icon: "rectangle.stack.fill", color: tabManager.useColoredStatistics ? Color(red: 0.1, green: 0.7, blue: 0.9) : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToGroups() }
        case .markers:
            StatCard(title: "Markers", value: formatCount(stats.sceneMarkerCount ?? 0), icon: "bookmark.fill", color: tabManager.useColoredStatistics ? .red : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToMarkers() }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func compactRow(for tab: TabConfig, stats: Statistics) -> some View {
        switch tab.id {
        case .scenes:
            compactStatRow(title: "Scenes", value: formatCount(stats.sceneCount), icon: "film", color: tabManager.useColoredStatistics ? .blue : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToScenes() }
        case .galleries:
            compactStatRow(title: "Galleries", value: formatCount(stats.galleryCount), icon: "photo.stack", color: tabManager.useColoredStatistics ? .green : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToGalleries() }
        case .images:
            compactStatRow(title: "Images", value: formatCount(stats.imageCount), icon: "photo", color: tabManager.useColoredStatistics ? .teal : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToImages() }
        case .performers:
            compactStatRow(title: "Performers", value: formatCount(stats.performerCount), icon: "person.2", color: tabManager.useColoredStatistics ? .purple : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToPerformers() }
        case .studios:
            compactStatRow(title: "Studios", value: formatCount(stats.studioCount), icon: "building.2", color: tabManager.useColoredStatistics ? .orange : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToStudios() }
        case .tags:
            compactStatRow(title: "Tags", value: formatCount(stats.tagCount), icon: "tag", color: tabManager.useColoredStatistics ? .pink : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToTags() }
        case .groups:
            compactStatRow(title: "Groups", value: formatCount(stats.groupCount), icon: "rectangle.stack.fill", color: tabManager.useColoredStatistics ? Color(red: 0.1, green: 0.7, blue: 0.9) : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToGroups() }
        case .markers:
            compactStatRow(title: "Markers", value: formatCount(stats.sceneMarkerCount ?? 0), icon: "bookmark.fill", color: tabManager.useColoredStatistics ? .red : appearanceManager.tintColor)
                .onTapGesture { coordinator.navigateToMarkers() }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func compactCard(sortedTabs: [TabConfig], stats: Statistics) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12),
                      GridItem(.flexible(), spacing: 12)],
            spacing: 8
        ) {
            ForEach(sortedTabs) { tab in compactRow(for: tab, stats: stats) }
        }
        .padding(.horizontal, 12)
    }

    private func compactStatRow(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 20, alignment: .leading)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 36) // Reduced height for more compact look
        .background(
            LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
        .cardShadow()
        .contentShape(Rectangle())
    }

    // MARK: - Formatters

    private func formatCount(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - StatCard

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: icon).font(.system(size: 28, weight: .bold)).foregroundColor(.white)
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(.white)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(width: homeSquareCardSide, height: homeSquareCardSide)
        .background(
            LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }
}
#endif
