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
        Group {
            Section {
                stashyScrollingSectionHeader("Playback")
                #if !os(tvOS)
                Toggle(isOn: $tabManager.isPiPEnabled) {
                    Label("Picture-in-Picture", systemImage: "pip")
                }
                .tint(appearanceManager.tintColor)
                .stashyGroupedBlockRow(index: 0, count: 3)

                Picker(selection: $tabManager.playerSkipSeconds) {
                    ForEach(TabManager.playerSkipOptions, id: \.self) { seconds in
                        Text("\(Int(seconds)) s").tag(seconds)
                    }
                } label: {
                    Label("Double-tap skip", systemImage: "goforward")
                }
                .stashyGroupedBlockRow(index: 1, count: 3)

                Toggle(isOn: $tabManager.playerDolbyVisionEnabled) {
                    Label("Dolby Vision", systemImage: "sparkles.tv")
                }
                .tint(appearanceManager.tintColor)
                .stashyGroupedBlockRow(index: 2, count: 3)

                #endif
            }

            #if !os(tvOS)
            subtitlesSection
            #endif
        }
    }

    #if !os(tvOS)
    /// Subtitle defaults and look. Shared by every player overlay (scene detail, downloads, tvOS).
    private var subtitlesSection: some View {
        Section {
            stashyScrollingSectionHeader("Subtitles")

            Toggle(isOn: $tabManager.subtitlesAutoEnabled) {
                Label("Show subtitles automatically", systemImage: "captions.bubble")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 0, count: 8)

            Picker(selection: $tabManager.subtitlePreferredLanguage) {
                ForEach(SubtitlePreferredLanguage.pickerOptions(), id: \.id) { option in
                    Text(option.label).tag(option.id)
                }
            } label: {
                Label("Preferred language", systemImage: "globe")
            }
            .stashyGroupedBlockRow(index: 1, count: 8)

            Picker(selection: $tabManager.subtitleFontSize) {
                ForEach(SubtitleFontSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            } label: {
                Label("Size", systemImage: "textformat.size")
            }
            .stashyGroupedBlockRow(index: 2, count: 8)

            Picker(selection: $tabManager.subtitleFontFamily) {
                ForEach(SubtitleFontFamily.allCases) { family in
                    Text(family.label).tag(family)
                }
            } label: {
                Label("Font", systemImage: "textformat")
            }
            .stashyGroupedBlockRow(index: 3, count: 8)

            Picker(selection: $tabManager.subtitleTextColor) {
                ForEach(SubtitleTextColorChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            } label: {
                Label("Text color", systemImage: "paintpalette")
            }
            .stashyGroupedBlockRow(index: 4, count: 8)

            Toggle(isOn: $tabManager.subtitleBoxEnabled) {
                Label("Background box", systemImage: "rectangle.fill")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 5, count: 8)

            Picker(selection: $tabManager.subtitleBackgroundColor) {
                ForEach(SubtitleBackgroundChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            } label: {
                Label("Background color", systemImage: "square.fill.on.square.fill")
            }
            .disabled(!tabManager.subtitleBoxEnabled)
            .stashyGroupedBlockRow(index: 6, count: 8)

            subtitlePreview
                .stashyGroupedBlockRow(index: 7, count: 8)
        }
    }

    /// Live preview: the cue as the player draws it, over a dark stand-in for the picture.
    private var subtitlePreview: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.22), Color(white: 0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            StashySubtitleText(text: "Sample subtitle",
                               scale: 1,
                               lineLimit: 2,
                               style: tabManager.subtitleStyle)
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.vertical, 4)
        .allowsHitTesting(false)
        .accessibilityLabel("Subtitle preview")
    }
    #endif
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
