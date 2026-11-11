//
//  ServerSetupWizardView.swift
//  stashy
//
//  Step-by-step wizard for first-time server setup
//

#if !os(tvOS) && !os(watchOS)
import SwiftUI

struct ServerSetupWizardView: View {
    /// Re-renders every text when the language is switched in step 1.
    @ObservedObject private var languageStore = AppLanguageStore.shared
    @Environment(\.stashyDismiss) private var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    // Wizard State
    @State private var currentStep = 1
    private let totalSteps = 2  // Reduced from 3
    
    // Form Data
    @State private var serverAddress = ""
    @State private var serverProtocol: ServerProtocol = .https
    @State private var apiKey = ""
    @State private var waitsForICloud = false
    /// Custom HTTP headers (SSO / reverse proxy); a server behind one can't pass the test without them.
    @State private var customHeaders: [ServerHTTPHeader] = []
    @State private var showsCustomHeaders = false
    @State private var serverName = tr("my_stash")
    /// Every language's preset server name ("My Stash", "Mein Stash" …), to tell it from a typed one.
    private static var presetNames: Set<String> {
        Set(AppLanguage.options.compactMap { option in
            Bundle.main.path(forResource: option.code, ofType: "lproj").flatMap(Bundle.init(path:))?
                .localizedString(forKey: "my_stash", value: nil, table: nil)
        })
    }
    
    // Auth State
    @State private var authMethod: AuthMethod = .none
    @State private var username = ""
    @State private var password = ""
    @State private var isFetchingKey = false
    @State private var loginErrorMessage: String? = nil
    
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
                #if os(macOS)
                // No paging TabView on macOS; the buttons below drive the steps anyway.
                Group {
                    if currentStep == 1 {
                        step1ServerDetails
                    } else {
                        step2Test
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut, value: currentStep)
                #else
                TabView(selection: $currentStep) {
                    step1ServerDetails.tag(1)
                    step2Test.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)
                #endif
                
                // Moving from another device: take servers and settings from an export instead.
                if currentStep == 1 {
                    SettingsTransferControls(importOnly: true) {
                        if ServerConfigManager.shared.activeConfig != nil { dismiss() }
                    }
                    .buttonStyle(.borderless)
                    .padding(.bottom, 8)

                    Button {
                        waitsForICloud = true
                        ICloudSettingsSync.shared.enable()
                    } label: {
                        Label(waitsForICloud ? tr("waiting_for_icloud_menu") : tr("action_restore_from_icloud"), systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(waitsForICloud)
                    .buttonStyle(.borderless)
                    .padding(.bottom, 8)
                    .onReceive(ServerConfigManager.shared.$activeConfig) { active in
                        if waitsForICloud, active != nil { dismiss() }
                    }
                }

                // Navigation Buttons
                navigationButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
            .applyAppBackground()
            .stashyModalSheetChrome(tr("server_setup"), onBack: { dismiss() })
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
                    
                    Text(tr("server_details"))
                        .font(.title2.bold())
                    
                    Text(tr("enter_your_stash_server_information"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                
                VStack(spacing: 16) {
                    // App language: stashy follows the device; the switch forces English.
                    if AppLanguage.offersEnglishSwitch {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tr("app_language"))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            AppLanguageSwitch()
                                .padding()
                                .background(Color.secondaryAppBackground)
                                .cornerRadius(DesignTokens.CornerRadius.card)
                        }
                    }

                    // Server Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("server_name"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField(tr("my_stash"), text: $serverName)
                            // The preset name follows a language switch until the user types one.
                            .onChange(of: languageStore.revision) { _, _ in
                                if Self.presetNames.contains(serverName) {
                                    serverName = tr("my_stash")
                                }
                            }
                            .padding()
                            .background(Color.secondaryAppBackground)
                            .cornerRadius(DesignTokens.CornerRadius.card)
                    }
                    
                    // Protocol Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("protocol"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker(tr("protocol"), selection: $serverProtocol) {
                            ForEach(ServerProtocol.allCases, id: \.self) { proto in
                                Text(proto.displayName).tag(proto)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        .background(Color.secondaryAppBackground)
                        .cornerRadius(DesignTokens.CornerRadius.card)
                    }
                    
                    // Server Address
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("server_address"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField(tr("n192_168_1_100_9999_or"), text: $serverAddress)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color.secondaryAppBackground)
                            .cornerRadius(DesignTokens.CornerRadius.card)
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
                        
                        Text(tr("hint_enter_address_e_g_timeout"))
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    
                    // Authentication Section Card
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tr("authentication"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker(tr("auth_method"), selection: $authMethod) {
                                ForEach(AuthMethod.allCases, id: \.self) { method in
                                    Text(method.displayName).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        if authMethod == .login {
                            VStack(spacing: 12) {
                                TextField(tr("username"), text: $username)
                                    .textContentType(.username)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .padding()
                                    .background(Color.appBackground.opacity(0.3))
                                    .cornerRadius(DesignTokens.CornerRadius.button)
                                
                                SecureField(tr("password"), text: $password)
                                    .textContentType(.password)
                                    .padding()
                                    .background(Color.appBackground.opacity(0.3))
                                    .cornerRadius(DesignTokens.CornerRadius.button)
                                
                                Button(action: fetchKeyViaLogin) {
                                    HStack {
                                        if isFetchingKey {
                                            InlineSpinner(scale: .medium)
                                                .padding(.trailing, 4)
                                        }
                                        Text(tr("action_fetch_api_key"))
                                    }
                                }
                                .buttonStyle(PrimaryFilledButtonStyle())
                                .opacity(username.isEmpty || password.isEmpty || isFetchingKey ? 0.45 : 1)
                                .disabled(username.isEmpty || password.isEmpty || isFetchingKey)
                                
                                if let error = loginErrorMessage {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        } else if authMethod == .apiKey {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(tr("api_key"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                SecureField(tr("enter_api_key"), text: $apiKey)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .padding()
                                    .background(Color.appBackground.opacity(0.3))
                                    .cornerRadius(DesignTokens.CornerRadius.button)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondaryAppBackground)
                    .cornerRadius(DesignTokens.CornerRadius.card)

                    customHeadersCard
                }
                .padding(.horizontal, 24)
                
                Spacer(minLength: 32)
            }
        }
    }
    
    /// Collapsed by default — most servers need no extra headers.
    private var customHeadersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation { showsCustomHeaders.toggle() }
            } label: {
                HStack {
                    Text(tr("custom_headers"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !ServerHTTPHeader.sanitized(customHeaders).isEmpty {
                        Text("\(ServerHTTPHeader.sanitized(customHeaders).count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: showsCustomHeaders ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showsCustomHeaders {
                ForEach($customHeaders) { $header in
                    HStack(spacing: 8) {
                        VStack(spacing: 8) {
                            TextField(tr("header_name"), text: $header.name)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.body.monospaced())
                                .padding(10)
                                .background(Color.appBackground.opacity(0.3))
                                .cornerRadius(DesignTokens.CornerRadius.button)
                            SecureField(tr("value"), text: $header.value)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(Color.appBackground.opacity(0.3))
                                .cornerRadius(DesignTokens.CornerRadius.button)
                        }
                        Button {
                            customHeaders.removeAll { $0.id == header.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tr("action_remove_header"))
                    }
                }
                Button {
                    customHeaders.append(ServerHTTPHeader(name: "", value: ""))
                } label: {
                    Label(tr("action_add_header"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundColor(AppearanceManager.shared.tintColor)

                Text(tr("hint_sent_with_every_request_to"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondaryAppBackground)
        .cornerRadius(DesignTokens.CornerRadius.card)
    }

    // MARK: - Step 2: Connection Test
    
    private var step2Test: some View {
        VStack(spacing: 32) {
            Spacer()
            
            switch connectionTestResult {
            case .notTested, .testing:
                VStack(spacing: 16) {
                    if case .testing = connectionTestResult {
                        InlineSpinner(scale: .large)
                            .padding(.bottom, 16)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 60))
                            .foregroundColor(appearanceManager.tintColor)
                    }
                    
                    Text(connectionTestResult == .testing ? tr("loading_connecting") : tr("action_test_connection"))
                        .font(.title2.bold())
                    
                    Text(tr("hint_were_checking_if_your_server"))
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
                    
                    Text(tr("connection_successful"))
                        .font(.title2.bold())
                    
                    Text(tr("your_stash_server_was_found"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
            case .failure(let message):
                VStack(spacing: 16) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.red)
                    
                    Text(tr("error_connection"))
                        .font(.title2.bold())
                    
                    Text(message)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button(tr("action_test_again")) {
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
                        Text(tr("back"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.secondaryAppBackground)
                    .foregroundColor(.primary)
                    .cornerRadius(DesignTokens.CornerRadius.button)
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
                    Text(currentStep == totalSteps ? tr("finish") : tr("next"))
                    if currentStep < totalSteps {
                        Image(systemName: "chevron.right")
                    } else {
                        Image(systemName: "checkmark")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canProceed ? appearanceManager.tintColor : Color.gray.opacity(0.3))
                .foregroundColor(Color.onAppTint)
                .cornerRadius(DesignTokens.CornerRadius.button)
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
            connectionTestResult = .failure(tr("invalid_url"))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = StashConnectionProbe.versionQueryBody.data(using: .utf8)
        
        if (authMethod == .apiKey || authMethod == .login) && !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        }
        for header in ServerHTTPHeader.sanitized(customHeaders) {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            // Only a real Stash version answer is a success — not a reachable host, not a 401.
            let outcome = StashConnectionProbe.evaluate(data: data, response: response, error: error)
            DispatchQueue.main.async {
                switch outcome {
                case .stash: connectionTestResult = .success
                case .failure(let message): connectionTestResult = .failure(message)
                }
            }
        }.resume()
    }
    
    private func buildConfig() -> ServerConfig {
        let parsed = ServerConfig.parseAddress(serverAddress)
        return ServerConfig(
            name: serverName,
            serverAddress: parsed.host,
            port: parsed.port,
            serverProtocol: serverProtocol,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            subpath: parsed.subpath
        )
    }
    
    private func completeSetup() {
        var config = buildConfig()
        // Header values go to the Keychain, never into the UserDefaults config.
        KeychainManager.shared.saveCustomHeaders(ServerHTTPHeader.sanitized(customHeaders), forServerID: config.id)
        config.customHeaders = nil
        onComplete(config)
        dismiss()
    }
    
    private func fetchKeyViaLogin() {
        let config = buildConfig()
        isFetchingKey = true
        loginErrorMessage = nil
        
        Task {
            do {
                let fetchedKey = try await LoginAuthHelper.shared.fetchAPIKey(
                    baseURL: config.baseURL,
                    username: username,
                    password: password,
                    extraHeaders: ServerHTTPHeader.sanitized(customHeaders)
                        .reduce(into: [:]) { $0[$1.name] = $1.value }
                )
                
                await MainActor.run {
                    self.apiKey = fetchedKey
                    self.isFetchingKey = false
                    self.authMethod = .apiKey
                    self.username = ""
                    self.password = ""
                    // Move to the next step immediately after successful login
                    withAnimation { currentStep = 2 }
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

#Preview {
    ServerSetupWizardView { config in
        AppLog.debug("Config saved: \(config)")
    }
}
#endif
