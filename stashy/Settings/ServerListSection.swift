//
//  ServerListSection.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI

struct ServerListSection: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject private var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator

    @Binding var isScanningLibrary: Bool
    @Binding var showingAddServerSheet: Bool
    @Binding var editingServer: ServerConfig?
    var onScan: () -> Void
    @State private var pendingDelete: ServerConfig?

    var body: some View {
        Section {
            stashyScrollingSectionHeader(tr("servers"))
            ForEach(Array(configManager.savedServers.enumerated()), id: \.element.id) { index, server in
                ServerListRow(
                    server: server,
                    viewModel: viewModel,
                    isActive: configManager.activeConfig?.id == server.id,
                    isConnected: configManager.activeConfig?.id == server.id && viewModel.isServerConnected,
                    isScanning: isScanningLibrary,
                    onConnect: {
                        configManager.saveConfig(server)
                        viewModel.resetData()
                        viewModel.testConnection(force: true)
                        viewModel.fetchStatistics()
                        coordinator.resetAllStacks()
                    },
                    onEdit: {
                        editingServer = server
                    },
                    onScan: onScan
                )
                .stashyGroupedBlockRow(index: index, count: configManager.savedServers.count + 1)
            }
            .onDelete { indexSet in
                // Ask first: the swipe would otherwise drop the server with its key and cache.
                pendingDelete = indexSet.compactMap { index in
                    configManager.savedServers.indices.contains(index) ? configManager.savedServers[index] : nil
                }.first
            }
            Button(action: {
                showingAddServerSheet = true
            }) {
                Label(tr("action_add_new_server"), systemImage: "plus")
            }
            .stashyGroupedBlockRow(index: configManager.savedServers.count, count: configManager.savedServers.count + 1)
            .alert(tr("action_delete_server"), isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )) {
                Button(tr("action_cancel"), role: .cancel) { pendingDelete = nil }
                Button(tr("action_delete"), role: .destructive) {
                    if let server = pendingDelete {
                        configManager.deleteServer(id: server.id)
                    }
                    pendingDelete = nil
                }
            } message: {
                Text(tr("hint_are_you_sure_you_want", pendingDelete?.name ?? tr("this_server")))
            }
        }
    }
}

// MARK: - Server List Row

struct ServerListRow: View {
    let server: ServerConfig
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject private var configManager = ServerConfigManager.shared
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

                        if let local = server.localBaseURL {
                            let usesLocal = configManager.usesLocalAddress
                            addressLine(tr("remote_arg", server.externalBaseURL), inUse: isActive && !usesLocal)
                            addressLine(tr("local_arg", local), inUse: isActive && usesLocal)
                        } else {
                            Text(server.externalBaseURL)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The link below would otherwise claim half the row and cut the addresses short.
            .layoutPriority(1)

            NavigationLink(destination: ServerDetailView(server: server, viewModel: viewModel)) {
                EmptyView()
            }
            .padding(.leading, 8)
        }
    }

    /// One address at full length and caption size; the one in use is bold. A long address
    /// wraps instead of shrinking.
    private func addressLine(_ text: String, inUse: Bool) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(inUse ? .bold : .regular)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var indicatorColor: Color {
        if isActive {
            return isConnected ? .green : .yellow
        } else {
            return .gray.opacity(0.3)
        }
    }
}
#endif
