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
    @State private var name: String = tr("my_stash")
    @State private var serverAddress: String = ""
    @State private var serverProtocol: ServerProtocol = .https
    /// Optional second address of the same server, used while it answers (home network).
    @State private var localAddress: String = ""
    @State private var isTestingLocal = false
    @State private var localTestResult: ConnectionTestResult = .none
    @State private var localTestMessage: String = ""
    @State private var apiKey: String = ""
    /// Custom HTTP headers (SSO / reverse proxy). Kept in the Keychain on save.
    @State private var customHeaders: [ServerHTTPHeader] = []
    @State private var originalCustomHeaders: [ServerHTTPHeader] = []
    /// API key as loaded (trimmed, empty = none), to detect an edit after the Keychain is overwritten.
    @State private var originalApiKey: String = ""
    
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
            return tr("empty_authentication_will_be_used")
        case .login:
            return tr("hint_login_with_your_stash_credentials")
        case .apiKey:
            return tr("hint_enter_your_stash_api_key")
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
                stashyScrollingSectionHeader(tr("server_details"))
                TextField(tr("server_name"), text: $name)
                    .textContentType(.organizationName)
                    .stashyGroupedBlockRow(index: 0, count: 3)

                Picker(tr("protocol"), selection: $serverProtocol) {
                    ForEach(ServerProtocol.allCases, id: \.self) { proto in
                        Text(proto.displayName).tag(proto)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: serverProtocol) { _, _ in resetTestState() }
                .stashyGroupedBlockRow(index: 1, count: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("server_address"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(tr("n192_168_1_100_9999"), text: $serverAddress)
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
                stashyScrollingSectionHeader(tr("local_address"))
                TextField("192.168.1.100:9999", text: $localAddress)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .onChange(of: localAddress) { _, _ in
                        localTestResult = .none
                        localTestMessage = ""
                    }
                    .stashyGroupedBlockRow(index: 0, count: localURL == nil ? 1 : 2)
                if localURL != nil {
                    Button(action: { testConnection(local: true) }) {
                        HStack {
                            if isTestingLocal {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Image(systemName: icon(for: localTestResult))
                                    .foregroundColor(color(for: localTestResult))
                            }
                            Text(isTestingLocal ? tr("loading_testing") : tr("action_test_local_address"))
                                .foregroundColor(.primary)
                            Spacer()
                            if !localTestMessage.isEmpty {
                                Text(localTestMessage)
                                    .font(.caption)
                                    .foregroundColor(localTestResult == .success ? .green : .secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .disabled(isTestingLocal)
                    .stashyGroupedBlockRow(index: 1, count: 2)
                }
                stashyScrollingSectionFooter(tr("hint_optional_used_instead_of_address"))
            }

            Section {
                stashyScrollingSectionHeader(tr("authentication"))
                Picker(tr("auth_method"), selection: $authMethod) {
                    ForEach(AuthMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
                .stashyGroupedBlockRow(index: 0, count: authCount)

                if authMethod == .login {
                    TextField(tr("username"), text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .stashyGroupedBlockRow(index: 1, count: authCount)

                    SecureField(tr("password"), text: $password)
                        .textContentType(.password)
                        .stashyGroupedBlockRow(index: 2, count: authCount)

                    Button(action: fetchKeyViaLogin) {
                        HStack {
                            if isFetchingKey {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.trailing, 4)
                            }
                            Text(tr("action_fetch_api_key"))
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(username.isEmpty || password.isEmpty || isFetchingKey ? Color.gray.opacity(0.3) : appearanceManager.tintColor)
                        .foregroundColor(Color.onAppTint)
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
                        SecureField(tr("api_key"), text: $apiKey)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)
                    .stashyGroupedBlockRow(index: 1, count: authCount)
                }

                stashyScrollingSectionFooter(authFooterText)
            }

            Section {
                stashyScrollingSectionHeader(tr("custom_headers"))
                ServerCustomHeadersEditor(headers: $customHeaders)
            }

            Section {
                stashyScrollingSectionHeader(tr("connection"))
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

                        Text(isTesting ? tr("loading_testing") : tr("action_test_connection"))
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
                            Label(tr("action_delete_server"), systemImage: "trash")
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
        .stashyModalSheetChrome(configToEdit == nil ? tr("action_add_server") : tr("action_edit_server"), onBack: {
            presentationMode.wrappedValue.dismiss()
        }) {
            StashyChromeTrailingTextButton(title: tr("action_save"), enabled: isConfigValid) {
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
                localAddress = config.localBaseURL ?? ""
                customHeaders = config.secureCustomHeaders
                originalCustomHeaders = customHeaders
                
                // Load API key from Keychain first, fallback to config
                if let savedKey = KeychainManager.shared.loadAPIKey(forServerID: config.id) {
                    apiKey = savedKey
                    originalApiKey = savedKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    authMethod = .apiKey
                } else if let configKey = config.apiKey, !configKey.isEmpty {
                    apiKey = configKey
                    originalApiKey = configKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    authMethod = .apiKey
                } else {
                    authMethod = .none
                }
            }
        }
        .alert(tr("action_delete_server"), isPresented: $showingDeleteAlert) {
            Button(tr("action_cancel"), role: .cancel) { }
            Button(tr("action_delete"), role: .destructive) {
                if let config = configToEdit {
                    KeychainManager.shared.deleteAPIKey(forServerID: config.id)
                    KeychainManager.shared.deleteCustomHeaders(forServerID: config.id)
                }
                onDelete?()
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text(tr("hint_are_you_sure_you_want_to"))
        }
    }
    
    private var testResultIcon: String { icon(for: testResult) }

    private var testResultColor: Color { color(for: testResult) }

    private func icon(for result: ConnectionTestResult) -> String {
        switch result {
        case .none: return "network"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    private func color(for result: ConnectionTestResult) -> Color {
        switch result {
        case .none: return .secondary
        case .success: return .green
        case .failure: return .red
        }
    }

    /// The local address as stored, nil while the field is empty or unusable.
    private var localURL: String? { ServerConfig.normalizedLocalURL(localAddress) }
    
    private func resetTestState() {
        testResult = .none
        testMessage = ""
    }
    
    private func testConnection(local: Bool = false) {
        func finish(_ result: ConnectionTestResult, _ message: String) {
            if local {
                isTestingLocal = false
                localTestResult = result
                localTestMessage = message
            } else {
                isTesting = false
                testResult = result
                testMessage = message
            }
        }
        if local { isTestingLocal = true } else { isTesting = true }
        finish(.none, "")
        if local { isTestingLocal = true } else { isTesting = true }

        guard let url = URL(string: "\(local ? (localURL ?? "") : currentBaseURL)/graphql"), url.host != nil else {
            finish(.failure, tr("invalid_url"))
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
        
        request.httpBody = StashConnectionProbe.versionQueryBody.data(using: .utf8)
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.timeoutIntervalForResource = 20
        // The local address may present a self-signed certificate, as in every other request.
        let sessionForTest = URLSession(configuration: sessionConfig, delegate: local ? StashTrustDelegate() : nil, delegateQueue: nil)
        
        sessionForTest.dataTask(with: request) { data, response, error in
            let outcome = StashConnectionProbe.evaluate(data: data, response: response, error: error)
            DispatchQueue.main.async {
                switch outcome {
                case .stash(let version): finish(.success, version)
                case .failure(let message): finish(.failure, message)
                }
            }
        }.resume()
    }
    
    private func saveServer() {
        let serverID = configToEdit?.id ?? UUID()
        
        // Save API key to Keychain
        let newApiKey = (authMethod == .apiKey || authMethod == .login)
            ? apiKey.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let apiKeyChanged = newApiKey != originalApiKey
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
            subpath: parsed.subpath,
            localURL: localURL
        )
        onSave(newConfig)

        // The manager compares Keychain reads of the same server, so a header or API key edit
        // on the active server is invisible to it — reset explicitly so nothing keeps the old auth.
        if headersChanged || apiKeyChanged, ServerConfigManager.shared.activeConfig?.id == serverID {
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
                    TextField(tr("header_name"), text: binding(for: header.id, \.name))
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
                    .accessibilityLabel(tr("action_remove_header"))
                }
                SecureField(tr("value"), text: binding(for: header.id, \.value))
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
            Label(tr("action_add_header"), systemImage: "plus.circle.fill")
                .foregroundColor(appearanceManager.tintColor)
        }
        .buttonStyle(.borderless)
        .stashyGroupedBlockRow(index: headers.count, count: rowCount)

        stashyScrollingSectionFooter(tr("hint_sent_with_every_request_to_this_server"))
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
        if name.isEmpty { return tr("enter_header_name") }
        if ServerHTTPHeader.reservedNames.contains(name.lowercased()) { return tr("hint_arg_is_managed_by_app", name) }
        if header.trimmedValue.isEmpty { return tr("enter_value") }
        if !header.isUsable { return tr("hint_header_names_may_only_contain") }
        return nil
    }
}

#Preview {
    NavigationView {
        ServerFormViewNew(configToEdit: nil, onSave: { _ in })
    }
}
#endif
