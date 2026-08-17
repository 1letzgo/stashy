//
//  SceneDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI
import AVFoundation
import AVKit
import WebKit
import Combine
import Translation

struct SceneDetailView: View {
    let scene: Scene
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var activeScene: Scene
    @ObservedObject var viewModel = StashDBViewModel()
    @ObservedObject var handyManager = HandyManager.shared
    @ObservedObject var buttplugManager = ButtplugManager.shared
    @ObservedObject var loveSpouseManager = LoveSpouseManager.shared
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @StateObject private var subtitleController = SubtitleController()
    @StateObject private var transcriptionController = SceneLiveTranscriptionController()
    @StateObject private var captionTranslator = SceneCaptionTranslator()
    @StateObject private var audioTrackController = SceneAudioTrackController()
    
    let autoPlay: Bool
    
    init(scene: Scene, autoPlay: Bool = false) {
        self.scene = scene
        self.autoPlay = autoPlay
        _activeScene = State(initialValue: scene)
    }
    @State private var player: AVPlayer?
    @State private var showDeleteWithFilesConfirmation = false
    @State private var isDeleting = false
    @State private var isDownloading = false
    @State private var isIdentifying = false
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var coordinator: NavigationCoordinator

    @State private var isHeaderExpanded = false
    @State private var isTagsExpanded = false
    @State private var isFullscreen = false
    @State private var isPlaybackStarted = false
    @State private var tagsTotalHeight: CGFloat = 0
    @State private var isMuted = ScenePlayerMute.initialValue()
    @State private var hasAddedPlay = false
    @State private var showingAddMarkerSheet = false
    @State private var capturedMarkerTime: Double = 0
    @State private var playbackSpeed: Double = 1.0
    @State private var currentPlaybackTime: Double = 0
    @State private var timeObserverToken: Any?
    @State private var playbackActivityTracker = ScenePlaybackActivityTracker()
    /// True while the user is actively dragging the heatmap scrubber. Used to
    /// suppress redundant work (sync restarts, play-state side-effects) during
    /// high-frequency seeks.
    @State private var isScrubbing: Bool = false
    
    // Preview Video State
    @State private var previewPlayer: AVPlayer?
    @State private var isPreviewing = false
    @State private var isPressing = false
    @State private var hasInitializedDevices = false

    private var chromePillHeight: CGFloat { StashyExpandingDock.activeHeight }

    @Environment(\.verticalSizeClass) var verticalSizeClass

    /// Custom top chrome: Back · Identify (if no Stash-ID) · Download.
    @ViewBuilder
    private var sceneDetailNavBar: some View {
        StashySectionChromeBar {
            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                        Text("Back")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                    .modifier(StashyChromePillStyle(height: chromePillHeight))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer(minLength: 8)

                if !activeScene.hasStashID {
                    sceneIdentifyNavButton
                }
                sceneDownloadNavButton
            }
            .frame(minHeight: chromePillHeight)
            .padding(.horizontal, StashyExpandingDock.edgePadding)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var sceneIdentifyNavButton: some View {
        if isIdentifying {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(appearanceManager.tintColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(isIdentifying ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isIdentifying)
            }
            .frame(
                width: StashyExpandingDock.circleSize,
                height: StashyExpandingDock.circleSize
            )
            .accessibilityLabel("Identifying")
        } else {
            Button {
                startSceneIdentify()
            } label: {
                Image(systemName: "person.crop.square.filled.and.at.rectangle")
                    .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                    .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                    .frame(
                        width: StashyExpandingDock.circleSize,
                        height: StashyExpandingDock.circleSize
                    )
                    .background(StashyExpandingDock.inactiveBackground)
                    .clipShape(Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Identify scene")
        }
    }

    private func startSceneIdentify() {
        HapticManager.light()
        isIdentifying = true
        viewModel.triggerIdentify(sceneIDs: [activeScene.id]) { success, message, jobId in
            DispatchQueue.main.async {
                guard success else {
                    self.isIdentifying = false
                    ToastManager.shared.show(message, icon: "exclamationmark.triangle", style: .error)
                    return
                }

                guard let jobId, !jobId.isEmpty else {
                    // Started but no job id to track — stop spinner after short feedback.
                    self.isIdentifying = false
                    ToastManager.shared.show(message, icon: "checkmark.circle", style: .success)
                    return
                }

                self.viewModel.waitForJob(id: jobId) { jobSuccess, jobMessage in
                    DispatchQueue.main.async {
                        self.refreshSceneDetailsAfterIdentify(jobSuccess: jobSuccess, fallbackMessage: jobMessage)
                    }
                }
            }
        }
    }

    private func refreshSceneDetailsAfterIdentify(jobSuccess: Bool, fallbackMessage: String) {
        viewModel.fetchSceneDetails(sceneId: activeScene.id) { updatedScene in
            DispatchQueue.main.async {
                if let updated = updatedScene {
                    let preservedResumeTime = self.activeScene.resumeTime
                    let preservedStreams = self.activeScene.streams
                    var newScene = updated
                    if let resTime = preservedResumeTime, resTime > 0 {
                        newScene = newScene.withResumeTime(resTime)
                    }
                    if let streams = preservedStreams, !streams.isEmpty {
                        newScene = newScene.withStreams(streams)
                    }
                    newScene = newScene.withUpdatedAt(Scene.newerUpdatedAt(newScene.updatedAt, self.activeScene.updatedAt))
                    self.activeScene = newScene
                    self.activeScene.postListMetadataUpdated()
                }

                self.isIdentifying = false

                if !jobSuccess {
                    ToastManager.shared.show(fallbackMessage, icon: "exclamationmark.triangle", style: .error)
                } else if self.activeScene.hasStashID {
                    ToastManager.shared.show("Scene identified", icon: "checkmark.circle", style: .success)
                } else {
                    ToastManager.shared.show("Identify finished — no match", icon: "info.circle", style: .info)
                }
            }
        }
    }

    @ViewBuilder
    private var sceneDownloadNavButton: some View {
        if downloadManager.isDownloaded(id: activeScene.id) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                .foregroundColor(.green)
                .frame(
                    width: StashyExpandingDock.circleSize,
                    height: StashyExpandingDock.circleSize
                )
                .accessibilityLabel("Downloaded")
        } else if let activeDownload = downloadManager.activeDownloads[activeScene.id] {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 2.5)

                if activeDownload.totalSize > 0 {
                    Circle()
                        .trim(from: 0, to: activeDownload.progress)
                        .stroke(appearanceManager.tintColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear, value: activeDownload.progress)
                } else {
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(appearanceManager.tintColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(isDownloading ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isDownloading)
                        .onAppear { isDownloading = true }
                }
            }
            .frame(
                width: StashyExpandingDock.circleSize,
                height: StashyExpandingDock.circleSize
            )
            .accessibilityLabel("Downloading")
        } else {
            Button {
                HapticManager.light()
                downloadManager.downloadScene(activeScene)
            } label: {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                    .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                    .frame(
                        width: StashyExpandingDock.circleSize,
                        height: StashyExpandingDock.circleSize
                    )
                    .background(StashyExpandingDock.inactiveBackground)
                    .clipShape(Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save scene")
        }
    }

    // Extracted main content to use modular components
    private var mainContentView: some View {
        ScrollView {
            VStack(spacing: 12) {
                SceneVideoPlayerCard(
                    activeScene: $activeScene,
                    player: $player,
                    isPlaybackStarted: $isPlaybackStarted,
                    isFullscreen: $isFullscreen,
                    isPreviewing: $isPreviewing,
                    subtitleController: subtitleController,
                    transcriptionController: transcriptionController,
                    onSeek: { seconds in seekTo(seconds) },
                    onStartPlayback: { resume in startPlayback(resume: resume) }
                )

                SceneDetailMetadataCard(
                    activeScene: $activeScene,
                    player: $player,
                    isHeaderExpanded: $isHeaderExpanded,
                    showingAddMarkerSheet: $showingAddMarkerSheet,
                    capturedMarkerTime: $capturedMarkerTime,
                    playbackSpeed: $playbackSpeed,
                    viewModel: viewModel,
                    subtitleController: subtitleController,
                    transcriptionController: transcriptionController,
                    captionTranslator: captionTranslator,
                    audioTrackController: audioTrackController,
                    onSeek: { seconds in seekTo(seconds) },
                    onTitleUpdated: { newTitle, newDetails in
                        applyLocalSceneEdit(Scene(id: activeScene.id, title: newTitle, details: newDetails, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: activeScene.performers, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, streams: activeScene.streams, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                    }
                )

                // Live captions render inside AVPlayer overlay — no separate teleprompter panel.
                
                let isStashSyncActive = handyManager.isStashSyncMode || buttplugManager.isStashSyncMode || loveSpouseManager.isStashSyncMode
                let isStashSyncEnabled = StashSyncManager.shared.isStashSyncEnabled
                
                if activeScene.interactive == true && activeScene.funscriptURL != nil && !isStashSyncActive {
                    SceneHeatmapCard(
                        heatmapURL: activeScene.heatmapURL,
                        funscriptURL: activeScene.funscriptURL,
                        durationSeconds: activeScene.sceneDuration ?? 0,
                        currentTimeSeconds: currentPlaybackTime,
                        onSeek: { seconds in seekTo(seconds) },
                        onSeekCommit: { seconds in commitScrub(to: seconds) },
                        onScrubStateChange: { active in
                            isScrubbing = active
                            if active {
                                playbackActivityTracker.stop()
                            }
                        }
                    )
                }

                if isStashSyncEnabled {
                    StashSyncCard()
                }
                
                if verticalSizeClass == .compact {
                    // Landscape Mode: Grid Layout for Metadata
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 12) {

                        // Item 1: Performers (full scroll row, spans both columns)
                        ScenePerformersCard(
                            sceneId: activeScene.id,
                            sceneDate: activeScene.date,
                            performers: activeScene.performers,
                            onPerformersUpdated: { updated in
                                applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: updated, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, streams: activeScene.streams, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                            },
                            viewModel: viewModel
                        )
                        .gridCellColumns(2)

                        // Item 2: Studio
                        SceneStudioCard(
                            sceneId: activeScene.id,
                            studio: activeScene.studio,
                            onStudioUpdated: { updated in
                                applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, date: activeScene.date, duration: activeScene.duration, studio: updated, performers: activeScene.performers, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, streams: activeScene.streams, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                            },
                            viewModel: viewModel
                        )

                        // Item 3: Groups
                        SceneGroupsCard(
                            sceneId: activeScene.id,
                            groups: activeScene.groups ?? [],
                            onGroupsUpdated: { updated in
                                applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: activeScene.performers, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: updated, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, streams: activeScene.streams, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                            },
                            viewModel: viewModel
                        )

                        // Item 4: Galleries
                        if let galleries = activeScene.galleries, !galleries.isEmpty {
                            SceneGalleriesCard(galleries: galleries)
                        }

                        // Item 5: Tags — always visible
                        SceneTagsCard(
                            sceneId: activeScene.id,
                            tags: activeScene.tags,
                            onTagsUpdated: { updated in
                                applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: activeScene.performers, files: activeScene.files, tags: updated, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, streams: activeScene.streams, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                            },
                            viewModel: viewModel,
                            isTagsExpanded: $isTagsExpanded,
                            tagsTotalHeight: $tagsTotalHeight
                        )

                        // Item 6: Delete Button
                        Button(role: .destructive) {
                            showDeleteWithFilesConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Scene")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(appearanceManager.tintColor.opacity(0.15))
                            .foregroundColor(Color.pillAccent)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                        }
                    }
                } else {
                    // Portrait Mode: Vertical Stack
                    // Row 1: Performers (full width, horizontal scroll)
                    ScenePerformersCard(
                        sceneId: activeScene.id,
                        sceneDate: activeScene.date,
                        performers: activeScene.performers,
                        onPerformersUpdated: { updated in
                            applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: updated, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, streams: activeScene.streams, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                        },
                        viewModel: viewModel
                    )

                    // Row 2: Studio + Groups side by side
                    HStack(alignment: .top, spacing: 12) {
                        SceneStudioCard(
                            sceneId: activeScene.id,
                            studio: activeScene.studio,
                            onStudioUpdated: { updated in
                                applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, date: activeScene.date, duration: activeScene.duration, studio: updated, performers: activeScene.performers, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, streams: activeScene.streams, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                            },
                            viewModel: viewModel
                        )
                        SceneGroupsCard(
                            sceneId: activeScene.id,
                            groups: activeScene.groups ?? [],
                            onGroupsUpdated: { updated in
                                applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: activeScene.performers, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: updated, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, streams: activeScene.streams, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                            },
                            viewModel: viewModel
                        )
                    }

                    if let galleries = activeScene.galleries, !galleries.isEmpty {
                        SceneGalleriesCard(galleries: galleries)
                    }

                    // Row 3: Tags — always visible
                    SceneTagsCard(
                        sceneId: activeScene.id,
                        tags: activeScene.tags,
                        onTagsUpdated: { updated in
                            applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: activeScene.performers, files: activeScene.files, tags: updated, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, streams: activeScene.streams, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                        },
                        viewModel: viewModel,
                        isTagsExpanded: $isTagsExpanded,
                        tagsTotalHeight: $tagsTotalHeight
                    )

                    // Delete Scene Button (Card Style)
                    Button(role: .destructive) {
                        showDeleteWithFilesConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Scene")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(appearanceManager.tintColor.opacity(0.15))
                        .foregroundColor(Color.pillAccent)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }



    var body: some View {
        mainContentView
            .applyAppBackground()
            .hideSystemNavigationBarForCustomChrome()
            .enableSwipeBackWhenNavBarHidden()
            .stashyCustomChromeInset(spacing: 0) {
                sceneDetailNavBar
            }
            .modifier(SceneDetailAlertModifier(
                showDeleteConfirmation: $showDeleteWithFilesConfirmation,
                showingAddMarkerSheet: $showingAddMarkerSheet,
                title: activeScene.title ?? "Unknown Title",
                capturedMarkerTime: capturedMarkerTime,
                sceneId: activeScene.id,
                player: player,
                videoURL: activeScene.videoURL,
                viewModel: viewModel,
                onRefresh: refreshSceneDetails,
                onDelete: deleteSceneWithFiles
            ))
            .modifier(lifecycleModifier)
            // `TranslationSession` lives as long as the view carrying `translationTask`, and the
            // system download sheet is presented from it — so it sits on the detail root rather
            // than the player card, which is rebuilt around fullscreen transitions. A zero-sized
            // background host cannot present that sheet.
            .translationTask(captionTranslator.configuration) { session in
                await captionTranslator.run(session: session)
            }
            .onAppear {
                captionTranslator.onTranslated = { [weak transcriptionController] cueID, text in
                    transcriptionController?.applyTranslation(cueID: cueID, text: text)
                }
            }
    }

    private var lifecycleModifier: SceneDetailLifecycleModifier {
        SceneDetailLifecycleModifier(
            sceneId: activeScene.id,
            isMuted: $isMuted,
            player: player,
            onAppear: handleOnAppear,
            onDisappear: handleOnDisappear,
            onPeriodicSync: handlePeriodicSync,
            onRefreshMarkers: refreshSceneDetails,
            onInitialSync: initialSync,
            onEnsureAnalysis: ensureVideoAnalysis,
            onTimeControlChange: handleTimeControlStatusChange,
            handyManager: handyManager,
            buttplugManager: buttplugManager,
            loveSpouseManager: loveSpouseManager
        )
    }


    private func ensureVideoAnalysis(for item: AVPlayerItem?) {
        guard let item = item else { return }
        let needsForDevice = handyManager.isStashSyncMode || buttplugManager.isStashSyncMode || loveSpouseManager.isStashSyncMode
        if needsForDevice {
            print("🎬 SceneDetail: Ensuring Video Analysis for StashSync")
            StashVideoSyncManager.shared.setup(for: item)
            StashVideoSyncManager.shared.isActive = true
        }
    }
    
    private func initialSync() {
        guard let player = player, StashSyncManager.shared.isActive else { return }
                ensureVideoAnalysis(for: player.currentItem)
        
        if player.timeControlStatus == .playing {
            let currentTime = player.currentTime().seconds
            print("🎬 SceneDetail: Executing initial StashSync play at \(currentTime)s")
            if handyManager.isStashSyncMode { handyManager.play(at: currentTime) }
            if buttplugManager.isStashSyncMode { buttplugManager.play(at: currentTime) }
            if loveSpouseManager.isStashSyncMode { loveSpouseManager.play(at: currentTime) }
        }
    }

    private func refreshSceneDetails() {
        viewModel.fetchSceneDetails(sceneId: activeScene.id) { updatedScene in
            if let updated = updatedScene {
                DispatchQueue.main.async {
                    let preservedResumeTime = self.activeScene.resumeTime
                    let preservedStreams = self.activeScene.streams
                    var newScene = updated
                    if let resTime = preservedResumeTime, resTime > 0 {
                        newScene = newScene.withResumeTime(resTime)
                    }
                    if let streams = preservedStreams, !streams.isEmpty {
                        newScene = newScene.withStreams(streams)
                    }
                    newScene = newScene.withUpdatedAt(Scene.newerUpdatedAt(newScene.updatedAt, self.activeScene.updatedAt))
                    self.activeScene = newScene
                    self.configureSubtitles()
                }
            }
        }
    }

    private func handleOnAppear() {
        print("🔍 Scene Detail: ID=\(activeScene.id), PlayCount=\(activeScene.playCount ?? -1)")
        isFullscreen = false
        
        // Reset all SYNC states only on very first appear - WE WANT MANUAL ACTIVATION
        if !hasInitializedDevices {
            handyManager.isSyncing = false
            handyManager.isStashSyncMode = false
            buttplugManager.isStashSyncMode = false
            buttplugManager.isSyncing = false
            loveSpouseManager.isStashSyncMode = false
            loveSpouseManager.isSyncing = false
            hasInitializedDevices = true
        }
        
        if activeScene.streams?.isEmpty ?? true {
            viewModel.fetchSceneStreams(sceneId: activeScene.id) { streams in
                if !streams.isEmpty {
                    DispatchQueue.main.async {
                        self.activeScene = self.activeScene.withStreams(streams)
                        self.updatePlayerStream()
                    }
                }
            }
        }
        
        if activeScene.performers.isEmpty || (activeScene.tags?.isEmpty ?? true) || activeScene.groups == nil || activeScene.sceneMarkers == nil || activeScene.captions == nil {
            viewModel.fetchSceneDetails(sceneId: activeScene.id) { updatedScene in
                if let updated = updatedScene {
                    DispatchQueue.main.async {
                        let preservedResumeTime = self.activeScene.resumeTime
                        var newScene = updated.withStreams(self.activeScene.streams)
                        if let resTime = preservedResumeTime, resTime > 0 {
                            newScene = newScene.withResumeTime(resTime)
                        }
                        newScene = newScene.withUpdatedAt(Scene.newerUpdatedAt(newScene.updatedAt, self.activeScene.updatedAt))
                        self.activeScene = newScene
                        self.configureSubtitles()
                    }
                }
            }
        } else {
            configureSubtitles()
        }
        
        // Removed automatic setupScene to enforce manual activation unless explicitly requested via autoPlay
        if autoPlay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if !isPlaybackStarted { 
                    startPlayback(resume: true) 
                }
            }
        }
    }

    private func configureSubtitles() {
        subtitleController.configure(scene: activeScene, player: player)
    }

    private func handleOnDisappear() {
        if isDeleting {
            player?.pause()
            stopPreview()
            return
        }

        stopPreview()

        // Fullscreen presentation can fire onDisappear before `isFullscreen` flips.
        // Defer teardown so we don't kill live CC / pause while entering fullscreen.
        DispatchQueue.main.async {
            self.finishDisappearTeardown()
        }
    }

    private func finishDisappearTeardown() {
        if isDeleting { return }

        // Always persist resume/play duration, including when this view only
        // disappears because native fullscreen hid it.
        persistPlaybackActivity(stopTracking: !isFullscreen)

        if isFullscreen { return }

        activeScene.postListMetadataUpdated()

        player?.pause()
        StashSyncManager.shared.stop()
        if handyManager.isSyncing || handyManager.isStashSyncMode { handyManager.pause() }
        if buttplugManager.isConnected { buttplugManager.stop() }
        if loveSpouseManager.isConnected { loveSpouseManager.stop() }
        removeTimeObserver()
        subtitleController.detach()
        audioTrackController.detach()
        captionTranslator.deactivate()
        Task { await transcriptionController.disable() }
    }

    private func persistPlaybackActivity(stopTracking: Bool) {
        if let player {
            let currentTime = player.currentTime().seconds
            let duration = player.currentItem?.duration.seconds ?? activeScene.sceneDuration ?? 0
            if currentTime.isFinite, currentTime >= 0 {
                playbackActivityTracker.setPosition(currentTime: currentTime, duration: duration)
            }
        }
        ensurePlaybackActivityConfigured()
        if stopTracking {
            playbackActivityTracker.stop()
        } else {
            playbackActivityTracker.flush()
        }
    }

    private func handlePeriodicSync() {
        if isDeleting { return }
        if let player = player, player.timeControlStatus == .playing {
            let currentTime = player.currentTime().seconds
            let duration = player.currentItem?.duration.seconds ?? activeScene.sceneDuration ?? 0
            playbackActivityTracker.setPosition(currentTime: currentTime, duration: duration)
            ensurePlaybackActivityConfigured()
            playbackActivityTracker.start()
            if !hasAddedPlay, currentTime > 1 {
                registerScenePlay()
            }
        }
    }

    private func ensurePlaybackActivityConfigured() {
        let sceneId = activeScene.id
        let vm = viewModel
        playbackActivityTracker.updatesResumeTime = true
        playbackActivityTracker.onSave = { resumeTime, playDuration in
            vm.updateSceneResumeTime(
                sceneId: sceneId,
                resumeTime: resumeTime,
                playDuration: playDuration
            ) { success in
                guard success, let resumeTime else { return }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SceneResumeTimeUpdated"),
                        object: nil,
                        userInfo: ["sceneId": sceneId, "resumeTime": resumeTime]
                    )
                }
            }
        }
    }

    private func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus) {
        guard let player = player else { return }
        // Scrubbing produces rapid play → waitingToPlay → playing transitions.
        // Running the full sync-restart below each time is expensive (Bluetooth
        // round-trips, StashSyncManager restart, video analysis). Skip while
        // the user is actively dragging; `commitScrub` handles the resume.
        if isScrubbing { return }
        let currentTime = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? activeScene.sceneDuration ?? 0
        playbackActivityTracker.setPosition(currentTime: currentTime, duration: duration)
        ensurePlaybackActivityConfigured()

        if status == .paused {
            playbackActivityTracker.stop()
            StashSyncManager.shared.stop()
            if handyManager.isSyncing || handyManager.isStashSyncMode { handyManager.pause() }
            if buttplugManager.isSyncing || buttplugManager.isStashSyncMode { buttplugManager.pause() }
            if loveSpouseManager.isSyncing || loveSpouseManager.isStashSyncMode { loveSpouseManager.pause() }
        } else if status == .playing {
            playbackActivityTracker.start()
            if audioTrackController.tracks.isEmpty {
                audioTrackController.attach(player: player)
            }
            ensureVideoAnalysis(for: player.currentItem)
            let stashSyncActive = handyManager.isStashSyncMode || buttplugManager.isStashSyncMode || loveSpouseManager.isStashSyncMode
            if stashSyncActive { StashSyncManager.shared.start() }
            if handyManager.isSyncing || handyManager.isStashSyncMode { handyManager.play(at: currentTime) }
            if buttplugManager.isSyncing || buttplugManager.isStashSyncMode { buttplugManager.play(at: currentTime) }
            if loveSpouseManager.isSyncing || loveSpouseManager.isStashSyncMode { loveSpouseManager.play(at: currentTime) }
        }
    }

    /// Updates local Scene Detail state and notifies catalog lists (title, studio, tags, …).
    private func applyLocalSceneEdit(_ updated: Scene) {
        activeScene = updated
        updated.postListMetadataUpdated()
    }

    private func startPlayback(resume: Bool) {
        guard let videoURL = activeScene.videoURL else { return }

        if player == nil {
            print("🎬 Player initializing with URL: \(redactedURLString(videoURL))")
            player = createPlayer(for: videoURL)
            player?.isMuted = isMuted
            addTimeObserverIfNeeded()
            configureSubtitles()

            if resume, let resumeTime = activeScene.resumeTime, resumeTime > 0 {
                let targetTime = CMTime(seconds: resumeTime, preferredTimescale: 600)
                player?.seek(to: targetTime)
            }
        } else if resume, let resumeTime = activeScene.resumeTime, resumeTime > 0 {
             let targetTime = CMTime(seconds: resumeTime, preferredTimescale: 600)
             player?.seek(to: targetTime)
        }
        
        withAnimation {
            isPlaybackStarted = true
        }
        player?.play()
        subtitleController.attach(player: player)
        audioTrackController.attach(player: player)
        if handyManager.isSyncing {
            handyManager.play(at: player?.currentTime().seconds ?? 0)
        }
        if buttplugManager.isConnected {
            buttplugManager.play(at: player?.currentTime().seconds ?? 0)
        }
        if loveSpouseManager.isSyncing {
            loveSpouseManager.play(at: player?.currentTime().seconds ?? 0)
        }
        player?.rate = Float(playbackSpeed)
        ensurePlaybackActivityConfigured()
        playbackActivityTracker.start()
        
        if !hasAddedPlay {
            registerScenePlay()
        }
    }

    private func addTimeObserverIfNeeded() {
        guard timeObserverToken == nil, let player = player else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            Task { @MainActor in
                if seconds >= 0 {
                    currentPlaybackTime = seconds
                    let duration = player.currentItem?.duration.seconds ?? activeScene.sceneDuration ?? 0
                    playbackActivityTracker.setPosition(currentTime: seconds, duration: duration)
                    if player.timeControlStatus == .playing {
                        ensurePlaybackActivityConfigured()
                        playbackActivityTracker.start()
                    }
                }
                if !hasAddedPlay, seconds > 1 {
                    registerScenePlay()
                }
            }
        }
    }

    private func registerScenePlay() {
        viewModel.addScenePlay(sceneId: activeScene.id)
        hasAddedPlay = true
        NotificationCenter.default.post(
            name: NSNotification.Name("ScenePlayAdded"),
            object: nil,
            userInfo: ["sceneId": activeScene.id]
        )
    }

    private func removeTimeObserver() {
        guard let token = timeObserverToken, let player = player else { return }
        player.removeTimeObserver(token)
        timeObserverToken = nil
    }

    private func deleteSceneWithFiles() {
        isDeleting = true
        viewModel.deleteSceneWithFiles(scene: activeScene) { success in
            if success {
                print("🎉 Scene and files completely removed!")
                ToastManager.shared.show("Scene deleted", icon: "trash", style: .success)
                self.dismiss()
            } else {
                isDeleting = false
                ToastManager.shared.show("Failed to delete scene", icon: "exclamationmark.triangle", style: .error)
                print("❌ Failed to delete scene or files")
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    private func startPreview() {
        guard let previewURL = activeScene.previewURL else { return }
        
        if previewPlayer == nil {
            previewPlayer = createMutedPreviewPlayer(for: previewURL)
        }
        
        withAnimation(.easeIn(duration: 0.2)) {
            isPreviewing = true
        }
        previewPlayer?.play()
    }
    
    private func stopPreview() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPreviewing = false
        }
        previewPlayer?.pause()
        previewPlayer?.seek(to: .zero)
    }
    
    private func seekTo(_ seconds: Double) {
        if !isPlaybackStarted {
            startPlayback(resume: false)
        }

        // Switch to scrub-buffer once when scrubbing begins so AVPlayer
        // can react to repeated seeks without re-buffering 6+ seconds.
        if isScrubbing, let item = player?.currentItem {
            configureForVOD(item, isScrubbing: true)
        }

        let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
        // Keyframe-tolerant seeks are dramatically faster on HLS / transcoded
        // streams because AVPlayer can snap to the nearest I-frame instead of
        // forcing the server to re-encode up to the exact frame.
        player?.seek(to: targetTime, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
        playbackActivityTracker.noteSeek(to: seconds)

        // While actively scrubbing we don't kick device-syncs on every micro-seek
        // (that explodes network/Bluetooth traffic). Final commit happens on
        // drag end via `commitScrub(to:)`.
        guard !isScrubbing else { return }
        player?.play()
        if handyManager.isSyncing {
            handyManager.play(at: seconds)
        }
        if buttplugManager.isConnected {
            buttplugManager.play(at: seconds)
        }
        if loveSpouseManager.isSyncing {
            loveSpouseManager.play(at: seconds)
        }
    }

    /// Called from the heatmap scrubber when the user releases the drag.
    /// Does the final accurate seek + sync resume.
    private func commitScrub(to seconds: Double) {
        // Restore the steady-state forward buffer for stable playback.
        if let item = player?.currentItem {
            configureForVOD(item, isScrubbing: false)
        }
        let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
        // Final commit should be precise; only intermediate drag seeks are
        // keyframe-tolerant for responsiveness.
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        playbackActivityTracker.noteSeek(to: seconds)
        player?.play()
        if handyManager.isSyncing { handyManager.play(at: seconds) }
        if buttplugManager.isConnected { buttplugManager.play(at: seconds) }
        if loveSpouseManager.isSyncing { loveSpouseManager.play(at: seconds) }
    }

    private func infoPill(icon: String, text: String, color: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color ?? Color.pillAccent)
            Text(text)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            ZStack {
                Color.appBackground
                (color ?? appearanceManager.tintColor).opacity(0.15)
            }
        )
        .clipShape(Capsule())
        .overlay(Capsule().stroke((color ?? appearanceManager.tintColor).opacity(0.4), lineWidth: 0.5))
    }
    
    /// Updates the player if a better stream becomes available (e.g. replacing an incompatible MKV fallback with a transcoded MP4).
    /// Uses the central `makeVODPlayerItem` helper so buffering, headers and apikey-signing stay consistent with `qualityMenu` switches.
    private func updatePlayerStream() {
        guard let currentAsset = player?.currentItem?.asset as? AVURLAsset else { return }
        guard let newURL = activeScene.videoURL else { return }

        if currentAsset.url.absoluteString == newURL.absoluteString { return }

        let oldIsFallback = currentAsset.url.pathExtension.lowercased() == "mkv"
        let newIsStream = newURL.pathExtension.lowercased() == "mp4" || newURL.absoluteString.contains("/stream")
        guard oldIsFallback || newIsStream else { return }

        print("♻️ Upgrading stream from \(currentAsset.url.lastPathComponent) to \(newURL.lastPathComponent)…")

        let currentTime = player?.currentTime() ?? .zero
        let wasPlaying = (player?.rate ?? 0) > 0

        let item = makeVODPlayerItem(for: newURL)
        player?.replaceCurrentItem(with: item)
        audioTrackController.attach(player: player)
        if currentTime > .zero {
            player?.seek(to: currentTime, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
        }
        if wasPlaying || isPlaybackStarted {
            player?.play()
        }
        StashVideoSyncManager.shared.setup(for: item)
    }
}

// Extensions for Scene conversion

// Extend Scene to include videoURL computed property
// REMOVED: Now in StashDBViewModel.swift

// Extension to convert ScenePerformer to Performer for navigation
extension ScenePerformer {
    func toPerformer() -> Performer {
        return Performer(
            id: self.id,
            name: self.name,
            disambiguation: nil,
            birthdate: self.birthdate,
            country: nil,
            imagePath: nil,
            sceneCount: self.sceneCount ?? 0,
            galleryCount: self.galleryCount ?? 0,
            gender: nil,
            ethnicity: nil,
            height: nil,
            weight: nil,
            measurements: nil,
            fakeTits: nil,
            penis_length: nil,
            careerLength: nil,
            tattoos: nil,
            piercings: nil,
            aliasList: nil,
            favorite: nil,
            rating100: nil,
            createdAt: nil,
            updatedAt: nil,
            oCounter: nil
        )
    }
}

// Extension to convert SceneStudio to Studio for navigation
extension SceneStudio {
    func toStudio() -> Studio {
        return Studio(
            id: self.id,
            name: self.name,
            url: nil,
            sceneCount: 0,
            performerCount: nil,
            galleryCount: nil,
            details: nil,
            imagePath: nil,
            favorite: nil,
            rating100: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }
}

struct AddMarkerSheet: View {
    let sceneId: String
    let seconds: Double
    /// Used to capture a still at the marker start (same path as Scene Cover).
    let player: AVPlayer?
    let videoURL: URL?
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: () -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    @State private var title: String = ""
    @State private var primaryTagId: String = ""
    @State private var tags: [Tag] = []
    @State private var searchText: String = ""
    @State private var isCreating = false
    @State private var isLoadingTags = false
    @State private var endTimeString: String = ""
    
    var filteredTags: [Tag] {
        if searchText.isEmpty {
            return tags
        } else {
            return tags.filter { $0.name.lowercased().contains(searchText.lowercased()) }
        }
    }
    
    private var canAddMarker: Bool {
        !title.isEmpty && !primaryTagId.isEmpty && !isCreating
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Marker Details")) {
                    TextField("Name", text: $title)
                    HStack {
                        Text("Start Time:")
                        Spacer()
                        Text(formatTime(seconds))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("End Time (optional):")
                        Spacer()
                        TextField("Seconds or MM:SS", text: $endTimeString)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section(header: Text("Primary Tag")) {
                    TextField("Search Tags...", text: $searchText)

                    if isLoadingTags {
                        HStack {
                            Spacer()
                            ProgressView("Loading tags...")
                            Spacer()
                        }
                        .padding()
                    } else if tags.isEmpty {
                        Text("No tags found on server")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(filteredTags.prefix(20), id: \.id) { tag in
                            HStack {
                                Text(tag.name)
                                if let count = tag.sceneCount {
                                    Spacer()
                                    Text("\(count)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if primaryTagId == tag.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(appearanceManager.tintColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                primaryTagId = tag.id
                                if title.isEmpty {
                                    title = tag.name
                                }
                            }
                        }

                        if filteredTags.count > 20 {
                            Text("Type more to refine search...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if !searchText.isEmpty && filteredTags.isEmpty {
                            Text("No tags match '\(searchText)'")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome("Add Marker", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(
                    title: "Add",
                    enabled: canAddMarker,
                    isBusy: isCreating
                ) {
                    createMarker()
                }
            }
            .onAppear {
                isLoadingTags = true
                viewModel.fetchAllTags { fetchedTags in
                    DispatchQueue.main.async {
                        self.tags = fetchedTags
                        self.isLoadingTags = false
                    }
                }
            }
        }
    }
    
    private func createMarker() {
        isCreating = true
        let endSeconds = parseTime(endTimeString)
        let captureTime = CMTime(seconds: max(0, seconds), preferredTimescale: 600)

        Task { @MainActor in
            // Capture start-frame still like Scene Cover (instant local thumb).
            let frameDataURL = await captureVideoFrameDataURL(
                from: player,
                fallbackURL: videoURL,
                at: captureTime
            )

            viewModel.createSceneMarker(
                sceneId: sceneId,
                title: title,
                seconds: seconds,
                endSeconds: endSeconds,
                primaryTagId: primaryTagId
            ) { success, createdMarker in
                DispatchQueue.main.async {
                    self.isCreating = false
                    guard success, let createdMarker else { return }

                    if let frameDataURL {
                        self.seedMarkerThumbnailCache(marker: createdMarker, dataURL: frameDataURL)
                    }

                    self.onComplete()
                    self.dismiss()

                    // Persist on the server: Stash has no marker image upload field
                    // (unlike scene `cover_image`), so generate the still at start time.
                    // Must scope by sceneIDs so Stash creates `generated/markers/<hash>/`.
                    self.viewModel.generateMarkerScreenshots(sceneId: self.sceneId) { genStarted, jobId in
                        guard genStarted else {
                            print("⚠️ Marker screenshot generate failed to start for scene \(self.sceneId)")
                            return
                        }
                        let finish: (Bool) -> Void = { success in
                            DispatchQueue.main.async {
                                guard success else { return }
                                ImageCache.shared.invalidateMarkerScreenshot(
                                    markerId: createdMarker.id,
                                    sceneId: self.sceneId,
                                    screenshotPath: createdMarker.screenshot
                                )
                                self.onComplete()
                            }
                        }
                        guard let jobId, !jobId.isEmpty else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                finish(true)
                            }
                            return
                        }
                        self.viewModel.waitForJob(id: jobId, timeout: 120) { jobSuccess, message in
                            if !jobSuccess {
                                print("⚠️ Marker screenshot generate job failed: \(message)")
                            }
                            finish(jobSuccess)
                        }
                    }
                }
            }
        }
    }

    /// Seeds memory/disk cache so the marker strip shows the captured frame immediately.
    private func seedMarkerThumbnailCache(marker: SceneMarker, dataURL: String) {
        guard let comma = dataURL.firstIndex(of: ","),
              let jpeg = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
              let config = ServerConfigManager.shared.activeConfig ?? ServerConfigManager.shared.loadConfig(),
              config.hasValidConfig
        else { return }

        var urls = [
            "\(config.baseURL)/scenemarker/\(marker.id)/screenshot",
            "\(config.baseURL)/scene/\(sceneId)/scene_marker/\(marker.id)/screenshot"
        ]
        if let screenshot = marker.screenshot, !screenshot.isEmpty {
            urls.append(screenshot)
        }
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            ImageCache.shared.setData(jpeg, forKey: url as NSURL)
        }
    }
    
    private func parseTime(_ timeString: String) -> Double? {
        if timeString.isEmpty { return nil }
        
        // Try direct double first
        if let s = Double(timeString) { return s }
        
        // Try MM:SS or HH:MM:SS
        let components = timeString.split(separator: ":").compactMap { Double($0) }.reversed()
        var total: Double = 0
        var multiplier: Double = 1
        
        for component in components {
            total += component * multiplier
            multiplier *= 60
        }
        
        return total > 0 ? total : nil
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "00:00"
    }
}


// MARK: - Alert + Sheet Modifier (splits body chain to help type-checker)

private struct SceneDetailAlertModifier: ViewModifier {
    @Binding var showDeleteConfirmation: Bool
    @Binding var showingAddMarkerSheet: Bool
    let title:              String
    let capturedMarkerTime: Double
    let sceneId:            String
    let player:             AVPlayer?
    let videoURL:           URL?
    let viewModel:          StashDBViewModel
    let onRefresh:          () -> Void
    let onDelete:           () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Really delete scene and files?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { onDelete() }
            } message: {
                Text("The scene '\(title)' and all associated files will be permanently deleted. This action cannot be undone.")
            }
            .sheet(isPresented: $showingAddMarkerSheet) {
                AddMarkerSheet(
                    sceneId: sceneId,
                    seconds: capturedMarkerTime,
                    player: player,
                    videoURL: videoURL,
                    viewModel: viewModel
                ) {
                    onRefresh()
                }
            }
    }
}

// MARK: - Lifecycle Modifier

private struct SceneDetailLifecycleModifier: ViewModifier {
    let sceneId:           String
    @Binding var isMuted:  Bool
    let player:            AVPlayer?
    let onAppear:          () -> Void
    let onDisappear:       () -> Void
    let onPeriodicSync:    () -> Void
    let onRefreshMarkers:  () -> Void
    let onInitialSync:     () -> Void
    let onEnsureAnalysis:  (AVPlayerItem?) -> Void
    let onTimeControlChange: (AVPlayer.TimeControlStatus) -> Void
    let handyManager:      HandyManager
    let buttplugManager:   ButtplugManager
    let loveSpouseManager: LoveSpouseManager

    func body(content: Content) -> some View {
        content
            .onAppear { onAppear() }
            .onDisappear { onDisappear() }
            .onChange(of: isMuted) { _, v in
                player?.isMuted = v
                ScenePlayerMute.persist(v)
            }
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in onPeriodicSync() }
            // The 0.5s fallback timer was removed — `addPeriodicTimeObserver`
            // (in SceneDetailView) publishes time at 0.25s already.
            .onChange(of: StashSyncManager.shared.isActive) { _, active in if active { onInitialSync() } }
            .overlay(playerOverlay)
    }

    @ViewBuilder
    private var playerOverlay: some View {
        if let player {
            Color.clear
                .onReceive(player.publisher(for: \.isMuted)) { muted in
                    if muted != isMuted {
                        isMuted = muted
                    }
                }
                .onReceive(player.publisher(for: \.timeControlStatus)) { status in
                    onTimeControlChange(status)
                }
                .onReceive(player.publisher(for: \.status)) { _ in }
                .onChange(of: player.currentItem) { _, item in onEnsureAnalysis(item) }
                .onChange(of: handyManager.isStashSyncMode) { _, on in
                    if on { onEnsureAnalysis(player.currentItem); onInitialSync() }
                }
                .onChange(of: buttplugManager.isStashSyncMode) { _, on in
                    if on { onEnsureAnalysis(player.currentItem); onInitialSync() }
                }
                .onChange(of: loveSpouseManager.isStashSyncMode) { _, on in
                    if on { onEnsureAnalysis(player.currentItem); onInitialSync() }
                }
        }
    }
}

#endif
