//
//  ServerFormViewNew.swift
//  stashy
//
//  Improved server form with live connection testing
//

#if !os(tvOS)
import SwiftUI

// MARK: - Improved Server Form View
struct ServerFormViewNew: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    // Form State
    @State private var name: String = "My Stash"
    @State private var serverAddress: String = ""
    @State private var serverProtocol: ServerProtocol = .https
    @State private var apiKey: String = ""
    
    // Connection Test State
    @State private var isTesting: Bool = false
    @State private var testResult: ConnectionTestResult = .none
    @State private var testMessage: String = ""
    
    let configToEdit: ServerConfig?
    let onSave: (ServerConfig) -> Void
    let onDelete: (() -> Void)?
    
    @State private var showingDeleteAlert = false
    
    enum ConnectionTestResult {
        case none
        case success
        case failure
    }
    
    init(configToEdit: ServerConfig?, onSave: @escaping (ServerConfig) -> Void, onDelete: (() -> Void)? = nil) {
        self.configToEdit = configToEdit
        self.onSave = onSave
        self.onDelete = onDelete
    }
    
    var isConfigValid: Bool {
        return !name.isEmpty && !serverAddress.isEmpty
    }
    
    var currentBaseURL: String {
        let parsed = ServerConfig.parseHostAndPort(serverAddress)
        let effectivePort = parsed.port ?? serverProtocol.defaultPort
        let scheme = serverProtocol == .https ? "https" : "http"
        
        let needsPort = (serverProtocol == .https && effectivePort != "443") || 
                       (serverProtocol == .http && effectivePort != "80")
        
        if needsPort {
            return "\(scheme)://\(parsed.host):\(effectivePort)"
        } else {
            return "\(scheme)://\(parsed.host)"
        }
    }
    
    var body: some View {
        Form {
            Section {
                TextField("Server Name", text: $name)
                    .textContentType(.organizationName)
                
                Picker("Protocol", selection: $serverProtocol) {
                    ForEach(ServerProtocol.allCases, id: \.self) { proto in
                        Text(proto.displayName).tag(proto)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: serverProtocol) { _, _ in resetTestState() }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server Address")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("192.168.1.100:9999 or stash.example.com", text: $serverAddress)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: serverAddress) { oldValue, newValue in
                            resetTestState()
                            if newValue.lowercased().hasPrefix("https://") {
                                serverProtocol = .https
                                if newValue.count > 8 {
                                    serverAddress = String(newValue.dropFirst(8))
                                }
                            } else if newValue.lowercased().hasPrefix("http://") {
                                serverProtocol = .http
                                if newValue.count > 7 {
                                    serverAddress = String(newValue.dropFirst(7))
                                }
                            }
                        }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Server Details")
            }
            
            // Authentication Section
            Section {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(.secondary)
                    SecureField("API Key (optional)", text: $apiKey)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Authentication")
            } footer: {
                Text("Enter the API key if authentication is enabled on your Stash server.")
            }
            
            // Connection Test Section
            Section {
                Button(action: {
                    // Clean address before testing
                    let detection = ServerConfig.detectProtocol(from: serverAddress)
                    if let proto = detection.protocol {
                        serverProtocol = proto
                    }
                    serverAddress = detection.address
                    testConnection()
                }) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: testResultIcon)
                                .foregroundColor(testResultColor)
                        }
                        
                        Text(isTesting ? "Testing..." : "Test Connection")
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if testResult == .success {
                            Text(testMessage)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                .disabled(!isConfigValid || isTesting)
                
                if testResult == .failure && !testMessage.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(testMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                if isConfigValid {
                    Text("URL: \(currentBaseURL)")
                }
            }
            
            // Delete Button (only if editing)
            if configToEdit != nil {
                Section {
                    Button(role: .destructive, action: { showingDeleteAlert = true }) {
                        HStack {
                            Spacer()
                            Label("Delete Server", systemImage: "trash")
                                .foregroundColor(appearanceManager.tintColor)
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(configToEdit == nil ? "Add Server" : "Edit Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    // Clean address before saving
                    let detection = ServerConfig.detectProtocol(from: serverAddress)
                    if let proto = detection.protocol {
                        serverProtocol = proto
                    }
                    serverAddress = detection.address
                    
                    saveServer()
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(!isConfigValid)
            }
        }
        .onAppear {
            if let config = configToEdit {
                name = config.name
                serverAddress = config.serverAddress + (config.port != nil ? ":\(config.port!)" : "")
                serverProtocol = config.serverProtocol
                
                // Load API key from Keychain first, fallback to config
                if let savedKey = KeychainManager.shared.loadAPIKey(forServerID: config.id) {
                    apiKey = savedKey
                } else {
                    apiKey = config.apiKey ?? ""
                }
            }
        }
        .alert("Delete Server", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let config = configToEdit {
                    KeychainManager.shared.deleteAPIKey(forServerID: config.id)
                }
                onDelete?()
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this server configuration? This action cannot be undone.")
        }
    }
    
    private var testResultIcon: String {
        switch testResult {
        case .none: return "network"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }
    
    private var testResultColor: Color {
        switch testResult {
        case .none: return .secondary
        case .success: return .green
        case .failure: return .red
        }
    }
    
    private func resetTestState() {
        testResult = .none
        testMessage = ""
    }
    
    private func testConnection() {
        isTesting = true
        testResult = .none
        testMessage = ""
        
        guard let url = URL(string: "\(currentBaseURL)/graphql") else {
            isTesting = false
            testResult = .failure
            testMessage = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15 // Consistent with GraphQLClient
        
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        }
        
        let query = """
        {"query": "{ version { version } }"}
        """
        request.httpBody = query.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isTesting = false
                
                if let error = error {
                    testResult = .failure
                    if (error as NSError).code == NSURLErrorCannotConnectToHost {
                        testMessage = "Cannot connect - check IP/Port"
                    } else if (error as NSError).code == NSURLErrorTimedOut {
                        testMessage = "Connection timed out"
                    } else {
                        testMessage = error.localizedDescription
                    }
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    testResult = .failure
                    testMessage = "Invalid response"
                    return
                }
                
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    testResult = .failure
                    testMessage = "Authentication required - check API Key"
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    testResult = .failure
                    testMessage = "Server error: \(httpResponse.statusCode)"
                    return
                }
                
                // Try to parse version
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataObj = json["data"] as? [String: Any],
                   let versionObj = dataObj["version"] as? [String: Any],
                   let version = versionObj["version"] as? String {
                    testResult = .success
                    testMessage = version
                } else {
                    testResult = .success
                    testMessage = "Connected"
                }
            }
        }.resume()
    }
    
    private func saveServer() {
        let serverID = configToEdit?.id ?? UUID()
        
        // Save API key to Keychain
        if !apiKey.isEmpty {
            _ = KeychainManager.shared.saveAPIKey(apiKey, forServerID: serverID)
        } else {
            KeychainManager.shared.deleteAPIKey(forServerID: serverID)
        }
        
        let parsed = ServerConfig.parseHostAndPort(serverAddress)
        let newConfig = ServerConfig(
            id: serverID,
            name: name,
            serverAddress: parsed.host,
            port: parsed.port,
            serverProtocol: serverProtocol,
            apiKey: nil // API key now stored in Keychain
        )
        onSave(newConfig)
    }
}

#Preview {
    NavigationView {
        ServerFormViewNew(configToEdit: nil, onSave: { _ in })
    }
}
#endif
