//
//  ServerStatisticsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

import SwiftUI

struct ServerStatisticsView: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var appearance = AppearanceManager.shared
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var hasAttemptedLoad = false
    @State private var didFailLoad = false

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { reload() }
            } else if let stats = viewModel.statistics {
                ScrollView {
                    VStack(spacing: 16) {
                        if isRegular {
                            HStack(alignment: .top, spacing: 16) {
                                heroCard(stats)
                                    .frame(maxWidth: .infinity)
                                storageCard(stats)
                                    .frame(width: 280)
                            }
                            catalogsCard(stats)
                        } else {
                            heroCard(stats)
                            catalogsCard(stats)
                            storageCard(stats)
                        }
                    }
                    .toolsHorizontalPadding(horizontalSizeClass)
                    .padding(.top, DesignTokens.Tools.menuTopPadding)
                    .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
                    .frame(maxWidth: DesignTokens.Tools.regularMaxContentWidth)
                    .frame(maxWidth: .infinity)
                }
            } else if !hasAttemptedLoad || (!didFailLoad && viewModel.errorMessage == nil) {
                StandardLoadingView(message: "Loading statistics...")
            } else {
                ConnectionErrorView { reload() }
            }
        }
        .applyAppBackground()
        .onAppear { reload() }
    }

    // MARK: - Hero

    @ViewBuilder
    private func heroCard(_ stats: Statistics) -> some View {
        let unplayed = max(0, stats.sceneCount - stats.scenesPlayed)
        let avgWatch = stats.totalPlayCount > 0
            ? stats.totalPlayDuration / Double(stats.totalPlayCount)
            : 0

        statsCard(title: "Playback") {
            LazyVGrid(
                columns: DesignTokens.Tools.rankedColumns(for: horizontalSizeClass, compact: 2, regular: 4),
                spacing: 16
            ) {
                heroStat(
                    icon: "clock.fill",
                    value: formatDuration(stats.totalPlayDuration),
                    label: "Watch Time"
                )
                heroStat(
                    icon: appearance.oCounterIconFilled,
                    value: formatCount(stats.totalOCount),
                    label: "O-Count"
                )
                heroStat(
                    icon: "play.fill",
                    value: formatCount(stats.totalPlayCount),
                    label: "Play Count"
                )
                heroStat(
                    icon: "chart.pie.fill",
                    value: formatPlayedShare(played: stats.scenesPlayed, total: stats.sceneCount),
                    label: "Played Share"
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            Text("Library \(formatDuration(stats.scenesDuration))  ·  Ø \(formatDuration(avgWatch))/play  ·  \(formatCount(unplayed)) unplayed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func heroStat(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(appearance.tintColor)
            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Catalogs

    @ViewBuilder
    private func catalogsCard(_ stats: Statistics) -> some View {
        statsCard(title: "Catalogs") {
            LazyVGrid(
                columns: DesignTokens.Tools.rankedColumns(for: horizontalSizeClass, compact: 2, regular: 4),
                spacing: 8
            ) {
                ForEach(catalogEntries(from: stats)) { entry in
                    Button {
                        entry.navigate(coordinator)
                    } label: {
                        catalogTile(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func catalogTile(_ entry: CatalogStatEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(appearance.tintColor)
                .frame(width: 18, alignment: .center)
            Text(entry.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(formatCount(entry.value))
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small, style: .continuous))
        .contentShape(Rectangle())
    }

    // MARK: - Storage

    @ViewBuilder
    private func storageCard(_ stats: Statistics) -> some View {
        statsCard(title: "Storage") {
            VStack(spacing: 0) {
                statRow("Scenes", value: formatBytes(stats.scenesSize))
                Divider().padding(.leading, 12)
                statRow("Images", value: formatBytes(stats.imagesSize))
                Divider().padding(.leading, 12)
                statRow("Total", value: formatBytes(stats.scenesSize + stats.imagesSize), emphasize: true)
            }
        }
    }

    private func statsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            content()
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondaryAppBackground(for: appearance.currentTheme))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
    }

    // MARK: - Data

    private func catalogEntries(from stats: Statistics) -> [CatalogStatEntry] {
        [
            .init(title: "Scenes", value: stats.sceneCount, icon: "film") { $0.navigateToScenes() },
            .init(title: "Performers", value: stats.performerCount, icon: "person.2") { $0.navigateToPerformers() },
            .init(title: "Galleries", value: stats.galleryCount, icon: "photo.stack") { $0.navigateToGalleries() },
            .init(title: "Images", value: stats.imageCount, icon: "photo") { $0.navigateToImages() },
            .init(title: "Markers", value: stats.sceneMarkerCount ?? 0, icon: "bookmark.fill") { $0.navigateToMarkers() },
            .init(title: "Studios", value: stats.studioCount, icon: "building.2") { $0.navigateToStudios() },
            .init(title: "Groups", value: stats.groupCount, icon: "rectangle.stack.fill") { $0.navigateToGroups() },
            .init(title: "Tags", value: stats.tagCount, icon: "tag") { $0.navigateToTags() },
        ]
    }

    private func reload() {
        hasAttemptedLoad = true
        didFailLoad = false
        viewModel.fetchStatistics { success in
            DispatchQueue.main.async {
                self.didFailLoad = !success
            }
        }
    }

    private func statRow(_ title: String, value: String, emphasize: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(emphasize ? .subheadline.weight(.semibold) : .subheadline)
            Spacer()
            Text(value)
                .font(emphasize ? .subheadline.weight(.semibold).monospacedDigit() : .subheadline.monospacedDigit())
                .foregroundColor(emphasize ? .primary : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func formatBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatPlayedShare(played: Int, total: Int) -> String {
        guard total > 0 else { return "—" }
        let percent = (Double(played) / Double(total)) * 100
        return String(format: "%.0f%%", percent)
    }

    private func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct CatalogStatEntry: Identifiable {
    var id: String { title }
    let title: String
    let value: Int
    let icon: String
    let navigate: (NavigationCoordinator) -> Void
}
