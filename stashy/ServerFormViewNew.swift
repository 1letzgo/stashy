//
//  ServerFormViewNew.swift
//  stashy
//
//  Improved server form with live connection testing
//

#if !os(tvOS) && !os(watchOS)
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
    /// Custom HTTP headers (SSO / reverse proxy). Kept in the Keychain on save.
    @State private var customHeaders: [ServerHTTPHeader] = []
    @State private var originalCustomHeaders: [ServerHTTPHeader] = []
    
    // Connection Test State
    @State private var isTesting: Bool = false
    @State private var testResult: ConnectionTestResult = .none
    @State private var testMessage: String = ""
    
    // Login State
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoginFlowVisible: Bool = false
    @State private var isFetchingKey: Bool = false
    @State private var loginErrorMessage: String? = nil
    
    let configToEdit: ServerConfig?
    let onSave: (ServerConfig) -> Void
    let onDelete: (() -> Void)?
    
    @State private var showingDeleteAlert = false
    
    enum ConnectionTestResult {
        case none
        case success
        case failure
    }
    
    @State private var authMethod: AuthMethod = .none
    
    init(configToEdit: ServerConfig?, onSave: @escaping (ServerConfig) -> Void, onDelete: (() -> Void)? = nil) {
        self.configToEdit = configToEdit
        self.onSave = onSave
        self.onDelete = onDelete
    }
    
    var isConfigValid: Bool {
        return !name.isEmpty && !serverAddress.isEmpty
    }

    private var authFooterText: String {
        switch authMethod {
        case .none:
            return "No authentication will be used."
        case .login:
            return "Login with your Stash credentials to retrieve the API key."
        case .apiKey:
            return "Enter your Stash API key directly."
        }
    }
    
    var currentBaseURL: String {
        let parsed = ServerConfig.parseAddress(serverAddress)
        let effectivePort = parsed.port ?? serverProtocol.defaultPort
        let scheme = serverProtocol == .https ? "https" : "http"
        
        let needsPort = (serverProtocol == .https && effectivePort != "443") || 
                       (serverProtocol == .http && effectivePort != "80")
        
        let url: String
        if needsPort {
            url = "\(scheme)://\(parsed.host):\(effectivePort)"
        } else {
            url = "\(scheme)://\(parsed.host)"
        }
        
        if let subpath = parsed.subpath, !subpath.isEmpty {
            let cleanSub = subpath.hasPrefix("/") ? subpath : "/\(subpath)"
            return url + cleanSub
        }
        
        return url
    }
    
    var body: some View {
        let authCount: Int = {
            switch authMethod {
            case .none: return 1
            case .login: return loginErrorMessage == nil ? 4 : 5
            case .apiKey: return 2
            }
        }()
        let connectionCount = (testResult == .failure && !testMessage.isEmpty) ? 2 : 1

        List {
            Section {
                stashyScrollingSectionHeader("Server Details")
                TextField("Server Name", text: $name)
                    .textContentType(.organizationName)
                    .stashyGroupedBlockRow(index: 0, count: 3)

                Picker("Protocol", selection: $serverProtocol) {
                    ForEach(ServerProtocol.allCases, id: \.self) { proto in
                        Text(proto.displayName).tag(proto)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: serverProtocol) { _, _ in resetTestState() }
                .stashyGroupedBlockRow(index: 1, count: 3)

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
                .stashyGroupedBlockRow(index: 2, count: 3)
            }

            Section {
                stashyScrollingSectionHeader("Authentication")
                Picker("Auth Method", selection: $authMethod) {
                    ForEach(AuthMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
                .stashyGroupedBlockRow(index: 0, count: authCount)

                if authMethod == .login {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .stashyGroupedBlockRow(index: 1, count: authCount)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .stashyGroupedBlockRow(index: 2, count: authCount)

                    Button(action: fetchKeyViaLogin) {
                        HStack {
                            if isFetchingKey {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.trailing, 4)
                            }
                            Text("Fetch API Key")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(username.isEmpty || password.isEmpty || isFetchingKey ? Color.gray.opacity(0.3) : appearanceManager.tintColor)
                        .foregroundColor(.white)
                        .cornerRadius(DesignTokens.CornerRadius.button)
                    }
                    .disabled(username.isEmpty || password.isEmpty || isFetchingKey)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .stashyGroupedBlockRow(index: 3, count: authCount)

                    if let error = loginErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .stashyGroupedBlockRow(index: 4, count: authCount)
                    }
                } else if authMethod == .apiKey {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.secondary)
                        SecureField("API Key", text: $apiKey)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)
                    .stashyGroupedBlockRow(index: 1, count: authCount)
                }

                stashyScrollingSectionFooter(authFooterText)
            }

            Section {
                stashyScrollingSectionHeader("Custom Headers")
                ServerCustomHeadersEditor(headers: $customHeaders)
            }

            Section {
                stashyScrollingSectionHeader("Connection")
                Button(action: {
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
                .stashyGroupedBlockRow(index: 0, count: connectionCount)

                if testResult == .failure && !testMessage.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(testMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .stashyGroupedBlockRow(index: 1, count: connectionCount)
                }

                if isConfigValid {
                    stashyScrollingSectionFooter("URL: \(currentBaseURL)")
                }
            }

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
                    .stashyGroupedSettingsRow()
                }
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashyModalSheetChrome(configToEdit == nil ? "Add Server" : "Edit Server", onBack: {
            presentationMode.wrappedValue.dismiss()
        }) {
            StashyChromeTrailingTextButton(title: "Save", enabled: isConfigValid) {
                // Clean address before saving
                let detection = ServerConfig.detectProtocol(from: serverAddress)
                if let proto = detection.protocol {
                    serverProtocol = proto
                }
                serverAddress = detection.address

                saveServer()
                presentationMode.wrappedValue.dismiss()
            }
        }
        .onAppear {
            if let config = configToEdit {
                name = config.name
                
                var address = config.serverAddress
                if let port = config.port {
                    address += ":\(port)"
                }
                if let subpath = config.subpath, !subpath.isEmpty {
                    address += subpath.hasPrefix("/") ? subpath : "/\(subpath)"
                }
                serverAddress = address
                
                serverProtocol = config.serverProtocol
                customHeaders = config.secureCustomHeaders
                originalCustomHeaders = customHeaders
                
                // Load API key from Keychain first, fallback to config
                if let savedKey = KeychainManager.shared.loadAPIKey(forServerID: config.id) {
                    apiKey = savedKey
                    authMethod = .apiKey
                } else if let configKey = config.apiKey, !configKey.isEmpty {
                    apiKey = configKey
                    authMethod = .apiKey
                } else {
                    authMethod = .none
                }
            }
        }
        .alert("Delete Server", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let config = configToEdit {
                    KeychainManager.shared.deleteAPIKey(forServerID: config.id)
                    KeychainManager.shared.deleteCustomHeaders(forServerID: config.id)
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
        
                if authMethod == .apiKey || authMethod == .login {
                    if !apiKey.isEmpty {
                        request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
                    }
                }
        // The proxy in front of Stash sees the test request too.
        for header in ServerHTTPHeader.sanitized(customHeaders) {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        
        let query = """
        {"query": "{ version { version } }"}
        """
        request.httpBody = query.data(using: .utf8)
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.timeoutIntervalForResource = 20
        let sessionForTest = URLSession(configuration: sessionConfig)
        
        sessionForTest.dataTask(with: request) { data, response, error in
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
                    testMessage = "Authentication failed"
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
        if authMethod == .apiKey || authMethod == .login {
            if !apiKey.isEmpty {
                _ = KeychainManager.shared.saveAPIKey(apiKey, forServerID: serverID)
            } else {
                KeychainManager.shared.deleteAPIKey(forServerID: serverID)
            }
        } else {
            // None selected, clear everything
            KeychainManager.shared.deleteAPIKey(forServerID: serverID)
        }
        
        let headers = ServerHTTPHeader.sanitized(customHeaders)
        KeychainManager.shared.saveCustomHeaders(headers, forServerID: serverID)
        let headersChanged = headers.map { [$0.name, $0.value] } != originalCustomHeaders.map { [$0.name, $0.value] }

        let parsed = ServerConfig.parseAddress(serverAddress)
        let newConfig = ServerConfig(
            id: serverID,
            name: name,
            serverAddress: parsed.host,
            port: parsed.port,
            serverProtocol: serverProtocol,
            apiKey: nil, // API key now stored in Keychain
            subpath: parsed.subpath
        )
        onSave(newConfig)

        // The manager compares Keychain reads of the same server, so a header edit on the
        // active server is invisible to it — reset explicitly so nothing keeps the old auth.
        if headersChanged, ServerConfigManager.shared.activeConfig?.id == serverID {
            URLCache.shared.removeAllCachedResponses()
            NotificationCenter.default.post(name: NSNotification.Name("ServerConfigChanged"), object: nil)
        }
    }
    
    private func fetchKeyViaLogin() {
        guard isConfigValid else { return }
        
        isFetchingKey = true
        loginErrorMessage = nil
        
        Task {
            do {
                let fetchedKey = try await LoginAuthHelper.shared.fetchAPIKey(
                    baseURL: currentBaseURL,
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
                    // Automatically test connection with the new key
                    self.testConnection()
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

// MARK: - Custom headers editor

/// Name/value rows for the server's custom HTTP headers. Shared by the server form and the
/// setup wizard. Values are secure fields — they are usually tokens.
struct ServerCustomHeadersEditor: View {
    @Binding var headers: [ServerHTTPHeader]
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    private var rowCount: Int { headers.count + 1 }

    var body: some View {
        ForEach(Array(headers.enumerated()), id: \.element.id) { index, header in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    TextField("Header name", text: binding(for: header.id, \.name))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button {
                        headers.removeAll { $0.id == header.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove header")
                }
                SecureField("Value", text: binding(for: header.id, \.value))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let problem = problem(for: header) {
                    Text(problem)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.vertical, 4)
            .stashyGroupedBlockRow(index: index, count: rowCount)
        }

        Button {
            headers.append(ServerHTTPHeader(name: "", value: ""))
        } label: {
            Label("Add Header", systemImage: "plus.circle.fill")
                .foregroundColor(appearanceManager.tintColor)
        }
        .buttonStyle(.borderless)
        .stashyGroupedBlockRow(index: headers.count, count: rowCount)

        stashyScrollingSectionFooter("Sent with every request to this server, e.g. for SSO or a reverse proxy that needs its own token. Stored in the Keychain.")
    }

    private func binding(for id: UUID, _ keyPath: WritableKeyPath<ServerHTTPHeader, String>) -> Binding<String> {
        Binding(
            get: { headers.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard let index = headers.firstIndex(where: { $0.id == id }) else { return }
                headers[index][keyPath: keyPath] = newValue
            }
        )
    }

    /// Only for rows the user has started filling in; empty rows are just ignored on save.
    private func problem(for header: ServerHTTPHeader) -> String? {
        let name = header.trimmedName
        guard !name.isEmpty || !header.trimmedValue.isEmpty else { return nil }
        if name.isEmpty { return "Enter a header name." }
        if ServerHTTPHeader.reservedNames.contains(name.lowercased()) { return "\(name) is managed by the app and can't be set." }
        if header.trimmedValue.isEmpty { return "Enter a value." }
        if !header.isUsable { return "Header names may only contain letters, digits and - _ . ! # $ % & ' * + ^ ` | ~" }
        return nil
    }
}

#Preview {
    NavigationView {
        ServerFormViewNew(configToEdit: nil, onSave: { _ in })
    }
}
#endif
