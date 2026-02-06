//
//  SettingsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator

    // UI State
    @State private var isScanningLibrary: Bool = false
    @State private var showScanAlert: Bool = false
    @State private var scanAlertMessage: String = ""
    @State private var showingAddServerSheet = false
    @State private var editingServer: ServerConfig?

    var body: some View {
        Form {
            // MARK: - Server
            ServerListSection(
                viewModel: viewModel,
                isScanningLibrary: $isScanningLibrary,
                showingAddServerSheet: $showingAddServerSheet,
                editingServer: $editingServer,
                onScan: { startLibraryScan() }
            )

            // MARK: - Playback
            if configManager.activeConfig != nil {
                PlaybackSettingsSection()
            }

            // MARK: - Appearance
            Section("Appearance") {
                NavigationLink(destination: AppearanceSettingsView()) {
                    Label("Appearance", systemImage: "paintbrush")
                }
            }

            // MARK: - Content & Tabs
            if configManager.activeConfig != nil {
                ContentSettingsSection()
            }

            // MARK: - Default Settings
            if configManager.activeConfig != nil {
                Section("Default Settings") {
                    NavigationLink(destination: DefaultSortView()) {
                        Label("Sorting", systemImage: "arrow.up.arrow.down")
                    }

                    NavigationLink(destination: DefaultFilterView()) {
                        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }

            // MARK: - Downloads
            if configManager.activeConfig != nil {
                Section("Downloads") {
                    NavigationLink(destination: DownloadsView()) {
                        Label("Downloads", systemImage: "square.and.arrow.down")
                    }
                }
            }

            // MARK: - About
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddServerSheet) {
            NavigationView {
                ServerFormViewNew(configToEdit: nil) { newConfig in
                    configManager.addOrUpdateServer(newConfig)
                    if configManager.activeConfig == nil {
                        configManager.saveConfig(newConfig)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingServer) { server in
            NavigationView {
                ServerFormViewNew(configToEdit: server, onSave: { updatedConfig in
                    configManager.addOrUpdateServer(updatedConfig)
                    if configManager.activeConfig?.id == updatedConfig.id {
                        configManager.saveConfig(updatedConfig)
                    }
                    editingServer = nil
                }, onDelete: {
                    configManager.deleteServer(id: server.id)
                    editingServer = nil
                })
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            if configManager.activeConfig != nil {
                viewModel.testConnection()
            }
        }
        .alert("Library Scan", isPresented: $showScanAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(scanAlertMessage)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Text("🚧 crafted by letzgo")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
    }

    // MARK: - Actions

    private func startLibraryScan() {
        isScanningLibrary = true
        viewModel.triggerLibraryScan { success, message in
            DispatchQueue.main.async {
                isScanningLibrary = false
                scanAlertMessage = message
                showScanAlert = true
            }
        }
    }
}

#Preview {
    SettingsView()
}
