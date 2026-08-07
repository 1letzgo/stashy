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
    @State private var hasAttemptedLoad = false
    @State private var didFailLoad = false

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { reload() }
            } else if let stats = viewModel.statistics {
                ScrollView {
                    VStack(spacing: 16) {
                        catalogsCard(stats)
                        storageCard(stats)
                        playbackCard(stats)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            } else if !hasAttemptedLoad || (!didFailLoad && viewModel.errorMessage == nil) {
                StandardLoadingView(message: "Loading statistics...")
            } else {
                ConnectionErrorView { reload() }
            }
        }
        .navigationTitle("Statistics")
        .applyAppBackground()
        .onAppear { reload() }
    }

    // MARK: - Cards

    @ViewBuilder
    private func catalogsCard(_ stats: Statistics) -> some View {
        let entries = catalogEntries(from: stats)
        statsCard(title: "Catalogs") {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    statRow(entry.title, value: formatCount(entry.value))
                    if index < entries.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
    }

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

    @ViewBuilder
    private func playbackCard(_ stats: Statistics) -> some View {
        statsCard(title: "Playback") {
            VStack(spacing: 0) {
                statRow("Library Duration", value: formatDuration(stats.scenesDuration))
                Divider().padding(.leading, 12)
                statRow("Watch Time", value: formatDuration(stats.totalPlayDuration))
                Divider().padding(.leading, 12)
                statRow("Play Count", value: "\(stats.totalPlayCount)")
                Divider().padding(.leading, 12)
                statRow("Scenes Played", value: "\(stats.scenesPlayed)")
                Divider().padding(.leading, 12)
                statRow("Played Share", value: formatPlayedShare(played: stats.scenesPlayed, total: stats.sceneCount))
                Divider().padding(.leading, 12)
                statRow("Total O-Count", value: "\(stats.totalOCount)")
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
        .background(Color.secondaryAppBackground)
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
            .init(title: "Scenes", value: stats.sceneCount),
            .init(title: "Performers", value: stats.performerCount),
            .init(title: "Galleries", value: stats.galleryCount),
            .init(title: "Images", value: stats.imageCount),
            .init(title: "Markers", value: stats.sceneMarkerCount ?? 0),
            .init(title: "Studios", value: stats.studioCount),
            .init(title: "Groups", value: stats.groupCount),
            .init(title: "Tags", value: stats.tagCount),
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
        return "\(hours)h \(minutes)m"
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
}
