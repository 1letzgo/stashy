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

    var body: some View {
        List {
            if let stats = viewModel.statistics {
                Section("Database Statistics") {
                    HStack {
                        Label("Scenes", systemImage: "film")
                        Spacer()
                        Text("\(stats.sceneCount)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Performers", systemImage: "person.2")
                        Spacer()
                        Text("\(stats.performerCount)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Studios", systemImage: "building.2")
                        Spacer()
                        Text("\(stats.studioCount)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Total Size", systemImage: "internaldrive")
                        Spacer()
                        Text(formatBytes(stats.scenesSize))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Total Duration", systemImage: "clock")
                        Spacer()
                        Text(formatDuration(stats.scenesDuration))
                            .foregroundColor(.secondary)
                    }
                }
            } else if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 40, height: 40)
                                .skeleton()
                            Text("Loading statistics...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .shimmer()
                        }
                        Spacer()
                    }
                }
            } else {
                Section {
                    Text("Unable to load statistics. Check server connection.")
                }
            }
        }
        .navigationTitle("Statistics")
        .onAppear {
            viewModel.fetchStatistics()
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDuration(_ seconds: Float) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}
