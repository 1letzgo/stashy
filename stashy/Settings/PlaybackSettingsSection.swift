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
        let qualityRows = configManager.activeConfig != nil ? 2 : 1
        let rowCount = qualityRows + 1

        Section {
            stashyScrollingSectionHeader("Playback")
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
                .stashyGroupedBlockRow(index: 0, count: rowCount)

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
                .stashyGroupedBlockRow(index: 1, count: rowCount)
            } else {
                Text("Connect to a server to configure quality settings.")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .stashyGroupedBlockRow(index: 0, count: rowCount)
            }

            #if !os(tvOS)
            Toggle(isOn: $tabManager.isPiPEnabled) {
                Label("Picture-in-Picture", systemImage: "pip")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: qualityRows, count: rowCount)
            #endif
        }
    }
}

/// stashy+ Direct Play toggle shown under Settings → stashy+.
///
/// Ships **off**. Direct Play plays the untouched file through the bundled
/// FFmpeg engine instead of asking the server to transcode; it is new, so it
/// is opted into per user rather than switched on for everyone at once.
struct StashyPlusDirectPlaySettings: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    /// UserDefaults alone does not refresh the toggle, so mirror it locally.
    @State private var isEnabled: Bool = DirectPlayPolicy.isEnabledBySetting

    var body: some View {
        Toggle(isOn: Binding(
            get: { isEnabled },
            set: { newValue in
                isEnabled = newValue
                DirectPlayPolicy.isEnabledBySetting = newValue
                // A re-enable should retry sources that failed under the old build.
                if newValue { DirectPlayPolicy.clearFailureMemory() }
            }
        )) {
            Label("Direct Play", systemImage: "film.stack")
        }
        .tint(appearanceManager.tintColor)
        .stashyGroupedBlockRow(index: 0, count: 2)

        Text("Plays formats the system cannot open — MKV, AVI, TS and friends — straight from the original file, without asking the server to transcode. Needs the full file bitrate over the network, so it works best on a local connection.")
            .font(.caption)
            .foregroundColor(.secondary)
            .stashyGroupedBlockRow(index: 1, count: 2)
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
            Label("My subtitle language", systemImage: "captions.bubble")
        }
        .stashyGroupedBlockRow(index: 0, count: 2)

        Toggle(isOn: $tabManager.isLiveCaptionLookaheadEnabled) {
            Label("Live CC Lookahead", systemImage: "hare")
        }
        .tint(appearanceManager.tintColor)
        .stashyGroupedBlockRow(index: 1, count: 2)
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
