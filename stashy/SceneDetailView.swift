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

struct SceneDetailView: View {
    let scene: Scene
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var activeScene: Scene
    @ObservedObject var viewModel = StashDBViewModel()
    @ObservedObject var handyManager = HandyManager.shared
    @ObservedObject var buttplugManager = ButtplugManager.shared
    @ObservedObject var loveSpouseManager = LoveSpouseManager.shared
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    init(scene: Scene) {
        self.scene = scene
        _activeScene = State(initialValue: scene)
    }
    @State private var player: AVPlayer?
    @State private var showDeleteWithFilesConfirmation = false
    @State private var isDeleting = false
    @State private var isDownloading = false
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var coordinator: NavigationCoordinator

    @State private var isHeaderExpanded = false
    @State private var isTagsExpanded = false
    @State private var isFullscreen = false
    @State private var isPlaybackStarted = false
    @State private var tagsTotalHeight: CGFloat = 0
    @State private var isMuted = !isHeadphonesConnected()
    @State private var hasAddedPlay = false
    @State private var showingAddMarkerSheet = false
    @State private var capturedMarkerTime: Double = 0
    @State private var playbackSpeed: Double = 1.0
    @State private var currentPlaybackTime: Double = 0
    @State private var timeObserverToken: Any?
    
    // Preview Video State
    @State private var previewPlayer: AVPlayer?
    @State private var isPreviewing = false
    @State private var isPressing = false
    @State private var hasInitializedDevices = false
    
    // Extracted toolbar content to reduce body complexity
    @ToolbarContentBuilder
    private var sceneToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 16) {
                // Download Button
                if downloadManager.isDownloaded(id: activeScene.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if let activeDownload = downloadManager.activeDownloads[activeScene.id] {
                    ZStack {
                        Circle()
                            .stroke(appearanceManager.tintColor.opacity(0.3), lineWidth: 2.5)
                        
                        // If we have a total size > 0, show determinate progress
                        if activeDownload.totalSize > 0 {
                            Circle()
                                .trim(from: 0, to: activeDownload.progress)
                                .stroke(appearanceManager.tintColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.linear, value: activeDownload.progress)
                        } else {
                            // Indeterminate state: Show a rotating segment
                            Circle()
                                .trim(from: 0, to: 0.25)
                                .stroke(appearanceManager.tintColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .rotationEffect(.degrees(isDownloading ? 360 : 0))
                                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isDownloading)
                                .onAppear { isDownloading = true }
                        }
                    }
                    .frame(width: 18, height: 18)
                } else {
                    Button {
                        downloadManager.downloadScene(activeScene)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }

            }
        }
    }


    @Environment(\.verticalSizeClass) var verticalSizeClass

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
                    isHeaderExpanded: $isHeaderExpanded,
                    showingAddMarkerSheet: $showingAddMarkerSheet,
                    capturedMarkerTime: $capturedMarkerTime,
                    playbackSpeed: $playbackSpeed,
                    viewModel: viewModel,
                    onSeek: { seconds in seekTo(seconds) },
                    onStartPlayback: { resume in startPlayback(resume: resume) }
                )
                
                let isAnyAudioModeActive = handyManager.isAudioMode || buttplugManager.isAudioMode || loveSpouseManager.isAudioMode
                
                if isAnyAudioModeActive {
                    AudioVibeCard()
                }
                
                if activeScene.interactive == true && activeScene.funscriptURL != nil && !isAnyAudioModeActive {
                    SceneHeatmapCard(
                        heatmapURL: activeScene.heatmapURL,
                        funscriptURL: activeScene.funscriptURL,
                        durationSeconds: activeScene.sceneDuration ?? 0,
                        currentTimeSeconds: currentPlaybackTime,
                        onSeek: { seconds in seekTo(seconds) }
                    )
                }
                
                if verticalSizeClass == .compact {
                    // Landscape Mode: Grid Layout for Metadata
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 12) {
                        
                        // Item 1: Performers & Studio
                        if !activeScene.performers.isEmpty || activeScene.studio != nil {
                            VStack(spacing: 12) {
                                if !activeScene.performers.isEmpty {
                                    ScenePerformersCard(performers: activeScene.performers)
                                }
                                if let studio = activeScene.studio {
                                    SceneStudioCard(studio: studio)
                                }
                            }
                        }
                        
                        // Item 2: Galleries
                        if let galleries = activeScene.galleries, !galleries.isEmpty {
                            SceneGalleriesCard(galleries: galleries)
                        }
                        
                        // Item 3: Tags
                        if let tags = activeScene.tags, !tags.isEmpty {
                            SceneTagsCard(
                                tags: tags,
                                isTagsExpanded: $isTagsExpanded,
                                tagsTotalHeight: $tagsTotalHeight
                            )
                        }
                        
                        // Item 4: Delete Button
                        Button(role: .destructive) {
                            showDeleteWithFilesConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Scene")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(appearanceManager.tintColor.opacity(0.1))
                            .foregroundColor(appearanceManager.tintColor)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                        }
                    }
                } else {
                    // Portrait Mode: Vertical Stack
                    if !activeScene.performers.isEmpty || activeScene.studio != nil {
                        HStack(alignment: .top, spacing: 12) {
                            if !activeScene.performers.isEmpty {
                                ScenePerformersCard(performers: activeScene.performers)
                            }
                            
                            if let studio = activeScene.studio {
                                SceneStudioCard(studio: studio)
                            }
                        }
                    }

                    if let galleries = activeScene.galleries, !galleries.isEmpty {
                        SceneGalleriesCard(galleries: galleries)
                    }
                    
                    if let tags = activeScene.tags, !tags.isEmpty {
                        SceneTagsCard(
                            tags: tags,
                            isTagsExpanded: $isTagsExpanded,
                            tagsTotalHeight: $tagsTotalHeight
                        )
                    }
                    
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
                        .background(appearanceManager.tintColor.opacity(0.1))
                        .foregroundColor(appearanceManager.tintColor)
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
            .background(Color.appBackground)
            .navigationTitle(scene.title ?? "Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { sceneToolbarContent }
            .toolbar(.visible, for: .navigationBar)
            .alert("Really delete scene and files?", isPresented: $showDeleteWithFilesConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { deleteSceneWithFiles() }
            } message: {
                Text("The scene '\(activeScene.title ?? "Unknown Title")' and all associated files will be permanently deleted. This action cannot be undone.")
            }
            .sheet(isPresented: $showingAddMarkerSheet) {
                AddMarkerSheet(sceneId: activeScene.id, seconds: capturedMarkerTime, viewModel: viewModel) {
                    refreshSceneDetails()
                }
            }
            .onAppear { handleOnAppear() }
            .onDisappear { handleOnDisappear() }
            .onChange(of: isMuted) { _, newValue in
                player?.isMuted = newValue
            }
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
                handlePeriodicSync()
            }
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                handlePlaybackMarkerUpdate()
            }
            .overlay(
                Group {
                    if let player = player {
                        Color.clear
                            .onReceive(player.publisher(for: \.timeControlStatus)) { status in
                                handleTimeControlStatusChange(status)
                            }
                                .onReceive(player.publisher(for: \.status)) { _ in
                                    ensureAudioAnalysis(for: player.currentItem)
                                }
                                .onChange(of: player.currentItem) { _, newItem in
                                    ensureAudioAnalysis(for: newItem)
                                }
                                .onChange(of: handyManager.isAudioMode) { _, isAudio in
                                    if isAudio { ensureAudioAnalysis(for: player.currentItem) }
                                }
                                .onChange(of: buttplugManager.isAudioMode) { _, isAudio in
                                    if isAudio { ensureAudioAnalysis(for: player.currentItem) }
                                }
                                .onChange(of: loveSpouseManager.isAudioMode) { _, isAudio in
                                    if isAudio { ensureAudioAnalysis(for: player.currentItem) }
                                }
                    }
                }
            )
            .onChange(of: handyManager.isSyncing) { _, isSyncing in
                // Standard HSSP handling
            }
    }

    private func ensureAudioAnalysis(for item: AVPlayerItem?) {
        guard let item = item else { return }
        // Only setup if at least one manager is in audio mode
        if handyManager.isAudioMode || buttplugManager.isAudioMode || loveSpouseManager.isAudioMode {
            print("🎙️ SceneDetail: Ensuring Audio Analysis is setup for current item")
            AudioAnalysisManager.shared.setup(for: item)
        }
    }

    private func refreshSceneDetails() {
        viewModel.fetchSceneDetails(sceneId: activeScene.id) { updatedScene in
            if let updated = updatedScene {
                DispatchQueue.main.async {
                    self.activeScene = updated
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
            handyManager.isAudioMode = false // In case we ever bring it back
            buttplugManager.isAudioMode = false
            buttplugManager.isSyncing = false
            loveSpouseManager.isAudioMode = false
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
        
        if activeScene.performers.isEmpty || (activeScene.tags?.isEmpty ?? true) {
            viewModel.fetchSceneDetails(sceneId: activeScene.id) { updatedScene in
                if let updated = updatedScene {
                    DispatchQueue.main.async {
                        self.activeScene = updated.withStreams(self.activeScene.streams)
                    }
                }
            }
        }
        
        // Removed automatic setupScene to enforce manual activation
    }

    private func handleOnDisappear() {
        if isDeleting {
            player?.pause()
            stopPreview()
            return
        }

        if !isFullscreen {
            player?.pause()
            if handyManager.isSyncing { handyManager.pause() }
            if buttplugManager.isConnected { buttplugManager.pause() }
            if loveSpouseManager.isConnected { loveSpouseManager.pause() }
        }
        stopPreview()
        removeTimeObserver()
        
        let currentTime = player?.currentTime().seconds
        let effectiveResumeTime = (currentTime != nil && currentTime! > 0) ? currentTime! : activeScene.resumeTime
        
        if let resumeTime = effectiveResumeTime, resumeTime > 0 {
            let sceneId = activeScene.id
            if currentTime != nil && currentTime! > 0 {
                viewModel.updateSceneResumeTime(sceneId: sceneId, resumeTime: resumeTime) { success in
                    if success {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: NSNotification.Name("SceneResumeTimeUpdated"), object: nil, userInfo: ["sceneId": sceneId, "resumeTime": resumeTime])
                        }
                    }
                }
            } else {
                NotificationCenter.default.post(name: NSNotification.Name("SceneResumeTimeUpdated"), object: nil, userInfo: ["sceneId": sceneId, "resumeTime": resumeTime])
            }
        }
    }

    private func handlePeriodicSync() {
        if isDeleting { return }
        if let player = player, player.timeControlStatus == .playing {
            let currentTime = player.currentTime().seconds
            if currentTime > 0 {
                viewModel.updateSceneResumeTime(sceneId: activeScene.id, resumeTime: currentTime)
            }
            if !hasAddedPlay, currentTime > 1 {
                registerScenePlay()
            }
        }
    }

    private func handlePlaybackMarkerUpdate() {
        guard let player = player else { return }
        let currentTime = player.currentTime().seconds
        if currentTime >= 0 {
            currentPlaybackTime = currentTime
        }
    }

    private func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus) {
        guard let player = player else { return }
        let currentTime = player.currentTime().seconds
        
        if status == .paused {
            if handyManager.isSyncing { handyManager.pause() }
            if buttplugManager.isConnected { buttplugManager.pause() }
            if loveSpouseManager.isSyncing { loveSpouseManager.pause() }
        } else if status == .playing {
            ensureAudioAnalysis(for: player.currentItem)
            if handyManager.isSyncing { handyManager.play(at: currentTime) }
            if buttplugManager.isConnected { buttplugManager.play(at: currentTime) }
            if loveSpouseManager.isSyncing { loveSpouseManager.play(at: currentTime) }
        }
    }

    private func startPlayback(resume: Bool) {
        guard let videoURL = activeScene.videoURL else { return }

        if player == nil {
            print("🎬 Player initializing with URL: \(videoURL.absoluteString)")
            player = createPlayer(for: videoURL)
            player?.isMuted = isMuted
            addTimeObserverIfNeeded()

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
        
        if !hasAddedPlay {
            registerScenePlay()
        }
    }

    private func addTimeObserverIfNeeded() {
        guard timeObserverToken == nil, let player = player else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            if seconds >= 0 {
                currentPlaybackTime = seconds
            }
            if !hasAddedPlay, seconds > 1 {
                registerScenePlay()
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
        
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
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

    private func infoPill(icon: String, text: String, color: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color ?? appearanceManager.tintColor)
            Text(text)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            ZStack {
                Color(UIColor.systemBackground)
                (color ?? appearanceManager.tintColor).opacity(0.1)
            }
        )
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color ?? appearanceManager.tintColor, lineWidth: 0.5))
    }
    
    /// Updates the player if a better stream becomes available (e.g. replacing an incompatible MKV fallback with a transcribed MP4)
    private func updatePlayerStream() {
        guard let currentURL = player?.currentItem?.asset as? AVURLAsset else { return }
        guard let newURL = activeScene.videoURL else { return }
        
        // Only switch if the URL path is different
        if currentURL.url.absoluteString != newURL.absoluteString {
            // Check if current URL is the likely incompatible fallback
            let oldIsFallback = currentURL.url.pathExtension.lowercased() == "mkv"
            let newIsStream = newURL.pathExtension.lowercased() == "mp4" || newURL.absoluteString.contains("/stream")
            
            if oldIsFallback || newIsStream {
                print("♻️ Upgrading stream in SceneDetailView from \(currentURL.url.lastPathComponent) to \(newURL.lastPathComponent)...")
                
                let headers = ["ApiKey": ServerConfigManager.shared.activeConfig?.secureApiKey ?? ""]
                let asset = AVURLAsset(url: newURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                let item = AVPlayerItem(asset: asset)
                
                let currentTime = player?.currentTime() ?? .zero
                let wasPlaying = player?.rate ?? 0 > 0
                
                player?.replaceCurrentItem(with: item)
                
                if currentTime > .zero {
                    player?.seek(to: currentTime)
                }
                
                if wasPlaying || isPlaybackStarted {
                    player?.play()
                }
            }
        }
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
            birthdate: nil,
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
            careerLength: nil,
            tattoos: nil,
            piercings: nil,
            aliasList: nil,
            favorite: nil,
            rating100: nil,
            createdAt: nil,
            updatedAt: nil
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
            }
            .navigationTitle("Add Marker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        createMarker()
                    }
                    .disabled(title.isEmpty || primaryTagId.isEmpty || isCreating)
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
        
        viewModel.createSceneMarker(
            sceneId: sceneId,
            title: title,
            seconds: seconds,
            endSeconds: endSeconds,
            primaryTagId: primaryTagId
        ) { success in
            DispatchQueue.main.async {
                isCreating = false
                if success {
                    onComplete()
                    dismiss()
                }
            }
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

// MARK: - AudioVibeCard Component
struct AudioVibeCard: View {
    @ObservedObject var audioManager = AudioAnalysisManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var handyManager = HandyManager.shared
    @ObservedObject var buttplugManager = ButtplugManager.shared
    @ObservedObject var loveSpouseManager = LoveSpouseManager.shared
    
    @State private var isSettingsExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("Audio Sync")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                    if buttplugManager.isEnabled {
                        Button {
                            if !buttplugManager.isAudioMode && !buttplugManager.isConnected {
                                buttplugManager.connect()
                            }
                            withAnimation { buttplugManager.isAudioMode.toggle() }
                            HapticManager.medium()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: buttplugManager.isAudioMode ? "waveform.and.mic" : "waveform")
                                Text("Intiface")
                            }
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(buttplugManager.isAudioMode ? .white : appearanceManager.tintColor)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 80, minHeight: 28)
                            .background(buttplugManager.isAudioMode ? Color.purple : appearanceManager.tintColor.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                    
                    // Love Spouse Button
                    if loveSpouseManager.isEnabled {
                        Button {
                            withAnimation { loveSpouseManager.isAudioMode.toggle() }
                            HapticManager.medium()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: loveSpouseManager.isAudioMode ? "waveform.and.mic" : "waveform")
                                Text("LoveSpouse")
                            }
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(loveSpouseManager.isAudioMode ? .white : appearanceManager.tintColor)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 80, minHeight: 28)
                            .background(loveSpouseManager.isAudioMode ? Color.purple : appearanceManager.tintColor.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                }
            
            VStack(spacing: 8) {
                // VU Meter
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [.green, .yellow, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * CGFloat(audioManager.visualLevel), height: 8)
                            .animation(.linear(duration: 0.1), value: audioManager.visualLevel)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)
                
                HStack {
                    Text("Live Audio Level")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(audioManager.visualLevel * 100))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .trailing, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Sensitivity
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Sensitivity")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(Int(audioManager.sensitivity * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $audioManager.sensitivity, in: 0...1)
                                .tint(appearanceManager.tintColor)
                        }
                        
                        // Intensity
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Max Intensity")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(Int(audioManager.maxIntensity * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $audioManager.maxIntensity, in: 0.1...1)
                                .tint(appearanceManager.tintColor)
                        }
                        
                        // Latency (Delay)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Latency Compensation")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(Int(audioManager.delayMs))ms")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $audioManager.delayMs, in: 0...1000, step: 10)
                                .tint(appearanceManager.tintColor)
                            Text("Signal will be sent \(Int(audioManager.delayMs))ms before the sound.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding(.top, 12)
                }
                .frame(maxHeight: isSettingsExpanded ? .none : 0, alignment: .topLeading)
                .clipped()
                
                Button(action: {
                    withAnimation(.spring()) {
                        isSettingsExpanded.toggle()
                    }
                }) {
                    Image(systemName: isSettingsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(appearanceManager.tintColor)
                        .padding(6)
                        .background(appearanceManager.tintColor.opacity(0.1))
                        .clipShape(Circle())
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}
#endif
