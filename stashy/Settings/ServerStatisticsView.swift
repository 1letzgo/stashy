//
//  ServerStatisticsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct ServerStatisticsView: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject private var configManager = ServerConfigManager.shared
    @State private var hasAttemptedLoad = false
    @State private var didFailLoad = false

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { reload() }
            } else if viewModel.statistics != nil {
                List {
                    if let stats = viewModel.statistics {
                        Section("Catalogs") {
#if canImport(Charts)
                            CatalogsBarChart(data: catalogEntries(from: stats))
                                .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
#else
                            ForEach(catalogEntries(from: stats), id: \.title) { entry in
                                statRow(entry.title, value: "\(entry.value)")
                            }
#endif
                        }
                        .listRowBackground(Color.secondaryAppBackground)

                        Section("Usage") {
                            statRow("Scenes Size", value: formatBytes(stats.scenesSize))
                            statRow("Images Size", value: formatBytes(stats.imagesSize))
                            statRow("Total Size", value: formatBytes(stats.scenesSize + stats.imagesSize))
                            statRow("Library Duration", value: formatDuration(stats.scenesDuration))
                            statRow("Watch Time", value: formatDuration(stats.totalPlayDuration))
                            statRow("Play Count", value: "\(stats.totalPlayCount)")
                            statRow("Scenes Played", value: "\(stats.scenesPlayed)")
                            statRow("Played Share", value: formatPlayedShare(played: stats.scenesPlayed, total: stats.sceneCount))
                            statRow("Total O-Count", value: "\(stats.totalOCount)")
                        }
                        .listRowBackground(Color.secondaryAppBackground)

                        Section("Performers") {
                            statRow("Total", value: "\(stats.performerCount)")

                            if viewModel.isLoadingPerformerGenderCounts {
                                HStack { Spacer(); ProgressView("Loading gender distribution..."); Spacer() }
                                    .padding(.vertical, 8)
                            } else {
                                let sorted = sortedGenderCounts(viewModel.performerGenderCounts)

                                if sorted.isEmpty {
                                    Text("No gender data available.")
                                        .foregroundColor(.secondary)
                                } else {
#if canImport(Charts)
                                    GenderBarChart(data: sorted.map {
                                        GenderBarChart.Entry(title: displayGender($0.key), value: $0.value)
                                    })
                                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
#else
                                    ForEach(sorted, id: \.key) { gender, count in
                                        HStack {
                                            Text(displayGender(gender))
                                            Spacer()
                                            Text("\(count)")
                                                .foregroundColor(.secondary)
                                        }
                                    }
#endif
                                }
                            }
                        }
                        .listRowBackground(Color.secondaryAppBackground)
                    }
                }
                .scrollContentBackground(.hidden)
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

    private func catalogEntries(from stats: Statistics) -> [CatalogStatEntry] {
        [
            .init(title: "Scenes", value: stats.sceneCount),
            .init(title: "Galleries", value: stats.galleryCount),
            .init(title: "Images", value: stats.imageCount),
            .init(title: "Markers", value: stats.sceneMarkerCount ?? 0),
            .init(title: "Studios", value: stats.studioCount),
            .init(title: "Groups", value: stats.groupCount),
            .init(title: "Tags", value: stats.tagCount),
        ]
    }

    private func sortedGenderCounts(_ counts: [String: Int]) -> [(key: String, value: Int)] {
        counts
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
    }

    private func reload() {
        hasAttemptedLoad = true
        didFailLoad = false
        viewModel.fetchStatistics { success in
            DispatchQueue.main.async {
                self.didFailLoad = !success
            }
        }
        // Gender aggregation pages all performers; keep warm when Tools sub-tabs switch.
        if viewModel.performerGenderCounts.isEmpty {
            viewModel.fetchPerformerGenderCounts()
        }
    }

    private func displayGender(_ rawKey: String) -> String {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch key {
        case "FEMALE": return "Female"
        case "MALE": return "Male"
        case "TRANSGENDER_FEMALE": return "Transgender (Female)"
        case "TRANSGENDER_MALE": return "Transgender (Male)"
        case "INTERSEX": return "Intersex"
        case "NON_BINARY", "NON-BINARY", "NONBINARY": return "Non-binary"
        case "UNKNOWN", "UNSPECIFIED": return "Unknown"
        default:
            let pretty = key
                .replacingOccurrences(of: "_", with: " ")
                .lowercased()
                .capitalized
            return pretty
        }
    }

    private func statRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
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
}

private struct CatalogStatEntry: Identifiable {
    var id: String { title }
    let title: String
    let value: Int
}

#if canImport(Charts)
private struct CatalogsBarChart: View {
    let data: [CatalogStatEntry]

    var body: some View {
        let maxValue = max(data.map(\.value).max() ?? 1, 1)

        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)

            Chart(data) { entry in
                BarMark(
                    x: .value("Catalog", entry.title),
                    y: .value("Count", entry.value)
                )
                .foregroundStyle(Color.accentColor)
                .cornerRadius(4)
                .annotation(position: .top, alignment: .center) {
                    Text("\(entry.value)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .chartYScale(domain: 0...Double(maxValue))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { _ in
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 180)
            .padding(.horizontal, 12)
        }
    }
}

private struct GenderBarChart: View {
    struct Entry: Identifiable {
        var id: String { title }
        let title: String
        let value: Int
    }

    let data: [Entry]

    var body: some View {
        let maxValue = max(data.map(\.value).max() ?? 1, 1)
        let chartHeight = max(CGFloat(data.count) * 28, 80)

        VStack(alignment: .leading, spacing: 8) {
            Text("Gender distribution")
                .font(.caption)
                .foregroundColor(.secondary)

            Chart(data) { entry in
                BarMark(
                    x: .value("Count", entry.value),
                    y: .value("Gender", entry.title)
                )
                .foregroundStyle(Color.accentColor)
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .center) {
                    Text("\(entry.value)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .chartXScale(domain: 0...Double(maxValue))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: chartHeight)
        }
        .padding(.vertical, 4)
    }
}
#endif
