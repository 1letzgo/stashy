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

    /// Verticals is a stashy+ feed mode; its own rule shows only while it can be used.
    private var verticalsAvailable: Bool { tabManager.enabledReelsModes.contains(.verticals) }

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
            stashyScrollingSectionHeader(tr("player"))
            Toggle(isOn: $tabManager.isPiPEnabled) {
                Label(tr("picture_in_picture"), systemImage: "pip")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 0, count: 10)

            Picker(selection: $tabManager.playerSkipSeconds) {
                ForEach(TabManager.playerSkipOptions, id: \.self) { seconds in
                    Text(TabManager.playerSkipLabel(seconds)).tag(seconds)
                }
            } label: {
                Label(tr("action_skip_interval"), systemImage: "goforward")
            }
            .stashyGroupedBlockRow(index: 1, count: 10)

            Toggle(isOn: $tabManager.showsPlayerSkipButtons) {
                Label(tr("action_skip_buttons"), systemImage: "goforward.10")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 2, count: 10)

            Toggle(isOn: $tabManager.hidesPlayerAirPlayButton) {
                Label(tr("action_hide_airplay_button"), systemImage: "airplayvideo")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 3, count: 10)

            // Fullscreen turns to landscape for landscape videos.
            Toggle(isOn: $tabManager.playerAutoRotateFullscreen) {
                Label(tr("auto_rotate_fullscreen"), systemImage: "rotate.right")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 4, count: 10)

            // Landscape fullscreen fills by itself when little of the picture is lost.
            Toggle(isOn: $tabManager.playerAutoZoom) {
                Label(tr("autozoom"), systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 5, count: 10)

            Toggle(isOn: $tabManager.playerDolbyVisionEnabled) {
                Label(tr("dolby_vision"), systemImage: "sparkles.tv")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 6, count: 10)

            Picker(selection: $tabManager.holdSpeedPlayer) {
                ForEach(TabManager.holdSpeedOptions, id: \.self) { rate in
                    Text(TabManager.holdSpeedLabel(rate)).tag(rate)
                }
            } label: {
                Label(tr("hold_to_speed_up"), systemImage: "forward.fill")
            }
            .stashyGroupedBlockRow(index: 7, count: 10)

            Picker(selection: $tabManager.playCountPlayerSeconds) {
                ForEach(TabManager.playCountThresholdOptions, id: \.self) { seconds in
                    Text(TabManager.playCountThresholdLabel(seconds)).tag(seconds)
                }
            } label: {
                Label(tr("count_as_played"), systemImage: "play.circle")
            }
            .stashyGroupedBlockRow(index: 8, count: 10)

            // Applies to the player, Feeds and image-viewer videos; card previews stay muted.
            Toggle(isOn: $tabManager.playbackStartMuted) {
                Label(tr("action_start_mute"), systemImage: "speaker.slash")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 9, count: 10)
        }
    }

    /// Feeds playback (Scenes / Markers rows).
    private var feedsSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("feeds"))
            // Feeds › Scenes: where a scene row starts, past the studio intro.
            Picker(selection: $tabManager.feedsSceneStartPosition) {
                ForEach(TabManager.FeedsSceneStartPosition.allCases) { position in
                    Text(position.label).tag(position)
                }
            } label: {
                Label(tr("action_start_position"), systemImage: "forward.end")
            }
            .stashyGroupedBlockRow(index: 0, count: verticalsAvailable ? 7 : 6)

            // Feeds › Markers: length of a marker without an end time.
            Picker(selection: $tabManager.feedsMarkerDefaultSeconds) {
                ForEach(TabManager.feedsMarkerLengthOptions, id: \.self) { seconds in
                    Text("\(Int(seconds)) s").tag(seconds)
                }
            } label: {
                Label(tr("marker_length"), systemImage: "bookmark")
            }
            .stashyGroupedBlockRow(index: 1, count: verticalsAvailable ? 7 : 6)

            Picker(selection: $tabManager.holdSpeedFeeds) {
                ForEach(TabManager.holdSpeedOptions, id: \.self) { rate in
                    Text(TabManager.holdSpeedLabel(rate)).tag(rate)
                }
            } label: {
                Label(tr("hold_to_speed_up"), systemImage: "forward.frame.fill")
            }
            .stashyGroupedBlockRow(index: 2, count: verticalsAvailable ? 7 : 6)

            Picker(selection: $tabManager.playCountFeedsSeconds) {
                ForEach(TabManager.playCountThresholdOptions, id: \.self) { seconds in
                    Text(TabManager.playCountThresholdLabel(seconds)).tag(seconds)
                }
            } label: {
                Label(verticalsAvailable ? tr("count_as_played_scenes") : tr("count_as_played"), systemImage: "rectangle.stack.badge.play")
            }
            .stashyGroupedBlockRow(index: 3, count: verticalsAvailable ? 7 : 6)

            if verticalsAvailable {
                Picker(selection: $tabManager.playCountVerticalsSeconds) {
                    ForEach(TabManager.playCountThresholdOptions, id: \.self) { seconds in
                        Text(TabManager.playCountThresholdLabel(seconds)).tag(seconds)
                    }
                } label: {
                    Label(tr("count_as_played_verticals"), systemImage: "rectangle.portrait")
                }
                .stashyGroupedBlockRow(index: 4, count: 7)
            }

            // Feeds › Scenes: a marker at the current position, beside the rating.
            Toggle(isOn: $tabManager.feedsAddMarkerButton) {
                Label(tr("action_add_marker_button"), systemImage: "plus.square.fill.on.square.fill")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: verticalsAvailable ? 5 : 4, count: verticalsAvailable ? 7 : 6)

            // Feeds › Scenes: double tap left / right goes to the previous / next marker.
            Toggle(isOn: $tabManager.feedsDoubleTapMarkers) {
                Label(tr("double_tap_jumps_to_markers"), systemImage: "bookmark")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: verticalsAvailable ? 6 : 5, count: verticalsAvailable ? 7 : 6)
            stashyScrollingSectionFooter(tr("hint_double_tap_jumps_to_markers"))
        }
    }

    /// Stash web "Track activity": play count, history, resume point, watch time.
    private var activitySection: some View {
        Section {
            stashyScrollingSectionHeader(tr("activity"))
            Toggle(isOn: $tabManager.tracksPlaybackActivity) {
                Label(tr("playback_activity"), systemImage: "clock.arrow.circlepath")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 0, count: 1)
            stashyScrollingSectionFooter(tr("hint_play_count_history_resume_point"))
        }
    }

    /// How much a "newest" download grabs — gallery / tag images and the scenes of a
    /// performer, studio, tag or group.
    private var downloadsSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("downloads"))

            Picker(selection: $tabManager.downloadBatchSize) {
                ForEach(TabManager.downloadBatchSizeOptions, id: \.self) { size in
                    Text("\(size)").tag(size)
                }
            } label: {
                Label(tr("newest_batch_images"), systemImage: "photo.stack")
            }
            .stashyGroupedBlockRow(index: 0, count: 2)

            Picker(selection: $tabManager.sceneDownloadBatchSize) {
                ForEach(TabManager.downloadBatchSizeOptions, id: \.self) { size in
                    Text("\(size)").tag(size)
                }
            } label: {
                Label(tr("newest_batch_scenes"), systemImage: "film")
            }
            .stashyGroupedBlockRow(index: 1, count: 2)
        }
    }

    /// Subtitle defaults and look. Shared by every player overlay (scene detail, downloads, tvOS).
    private var subtitlesSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("subtitles"))

            Toggle(isOn: $tabManager.subtitlesAutoEnabled) {
                Label(tr("action_show_subtitles_automatically"), systemImage: "captions.bubble")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 0, count: 8)

            Picker(selection: $tabManager.subtitlePreferredLanguage) {
                ForEach(SubtitlePreferredLanguage.pickerOptions(), id: \.id) { option in
                    Text(option.label).tag(option.id)
                }
            } label: {
                Label(tr("preferred_language"), systemImage: "globe")
            }
            .stashyGroupedBlockRow(index: 1, count: 8)

            Picker(selection: $tabManager.subtitleFontSize) {
                ForEach(SubtitleFontSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            } label: {
                Label(tr("size"), systemImage: "textformat.size")
            }
            .stashyGroupedBlockRow(index: 2, count: 8)

            Picker(selection: $tabManager.subtitleFontFamily) {
                ForEach(SubtitleFontFamily.allCases) { family in
                    Text(family.label).tag(family)
                }
            } label: {
                Label(tr("font"), systemImage: "textformat")
            }
            .stashyGroupedBlockRow(index: 3, count: 8)

            Picker(selection: $tabManager.subtitleTextColor) {
                ForEach(SubtitleTextColorChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            } label: {
                Label(tr("text_color"), systemImage: "paintpalette")
            }
            .stashyGroupedBlockRow(index: 4, count: 8)

            Toggle(isOn: $tabManager.subtitleBoxEnabled) {
                Label(tr("background_box"), systemImage: "rectangle.fill")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 5, count: 8)

            Picker(selection: $tabManager.subtitleBackgroundColor) {
                ForEach(SubtitleBackgroundChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            } label: {
                Label(tr("background_color"), systemImage: "square.fill.on.square.fill")
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
            StashySubtitleText(text: tr("sample_subtitle"),
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
        .accessibilityLabel(tr("subtitle_preview"))
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
            Label(tr("my_subtitle_language"), systemImage: "captions.bubble")
        }
        .stashyGroupedBlockRow(index: 0, count: 1)
    }
}

#endif
