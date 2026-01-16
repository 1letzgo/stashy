
// MARK: - Server Detail View
struct ServerDetailView: View {
    let server: ServerConfig
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    @State private var showingEditSheet = false
    @Environment(\.presentationMode) var presentationMode
    
    var isActive: Bool {
        configManager.activeConfig?.id == server.id
    }
    
    var body: some View {
        Form {
            Section("Server Information") {
                LabeledContent("Name", value: server.name)
                LabeledContent("URL", value: server.baseURL)
                LabeledContent("Platform", value: server.domain.isEmpty ? "IP Address" : "Domain")
                
                if isActive {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(viewModel.serverStatus)
                            .foregroundColor(viewModel.serverStatus.contains("Verbunden") ? .green : .red)
                    }
                }
            }
            
            Section("Actions") {
                if !isActive {
                    Button(action: connectServer) {
                        Label("Connect to Server", systemImage: "power")
                    }
                }
                
                Button(action: {
                     viewModel.triggerLibraryScan { success, message in
                         // Scan triggered in background
                     }
                }) {
                    Label(isActive ? "Scan Library" : "Scan Library (Connect First)", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!isActive)
                
                Button(action: { showingEditSheet = true }) {
                    Label("Edit Configuration", systemImage: "pencil")
                }
            }
            
            Section {
                Button(role: .destructive, action: {
                    configManager.deleteServer(id: server.id)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Label("Delete Server", systemImage: "trash")
                }
            }
        }
        .navigationTitle(server.name)
        .sheet(isPresented: $showingEditSheet) {
            NavigationView {
                ServerFormView(configToEdit: server) { updatedConfig in
                    configManager.addOrUpdateServer(updatedConfig)
                    if configManager.activeConfig?.id == updatedConfig.id {
                        configManager.saveConfig(updatedConfig)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .toolbar {
            if isActive && viewModel.serverStatus.contains("Verbunden") {
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
    }
}
