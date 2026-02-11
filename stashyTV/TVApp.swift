//
//  TVApp.swift
//  stashyTV
//
//  Created for stashy tvOS.
//

import SwiftUI

@main
struct TVApp: App {
    @ObservedObject private var configManager = ServerConfigManager.shared

    var body: some SwiftUI.Scene {
        WindowGroup {
            if configManager.activeConfig?.hasValidConfig == true {
                TVMainTabView()
            } else {
                TVServerSetupView()
            }
        }
    }
}

// MARK: - Server Setup View (shown when no config exists)

struct TVServerSetupView: View {
    @ObservedObject private var configManager = ServerConfigManager.shared

    @State private var serverName: String = "My Stash"
    @State private var serverAddress: String = ""
    @State private var port: String = ""
    @State private var selectedProtocol: ServerProtocol = .https
    @State private var apiKey: String = ""
    @State private var errorMessage: String?
    @State private var isTesting: Bool = false

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case name, address, port, apiKey
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 48) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 80))
                        .foregroundStyle(.secondary)

                    Text("Connect to Stash")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Enter your Stash server details to get started.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                // Form
                VStack(spacing: 24) {
                    TextField("Server Name", text: $serverName)
                        .focused($focusedField, equals: .name)
                        .textContentType(.name)

                    TextField("Server Address (e.g. 192.168.1.100 or stash.example.com)", text: $serverAddress)
                        .focused($focusedField, equals: .address)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: serverAddress) { _, newValue in
                            let detection = ServerConfig.detectProtocol(from: newValue)
                            if let detectedProtocol = detection.protocol {
                                selectedProtocol = detectedProtocol
                                serverAddress = detection.address
                            }
                        }

                    HStack(spacing: 24) {
                        TextField("Port (optional)", text: $port)
                            .focused($focusedField, equals: .port)
                            .frame(maxWidth: 300)
                        #if swift(>=5.9)
                            .keyboardType(.numberPad)
                        #endif

                        Picker("Protocol", selection: $selectedProtocol) {
                            ForEach(ServerProtocol.allCases, id: \.self) { proto in
                                Text(proto.displayName).tag(proto)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                    }

                    TextField("API Key (optional)", text: $apiKey)
                        .focused($focusedField, equals: .apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.callout)
                    }
                }
                .frame(maxWidth: 800)

                // Connect Button
                Button {
                    saveAndConnect()
                } label: {
                    HStack(spacing: 12) {
                        if isTesting {
                            ProgressView()
                        }
                        Text(isTesting ? "Connecting..." : "Connect")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .frame(minWidth: 300)
                }
                .disabled(serverAddress.isEmpty || isTesting)

                Spacer()
            }
            .padding(60)
        }
    }

    private func saveAndConnect() {
        let parsed = ServerConfig.parseHostAndPort(serverAddress)
        let finalAddress = parsed.host
        let finalPort = !port.isEmpty ? port : parsed.port

        let config = ServerConfig(
            name: serverName.isEmpty ? "My Stash" : serverName,
            serverAddress: finalAddress,
            port: finalPort,
            serverProtocol: selectedProtocol,
            apiKey: apiKey.isEmpty ? nil : apiKey
        )

        isTesting = true
        errorMessage = nil

        // Save and activate the config
        configManager.addOrUpdateServer(config)
        configManager.saveConfig(config)

        // Give a brief moment for the config to propagate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isTesting = false
        }
    }
}
