//
//  ServerListSection.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

import SwiftUI

struct ServerListSection: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject private var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator

    @Binding var isScanningLibrary: Bool
    @Binding var showingAddServerSheet: Bool
    @Binding var editingServer: ServerConfig?
    var onScan: () -> Void

    var body: some View {
        Section("Servers") {
            List {
                ForEach(configManager.savedServers) { server in
                    ServerListRow(
                        server: server,
                        viewModel: viewModel,
                        isActive: configManager.activeConfig?.id == server.id,
                        isConnected: configManager.activeConfig?.id == server.id && viewModel.isServerConnected,
                        isScanning: isScanningLibrary,
                        onConnect: {
                            configManager.saveConfig(server)
                            viewModel.resetData()
                            viewModel.testConnection()
                            viewModel.fetchStatistics()
                            coordinator.resetAllStacks()
                        },
                        onEdit: {
                            editingServer = server
                        },
                        onScan: onScan
                    )
                }
                .onDelete { indexSet in
                    configManager.deleteServer(at: indexSet)
                }
            }

            Button(action: {
                showingAddServerSheet = true
            }) {
                Label("Add New Server", systemImage: "plus")
            }
        }
    }
}

// MARK: - Server List Row

struct ServerListRow: View {
    let server: ServerConfig
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    let isActive: Bool
    let isConnected: Bool
    let isScanning: Bool
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onScan: () -> Void

    var body: some View {
        HStack {
            Button(action: {
                if !isActive {
                    onConnect()
                }
            }) {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(indicatorColor)
                        .font(.caption)
                        .padding(.trailing, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(server.baseURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            NavigationLink(destination: ServerDetailView(server: server, viewModel: viewModel)) {
                EmptyView()
            }
            .padding(.leading, 8)
        }
    }

    private var indicatorColor: Color {
        if isActive {
            return isConnected ? .green : .yellow
        } else {
            return .gray.opacity(0.3)
        }
    }
}
