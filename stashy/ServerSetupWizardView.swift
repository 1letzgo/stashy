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
    private let totalSteps = 3
    
    // Form Data
    @State private var connectionType: ConnectionType = .ipAddress
    @State private var ipAddress = ""
    @State private var port = "9999"
    @State private var domain = ""
    @State private var useHTTPS = true
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
                    step1ConnectionType.tag(1)
                    step2AddressAndKey.tag(2)
                    step3Test.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)
                
                // Navigation Buttons
                navigationButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
            .navigationTitle("Server-Einrichtung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
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
    
    // MARK: - Step 1: Connection Type
    
    private var step1ConnectionType: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 60))
                    .foregroundColor(appearanceManager.tintColor)
                
                Text("Wie verbindest du dich?")
                    .font(.title2.bold())
                
                Text("Wähle wie du auf deinen Stash-Server zugreifst")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                connectionTypeButton(
                    type: .ipAddress,
                    icon: "number",
                    title: "IP-Adresse",
                    description: "Lokales Netzwerk (z.B. 192.168.1.100)"
                )
                
                connectionTypeButton(
                    type: .domain,
                    icon: "globe",
                    title: "Domain",
                    description: "Externe Adresse (z.B. stash.example.com)"
                )
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
    
    private func connectionTypeButton(type: ConnectionType, icon: String, title: String, description: String) -> some View {
        Button(action: {
            connectionType = type
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(connectionType == type ? appearanceManager.tintColor : Color.gray.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(connectionType == type ? .white : .primary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if connectionType == type {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(appearanceManager.tintColor)
                        .font(.title2)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(connectionType == type ? appearanceManager.tintColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Step 2: Address & API Key
    
    private var step2AddressAndKey: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: connectionType == .ipAddress ? "number" : "globe")
                        .font(.system(size: 50))
                        .foregroundColor(appearanceManager.tintColor)
                    
                    Text("Server-Details")
                        .font(.title2.bold())
                }
                .padding(.top, 32)
                
                VStack(spacing: 16) {
                    // Server Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server-Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("My Stash", text: $serverName)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                    }
                    
                    if connectionType == .ipAddress {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("IP-Adresse")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("192.168.1.100", text: $ipAddress)
                                .keyboardType(.numbersAndPunctuation)
                                .autocapitalization(.none)
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Port")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("9999", text: $port)
                                .keyboardType(.numberPad)
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Domain")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("stash.example.com", text: $domain)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                        }
                        
                        Toggle(isOn: $useHTTPS) {
                            HStack {
                                Image(systemName: "lock.shield")
                                Text("HTTPS verwenden")
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
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
                        
                        SecureField("Falls Server geschützt", text: $apiKey)
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
    
    // MARK: - Step 3: Connection Test
    
    private var step3Test: some View {
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
                    
                    Text(connectionTestResult == .testing ? "Verbinde..." : "Verbindung testen")
                        .font(.title2.bold())
                    
                    Text("Wir prüfen ob dein Server erreichbar ist")
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
                    
                    Text("Verbindung erfolgreich!")
                        .font(.title2.bold())
                    
                    Text("Dein Stash-Server wurde gefunden")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
            case .failure(let message):
                VStack(spacing: 16) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.red)
                    
                    Text("Verbindung fehlgeschlagen")
                        .font(.title2.bold())
                    
                    Text(message)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button("Erneut testen") {
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
                    if currentStep == 2 {
                        connectionTestResult = .notTested
                    }
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Zurück")
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
                    withAnimation { currentStep += 1 }
                } else {
                    completeSetup()
                }
            }) {
                HStack {
                    Text(currentStep == totalSteps ? "Fertig" : "Weiter")
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
            return true
        case 2:
            if connectionType == .ipAddress {
                return !ipAddress.isEmpty && !port.isEmpty && !serverName.isEmpty
            } else {
                return !domain.isEmpty && !serverName.isEmpty
            }
        case 3:
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
            connectionTestResult = .failure("Ungültige URL")
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
                    connectionTestResult = .failure("Fehler: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    connectionTestResult = .failure("Keine Antwort vom Server")
                    return
                }
                
                if httpResponse.statusCode == 200 {
                    connectionTestResult = .success
                } else if httpResponse.statusCode == 401 {
                    // Needs API key but server is reachable
                    connectionTestResult = .success
                } else {
                    connectionTestResult = .failure("HTTP Fehler: \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }
    
    private func buildConfig() -> ServerConfig {
        ServerConfig(
            name: serverName,
            connectionType: connectionType,
            ipAddress: ipAddress,
            port: port,
            domain: domain,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            useHTTPS: useHTTPS
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
