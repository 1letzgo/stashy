
import SwiftUI

struct HomeStatisticsRowView: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var tabManager = TabManager.shared
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
                        (tab.id == .scenes || tab.id == .galleries ||
                         tab.id == .performers || tab.id == .studios || tab.id == .tags) && tab.isVisible
                    }
                    .sorted { $0.sortOrder < $1.sortOrder }

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
                                    // Binde images immer hinter galleries
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
                                default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            } else if viewModel.isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<6) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
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
        .cornerRadius(12)
    }
}
