//
//  SettingsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI
import StoreKit

struct SettingsView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator

    // UI State
    @State private var isScanningLibrary: Bool = false
    @State private var showScanAlert: Bool = false
    @State private var scanAlertMessage: String = ""
    @State private var showingAddServerSheet = false
    @State private var editingServer: ServerConfig?
    @State private var selectedSection: SettingsSection = .main
    
    // IAP
    @StateObject private var storeManager = StoreManager()

    enum SettingsSection: String, CaseIterable, Identifiable {
        case main = "Main"
        case actions = "Actions"
        case design = "Design"
        case devices = "StashSync"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .main: return "gearshape.fill"
            case .actions: return "server.rack"
            case .design: return "paintbrush.fill"
            case .devices: return "bolt.horizontal.fill"
            }
        }
    }

    var body: some View {
        Group {
            if selectedSection == .actions {
                ToolsServerView(embedded: true)
            } else {
                Form {
                    switch selectedSection {
                    case .main:
                        mainSettings
                    case .design:
                        designSettings
                    case .devices:
                        devicesSettings
                    case .actions:
                        EmptyView()
                    }
                }
            }
        }
        .applyAppBackground()
        .navigationBarHidden(true)
        .popNavigationToRootOnChange(selectedSection.rawValue)
        .stashyCustomChromeInset(spacing: 0) {
            StashySectionChromeBar {
                SettingsCategoryRow(selection: $selectedSection)
                    .padding(.horizontal, StashyExpandingDock.edgePadding)
                    .padding(.vertical, 6)
            }
        }
        .sheet(isPresented: $showingAddServerSheet) {
            NavigationView {
                ServerFormViewNew(configToEdit: nil) { newConfig in
                    configManager.addOrUpdateServer(newConfig)
                    if configManager.activeConfig == nil {
                        configManager.saveConfig(newConfig)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingServer) { server in
            NavigationView {
                ServerFormViewNew(configToEdit: server, onSave: { updatedConfig in
                    configManager.addOrUpdateServer(updatedConfig)
                    if configManager.activeConfig?.id == updatedConfig.id {
                        configManager.saveConfig(updatedConfig)
                    }
                    editingServer = nil
                }, onDelete: {
                    configManager.deleteServer(id: server.id)
                    editingServer = nil
                })
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            if configManager.activeConfig != nil {
                viewModel.testConnection()
            }
        }
        .alert("Library Scan", isPresented: $showScanAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(scanAlertMessage)
        }
    }

    // MARK: - Section Content

    @ViewBuilder
    private var mainSettings: some View {
        // 1. Main: Beta Hinweis, Server, Tipp, Link
        if isTestFlightBuild() {
            Section {
                appStoreBanner
            }
        }

        ServerListSection(
            viewModel: viewModel,
            isScanningLibrary: $isScanningLibrary,
            showingAddServerSheet: $showingAddServerSheet,
            editingServer: $editingServer,
            onScan: { startLibraryScan() }
        )

        if configManager.activeConfig != nil {
            PlaybackSettingsSection()
        }

        tipSection
        aboutSection
    }

    @ViewBuilder
    private var designSettings: some View {
        // Design: Appearance, Security, Content & Tabs, Default Settings
        Section(header: Text("Appearance")) {
            NavigationLink(destination: AppearanceSettingsView()) {
                Label("Appearance", systemImage: "paintbrush")
            }
            NavigationLink(destination: EditModeSettingsView()) {
                Label("Editing", systemImage: "pencil.circle")
            }
        }
        .listRowBackground(Color.secondaryAppBackground)

        Section(header: Text("Security")) {
            NavigationLink(destination: SecuritySettingsView()) {
                Label("Security", systemImage: "lock.shield")
            }
        }
        .listRowBackground(Color.secondaryAppBackground)

        if configManager.activeConfig != nil {
            ContentSettingsSection()

            Section("Default Settings") {
                NavigationLink(destination: DefaultSortView()) {
                    Label("Sorting", systemImage: "arrow.up.arrow.down")
                }

                NavigationLink(destination: DefaultFilterView()) {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
        } else {
            Section {
                Text("Content & default settings require an active server.")
                    .foregroundColor(.secondary)
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
    }

    @ViewBuilder
    private var devicesSettings: some View {
        Section(header: Text("StashySync")) {
            NavigationLink(destination: StashSyncSettingsView()) {
                Label("StashSync", systemImage: "bolt.fill")
            }
        }
        .listRowBackground(Color.secondaryAppBackground)

        interactiveDevicesSection
    }

    // MARK: - App Store Banner

    @Environment(\.openURL) private var openURL

    private var appStoreBanner: some View {
        Button {
            if let url = URL(string: "https://apps.apple.com/us/app/stashy/id6754876029") {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("You're using a TestFlight build")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                        Text("Help support stashy on the App Store")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    featureRow(icon: "arrow.triangle.2.circlepath", text: "Free updates, forever")
                    featureRow(icon: "star.fill", text: "Ratings help others discover stashy")
                    featureRow(icon: "bolt.heart.fill", text: "Directly supports solo development")
                }

                HStack {
                    Spacer()
                    Text("Get stashy on the App Store")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(
            LinearGradient(
                colors: [Color(red: 0.18, green: 0.38, blue: 0.95), Color(red: 0.55, green: 0.2, blue: 0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
        }
    }

    // MARK: - Tip Jar

    private var tipSection: some View {
        Section(header: Text("Tipp")) {
            if storeManager.products.isEmpty {
                // Fallback / Loading state
                tipRow(icon: "heart", title: "Small", price: "2,99 €")
                tipRow(icon: "heart.fill", title: "Medium", price: "4,99 €")
                tipRow(icon: "bolt.heart.fill", title: "Large", price: "9,99 €")
            } else {
                ForEach(storeManager.products) { product in
                    Button {
                        Task {
                            do {
                                try await storeManager.purchase(product)
                            } catch {
                                print("Purchase failed: \(error)")
                            }
                        }
                    } label: {
                        HStack {
                            let title = storeManager.productDict[product.id] ?? product.displayName
                            Label(title, systemImage: iconFor(productID: product.id))
                                .foregroundColor(appearanceManager.tintColor)
                            Spacer()
                            Text(product.displayPrice)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listRowBackground(Color.secondaryAppBackground)
    }

    private func tipRow(icon: String, title: String, price: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundColor(appearanceManager.tintColor)
            Spacer()
            Text(price)
                .foregroundColor(.secondary)
        }
        .opacity(0.5) // disabled look since products aren't loaded yet
    }
    
    private func iconFor(productID: String) -> String {
        switch productID {
        case "de.stashy.tip1": return "heart"
        case "de.stashy.tip2": return "heart.fill"
        case "de.stashy.tip3": return "bolt.heart.fill"
        default: return "heart"
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Group {
            Section("Links") {
                Link(destination: URL(string: "https://github.com/1letzgo/stashy")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .foregroundColor(appearanceManager.tintColor)
                }
                Link(destination: URL(string: "https://discord.gg/D8wXv6Pm")!) {
                    Label("Discord", systemImage: "bubble.left.and.bubble.right.fill")
                        .foregroundColor(appearanceManager.tintColor)
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
            
        }
    }
    // MARK: - Interactive Devices
    private var interactiveDevicesSection: some View {
        Section(header: Text("Device Synchronization")) {
            NavigationLink(destination: HandySettingsView()) {
                Label("The Handy", systemImage: "hand.tap")
            }
            NavigationLink(destination: IntifaceSettingsView()) {
                Label("Intiface", systemImage: "cable.connector")
            }
            NavigationLink(destination: LoveSpouseSettingsView()) {
                Label("Love Spouse", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
        .listRowBackground(Color.secondaryAppBackground)
    }

    // MARK: - Actions

    private func startLibraryScan() {
        isScanningLibrary = true
        viewModel.triggerLibraryScan { success, message in
            DispatchQueue.main.async {
                isScanningLibrary = false
                scanAlertMessage = message
                showScanAlert = true
            }
        }
    }
}

// MARK: - StoreManager

public enum StoreError: Error {
    case failedVerification
}

@MainActor
class StoreManager: ObservableObject {
    @Published var products: [Product] = []
    @AppStorage("totalTipsCount") var totalTipsCount: Int = 0
    
    let productDict: [String: String] = [
        "de.stashy.tip1": "Small",
        "de.stashy.tip2": "Medium",
        "de.stashy.tip3": "Large"
    ]
    
    init() {
        Task {
            await fetchProducts()
        }
    }
    
    func fetchProducts() async {
        do {
            let products = try await Product.products(for: productDict.keys)
            // Sort by price
            self.products = products.sorted(by: { $0.price < $1.price })
        } catch {
            print("Failed product request from the App Store server: \(error)")
        }
    }
    
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            
            // Increment total tips locally
            totalTipsCount += 1
            
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }
    
    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}


struct IntifaceSettingsView: View {
    @ObservedObject var buttplugManager = ButtplugManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Intiface", isOn: $buttplugManager.isEnabled)
                    .tint(appearanceManager.tintColor)
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            Section(header: Text("Intiface Server")) {
                TextField("Server Address", text: $buttplugManager.serverAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .disabled(!buttplugManager.isEnabled)
                
                HStack {
                    Text("Status")
                    Spacer()
                    Text(buttplugManager.statusMessage)
                        .foregroundColor(buttplugManager.isConnected ? .green : .secondary)
                }
                
                if buttplugManager.isConnected {
                    Button("Disconnect", role: .destructive) {
                        buttplugManager.disconnect()
                    }
                } else {
                    Button("Connect") {
                        buttplugManager.connect()
                    }
                    .disabled(!buttplugManager.isEnabled)
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            if !buttplugManager.devices.isEmpty {
                Section(header: Text("Discovered Devices")) {
                    ForEach(buttplugManager.devices) { device in
                        HStack {
                            Image(systemName: "cable.connector")
                            Text(device.name)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            
            Section(footer: Text("Stashy connects to Intiface Desktop or Intiface Central via WebSockets. Ensure 'Enable Remote Network Access' is turned on in Intiface settings.")) {
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .applyAppBackground()
        .scrollContentBackground(.hidden)
        .stashySettingsDetailChrome("Intiface")
    }
}

struct HandySettingsView: View {
    @ObservedObject var handyManager = HandyManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable The Handy", isOn: $handyManager.isEnabled)
                    .tint(appearanceManager.tintColor)
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section(header: Text("Device Type"), footer: Text("The Handy uses HAMP protocol. The Oh. uses HVP protocol.")) {
                Picker("Device", selection: $handyManager.deviceType) {
                    Text("The Handy").tag("The Handy")
                    Text("The Oh.").tag("Oh.")
                }
                .pickerStyle(.segmented)
                .disabled(!handyManager.isEnabled)
            }
            .listRowBackground(Color.secondaryAppBackground)

            if handyManager.deviceType == "The Handy" {
                Section(header: Text("StashSync Controls")) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Stroke Length")
                            Spacer()
                            Text("\(Int(handyManager.strokeLength))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $handyManager.strokeLength, in: 10...100, step: 5)
                            .tint(appearanceManager.tintColor)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max Velocity")
                            Spacer()
                            Text("\(Int(handyManager.maxVelocity))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $handyManager.maxVelocity, in: 10...100, step: 5)
                            .tint(appearanceManager.tintColor)
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
                .disabled(!handyManager.isEnabled)
            } else {
                Section(header: Text("StashSync Controls")) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max Intensity")
                            Spacer()
                            Text("\(Int(handyManager.maxAmplitude * 100))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $handyManager.maxAmplitude, in: 0.1...1.0, step: 0.05)
                            .tint(appearanceManager.tintColor)
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
                .disabled(!handyManager.isEnabled)
            }

            Section(header: Text("Handy Connection"), footer: Text("Stashy now automatically uploads local funscripts to Handy Cloud. The Public URL is only needed for advanced setups.")) {
                TextField("Connection Key", text: HandyManager.shared.$connectionKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .disabled(!handyManager.isEnabled)

                TextField("Public URL Override (Optional)", text: HandyManager.shared.$publicUrl)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .disabled(!handyManager.isEnabled)

                HStack {
                    Text("Status")
                    Spacer()
                    Text(handyManager.statusMessage)
                        .foregroundColor(handyManager.isConnected ? .green : .secondary)
                }

                Button("Check Connection") {
                    handyManager.checkConnection()
                }
                .disabled(!handyManager.isEnabled)
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .applyAppBackground()
        .scrollContentBackground(.hidden)
        .stashySettingsDetailChrome("The Handy")
    }
}

struct LoveSpouseSettingsView: View {
    @ObservedObject var loveSpouseManager = LoveSpouseManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Love Spouse", isOn: $loveSpouseManager.isEnabled)
                    .tint(appearanceManager.tintColor)
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            Section(header: Text("Connection Status")) {
                HStack {
                    Text("Bluetooth")
                    Spacer()
                    Text(loveSpouseManager.statusMessage)
                        .foregroundColor(loveSpouseManager.isConnected ? .green : .secondary)
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            Section(footer: Text("Love Spouse 2.4g toys use BLE advertising. Ensure Bluetooth is enabled and the toy is in pairing/scan mode. Both toys in range will react simultaneously.")) {
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .applyAppBackground()
        .scrollContentBackground(.hidden)
        .stashySettingsDetailChrome("Love Spouse")
    }
}


struct StashSyncSettingsView: View {
    @ObservedObject var videoManager = StashVideoSyncManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var showingDisclaimer = false
    
    var body: some View {
        let syncEnabledBinding = Binding<Bool>(
            get: { videoManager.isVideoSyncEnabled },
            set: { newValue in
                if newValue && !videoManager.isDisclaimerAccepted {
                    showingDisclaimer = true
                } else {
                    videoManager.isVideoSyncEnabled = newValue
                }
            }
        )
        
        Form {
            Section(header: Text("StashSync Features"), footer: Text("StashSync uses real-time on-device video analysis to synchronize your devices. This process is CPU-intensive and can lead to increased battery drain and device heating. By enabling this feature, you acknowledge that you use StashSync and any controlled hardware devices at your own risk. Any potential damage or injury resulting from the use of connected hardware is your sole responsibility.")) {
                Toggle(isOn: syncEnabledBinding) {
                    Label("StashSync", systemImage: "bolt.fill")
                }
                .tint(appearanceManager.tintColor)
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            Section(header: Text("Sensitivity")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("StashSync Sensitivity")
                        Spacer()
                        Text("\(Int(videoManager.sensitivity * 50))%").foregroundColor(.secondary)
                    }
                    Slider(value: $videoManager.sensitivity, in: 0.1...2.0).tint(.orange)
                }.padding(.vertical, 4)
            }
            .disabled(!videoManager.isVideoSyncEnabled)
            .listRowBackground(Color.secondaryAppBackground)

            Section(header: Text("Optical Flow Smoothing")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Smoothing")
                        Spacer()
                        Text("\(Int(videoManager.smoothing * 100))%").foregroundColor(.secondary)
                    }
                    Slider(value: $videoManager.smoothing, in: 0.0...0.9).tint(.orange)
                }
            }
            .disabled(!videoManager.isVideoSyncEnabled)
            .listRowBackground(Color.secondaryAppBackground)
            

        }
        .applyAppBackground()
        .scrollContentBackground(.hidden)
        .stashySettingsDetailChrome("StashSync")
        .alert("StashSync Disclaimer", isPresented: $showingDisclaimer) {
            Button("Cancel", role: .cancel) { }
            Button("Accept & Enable") {
                videoManager.isDisclaimerAccepted = true
                videoManager.isVideoSyncEnabled = true
            }
        } message: {
            Text("StashSync uses real-time on-device video analysis to synchronize your devices. This process is CPU-intensive and can lead to increased battery drain and device heating. By enabling this feature, you acknowledge that you use StashSync and any controlled hardware devices at your own risk. Any potential damage or injury resulting from the use of connected hardware is your sole responsibility.")
        }
    }
}

#Preview {
    SettingsView()
}

#endif
