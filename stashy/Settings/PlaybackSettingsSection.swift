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
    @ObservedObject var tabManager = TabManager.shared

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
            
            #if !os(tvOS)
            Toggle("Picture-in-Picture", isOn: $tabManager.isPiPEnabled)
                .tint(appearanceManager.tintColor)
            #endif
        }
        .listRowBackground(Color.secondaryAppBackground)

    }
}
