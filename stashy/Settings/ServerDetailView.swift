//
//  ServerDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI

struct ServerDetailView: View {
    let server: ServerConfig
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator

    @State private var showingEditSheet = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var runningTask: String? = nil

    @Environment(\.presentationMode) var presentationMode

    var isActive: Bool {
        configManager.activeConfig?.id == server.id
    }

    var body: some View {
        let infoCount = isActive ? 4 : 3
        List {
            Section {
                stashyScrollingSectionHeader("Server Information")
                LabeledContent("Name", value: server.name)
                    .stashyGroupedBlockRow(index: 0, count: infoCount)
                LabeledContent("URL", value: server.baseURL)
                    .stashyGroupedBlockRow(index: 1, count: infoCount)
                LabeledContent("Protocol", value: server.serverProtocol.displayName)
                    .stashyGroupedBlockRow(index: 2, count: infoCount)
                if isActive {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(viewModel.serverStatus)
                            .foregroundColor(viewModel.isServerConnected ? .green : .red)
                    }
                    .stashyGroupedBlockRow(index: 3, count: infoCount)
                }
            }

            if !isActive {
                Section {
                    taskRow(label: "Connect to Server", icon: "power", taskId: "connect") {
                        connectServer()
                    }
                    .stashyGroupedSettingsRow()
                }
            }

            Section {
                stashyScrollingSectionHeader("Server Configuration")
                Button(action: { showingEditSheet = true }) {
                    Label("Edit Configuration", systemImage: "pencil")
                        .foregroundColor(.primary)
                }
                .stashyGroupedBlockRow(index: 0, count: 2)
                Button(role: .destructive, action: {
                    configManager.deleteServer(id: server.id)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Label("Delete Server", systemImage: "trash")
                        .foregroundColor(appearanceManager.tintColor)
                }
                .stashyGroupedBlockRow(index: 1, count: 2)
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome(server.name) {
            if isActive && viewModel.isServerConnected {
                Image(systemName: "circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
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
    }

    @ViewBuilder
    private func taskRow(label: String, icon: String, taskId: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon)
                    .frame(width: 24, alignment: .center)
            }
            .foregroundColor(.primary)
            Spacer()
            if runningTask == taskId {
                ProgressView()
                    .padding(.trailing, 4)
            } else {
                Button(action: {
                    if !isActive { connectServer() }
                    runningTask = taskId
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        action()
                    }
                }) {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(appearanceManager.tintColor)
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(runningTask != nil)
            }
        }
    }

    private func showResult(title: String, message: String) {
        DispatchQueue.main.async {
            runningTask = nil
            alertTitle = title
            alertMessage = message
            showAlert = true
        }
    }

    private func connectServer() {
        configManager.saveConfig(server)
        viewModel.resetData()
        viewModel.testConnection(force: true)
        viewModel.fetchStatistics()
        coordinator.resetAllStacks()
    }
}
#endif
