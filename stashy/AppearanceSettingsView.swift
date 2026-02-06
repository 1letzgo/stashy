//
//  AppearanceSettingsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        List {
            Section(header: Text("Video Quality")) {
                if let config = ServerConfigManager.shared.activeConfig {
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
                    
                    Picker("Reels Quality", selection: Binding(
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
            
            Section(header: Text("App Accent Color"), footer: Text("This color will be applied to the tab bar, navigation bar buttons, and other interactive elements throughout the app.")) {
                // Color Picker
                ColorPicker("Custom Color", selection: $appearanceManager.tintColor, supportsOpacity: false)
                
                // Presets Grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                    ForEach(appearanceManager.presets) { option in
                        Circle()
                            .fill(option.color)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                            )
                            .overlay(
                                Image(systemName: "checkmark")
                                    .foregroundColor(.white)
                                    .opacity(appearanceManager.tintColor == option.color ? 1 : 0)
                            )
                            .onTapGesture {
                                withAnimation {
                                    appearanceManager.tintColor = option.color
                                }
                            }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Appearance")
    }
}
