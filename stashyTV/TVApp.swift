//
//  TVApp.swift
//  stashyTV
//
//  Created for stashy tvOS.
//

import SwiftUI
import CryptoKit
import Combine
import AVFoundation

@main
struct TVApp: App {
    @ObservedObject private var configManager = ServerConfigManager.shared
    @StateObject private var securityManager = TVSecurityManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastScenePhase: ScenePhase = .active

    init() {
        // Konfiguriere Audio-Session einmal beim App-Start:
        // - `.playback`: erlaubt Audio, auch wenn der Silent-Switch aktiv ist (irrelevant auf tvOS,
        //   wichtig aber für Audio-Routing/Mixing-Verhalten)
        // - dadurch wird Hintergrund-/System-Audio ordnungsgemäß unterbrochen statt zu konkurrieren.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            print("⚠️ AVAudioSession setup failed: \(error)")
        }
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            Group {
                if configManager.activeConfig?.hasValidConfig == true {
                    TVMainTabView()
                } else {
                    TVServerSetupView()
                }
            }
            .fullScreenCover(isPresented: $securityManager.isAppLocked) {
                TVPasscodeEntryView()
                    .presentationBackground(Color.black)
            }
            .onChange(of: scenePhase) { _, newPhase in
                defer { lastScenePhase = newPhase }

                // Always lock when leaving active, and also lock again when re-entering active
                // (covers cold start + returning from background).
                if newPhase != .active {
                    securityManager.lock()
                } else if lastScenePhase != .active {
                    securityManager.lock()
                }
            }
        }
    }
}

// MARK: - tvOS Security (PIN Lock)

@MainActor
final class TVSecurityManager: ObservableObject {
    static let shared = TVSecurityManager()

    @Published var isAppLocked: Bool = false
    @Published var isPinSet: Bool = false
    @Published var isPinLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPinLockEnabled, forKey: kEnabled)
            if isPinLockEnabled {
                lock()
            } else {
                isAppLocked = false
            }
        }
    }

    private let kEnabled = "tv_pin_lock_enabled"
    private let kSalt = "tv_pin_salt"
    private let kHash = "tv_pin_hash"

    private init() {
        self.isPinLockEnabled = UserDefaults.standard.bool(forKey: kEnabled)
        self.isPinSet = (UserDefaults.standard.string(forKey: kHash) != nil)
        if isPinLockEnabled && isPinSet {
            self.isAppLocked = true
        }
    }

    func lock() {
        if isPinLockEnabled && isPinSet {
            isAppLocked = true
        }
    }

    func unlock() {
        isAppLocked = false
    }

    func setPin(_ pin: String) {
        guard pin.count == 4 else { return }

        let salt: String
        if let existing = UserDefaults.standard.string(forKey: kSalt), !existing.isEmpty {
            salt = existing
        } else {
            salt = UUID().uuidString
            UserDefaults.standard.set(salt, forKey: kSalt)
        }

        let hash = Self.sha256Hex(pin + ":" + salt)
        UserDefaults.standard.set(hash, forKey: kHash)
        isPinSet = true
        isPinLockEnabled = true
        // isAppLocked NICHT hier setzen – die Sperre greift beim nächsten
        // scenePhase-Wechsel (Background/Launch). Setzen hier würde den
        // Lock-Screen über den Settings aufschlagen (Flackern).
    }

    func removePin() {
        UserDefaults.standard.removeObject(forKey: kHash)
        UserDefaults.standard.removeObject(forKey: kSalt)
        isPinSet = false
        isPinLockEnabled = false
        isAppLocked = false
    }

    func verify(pin: String) -> Bool {
        guard pin.count == 4 else { return false }
        guard let salt = UserDefaults.standard.string(forKey: kSalt),
              let savedHash = UserDefaults.standard.string(forKey: kHash) else { return false }
        return Self.sha256Hex(pin + ":" + salt) == savedHash
    }

    private static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct TVPasscodeEntryView: View {
    @ObservedObject private var securityManager = TVSecurityManager.shared

    @State private var pin: String = ""
    @State private var errorMessage: String?
    @State private var shakeTrigger: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    Spacer().frame(height: 80)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.primary)

                    Text("Enter PIN")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.title3)
                    }

                    HStack(spacing: 18) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(index < pin.count ? Color.white : Color.white.opacity(0.25))
                                .frame(width: 14, height: 14)
                        }
                    }
                    .offset(x: shakeTrigger ? 12 : 0)
                    .animation(.default, value: shakeTrigger)
                    .padding(.top, 8)
                }

                Spacer()

                TVPinPad(
                    onDigit: { digit in
                        if pin.count < 4 { pin.append(digit) }
                    },
                    onDelete: {
                        if !pin.isEmpty { pin.removeLast() }
                    },
                    onCancel: nil,
                    isFocused: $isFocused
                )
                .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 80)
        }
        .onChange(of: pin) { _, newValue in
            guard newValue.count == 4 else { return }
            if securityManager.verify(pin: newValue) {
                securityManager.unlock()
            } else {
                errorMessage = "Wrong PIN"
                shakeTrigger.toggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    pin = ""
                    errorMessage = nil
                }
            }
        }
        .onExitCommand {
            // Menu/Back-Taste darf die PIN-Sperre NICHT umgehen.
            // Fehler-Feedback statt dismiss.
            errorMessage = "Enter PIN to unlock"
            shakeTrigger.toggle()
        }
        .onAppear {
            // Ensure the lock is actually active when shown.
            securityManager.lock()
            isFocused = true
        }
    }
}

struct TVPasscodeSetupView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var securityManager = TVSecurityManager.shared

    @State private var step: Int = 1 // 1 set, 2 confirm
    @State private var pin: String = ""
    @State private var confirm: String = ""
    @State private var errorMessage: String?
    @State private var shakeTrigger: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    Spacer().frame(height: 80)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.primary)

                    Text(step == 1 ? "Set PIN" : "Confirm PIN")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.title3)
                    }

                    HStack(spacing: 18) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(index < (step == 1 ? pin.count : confirm.count) ? Color.white : Color.white.opacity(0.25))
                                .frame(width: 14, height: 14)
                        }
                    }
                    .offset(x: shakeTrigger ? 12 : 0)
                    .animation(.default, value: shakeTrigger)
                    .padding(.top, 8)
                }

                Spacer()

                TVPinPad(
                    onDigit: { digit in
                        if step == 1 {
                            if pin.count < 4 { pin.append(digit) }
                        } else {
                            if confirm.count < 4 { confirm.append(digit) }
                        }
                    },
                    onDelete: {
                        if step == 1 {
                            if !pin.isEmpty { pin.removeLast() }
                        } else {
                            if !confirm.isEmpty { confirm.removeLast() }
                        }
                    },
                    onCancel: { isPresented = false },
                    isFocused: $isFocused
                )

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 80)
        }
        .onChange(of: pin) { _, v in
            if step == 1 && v.count == 4 {
                step = 2
            }
        }
        .onChange(of: confirm) { _, v in
            if step == 2 && v.count == 4 {
                if pin == confirm {
                    securityManager.setPin(pin)
                    isPresented = false
                } else {
                    errorMessage = "PINs do not match"
                    shakeTrigger.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        pin = ""
                        confirm = ""
                        step = 1
                        errorMessage = nil
                    }
                }
            }
        }
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            // Setup kann jederzeit über Menu/Back abgebrochen werden.
            isPresented = false
        }
    }
}

private struct TVPinPad: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    let onCancel: (() -> Void)?
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 18) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(1..<4, id: \.self) { col in
                        let number = row * 3 + col
                        digitButton("\(number)")
                    }
                }
            }
            HStack(spacing: 18) {
                if let onCancel {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.title3)
                            .frame(width: 140, height: 80)
                    }
                    .buttonStyle(.bordered)
                } else {
                    // Left spacer (invisible but keeps grid)
                    Button(action: {}) {
                        Text("")
                            .frame(width: 140, height: 80)
                    }
                    .buttonStyle(.bordered)
                    .hidden()
                }

                digitButton("0")

                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.title2)
                        .frame(width: 140, height: 80)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: 600)
    }

    private func digitButton(_ digit: String) -> some View {
        Button {
            onDigit(digit)
        } label: {
            Text(digit)
                .font(.title)
                .frame(width: 140, height: 80)
        }
        .buttonStyle(.borderedProminent)
        .focused(isFocused)
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
    
    // Auth State
    @State private var authMethod: AuthMethod = .none
    @State private var username = ""
    @State private var password = ""
    @State private var isFetchingKey = false
    @State private var loginErrorMessage: String? = nil
    
    @State private var errorMessage: String?
    @State private var isTesting: Bool = false

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case name, address, port, apiKey
    }

    var body: some View {
        NavigationStack {
            ScrollView {
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
                    .padding(.bottom, 60)
                }
                .padding(.horizontal, 60)
            }
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
            apiKey: apiKey.isEmpty ? nil : apiKey,
            defaultQuality: .original,
            reelsQuality: .original
        )

        isTesting = true
        errorMessage = nil

        // Erst Verbindung testen, dann erst speichern/aktivieren.
        let testVM = StashDBViewModel()
        testVM.testConnection(with: config)

        // testConnection läuft asynchron (Combine). Pollen bis fertig, max 15s.
        checkTestResult(testVM: testVM, config: config, deadline: Date().addingTimeInterval(15))
    }

    private func checkTestResult(testVM: StashDBViewModel, config: ServerConfig, deadline: Date) {
        if !testVM.isLoading {
            isTesting = false
            if testVM.isServerConnected {
                configManager.addOrUpdateServer(config)
                configManager.saveConfig(config)
            } else {
                errorMessage = testVM.errorMessage
                    ?? "Could not reach \(config.baseURL). Check address, port and protocol."
            }
            return
        }
        if Date() >= deadline {
            isTesting = false
            errorMessage = "Connection timed out. Check address, port and protocol."
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.checkTestResult(testVM: testVM, config: config, deadline: deadline)
        }
    }
    
    private func fetchKeyViaLogin() {
        let parsed = ServerConfig.parseHostAndPort(serverAddress)
        let finalAddress = parsed.host
        let finalPort = !port.isEmpty ? port : parsed.port
        
        let config = ServerConfig(
            name: serverName,
            serverAddress: finalAddress,
            port: finalPort,
            serverProtocol: selectedProtocol,
            defaultQuality: .original,
            reelsQuality: .original
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
                    // Auth-Method nicht wechseln – User bleibt im Login-Flow.
                    // Username/Password behalten für eventuelle Retry.
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
