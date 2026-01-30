//
//  ServerSetupWizardView.swift
//  stashy
//
//  Step-by-step wizard for first-time server setup
//

import SwiftUI

struct ServerSetupWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    // Wizard State
    @State private var currentStep = 1
    private let totalSteps = 2  // Reduced from 3
    
    // Form Data
    @State private var serverAddress = ""
    @State private var serverProtocol: ServerProtocol = .https
    @State private var apiKey = ""
    @State private var serverName = "My Stash"
    
    // Connection Test State
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult = .notTested
    
    enum ConnectionTestResult: Equatable {
        case notTested
        case testing
        case success
        case failure(String)
    }
    
    var onComplete: (ServerConfig) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress Indicator
                progressBar
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                
                // Step Content
                TabView(selection: $currentStep) {
                    step1ServerDetails.tag(1)
                    step2Test.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)
                
                // Navigation Buttons
                navigationButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
            .navigationTitle("Server Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? appearanceManager.tintColor : Color.gray.opacity(0.3))
                    .frame(height: 4)
            }
        }
    }
    
    // MARK: - Step 1: Server Details
    
    private var step1ServerDetails: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 50))
                        .foregroundColor(appearanceManager.tintColor)
                    
                    Text("Server Details")
                        .font(.title2.bold())
                    
                    Text("Enter your Stash server information")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                
                VStack(spacing: 16) {
                    // Server Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("My Stash", text: $serverName)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                    }
                    
                    // Protocol Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Protocol")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker("Protocol", selection: $serverProtocol) {
                            ForEach(ServerProtocol.allCases, id: \.self) { proto in
                                Text(proto.displayName).tag(proto)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                    
                    // Server Address
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server Address")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("192.168.1.100:9999 or stash.example.com", text: $serverAddress)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .onChange(of: serverAddress) { oldValue, newValue in
                                if newValue.lowercased().hasPrefix("https://") {
                                    serverProtocol = .https
                                    // Only strip if there's more after the prefix (e.g. pasted or typed first char)
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
                        
                        Text("Enter address (e.g. timeout.com:9999)")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    
                    // API Key
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("API Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("(Optional)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        
                        SecureField("If server is protected", text: $apiKey)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer(minLength: 32)
            }
        }
    }
    
    // MARK: - Step 2: Connection Test
    
    private var step2Test: some View {
        VStack(spacing: 32) {
            Spacer()
            
            switch connectionTestResult {
            case .notTested, .testing:
                VStack(spacing: 16) {
                    if case .testing = connectionTestResult {
                        ProgressView()
                            .scaleEffect(2)
                            .padding(.bottom, 16)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 60))
                            .foregroundColor(appearanceManager.tintColor)
                    }
                    
                    Text(connectionTestResult == .testing ? "Connecting..." : "Test Connection")
                        .font(.title2.bold())
                    
                    Text("We're checking if your server is reachable")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
            case .success:
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                    
                    Text("Connection successful!")
                        .font(.title2.bold())
                    
                    Text("Your Stash server was found")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
            case .failure(let message):
                VStack(spacing: 16) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.red)
                    
                    Text("Connection failed")
                        .font(.title2.bold())
                    
                    Text(message)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button("Test again") {
                        testConnection()
                    }
                    .buttonStyle(.bordered)
                    .tint(appearanceManager.tintColor)
                }
            }
            
            Spacer()
        }
        .onAppear {
            if case .notTested = connectionTestResult {
                testConnection()
            }
        }
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep > 1 {
                Button(action: { 
                    withAnimation { currentStep -= 1 }
                    // Reset connection test when going back
                    connectionTestResult = .notTested
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(14)
                }
            }
            
            Button(action: {
                if currentStep < totalSteps {
                    // Clean address before moving to test step
                    let detection = ServerConfig.detectProtocol(from: serverAddress)
                    if let proto = detection.protocol {
                        serverProtocol = proto
                    }
                    serverAddress = detection.address
                    
                    withAnimation { currentStep += 1 }
                } else {
                    completeSetup()
                }
            }) {
                HStack {
                    Text(currentStep == totalSteps ? "Finish" : "Next")
                    if currentStep < totalSteps {
                        Image(systemName: "chevron.right")
                    } else {
                        Image(systemName: "checkmark")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canProceed ? appearanceManager.tintColor : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .disabled(!canProceed)
        }
    }
    
    // MARK: - Validation
    
    private var canProceed: Bool {
        switch currentStep {
        case 1:
            return !serverAddress.isEmpty && !serverName.isEmpty
        case 2:
            if case .success = connectionTestResult {
                return true
            }
            return false
        default:
            return true
        }
    }
    
    // MARK: - Actions
    
    private func testConnection() {
        connectionTestResult = .testing
        
        let config = buildConfig()
        guard let url = URL(string: config.baseURL + "/graphql") else {
            connectionTestResult = .failure("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Simple query to test connection
        let testQuery = ["query": "{ systemStatus { status } }"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: testQuery)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    connectionTestResult = .failure("Error: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    connectionTestResult = .failure("No response from server")
                    return
                }
                
                if httpResponse.statusCode == 200 {
                    connectionTestResult = .success
                } else if httpResponse.statusCode == 401 {
                    // Needs API key but server is reachable
                    connectionTestResult = .success
                } else {
                    connectionTestResult = .failure("HTTP Error: \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }
    
    private func buildConfig() -> ServerConfig {
        let parsed = ServerConfig.parseHostAndPort(serverAddress)
        return ServerConfig(
            name: serverName,
            serverAddress: parsed.host,
            port: parsed.port,
            serverProtocol: serverProtocol,
            apiKey: apiKey.isEmpty ? nil : apiKey
        )
    }
    
    private func completeSetup() {
        let config = buildConfig()
        onComplete(config)
        dismiss()
    }
}

#Preview {
    ServerSetupWizardView { config in
        print("Config saved: \(config)")
    }
}
