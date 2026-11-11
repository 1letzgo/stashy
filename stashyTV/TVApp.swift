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
        // English by default (beta); a language picked on iPhone / Mac applies from the next start.
        AppLanguage.applyPreferredLanguages()
        #if canImport(AetherEngine)
        // TLS-Policy und Logging der Playback-Engine einmalig verdrahten.
        AetherPlaybackBootstrap.installOnce()
        #endif

        // Audio-Session beim Start nur deklarieren, nicht aktivieren: der App-Start soll laufendes
        // System-Audio nicht unterbrechen. Aktiviert wird erst, wenn wirklich hörbar abgespielt wird
        // (`AudioSessionCoordinator`, bzw. AVKit/Engine pro Wiedergabe). `setCategory` blockiert;
        // auf dem Main Thread meldet Xcode ein Hang-Risiko.
        Task.detached(priority: .userInitiated) {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            } catch {
                AppLog.error("AVAudioSession setup failed: \(error)")
            }
        }
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            // Die Sperre hat ein eigenes Fenster über allem (`TVLockScreenWindow`): als Overlay
            // in diesem Fenster erschien sie erst beim nächsten SwiftUI-Update — offene Player
            // und Covers lagen bis dahin darüber, und der App-Umschalter zeigte den Inhalt.
            // Kein `fullScreenCover`: tvOS schließt ein Cover bei Menu trotz
            // `interactiveDismissDisabled`. Die App darunter ist `disabled`, offene Covers
            // schließen sich über `dismissOnAppLock` (der Player hört damit auch auf).
            Group {
                if configManager.activeConfig?.hasValidConfig == true {
                    TVMainTabView()
                } else {
                    TVServerSetupView()
                }
            }
            .disabled(securityManager.isAppLocked)
            .onChange(of: securityManager.isAppLocked, initial: true) { _, locked in
                // Kaltstart: `init` sperrt, bevor es eine Szene gibt — hier kommt das Fenster nach.
                TVLockScreenWindow.shared.update(locked: locked)
            }
            // Alle tvOS-Themes sind dunkel (`AppTheme.tvOSThemes`) — ohne das würden
            // `.primary`/`.secondary`-Texte beim hellen Apple-TV-Design unlesbar.
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, newPhase in
                defer { lastScenePhase = newPhase }

                // Nur bei echtem Background sperren. `.inactive` kommt auch für
                // Kontrollzentrum/Mitteilungen – dort nicht nach der PIN fragen.
                // Kaltstart deckt `TVSecurityManager.init` ab.
                if newPhase == .background {
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

    /// Zeigt/entfernt das Sperrfenster sofort, nicht erst beim nächsten SwiftUI-Update.
    @Published var isAppLocked: Bool = false {
        didSet {
            guard isAppLocked != oldValue else { return }
            TVLockScreenWindow.shared.update(locked: isAppLocked)
        }
    }
    private var backgroundObserver: NSObjectProtocol?
    @Published var isPinSet: Bool = false
    @Published var isPinLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPinLockEnabled, forKey: kEnabled)
            // Einschalten sperrt NICHT sofort (sonst schlägt der Lock-Screen über
            // Settings bzw. dem noch offenen PIN-Setup auf) – die Sperre greift beim
            // nächsten Background/Launch.
            if !isPinLockEnabled {
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
        // Synchron beim Wechsel in den Hintergrund sperren: `scenePhase` kommt erst danach,
        // dann hat tvOS das Bild für den App-Umschalter schon mit dem Inhalt aufgenommen.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { TVSecurityManager.shared.lock() }
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
    @FocusState private var focusedDigit: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    Spacer().frame(height: 80)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.primary)

                    Text(tr("enter_pin"))
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
                        guard pin.count < 4 else { return }
                        pin.append(digit)
                        // Direkt prüfen statt per `onChange(of: pin)`: im eigenen Sperrfenster
                        // (Root eines UIHostingController) feuerte das nicht.
                        if pin.count == 4 { check(pin) }
                    },
                    onDelete: {
                        if !pin.isEmpty { pin.removeLast() }
                    },
                    onCancel: nil,
                    isFocused: $focusedDigit
                )
                .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 80)
        }
        .onExitCommand {
            // Menu/Back-Taste darf die PIN-Sperre NICHT umgehen.
            // Fehler-Feedback statt dismiss.
            errorMessage = tr("enter_pin_to_unlock")
            shakeTrigger.toggle()
        }
        .onAppear {
            // Ensure the lock is actually active when shown.
            securityManager.lock()
            focusedDigit = "5"
        }
    }

    private func check(_ entered: String) {
        if securityManager.verify(pin: entered) {
            pin = ""
            securityManager.unlock()
        } else {
            errorMessage = tr("wrong_pin")
            shakeTrigger.toggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                pin = ""
                errorMessage = nil
            }
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
    @FocusState private var focusedDigit: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    Spacer().frame(height: 80)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.primary)

                    Text(step == 1 ? tr("action_set_pin") : tr("confirm_pin"))
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
                    isFocused: $focusedDigit
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
                    errorMessage = tr("pins_do_not_match")
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
            focusedDigit = "5"
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
    var isFocused: FocusState<String?>.Binding

    private let digits = ["1","2","3","4","5","6","7","8","9","0"]

    var body: some View {
        VStack(spacing: 18) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(1..<4, id: \.self) { col in
                        let number = "\(row * 3 + col)"
                        digitButton(number)
                    }
                }
            }
            HStack(spacing: 18) {
                if let onCancel {
                    Button(action: onCancel) {
                        Text(tr("action_cancel"))
                            .font(.title3)
                            .frame(width: 140, height: 80)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Color.clear
                        .frame(width: 140, height: 80)
                        .focusable(false)
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
        .onAppear {
            if isFocused.wrappedValue == nil {
                isFocused.wrappedValue = "5"
            }
        }
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
        .focused(isFocused, equals: digit)
    }
}

// MARK: - Server Setup View (shown when no config exists)

struct TVServerSetupView: View {
    @ObservedObject private var configManager = ServerConfigManager.shared

    @State private var serverName: String = tr("my_stash")
    @State private var serverAddress: String = ""
    @State private var port: String = ""
    @State private var selectedProtocol: ServerProtocol = .https
    @State private var apiKey: String = ""
    /// Custom HTTP headers — a server behind SSO can't be reached without them.
    @State private var customHeaders: [ServerHTTPHeader] = []
    
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

                        Text(tr("action_connect_to_stash"))
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text(tr("hint_enter_your_stash_server_details"))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    // Form
                    VStack(spacing: 24) {
                        TextField(tr("server_name"), text: $serverName)
                            .focused($focusedField, equals: .name)
                            .textContentType(.name)

                        TextField(tr("hint_server_address_e_g_192"), text: $serverAddress)
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
                            TextField(tr("port_optional"), text: $port)
                                .focused($focusedField, equals: .port)
                                .frame(maxWidth: 300)
                            #if swift(>=5.9)
                                .keyboardType(.numberPad)
                            #endif

                            Picker(tr("protocol"), selection: $selectedProtocol) {
                                ForEach(ServerProtocol.allCases, id: \.self) { proto in
                                    Text(proto.displayName).tag(proto)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 300)
                        }

                        // Authentication Section
                        VStack(alignment: .leading, spacing: 24) {
                            Text(tr("authentication"))
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Picker(tr("auth_method"), selection: $authMethod) {
                                ForEach(AuthMethod.allCases, id: \.self) { method in
                                    Text(method.displayName).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            if authMethod == .login {
                                VStack(spacing: 24) {
                                    TextField(tr("username"), text: $username)
                                        .textContentType(.username)
                                        .textInputAutocapitalization(.never)
                                    
                                    SecureField(tr("password"), text: $password)
                                        .textContentType(.password)
                                    
                                    Button {
                                        fetchKeyViaLogin()
                                    } label: {
                                        HStack(spacing: 12) {
                                            if isFetchingKey {
                                                ProgressView()
                                            }
                                            Text(isFetchingKey ? tr("logging_in_menu") : tr("action_fetch_api_key"))
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
                                TextField(tr("api_key"), text: $apiKey)
                                    .focused($focusedField, equals: .apiKey)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(20)

                        TVCustomHeadersCard(headers: $customHeaders)

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
                            Text(isTesting ? "Connecting..." : tr("action_connect"))
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
            name: serverName.isEmpty ? tr("my_stash") : serverName,
            serverAddress: finalAddress,
            port: finalPort,
            serverProtocol: selectedProtocol,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            customHeaders: {
                let usable = ServerHTTPHeader.sanitized(customHeaders)
                return usable.isEmpty ? nil : usable
            }()
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
                    ?? tr("error_reach_arg_check_address_port", config.baseURL)
            }
            return
        }
        if Date() >= deadline {
            isTesting = false
            errorMessage = tr("hint_connection_timed_out_check_address")
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
            serverProtocol: selectedProtocol
        )
        
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

// MARK: - Lock hand-off

extension View {
    /// Schließt eine Präsentation (Player, Bildbetrachter, Sheet), sobald die App
    /// sperrt — sonst läge sie über dem Sperr-Overlay an der Wurzel.
    func dismissOnAppLock(_ dismiss: @escaping () -> Void) -> some View {
        modifier(TVDismissOnAppLock(dismiss: dismiss))
    }
}

/// `onChange` statt `onReceive($isAppLocked)`: der `@Published`-Publisher liefert beim
/// Abonnieren sofort den aktuellen Wert, und `onReceive` abonniert bei jedem Body-Update
/// neu — gesperrt ergab das eine Endlosschleife aus dismiss → Update → dismiss.
private struct TVDismissOnAppLock: ViewModifier {
    @ObservedObject private var security = TVSecurityManager.shared
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: security.isAppLocked) { _, locked in
            if locked { dismiss() }
        }
    }
}


// MARK: - Lock window

/// Die PIN-Sperre in einem eigenen Fenster auf Alert-Ebene: nichts aus dem App-Fenster
/// (Player, Covers, Bildbetrachter) kann darüber liegen, und sie steht im selben Moment,
/// in dem gesperrt wird.
@MainActor
final class TVLockScreenWindow {
    static let shared = TVLockScreenWindow()
    private var windows: [ObjectIdentifier: UIWindow] = [:]

    func update(locked: Bool) {
        if locked {
            show()
            // Beim Kaltstart verbinden sich die Szenen evtl. noch.
            DispatchQueue.main.async { if TVSecurityManager.shared.isAppLocked { self.show() } }
        } else {
            hide()
        }
    }

    private func show() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where windows[ObjectIdentifier(scene)] == nil {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            let host = UIHostingController(rootView: TVPasscodeEntryView().preferredColorScheme(.dark))
            host.view.backgroundColor = .black
            window.rootViewController = host
            window.backgroundColor = .black
            // Key, damit der Fokus (PIN-Feld) hier landet und nicht in der App darunter.
            window.makeKeyAndVisible()
            // Gleich zeichnen, bevor tvOS das Bild für den App-Umschalter nimmt.
            window.layoutIfNeeded()
            windows[ObjectIdentifier(scene)] = window
        }
    }

    private func hide() {
        let leaving = windows
        windows.removeAll()
        for (_, window) in leaving {
            // Fokus zurück ans App-Fenster der Szene.
            window.windowScene?.windows
                .first { $0 !== window && $0.windowLevel == .normal }?
                .makeKey()
            UIView.animate(withDuration: 0.2, animations: {
                window.alpha = 0
            }, completion: { _ in
                window.isHidden = true
                window.rootViewController = nil
            })
        }
    }
}
