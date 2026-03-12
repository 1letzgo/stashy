//
//  TVSettingsView.swift
//  stashyTV
//
//  Created for stashy tvOS.
//

import SwiftUI

struct TVSettingsView: View {
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var showingAddServer = false
    @State private var editingServer: ServerConfig?

    var body: some View {
        List {
                // MARK: - Current Server
                Section {
                    if let config = configManager.activeConfig {
                        HStack(spacing: 20) {
                            Image(systemName: "server.rack")
                                .font(.title2)
                                .foregroundColor(appearanceManager.tintColor)
                                .frame(width: 44)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(config.name)
                                    .font(.headline)
                                Text(config.baseURL)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.yellow)
                            Text("No server configured")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Active Server")
                }

                // MARK: - Saved Servers
                Section {
                    ForEach(configManager.savedServers) { server in
                        Button {
                            switchToServer(server)
                        } label: {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(server.name)
                                        .font(.headline)
                                    Text(server.baseURL)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if server.id == configManager.activeConfig?.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(appearanceManager.tintColor)
                                }
                            }
                        }
                        .contextMenu {
                            Button("Edit") {
                                editingServer = server
                            }
                            Button("Delete", role: .destructive) {
                                configManager.deleteServer(id: server.id)
                            }
                        }
                    }

                    Button {
                        showingAddServer = true
                    } label: {
                        Label("Add Server", systemImage: "plus")
                    }
                } header: {
                    Text("Saved Servers")
                }

                // MARK: - Appearance
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Accent Color")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                ForEach(appearanceManager.presets) { preset in
                                    Button {
                                        appearanceManager.tintColor = preset.color
                                    } label: {
                                        TVColorPresetButton(preset: preset, isSelected: preset.color == appearanceManager.tintColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                } header: {
                    Text("Appearance")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("App")
                        Spacer()
                        Text("stashy for Apple TV")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text(buildNumber)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingAddServer) {
                TVServerFormView(server: nil) { newServer in
                    configManager.addOrUpdateServer(newServer)
                    configManager.saveConfig(newServer)
                    showingAddServer = false
                }
            }
            .sheet(item: $editingServer) { server in
                TVServerFormView(server: server) { updatedServer in
                    configManager.addOrUpdateServer(updatedServer)
                    if updatedServer.id == configManager.activeConfig?.id {
                        configManager.saveConfig(updatedServer)
                    }
                    editingServer = nil
                }
            }
    }

    private func switchToServer(_ server: ServerConfig) {
        configManager.saveConfig(server)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Server Form View

struct TVServerFormView: View {
    let server: ServerConfig?
    let onSave: (ServerConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var port: String = ""
    @State private var selectedProtocol: ServerProtocol = .https
    @State private var apiKey: String = ""
    
    // Auth State
    @State private var authMethod: AuthMethod = .none
    @State private var username = ""
    @State private var password = ""
    @State private var isFetchingKey = false
    @State private var loginErrorMessage: String? = nil

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case name, address, port, apiKey
    }

    init(server: ServerConfig?, onSave: @escaping (ServerConfig) -> Void) {
        self.server = server
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 40) {
                    Text(server == nil ? "Add Server" : "Edit Server")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 40)

                    VStack(spacing: 24) {
                        TextField("Server Name", text: $name)
                            .focused($focusedField, equals: .name)

                        TextField("Server Address", text: $address)
                            .focused($focusedField, equals: .address)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: address) { _, newValue in
                                let detection = ServerConfig.detectProtocol(from: newValue)
                                if let detectedProtocol = detection.protocol {
                                    selectedProtocol = detectedProtocol
                                    address = detection.address
                                }
                            }

                        HStack(spacing: 24) {
                            TextField("Port (optional)", text: $port)
                                .focused($focusedField, equals: .port)
                                .frame(maxWidth: 300)

                            Picker("Protocol", selection: $selectedProtocol) {
                                ForEach(ServerProtocol.allCases, id: \.self) { proto in
                                    Text(proto.displayName).tag(proto)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 300)
                        }

                        // Authentication Section
                        VStack(alignment: .leading, spacing: 24) {
                            Text("Authentication")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Picker("Auth Method", selection: $authMethod) {
                                ForEach(AuthMethod.allCases, id: \.self) { method in
                                    Text(method.rawValue).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            if authMethod == .login {
                                VStack(spacing: 24) {
                                    TextField("Username", text: $username)
                                        .textContentType(.username)
                                        .textInputAutocapitalization(.never)
                                    
                                    SecureField("Password", text: $password)
                                        .textContentType(.password)
                                    
                                    Button {
                                        fetchKeyViaLogin()
                                    } label: {
                                        HStack(spacing: 12) {
                                            if isFetchingKey {
                                                ProgressView()
                                            }
                                            Text(isFetchingKey ? "Logging in..." : "Fetch API Key")
                                        }
                                        .frame(minWidth: 300)
                                    }
                                    .disabled(username.isEmpty || password.isEmpty || isFetchingKey)
                                    
                                    if let error = loginErrorMessage {
                                        Text(error)
                                            .foregroundColor(.red)
                                            .font(.callout)
                                    }
                                }
                            } else if authMethod == .apiKey {
                                TextField("API Key", text: $apiKey)
                                    .focused($focusedField, equals: .apiKey)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(20)
                    }
                    .frame(maxWidth: 800)

                    HStack(spacing: 40) {
                        Button("Cancel") {
                            dismiss()
                        }

                        Button("Save") {
                            save()
                        }
                        .disabled(address.isEmpty)
                    }
                    .padding(.bottom, 60)
                }
                .padding(.horizontal, 60)
            }
        }
            .onAppear {
                if let server = server {
                    name = server.name
                    address = server.serverAddress
                    port = server.port ?? ""
                    selectedProtocol = server.serverProtocol
                    apiKey = server.secureApiKey ?? ""
                    
                    // Determine initial auth method
                    if let key = server.secureApiKey, !key.isEmpty {
                        authMethod = .apiKey
                    } else {
                        authMethod = .none
                    }
                }
            }
        }

    private func save() {
        let parsed = ServerConfig.parseHostAndPort(address)
        let finalAddress = parsed.host
        let finalPort = !port.isEmpty ? port : parsed.port

        let config = ServerConfig(
            id: server?.id ?? UUID(),
            name: name.isEmpty ? "My Stash" : name,
            serverAddress: finalAddress,
            port: finalPort,
            serverProtocol: selectedProtocol,
            apiKey: authMethod == .none ? nil : (apiKey.isEmpty ? nil : apiKey)
        )

        onSave(config)
    }
    
    private func fetchKeyViaLogin() {
        let parsed = ServerConfig.parseHostAndPort(address)
        let finalAddress = parsed.host
        let finalPort = !port.isEmpty ? port : parsed.port
        
        let config = ServerConfig(
            name: name,
            serverAddress: finalAddress,
            port: finalPort,
            serverProtocol: selectedProtocol
        )
        
        isFetchingKey = true
        loginErrorMessage = nil
        
        Task {
            do {
                let fetchedKey = try await LoginAuthHelper.shared.fetchAPIKey(
                    baseURL: config.baseURL,
                    username: username,
                    password: password
                )
                
                await MainActor.run {
                    self.apiKey = fetchedKey
                    self.isFetchingKey = false
                    self.authMethod = .apiKey
                    self.username = ""
                    self.password = ""
                }
            } catch {
                await MainActor.run {
                    self.loginErrorMessage = error.localizedDescription
                    self.isFetchingKey = false
                }
            }
        }
    }
}

// MARK: - Color Preset Button

struct TVColorPresetButton: View {
    let preset: ColorOption
    let isSelected: Bool
    @Environment(\.isFocused) var isFocused

    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(preset.color)
                .frame(width: 60, height: 60)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.white : (isFocused ? Color.white.opacity(0.5) : Color.clear), lineWidth: 4)
                )
                .scaleEffect(isFocused ? 1.2 : 1.0)
                .shadow(color: preset.color.opacity(isFocused ? 0.8 : 0.4), radius: isFocused ? 12 : (isSelected ? 8 : 0))

            Text(preset.localizedName)
                .font(.caption)
                .foregroundStyle(isFocused ? .primary : .secondary)
        }
        .padding(16) // Padding to avoid clipping the scale effect
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
