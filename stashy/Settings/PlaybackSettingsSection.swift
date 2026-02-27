//
//  PlaybackSettingsSection.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

import SwiftUI

struct PlaybackSettingsSection: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared

    var body: some View {
        Section(header: Text("Playback")) {
            if let config = configManager.activeConfig {
                Picker("Library Quality", selection: Binding(
                    get: { config.defaultQuality },
                    set: { newValue in
                        var updated = config
                        updated.defaultQuality = newValue
                        ServerConfigManager.shared.saveConfig(updated)
                        ServerConfigManager.shared.addOrUpdateServer(updated)
                    }
                )) {
                    ForEach(StreamingQuality.allCases, id: \.self) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }

                Picker("StashTok Quality", selection: Binding(
                    get: { config.reelsQuality },
                    set: { newValue in
                        var updated = config
                        updated.reelsQuality = newValue
                        ServerConfigManager.shared.saveConfig(updated)
                        ServerConfigManager.shared.addOrUpdateServer(updated)
                    }
                )) {
                    ForEach(StreamingQuality.allCases, id: \.self) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
            } else {
                Text("Connect to a server to configure quality settings.")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }

        #if !os(tvOS)
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
        #endif
    }
}

#if !os(tvOS)
struct IntifaceSettingsView: View {
    @ObservedObject var buttplugManager = ButtplugManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Intiface", isOn: $buttplugManager.isEnabled)
                    .tint(appearanceManager.tintColor)
            }
            
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
            }
            
            Section(footer: Text("Stashy connects to Intiface Desktop or Intiface Central via WebSockets. Ensure 'Enable Remote Network Access' is turned on in Intiface settings.")) {
            }
        }
        .navigationTitle("Intiface")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

#if !os(tvOS)
struct HandySettingsView: View {
    @ObservedObject var handyManager = HandyManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable The Handy", isOn: $handyManager.isEnabled)
                    .tint(appearanceManager.tintColor)
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
        }
        .navigationTitle("The Handy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

#if !os(tvOS)
struct LoveSpouseSettingsView: View {
    @ObservedObject var loveSpouseManager = LoveSpouseManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Love Spouse", isOn: $loveSpouseManager.isEnabled)
                    .tint(appearanceManager.tintColor)
            }
            
            Section(header: Text("Connection Status")) {
                HStack {
                    Text("Bluetooth")
                    Spacer()
                    Text(loveSpouseManager.statusMessage)
                        .foregroundColor(loveSpouseManager.isConnected ? .green : .secondary)
                }
            }
            
            Section(footer: Text("Love Spouse 2.4g toys use BLE advertising. Ensure Bluetooth is enabled and the toy is in pairing/scan mode. Both toys in range will react simultaneously.")) {
            }
        }
        .navigationTitle("Love Spouse")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
