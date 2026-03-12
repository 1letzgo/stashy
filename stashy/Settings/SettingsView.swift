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
    
    // IAP
    @StateObject private var storeManager = StoreManager()

    var body: some View {
        Form {
            // MARK: - App Store (TestFlight only)
            if isTestFlightBuild() {
                Section {
                    appStoreBanner
                }
            }

            // MARK: - Server
            ServerListSection(
                viewModel: viewModel,
                isScanningLibrary: $isScanningLibrary,
                showingAddServerSheet: $showingAddServerSheet,
                editingServer: $editingServer,
                onScan: { startLibraryScan() }
            )

            // MARK: - Playback
            if configManager.activeConfig != nil {
                PlaybackSettingsSection()
            }
            
            Section(header: Text("Security")) {
                NavigationLink(destination: SecuritySettingsView()) {
                    Label("Security", systemImage: "lock.shield")
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            Section(header: Text("Appearance")) {
                NavigationLink(destination: AppearanceSettingsView()) {
                    Label("Appearance", systemImage: "paintbrush")
                }
            }
            .listRowBackground(Color.secondaryAppBackground)

            // MARK: - Content & Tabs
            if configManager.activeConfig != nil {
                ContentSettingsSection()
            }

            // MARK: - Default Settings
            if configManager.activeConfig != nil {
                Section("Default Settings") {
                    NavigationLink(destination: DefaultSortView()) {
                        Label("Sorting", systemImage: "arrow.up.arrow.down")
                    }

                    NavigationLink(destination: DefaultFilterView()) {
                        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
            }

            // MARK: - About
            #if !os(tvOS)
            interactiveDevicesSection
            #endif
            tipSection
            aboutSection
        }
        .applyAppBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - App Store Banner

    @Environment(\.openURL) private var openURL

    private var appStoreBanner: some View {
        Button {
            if let url = URL(string: "https://apps.apple.com/us/app/stashy/id6754876029") {
                openURL(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Get on the App Store")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("Support with an App Store download")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(
            LinearGradient(
                colors: [Color.blue, Color.purple.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    // MARK: - Tip Jar

    private var tipSection: some View {
        Section(
            header: Text("Tipp"),
            footer: VStack(alignment: .leading, spacing: 4) {
                if storeManager.totalTipsCount > 0 {
                    Text("You have tipped \(storeManager.totalTipsCount) times. Thank you! 💖")
                        .foregroundColor(appearanceManager.tintColor)
                        .fontWeight(.medium)
                        .padding(.top, 2)
                } else {
                    Text("Support the development of stashy!")
                }
            }
        ) {
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
                Link(destination: URL(string: "https://discord.gg/hYWBxY7P")!) {
                    Label("Discord", systemImage: "bubble.left.and.bubble.right.fill")
                        .foregroundColor(appearanceManager.tintColor)
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            Text("🚧 crafted by letzgo")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Interactive Devices
    #if !os(tvOS)
    private var interactiveDevicesSection: some View {
        Section(header: Text("Interactive Devices")) {
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
    #endif

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
        .navigationTitle("Intiface")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .scrollContentBackground(.hidden)
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
        .navigationTitle("The Handy")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .scrollContentBackground(.hidden)
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
        .navigationTitle("Love Spouse")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    SettingsView()
}
#endif
