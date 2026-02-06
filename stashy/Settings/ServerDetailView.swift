//
//  ServerDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

import SwiftUI

struct ServerDetailView: View {
    let server: ServerConfig
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator

    @State private var showingEditSheet = false
    @State private var isScanning = false
    @State private var showScanAlert = false
    @State private var scanAlertMessage = ""
    @Environment(\.presentationMode) var presentationMode

    var isActive: Bool {
        configManager.activeConfig?.id == server.id
    }

    var body: some View {
        Form {
            Section("Server Information") {
                LabeledContent("Name", value: server.name)
                LabeledContent("URL", value: server.baseURL)
                LabeledContent("Protocol", value: server.serverProtocol.displayName)

                if isActive {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(viewModel.serverStatus)
                            .foregroundColor(viewModel.isServerConnected ? .green : .red)
                    }
                }
            }

            Section("Actions") {
                if !isActive {
                    Button(action: connectServer) {
                        Label("Connect to Server", systemImage: "power")
                            .foregroundColor(.primary)
                    }
                }

                Button(action: {
                    if !isActive {
                        connectServer()
                    }
                    isScanning = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        viewModel.triggerLibraryScan { success, message in
                            DispatchQueue.main.async {
                                isScanning = false
                                scanAlertMessage = message
                                showScanAlert = true
                            }
                        }
                    }
                }) {
                    HStack {
                        Label("Scan Library", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundColor(.primary)
                        Spacer()
                        if isScanning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isScanning)

                if isActive {
                    NavigationLink(destination: ServerStatisticsView(viewModel: viewModel)) {
                        Label("Statistics", systemImage: "chart.bar")
                            .foregroundColor(.primary)
                    }
                }

                Button(action: { showingEditSheet = true }) {
                    Label("Edit Configuration", systemImage: "pencil")
                        .foregroundColor(.primary)
                }
            }

            Section {
                Button(role: .destructive, action: {
                    configManager.deleteServer(id: server.id)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Label("Delete Server", systemImage: "trash")
                        .foregroundColor(appearanceManager.tintColor)
                }
            }
        }
        .navigationTitle(server.name)
        .alert("Library Scan", isPresented: $showScanAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(scanAlertMessage)
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationView {
                ServerFormViewNew(configToEdit: server) { updatedConfig in
                    configManager.addOrUpdateServer(updatedConfig)
                    if configManager.activeConfig?.id == updatedConfig.id {
                        configManager.saveConfig(updatedConfig)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .toolbar {
            if isActive && viewModel.isServerConnected {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
    }

    private func connectServer() {
        configManager.saveConfig(server)
        viewModel.resetData()
        viewModel.testConnection()
        viewModel.fetchStatistics()
        coordinator.resetAllStacks()
    }
}
