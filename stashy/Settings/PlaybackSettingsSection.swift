//
//  PlaybackSettingsSection.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

import SwiftUI

struct PlaybackSettingsSection: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var tabManager = TabManager.shared

    var body: some View {
        Section {
            stashyScrollingSectionHeader("Playback")
            #if !os(tvOS)
            Toggle(isOn: $tabManager.isPiPEnabled) {
                Label("Picture-in-Picture", systemImage: "pip")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 0, count: 1)
            #endif
        }
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
        .stashyGroupedBlockRow(index: 0, count: 1)
    }
}

#endif
