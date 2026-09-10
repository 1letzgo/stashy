//
//  SceneDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI
import AVFoundation
import WebKit
import Combine
import Translation

struct SceneDetailView: View {
    let scene: Scene
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var activeScene: Scene
    // `@StateObject`: als `@ObservedObject` mit Inline-Initializer entstand bei jedem
    // Neuaufbau der Struct ein weiteres 12k-Zeilen-ViewModel samt Observern.
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var handyManager = HandyManager.shared
    @ObservedObject var buttplugManager = ButtplugManager.shared
    @ObservedObject var loveSpouseManager = LoveSpouseManager.shared
    @ObservedObject private var stashSyncManager = StashSyncManager.shared
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @StateObject private var subtitleController = SubtitleController()
    @StateObject private var transcriptionController = SceneLiveTranscriptionController()
    @StateObject private var captionTranslator = SceneCaptionTranslator()
    
    let autoPlay: Bool
    
    init(scene: Scene, autoPlay: Bool = false) {
        self.scene = scene
        self.autoPlay = autoPlay
        _activeScene = State(initialValue: scene)
    }
    /// The one player. Non-nil from the first `startPlayback` until teardown.
    @State private var aetherEngine: AetherSceneEngine?
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
    /// The transcode-fallback toast is shown once per screen, not once per rung.
    @State private var didAnnounceTranscodeFallback = false
    @State private var showingAddMarkerSheet = false
    @State private var capturedMarkerTime: Double = 0
    @State private var playbackSpeed: Double = 1.0
    @State private var currentPlaybackTime: Double = 0
    @State private var playbackActivityTracker = ScenePlaybackActivityTracker()
    /// True while the user is actively dragging the heatmap scrubber. Used to
    /// suppress redundant work (sync restarts, play-state side-effects) during
    /// high-frequency seeks.
    @State private var isScrubbing: Bool = false
    /// Coalesces scrub seeks on the engine: one in-flight seek, latest target wins.
    @State private var pendingAetherSeek: Double?
    @State private var aetherSeekInFlight = false
    
    // Preview Video State
    @State private var isPreviewing = false
    @State private var isPressing = false
    @State private var hasInitializedDevices = false

    private var chromePillHeight: CGFloat { StashyExpandingDock.activeHeight }

    @Environment(\.verticalSizeClass) var verticalSizeClass

    /// Shared detail chrome: `sceneDetailNavBar` renders the actual bar content.
    private var sceneDetailChromeConfig: StashyDetailChromeConfig {
        StashyDetailChromeConfig(insetSpacing: 0)
    }

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
                    var newScene = updated
                    if let resTime = preservedResumeTime, resTime > 0 {
                        newScene = newScene.withResumeTime(resTime)
                    }
                    newScene = newScene.withUpdatedAt(Scene.newerUpdatedAt(newScene.updatedAt, self.activeScene.updatedAt))
                    self.activeScene = newScene
                    self.activeScene.postListMetadataUpdated()

                    if jobSuccess {
                        // Identify usually replaces the cover, but the cache key strips the
                        // timestamp — so bust like "Set as cover" does: the cache drops the
                        // stale screenshot, loaders refetch, lists patch their thumbnails.
                        let bust = String(Int(Date().timeIntervalSince1970 * 1000))
                        self.activeScene = self.activeScene.withUpdatedAt(bust)
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SceneCoverUpdated"),
                            object: nil,
                            userInfo: [
                                "sceneId": self.activeScene.id,
                                "updatedAt": bust,
                                "screenshotPath": self.activeScene.paths?.screenshot as Any
                            ]
                        )
                    }
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
        // The reader sits *outside* the ScrollView, so it reports the space available to the
        // view rather than the width its own content ended up needing.
        GeometryReader { proxy in
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    SceneVideoPlayerCard(
                        activeScene: $activeScene,
                        aetherEngine: aetherEngine,
                        isPlaybackStarted: $isPlaybackStarted,
                        isFullscreen: $isFullscreen,
                        isPreviewing: $isPreviewing,
                        isMuted: $isMuted,
                        subtitleController: subtitleController,
                        transcriptionController: transcriptionController,
                        onSeek: { seconds in seekTo(seconds) },
                        onStartPlayback: { resume in startPlayback(resume: resume) }
                    )

                    SceneDetailMetadataCard(
                        activeScene: $activeScene,
                        aetherEngine: aetherEngine,
                        isHeaderExpanded: $isHeaderExpanded,
                        showingAddMarkerSheet: $showingAddMarkerSheet,
                        capturedMarkerTime: $capturedMarkerTime,
                        playbackSpeed: $playbackSpeed,
                        viewModel: viewModel,
                        subtitleController: subtitleController,
                        transcriptionController: transcriptionController,
                        captionTranslator: captionTranslator,
                        onSeek: { seconds in seekTo(seconds) },
                        onTitleUpdated: { newTitle, newDetails in
                            applyLocalSceneEdit(Scene(id: activeScene.id, title: newTitle, details: newDetails, director: activeScene.director, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: activeScene.performers, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                        }
                    )
                }
                .background(Color.secondaryAppBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                .cardShadow()

                
                let isStashSyncActive = handyManager.isStashSyncMode || buttplugManager.isStashSyncMode || loveSpouseManager.isStashSyncMode
                
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

                if stashSyncManager.isSyncing {
                    StashSyncCard()
                }
                
                if verticalSizeClass == .compact {
                    // Landscape Mode: Grid Layout for Metadata
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 12) {

                        // stashy+ — hides itself when Suggestions is off or nothing is similar.
                        SceneSimilarScenesCard(scene: activeScene)
                            .gridCellColumns(2)

                        // Item 1: Performers (+ Director, full scroll row, spans both columns)
                        ScenePerformersCard(
                            sceneId: activeScene.id,
                            sceneDate: activeScene.date,
                            performers: activeScene.performers,
                            director: activeScene.normalizedDirector,
                            onPerformersUpdated: { updated in
                                applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, director: activeScene.director, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: updated, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                            },
                            viewModel: viewModel
                        )
                        .gridCellColumns(2)

                        // Item 2: Studio
                        SceneStudioCard(
                            sceneId: activeScene.id,
                            studio: activeScene.studio,
                            onStudioUpdated: { updated in
                                applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, director: activeScene.director, date: activeScene.date, duration: activeScene.duration, studio: updated, performers: activeScene.performers, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                            },
                            viewModel: viewModel
                        )

                        // Item 3: Groups
                        SceneGroupsCard(
                            sceneId: activeScene.id,
                            groups: activeScene.groups ?? [],
                            onGroupsUpdated: { updated in
                                applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, director: activeScene.director, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: activeScene.performers, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: updated, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                            },
                            viewModel: viewModel
                        )

                        // Item 4: Tags — always visible
                        SceneTagsCard(
                            sceneId: activeScene.id,
                            tags: activeScene.tags,
                            onTagsUpdated: { updated in
                                applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, director: activeScene.director, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: activeScene.performers, files: activeScene.files, tags: updated, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                            },
                            viewModel: viewModel,
                            isTagsExpanded: $isTagsExpanded,
                            tagsTotalHeight: $tagsTotalHeight
                        )

                        // Item 5: Galleries — always visible (full width)
                        SceneGalleriesCard(
                            sceneId: activeScene.id,
                            galleries: activeScene.galleries,
                            performers: activeScene.performers,
                            onGalleriesUpdated: { updated in
                                applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, director: activeScene.director, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: activeScene.performers, files: activeScene.files, tags: activeScene.tags, galleries: updated, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                            },
                            viewModel: viewModel
                        )
                        .gridCellColumns(2)

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
                    // stashy+ — hides itself when Suggestions is off or nothing is similar.
                    SceneSimilarScenesCard(scene: activeScene)

                    // Row 1: Performers (+ Director, full width, horizontal scroll)
                    ScenePerformersCard(
                        sceneId: activeScene.id,
                        sceneDate: activeScene.date,
                        performers: activeScene.performers,
                        director: activeScene.normalizedDirector,
                        onPerformersUpdated: { updated in
                            applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, director: activeScene.director, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: updated, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                        },
                        viewModel: viewModel
                    )

                    // Row 2: Studio + Groups side by side
                    HStack(alignment: .top, spacing: 12) {
                        SceneStudioCard(
                            sceneId: activeScene.id,
                            studio: activeScene.studio,
                            onStudioUpdated: { updated in
                                applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, director: activeScene.director, date: activeScene.date, duration: activeScene.duration, studio: updated, performers: activeScene.performers, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                            },
                            viewModel: viewModel
                        )
                        SceneGroupsCard(
                            sceneId: activeScene.id,
                            groups: activeScene.groups ?? [],
                            onGroupsUpdated: { updated in
                                applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, director: activeScene.director, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: activeScene.performers, files: activeScene.files, tags: activeScene.tags, galleries: activeScene.galleries, groups: updated, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                            },
                            viewModel: viewModel
                        )
                    }

                    // Row 3: Tags — always visible
                    SceneTagsCard(
                        sceneId: activeScene.id,
                        tags: activeScene.tags,
                        onTagsUpdated: { updated in
                            applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, director: activeScene.director, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: activeScene.performers, files: activeScene.files, tags: updated, galleries: activeScene.galleries, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                        },
                        viewModel: viewModel,
                        isTagsExpanded: $isTagsExpanded,
                        tagsTotalHeight: $tagsTotalHeight
                    )

                    // Row 4: Galleries — always visible
                    SceneGalleriesCard(
                        sceneId: activeScene.id,
                        galleries: activeScene.galleries,
                        performers: activeScene.performers,
                        onGalleriesUpdated: { updated in
                            applyLocalSceneEdit(Scene(id: activeScene.id, title: activeScene.title, details: activeScene.details, director: activeScene.director, date: activeScene.date, duration: activeScene.duration, studio: activeScene.studio, performers: activeScene.performers, files: activeScene.files, tags: activeScene.tags, galleries: updated, groups: activeScene.groups, organized: activeScene.organized, resumeTime: activeScene.resumeTime, playCount: activeScene.playCount, oCounter: activeScene.oCounter, rating100: activeScene.rating100, createdAt: activeScene.createdAt, updatedAt: activeScene.updatedAt, paths: activeScene.paths, sceneMarkers: activeScene.sceneMarkers, interactive: activeScene.interactive, stashIds: activeScene.stashIds, captions: activeScene.captions, customFields: activeScene.customFields))
                        },
                        viewModel: viewModel
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
            // Pins the content to the viewport width. Without this a single unbreakable
            // string (long file-name title, URL in the details) grows the scroll content
            // sideways, and the horizontal drag then pans the cards instead of triggering
            // the interactive back gesture. `containerRelativeFrame` looked right but
            // reported half the width in landscape, where the size class turns regular.
            .frame(width: proxy.size.width)
        }
        }
    }



    var body: some View {
        mainContentView
            .applyAppBackground()
            .stashyDetailChrome(sceneDetailChromeConfig) {
                sceneDetailNavBar
            }
            .modifier(SceneDetailAlertModifier(
                showDeleteConfirmation: $showDeleteWithFilesConfirmation,
                showingAddMarkerSheet: $showingAddMarkerSheet,
                title: activeScene.displayTitle ?? "Unknown Title",
                capturedMarkerTime: capturedMarkerTime,
                sceneId: activeScene.id,
                sceneTagIds: Set((activeScene.tags ?? []).map(\.id)),
                videoURL: activeScene.aetherVideoURL,
                aetherEngine: aetherEngine,
                viewModel: viewModel,
                onRefresh: refreshSceneDetails,
                onDelete: deleteSceneWithFiles
            ))
            .modifier(lifecycleModifier)
            .fullScreenCover(isPresented: $isFullscreen) {
                fullscreenPlayer
            }
            .onChange(of: playbackSpeed) { _, speed in
                aetherEngine?.rate = Float(speed)
            }
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
            // Similar Scenes is loaded by the detail view for the scene it is showing, not by the
            // card for itself. Keyed on the metadata, so it runs again once `fetchSceneDetails`
            // replaces the slim list version of the scene with the full one.
            .task(id: SimilarScenesFinder.signature(for: activeScene)) {
                await SimilarScenesFinder.shared.load(for: activeScene)
            }
    }

    /// Own fullscreen presentation: the same engine, rebound to a full-bleed surface.
    /// The inline card drops its surface while this is up, so only one view ever hosts the
    /// engine's layer.
    @ViewBuilder
    private var fullscreenPlayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let aether = aetherEngine {
                AetherSceneSurface(
                    engine: aether,
                    posterURL: activeScene.thumbnailURL,
                    isMuted: $isMuted,
                    onSeek: { seconds in seekTo(seconds) },
                    liveCaptionText: subtitleController.isLiveCaptionsActive
                        ? subtitleController.currentText
                        : "",
                    onToggleFullscreen: { isFullscreen = false },
                    isFullscreen: true
                )
                // Only the black backdrop bleeds under the notch and home indicator; the
                // surface (and with it the transport) stays inside the safe area so every
                // control is reachable.
            }
        }
        .statusBarHidden(true)
        // Best effort: an attached keyboard (iPad / Mac) skips ±15 s. Deliberately without
        // `.focusable()` — that steals the taps the transport needs.
        .onKeyPress(.leftArrow) {
            skipFullscreen(by: -15)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            skipFullscreen(by: 15)
            return .handled
        }
    }

    private func skipFullscreen(by delta: Double) {
        guard let aether = aetherEngine else { return }
        let duration = aether.duration
        let raw = aether.currentTime + delta
        seekTo(duration > 0 ? min(max(0, raw), duration) : max(0, raw))
    }

    private var lifecycleModifier: SceneDetailLifecycleModifier {
        SceneDetailLifecycleModifier(
            sceneId: activeScene.id,
            isMuted: $isMuted,
            aetherEngine: aetherEngine,
            onAppear: handleOnAppear,
            onDisappear: handleOnDisappear,
            onPeriodicSync: handlePeriodicSync,
            onRefreshMarkers: refreshSceneDetails,
            onInitialSync: initialSync,
            onEnsureAetherAnalysis: ensureAetherVideoAnalysis,
            handyManager: handyManager,
            buttplugManager: buttplugManager,
            loveSpouseManager: loveSpouseManager
        )
    }


    /// Analysis rides the engine's native-route player item plus its decoded PCM tap; on the
    /// software route there is no item and this is a no-op.
    private func ensureAetherVideoAnalysis() {
        #if canImport(AetherEngine)
        guard let aether = aetherEngine else { return }
        AetherMotionAnalysis.ensure(engine: aether)
        #endif
    }

    private func initialSync() {
        guard let aether = aetherEngine, StashSyncManager.shared.isActive else { return }
        ensureAetherVideoAnalysis()

        if aether.isPlaying {
            let currentTime = aether.currentTime
            AppLog.debug("🎬 SceneDetail: Executing initial StashSync play at \(currentTime)s")
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
                    var newScene = updated
                    if let resTime = preservedResumeTime, resTime > 0 {
                        newScene = newScene.withResumeTime(resTime)
                    }
                    newScene = newScene.withUpdatedAt(Scene.newerUpdatedAt(newScene.updatedAt, self.activeScene.updatedAt))
                    self.activeScene = newScene
                    self.configureSubtitles()
                }
            }
        }
    }

    private func handleOnAppear() {
        AppLog.debug("🔍 Scene Detail: ID=\(activeScene.id), PlayCount=\(activeScene.playCount ?? -1)")
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
        
        if activeScene.performers.isEmpty || (activeScene.tags?.isEmpty ?? true) || activeScene.groups == nil || activeScene.sceneMarkers == nil || activeScene.captions == nil {
            viewModel.fetchSceneDetails(sceneId: activeScene.id) { updatedScene in
                if let updated = updatedScene {
                    DispatchQueue.main.async {
                        let preservedResumeTime = self.activeScene.resumeTime
                        var newScene = updated
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
        // Stash's VTT captions are external subtitle tracks on the engine, with their own cue
        // pipeline. The controller is still attached, because live captions share its
        // display channel.
        guard let aether = aetherEngine else { return }
        subtitleController.attach(aether: aether)
    }

    private func handleOnDisappear() {
        if isDeleting {
            aetherEngine?.pause()
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

        aetherEngine?.pause()
        StashSyncManager.shared.stop()
        if handyManager.isSyncing || handyManager.isStashSyncMode { handyManager.pause() }
        if buttplugManager.isConnected { buttplugManager.stop() }
        if loveSpouseManager.isConnected { loveSpouseManager.stop() }
        subtitleController.detach()
        captionTranslator.deactivate()
        // Releases this session's share of the engine audio tap (`stopSession`), so the
        // AI Motion teardown below can close it for good.
        Task { await transcriptionController.disable() }
        AetherMotionAnalysis.teardown(engine: aetherEngine)
        // `@State` release is not deterministic, so the engine is torn down explicitly.
        aetherEngine?.stop()
        aetherEngine = nil
    }

    private func persistPlaybackActivity(stopTracking: Bool) {
        if let aether = aetherEngine {
            let currentTime = aether.currentTime
            let duration = aether.duration > 0 ? aether.duration : (activeScene.sceneDuration ?? 0)
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
        if let aether = aetherEngine {
            guard aether.isPlaying else { return }
            let currentTime = aether.currentTime
            let duration = aether.duration > 0 ? aether.duration : (activeScene.sceneDuration ?? 0)
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

    /// Updates local Scene Detail state and notifies catalog lists (title, studio, tags, …).
    private func applyLocalSceneEdit(_ updated: Scene) {
        activeScene = updated
        updated.postListMetadataUpdated()
    }

    private func startPlayback(resume: Bool) {
        guard let url = activeScene.aetherVideoURL else { return }

        let resumeTarget: Double? = {
            guard resume, let time = activeScene.resumeTime, time > 0 else { return nil }
            return time
        }()

        if aetherEngine == nil {
            let engine: AetherSceneEngine
            do {
                engine = try AetherSceneEngine()
            } catch {
                AppLog.error("Playback engine unavailable: \(error.localizedDescription)")
                ToastManager.shared.show(
                    "Playback engine unavailable",
                    icon: "exclamationmark.triangle",
                    style: .error
                )
                return
            }

            AppLog.debug("🎬 Player initializing with URL: \(redactedURLString(url))")
            // Re-read here, not at `@State` init: only now is the playback audio session active,
            // so only now does the route report connected headphones.
            isMuted = ScenePlayerMute.initialValueForPlayback()
            engine.isMuted = isMuted
            engine.rate = Float(playbackSpeed)

            engine.onTime = { [weak engine] seconds, duration in
                if seconds >= 0 {
                    currentPlaybackTime = seconds
                    let total = duration > 0 ? duration : (activeScene.sceneDuration ?? 0)
                    playbackActivityTracker.setPosition(currentTime: seconds, duration: total)
                    if engine?.isPlaying == true {
                        ensurePlaybackActivityConfigured()
                        playbackActivityTracker.start()
                    }
                }
                if !hasAddedPlay, seconds > 1 {
                    registerScenePlay()
                }
            }
            engine.onPlayingChanged = { [weak engine] playing in
                guard let engine else { return }
                handleAetherPlayingChange(engine, playing: playing)
            }
            // A (re)load swaps the analysis item in place — re-attach AI Motion to the new one.
            engine.onAnalysisItemChanged = { _ in
                ensureAetherVideoAnalysis()
            }

            // Server transcodes the engine falls back to when the original will not play.
            engine.fallbackSources = activeScene.transcodeFallbackURLs
            engine.fallbackDeclaredDuration = activeScene.sceneDuration
            engine.onTranscodeFallback = { _ in
                guard !didAnnounceTranscodeFallback else { return }
                didAnnounceTranscodeFallback = true
                ToastManager.shared.show(
                    "Original could not be played — using the server transcode",
                    icon: "arrow.triangle.2.circlepath",
                    style: .error
                )
            }

            aetherEngine = engine
            let scene = activeScene
            Task {
                await engine.load(url: url, startAt: resumeTarget, autoplay: true)
                registerAetherCaptions(on: engine, scene: scene)
            }
        } else if let resumeTarget, let engine = aetherEngine {
            Task { await engine.seek(to: resumeTarget) }
        }

        withAnimation {
            isPlaybackStarted = true
        }
        // Live captions (AI Subs) share the caption channel with server VTT; the controller is
        // driven by the engine clock.
        if let engine = aetherEngine {
            subtitleController.attach(aether: engine)
        }
        aetherEngine?.play()

        let position = aetherEngine?.currentTime ?? resumeTarget ?? 0
        if handyManager.isSyncing {
            handyManager.play(at: position)
        }
        if buttplugManager.isConnected {
            buttplugManager.play(at: position)
        }
        if loveSpouseManager.isSyncing {
            loveSpouseManager.play(at: position)
        }
        ensurePlaybackActivityConfigured()
        playbackActivityTracker.start()

        if !hasAddedPlay {
            registerScenePlay()
        }
    }

    /// Stash's server captions as selectable external subtitle tracks on the engine. Nothing is
    /// auto-selected — the user picks from the Audio & Subtitles menu.
    private func registerAetherCaptions(on engine: AetherSceneEngine, scene: Scene) {
        guard let captions = scene.captions, !captions.isEmpty else { return }
        for caption in captions {
            guard let url = SubtitleController.captionURL(for: caption, scene: scene) else { continue }
            let language = caption.languageCode.isEmpty || caption.languageCode == "00"
                ? nil
                : caption.languageCode
            let name = language.flatMap { Locale.current.localizedString(forIdentifier: $0) }
                ?? language?.uppercased()
                ?? "Captions"
            engine.addExternalSubtitleTrack(url: url,
                                            name: name,
                                            language: language,
                                            formatHint: caption.captionType)
        }
    }

    /// Play-state fan-out: activity tracker, StashSync and the device managers.
    private func handleAetherPlayingChange(_ aether: AetherSceneEngine, playing: Bool) {
        // Scrubbing produces rapid playing/paused transitions; `commitScrub` handles the resume.
        if isScrubbing { return }
        let currentTime = aether.currentTime
        let duration = aether.duration > 0 ? aether.duration : (activeScene.sceneDuration ?? 0)
        playbackActivityTracker.setPosition(currentTime: currentTime, duration: duration)
        ensurePlaybackActivityConfigured()

        if !playing {
            playbackActivityTracker.stop()
            StashSyncManager.shared.stop()
            if handyManager.isSyncing || handyManager.isStashSyncMode { handyManager.pause() }
            if buttplugManager.isSyncing || buttplugManager.isStashSyncMode { buttplugManager.pause() }
            if loveSpouseManager.isSyncing || loveSpouseManager.isStashSyncMode { loveSpouseManager.pause() }
        } else {
            playbackActivityTracker.start()
            ensureAetherVideoAnalysis()
            let stashSyncActive = handyManager.isStashSyncMode || buttplugManager.isStashSyncMode || loveSpouseManager.isStashSyncMode
            if stashSyncActive { StashSyncManager.shared.start() }
            if handyManager.isSyncing || handyManager.isStashSyncMode { handyManager.play(at: currentTime) }
            if buttplugManager.isSyncing || buttplugManager.isStashSyncMode { buttplugManager.play(at: currentTime) }
            if loveSpouseManager.isSyncing || loveSpouseManager.isStashSyncMode { loveSpouseManager.play(at: currentTime) }
        }
    }

    /// One in-flight engine seek at a time; the latest scrub target wins.
    private func enqueueAetherSeek(_ aether: AetherSceneEngine, to seconds: Double) {
        pendingAetherSeek = seconds
        guard !aetherSeekInFlight else { return }
        aetherSeekInFlight = true
        Task { @MainActor in
            while let target = pendingAetherSeek {
                pendingAetherSeek = nil
                await aether.seek(to: target)
            }
            aetherSeekInFlight = false
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

    private func deleteSceneWithFiles() {
        isDeleting = true
        viewModel.deleteSceneWithFiles(scene: activeScene) { success in
            if success {
                AppLog.debug("🎉 Scene and files completely removed!")
                ToastManager.shared.show("Scene deleted", icon: "trash", style: .success)
                self.dismiss()
            } else {
                isDeleting = false
                ToastManager.shared.show("Failed to delete scene", icon: "exclamationmark.triangle", style: .error)
                AppLog.error("❌ Failed to delete scene or files")
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

    private func stopPreview() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPreviewing = false
        }
    }

    private func seekTo(_ seconds: Double) {
        if !isPlaybackStarted {
            startPlayback(resume: false)
        }

        guard let aether = aetherEngine else { return }
        enqueueAetherSeek(aether, to: seconds)
        playbackActivityTracker.noteSeek(to: seconds)
        // While actively scrubbing we don't kick device-syncs on every micro-seek (that
        // explodes network / Bluetooth traffic). Final commit happens on drag end via
        // `commitScrub(to:)`.
        guard !isScrubbing else { return }
        aether.play()
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
        guard let aether = aetherEngine else { return }
        enqueueAetherSeek(aether, to: seconds)
        playbackActivityTracker.noteSeek(to: seconds)
        aether.play()
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
    
}

// Extensions for Scene conversion

// Scene detail helpers
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
    let sceneTitle: String
    let sceneTagIds: Set<String>
    let seconds: Double
    /// Source of the marker still. Only used for the log line — the frame itself comes from
    /// the engine, which already has the file open.
    let videoURL: URL?
    /// Captures the still at the marker start (same path as Scene Cover). nil before playback
    /// has started, in which case the marker is created without a local thumbnail.
    let aetherEngine: AetherSceneEngine?
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
        let base: [Tag]
        if searchText.isEmpty {
            base = tags
        } else {
            base = tags.filter { $0.name.lowercased().contains(searchText.lowercased()) }
        }
        var sceneTags: [Tag] = []
        var otherTags: [Tag] = []
        for tag in base {
            if sceneTagIds.contains(tag.id) {
                sceneTags.append(tag)
            } else {
                otherTags.append(tag)
            }
        }
        return sceneTags + otherTags
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
                            .numericKeyboardDoneBar()
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

        Task { @MainActor in
            // Capture start-frame still like Scene Cover (instant local thumb). The engine
            // decodes it from the source it is already playing; without one there is no still.
            let frameDataURL: String? = await {
                guard let aetherEngine, videoURL != nil else { return nil }
                guard let image = await aetherEngine.captureFrame(at: max(0, seconds),
                                                                  maxSize: kCaptureFrameMaxSize)
                else { return nil }
                return videoFrameDataURL(from: image)
            }()

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

                    NotificationCenter.default.post(
                        name: NSNotification.Name("SceneMarkerCreated"),
                        object: nil,
                        userInfo: [
                            "sceneId": sceneId,
                            "markerId": createdMarker.id,
                            "title": createdMarker.title ?? title,
                            "sceneTitle": sceneTitle,
                            "thumbnailPath": createdMarker.screenshot as Any
                        ]
                    )

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
                            AppLog.error("⚠️ Marker screenshot generate failed to start for scene \(self.sceneId)")
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
                                AppLog.error("⚠️ Marker screenshot generate job failed: \(message)")
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
    let sceneTagIds:        Set<String>
    let videoURL:           URL?
    let aetherEngine:       AetherSceneEngine?
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
                    sceneTitle: title,
                    sceneTagIds: sceneTagIds,
                    seconds: capturedMarkerTime,
                    videoURL: videoURL,
                    aetherEngine: aetherEngine,
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
    let aetherEngine:      AetherSceneEngine?
    let onAppear:          () -> Void
    let onDisappear:       () -> Void
    let onPeriodicSync:    () -> Void
    let onRefreshMarkers:  () -> Void
    let onInitialSync:     () -> Void
    let onEnsureAetherAnalysis: () -> Void
    let handyManager:      HandyManager
    let buttplugManager:   ButtplugManager
    let loveSpouseManager: LoveSpouseManager

    func body(content: Content) -> some View {
        content
            .onAppear { onAppear() }
            .onDisappear { onDisappear() }
            .unmutesOnHardwareVolume($isMuted)
            .onChange(of: isMuted) { _, v in
                // No persist: this view has no mute button of its own, so the handler only
                // ever sees programmatic writes.
                aetherEngine?.isMuted = v
            }
            // Without a mute button here the route is the only control the user has: plugging
            // headphones in mid-playback must turn the sound on, unplugging must mute again.
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
                .receive(on: DispatchQueue.main)) { _ in
                let muted = ScenePlayerMute.initialValue()
                if muted != isMuted { isMuted = muted }
            }
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in onPeriodicSync() }
            .onChange(of: StashSyncManager.shared.isActive) { _, active in if active { onInitialSync() } }
            .overlay(aetherOverlay)
    }

    /// Only the device-mode toggles: the engine reports play/pause through `onPlayingChanged`
    /// and item swaps through `onAnalysisItemChanged`.
    @ViewBuilder
    private var aetherOverlay: some View {
        if aetherEngine != nil {
            Color.clear
                .onChange(of: handyManager.isStashSyncMode) { _, on in
                    if on { onEnsureAetherAnalysis(); onInitialSync() }
                }
                .onChange(of: buttplugManager.isStashSyncMode) { _, on in
                    if on { onEnsureAetherAnalysis(); onInitialSync() }
                }
                .onChange(of: loveSpouseManager.isStashSyncMode) { _, on in
                    if on { onEnsureAetherAnalysis(); onInitialSync() }
                }
        }
    }
}

#endif
