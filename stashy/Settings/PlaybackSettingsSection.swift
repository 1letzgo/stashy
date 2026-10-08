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
            #if !os(tvOS)
            playerSection
            feedsSection
            activitySection
            #endif

            #if !os(tvOS)
            downloadsSection
            subtitlesSection
            #endif
        }
    }

    #if !os(tvOS)
    /// The scene player (scene detail, fullscreen, PiP).
    private var playerSection: some View {
        Section {
            stashyScrollingSectionHeader("Player")
            Toggle(isOn: $tabManager.isPiPEnabled) {
                Label("Picture-in-Picture", systemImage: "pip")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 0, count: 8)

            Picker(selection: $tabManager.playerSkipSeconds) {
                ForEach(TabManager.playerSkipOptions, id: \.self) { seconds in
                    Text("\(Int(seconds)) s").tag(seconds)
                }
            } label: {
                Label("Skip interval", systemImage: "goforward")
            }
            .stashyGroupedBlockRow(index: 1, count: 8)

            Toggle(isOn: $tabManager.showsPlayerSkipButtons) {
                Label("Skip buttons", systemImage: "goforward.10")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 2, count: 8)

            // Fullscreen turns to landscape for landscape videos.
            Toggle(isOn: $tabManager.playerAutoRotateFullscreen) {
                Label("Auto-rotate fullscreen", systemImage: "rotate.right")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 3, count: 8)

            // Landscape fullscreen fills by itself when little of the picture is lost.
            Toggle(isOn: $tabManager.playerAutoZoom) {
                Label("Autozoom", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 4, count: 8)

            Toggle(isOn: $tabManager.playerDolbyVisionEnabled) {
                Label("Dolby Vision", systemImage: "sparkles.tv")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 5, count: 8)

            Picker(selection: $tabManager.holdSpeedPlayer) {
                ForEach(TabManager.holdSpeedOptions, id: \.self) { rate in
                    Text(TabManager.holdSpeedLabel(rate)).tag(rate)
                }
            } label: {
                Label("Hold to speed up", systemImage: "forward.fill")
            }
            .stashyGroupedBlockRow(index: 6, count: 8)

            Picker(selection: $tabManager.playCountPlayerSeconds) {
                ForEach(TabManager.playCountThresholdOptions, id: \.self) { seconds in
                    Text(TabManager.playCountThresholdLabel(seconds)).tag(seconds)
                }
            } label: {
                Label("Count as played", systemImage: "play.circle")
            }
            .stashyGroupedBlockRow(index: 7, count: 8)
        }
    }

    /// Feeds playback (Scenes / Markers rows).
    private var feedsSection: some View {
        Section {
            stashyScrollingSectionHeader("Feeds")
            // Feeds › Scenes: where a scene row starts, past the studio intro.
            Picker(selection: $tabManager.feedsSceneStartPosition) {
                ForEach(TabManager.FeedsSceneStartPosition.allCases) { position in
                    Text(position.label).tag(position)
                }
            } label: {
                Label("Start position", systemImage: "forward.end")
            }
            .stashyGroupedBlockRow(index: 0, count: 4)

            // Feeds › Markers: length of a marker without an end time.
            Picker(selection: $tabManager.feedsMarkerDefaultSeconds) {
                ForEach(TabManager.feedsMarkerLengthOptions, id: \.self) { seconds in
                    Text("\(Int(seconds)) s").tag(seconds)
                }
            } label: {
                Label("Marker length", systemImage: "bookmark")
            }
            .stashyGroupedBlockRow(index: 1, count: 4)

            Picker(selection: $tabManager.holdSpeedFeeds) {
                ForEach(TabManager.holdSpeedOptions, id: \.self) { rate in
                    Text(TabManager.holdSpeedLabel(rate)).tag(rate)
                }
            } label: {
                Label("Hold to speed up", systemImage: "forward.frame.fill")
            }
            .stashyGroupedBlockRow(index: 2, count: 4)

            Picker(selection: $tabManager.playCountFeedsSeconds) {
                ForEach(TabManager.playCountThresholdOptions, id: \.self) { seconds in
                    Text(TabManager.playCountThresholdLabel(seconds)).tag(seconds)
                }
            } label: {
                Label("Count as played", systemImage: "rectangle.stack.badge.play")
            }
            .stashyGroupedBlockRow(index: 3, count: 4)
        }
    }

    /// Stash web "Track activity": play count, history, resume point, watch time.
    private var activitySection: some View {
        Section {
            stashyScrollingSectionHeader("Activity")
            Toggle(isOn: $tabManager.tracksPlaybackActivity) {
                Label("Playback activity", systemImage: "clock.arrow.circlepath")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 0, count: 1)
            stashyScrollingSectionFooter("Play count, history, resume point and watch time on the server. The player menu can pause it for one scene.")
        }
    }

    /// How much a "newest" download grabs — gallery / tag images and the scenes of a
    /// performer, studio, tag or group.
    private var downloadsSection: some View {
        Section {
            stashyScrollingSectionHeader("Downloads")

            Picker(selection: $tabManager.downloadBatchSize) {
                ForEach(TabManager.downloadBatchSizeOptions, id: \.self) { size in
                    Text("\(size)").tag(size)
                }
            } label: {
                Label("Newest batch — Images", systemImage: "photo.stack")
            }
            .stashyGroupedBlockRow(index: 0, count: 2)

            Picker(selection: $tabManager.sceneDownloadBatchSize) {
                ForEach(TabManager.downloadBatchSizeOptions, id: \.self) { size in
                    Text("\(size)").tag(size)
                }
            } label: {
                Label("Newest batch — Scenes", systemImage: "film")
            }
            .stashyGroupedBlockRow(index: 1, count: 2)
        }
    }

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
