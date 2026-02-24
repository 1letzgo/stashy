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
            Section(header: Text("Intiface Server")) {
                TextField("Server Address", text: $buttplugManager.serverAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
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
            Section(header: Text("Handy Connection"), footer: Text("Stashy now automatically uploads local funscripts to Handy Cloud. The Public URL is only needed for advanced setups.")) {
                TextField("Connection Key", text: HandyManager.shared.$connectionKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                TextField("Public URL Override (Optional)", text: HandyManager.shared.$publicUrl)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                
                HStack {
                    Text("Status")
                    Spacer()
                    Text(handyManager.statusMessage)
                        .foregroundColor(handyManager.isConnected ? .green : .secondary)
                }
                
                Button("Check Connection") {
                    handyManager.checkConnection()
                }
            }
        }
        .navigationTitle("The Handy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
