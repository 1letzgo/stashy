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
                Picker(selection: Binding(
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
                } label: {
                    Label("Library Quality", systemImage: "film")
                }

                Picker(selection: Binding(
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
                } label: {
                    Label("Feeds Quality", systemImage: "play.rectangle.on.rectangle")
                }
            } else {
                Text("Connect to a server to configure quality settings.")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            
            #if !os(tvOS)
            Toggle(isOn: $tabManager.isPiPEnabled) {
                Label("Picture-in-Picture", systemImage: "pip")
            }
            .tint(appearanceManager.tintColor)
            #endif
        }
        .listRowBackground(Color.secondaryAppBackground)

    }
}

#if !os(tvOS)
/// AI subtitle and translation controls shown under Settings → stashy+.
struct StashyPlusAISubtitlesSettings: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var tabManager = TabManager.shared
    /// Local selection so the picker label refreshes after a pick (UserDefaults alone does not).
    @State private var subtitleLanguageCode: String = SubtitleTargetLanguage.load()

    var body: some View {
        Picker(selection: Binding(
            get: { subtitleLanguageCode },
            set: { newValue in
                subtitleLanguageCode = newValue
                SubtitleTargetLanguage.persist(newValue)
            }
        )) {
            ForEach(SubtitleTargetLanguage.pickerOptions(), id: \.id) { option in
                Text(option.label).tag(option.id)
            }
        } label: {
            Label("Subtitle Language", systemImage: "captions.bubble")
        }

        Toggle(isOn: $tabManager.isLiveCaptionLookaheadEnabled) {
            Label("Live CC Lookahead", systemImage: "hare")
        }
        .tint(appearanceManager.tintColor)
    }
}

/// Single stashy+ tool enablement row.
struct StashyPlusToolToggle: View {
    let item: ToolsItem
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { tabManager.tools.first(where: { $0.id == item })?.isEnabled ?? false },
            set: { _ in tabManager.toggleTool(item) }
        )) {
            Label(item.plusFeatureTitle, systemImage: item.icon)
        }
        .tint(appearanceManager.tintColor)
    }
}
#endif
