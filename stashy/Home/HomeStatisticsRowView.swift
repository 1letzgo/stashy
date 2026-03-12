
#if !os(tvOS)
import SwiftUI

struct HomeStatisticsRowView: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 12)

            // Einzeiliges scrollbares Menü
            if let stats = viewModel.statistics {
                let sortedTabs = tabManager.tabs
                    .filter { tab in
                        (tab.id == .scenes || tab.id == .galleries || tab.id == .images ||
                         tab.id == .performers || tab.id == .studios || tab.id == .tags || tab.id == .groups) && tab.isVisible
                    }
                    .sorted { $0.sortOrder < $1.sortOrder }

                if tabManager.useCompactStatistics {
                    compactStatisticsCard(sortedTabs: sortedTabs, stats: stats)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                        ForEach(sortedTabs) { tab in
                            Group {
                                switch tab.id {
                                case .scenes:
                                    StatCard(title: "Scenes", value: formatCount(stats.sceneCount), icon: "film", color: .blue)
                                        .onTapGesture { coordinator.navigateToScenes() }
                                case .galleries:
                                    StatCard(title: "Galleries", value: formatCount(stats.galleryCount), icon: "photo.stack", color: .green)
                                        .onTapGesture { coordinator.navigateToGalleries() }
                                case .images:
                                    StatCard(title: "Images", value: formatCount(stats.imageCount), icon: "photo", color: .teal)
                                        .onTapGesture { coordinator.navigateToImages() }
                                case .performers:
                                    StatCard(title: "Performers", value: formatCount(stats.performerCount), icon: "person.2", color: .purple)
                                        .onTapGesture { coordinator.navigateToPerformers() }
                                case .studios:
                                    StatCard(title: "Studios", value: formatCount(stats.studioCount), icon: "building.2", color: .orange)
                                        .onTapGesture { coordinator.navigateToStudios() }
                                case .tags:
                                    StatCard(title: "Tags", value: formatCount(stats.tagCount), icon: "tag", color: .pink)
                                        .onTapGesture { coordinator.navigateToTags() }
                                case .groups:
                                    StatCard(title: "Groups", value: formatCount(stats.movieCount), icon: "rectangle.stack.fill", color: Color(red: 0.1, green: 0.7, blue: 0.9))
                                        .onTapGesture { coordinator.navigateToGroups() }
                                default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        } else if viewModel.isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<6) { _ in
                            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                                .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .frame(width: 80, height: 90)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            } else {
                // Error state
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.secondary)
                    Text("Stats unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
            }
        }
    }
    
    // MARK: - Formatting Helpers
    
    private func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current // Respect user's country/region
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    private func formatSize(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useTB, .useGB, .useMB]
        formatter.includesUnit = true
        return formatter.string(fromByteCount: value)
    }
    
    private func formatDuration(_ value: Float) -> String {
        let totalSeconds = Int(value)
        let hours = totalSeconds / 3600
        
        // Formatter for nicer output "124h 30m"
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        
        return formatter.string(from: TimeInterval(value)) ?? "\(hours)h"
    }

    // MARK: - Compact View Helpers

    @ViewBuilder
    private func compactStatisticsCard(sortedTabs: [TabConfig], stats: Statistics) -> some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 24, alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 16) {
                ForEach(sortedTabs) { tab in
                    Group {
                        switch tab.id {
                        case .scenes: compactStatRow(title: "Scenes", value: formatCount(stats.sceneCount), icon: "film", color: .blue)
                                .onTapGesture { coordinator.navigateToScenes() }
                        case .galleries: compactStatRow(title: "Galleries", value: formatCount(stats.galleryCount), icon: "photo.stack", color: .green)
                                .onTapGesture { coordinator.navigateToGalleries() }
                        case .images: compactStatRow(title: "Images", value: formatCount(stats.imageCount), icon: "photo", color: .teal)
                                .onTapGesture { coordinator.navigateToImages() }
                        case .performers: compactStatRow(title: "Performers", value: formatCount(stats.performerCount), icon: "person.2", color: .purple)
                                .onTapGesture { coordinator.navigateToPerformers() }
                        case .studios: compactStatRow(title: "Studios", value: formatCount(stats.studioCount), icon: "building.2", color: .orange)
                                .onTapGesture { coordinator.navigateToStudios() }
                        case .tags: compactStatRow(title: "Tags", value: formatCount(stats.tagCount), icon: "tag", color: .pink)
                                .onTapGesture { coordinator.navigateToTags() }
                        case .groups: compactStatRow(title: "Groups", value: formatCount(stats.movieCount), icon: "rectangle.stack.fill", color: Color(red: 0.1, green: 0.7, blue: 0.9))
                                .onTapGesture { coordinator.navigateToGroups() }
                        default: EmptyView()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.secondaryAppBackground)
        .cornerRadius(DesignTokens.CornerRadius.card)
        .cardShadow()
        .padding(.horizontal, 12)
    }

    private func compactStatRow(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(appearanceManager.tintColor)
                .frame(width: 20)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle()) // makes the whole row tappable
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(width: 80, height: 90)
        .background(
            LinearGradient(
                colors: [color, color.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(DesignTokens.CornerRadius.card)
    }
}
#endif
