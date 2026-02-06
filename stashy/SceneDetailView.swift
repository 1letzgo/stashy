//
//  SceneDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

import SwiftUI
import AVFoundation
import AVKit
import WebKit

struct SceneDetailView: View {
    let scene: Scene
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var activeScene: Scene
    @StateObject private var viewModel = StashDBViewModel()
    
    init(scene: Scene) {
        self.scene = scene
        _activeScene = State(initialValue: scene)
    }
    @State private var player: AVPlayer?
    @State private var showDeleteWithFilesConfirmation = false
    @State private var isDeleting = false
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
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    // Preview Video State
    @State private var previewPlayer: AVPlayer?
    @State private var isPreviewing = false
    @State private var isPressing = false
    
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
                        
                        Circle()
                            .trim(from: 0, to: activeDownload.progress)
                            .stroke(appearanceManager.tintColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear, value: activeDownload.progress)
                    }
                    .frame(width: 18, height: 18)
                } else {
                    Button {
                        downloadManager.downloadScene(activeScene)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }

                // Delete Button
                Button(role: .destructive) {
                    showDeleteWithFilesConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(appearanceManager.tintColor)
                }
                .tint(appearanceManager.tintColor)
            }
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
                    isHeaderExpanded: $isHeaderExpanded,
                    showingAddMarkerSheet: $showingAddMarkerSheet,
                    capturedMarkerTime: $capturedMarkerTime,
                    playbackSpeed: $playbackSpeed,
                    viewModel: viewModel,
                    onSeek: { seconds in seekTo(seconds) },
                    onStartPlayback: { resume in startPlayback(resume: resume) }
                )
                
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        mainContentView
            .background(Color.appBackground)
            .navigationTitle(scene.title ?? "Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                sceneToolbarContent
            }
        .alert("Really delete scene and files?", isPresented: $showDeleteWithFilesConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSceneWithFiles()
            }
        } message: {
            Text("The scene '\(activeScene.title ?? "Unknown Title")' and all associated files will be permanently deleted. This action cannot be undone.")
        }
        .sheet(isPresented: $showingAddMarkerSheet) {
            AddMarkerSheet(sceneId: activeScene.id, seconds: capturedMarkerTime, viewModel: viewModel) {
                // Refresh scene details to show the new marker
                viewModel.fetchSceneDetails(sceneId: activeScene.id) { updatedScene in
                    if let updated = updatedScene {
                        DispatchQueue.main.async {
                            self.activeScene = updated
                        }
                    }
                }
            }
        }
        .onAppear {
            // Ensure state is reset when view appears
            print("🔍 Scene Detail: ID=\(activeScene.id), PlayCount=\(activeScene.playCount ?? -1)")
            isFullscreen = false
            
            // 1. Fetch Transcoded Streams in background (Fast Start)
            viewModel.fetchSceneStreams(sceneId: activeScene.id) { streams in
                if !streams.isEmpty {
                    DispatchQueue.main.async {
                        self.activeScene = self.activeScene.withStreams(streams)
                        print("✅ Transcoded streams loaded in background: \(streams.count) options")
                        self.updatePlayerStream()
                    }
                }
            }
            
            // 2. Refresh main scene details (stable query)
            viewModel.fetchSceneDetails(sceneId: activeScene.id) { updatedScene in
                if let updated = updatedScene {
                    DispatchQueue.main.async {
                        // Preserve existing streams if they were already loaded
                        self.activeScene = updated.withStreams(self.activeScene.streams)
                        print("✅ Scene data refreshed: ResumeTime=\(updated.resumeTime ?? 0)")
                    }
                }
            }
        }
        .onDisappear {
            if isDeleting {
                player?.pause()
                stopPreview()
                return
            }
            
            if !isFullscreen {
                player?.pause()
            }
            stopPreview()
            
            // Determine current resume time
            let currentTime = player?.currentTime().seconds
            let effectiveResumeTime = (currentTime != nil && currentTime! > 0) ? currentTime! : activeScene.resumeTime
            
            // Save and notify parent views if we have a resume time
            if let resumeTime = effectiveResumeTime, resumeTime > 0 {
                let sceneId = activeScene.id
                
                // Only save to server if player was used
                if currentTime != nil && currentTime! > 0 {
                    viewModel.updateSceneResumeTime(sceneId: sceneId, resumeTime: resumeTime) { success in
                        if success {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("SceneResumeTimeUpdated"),
                                    object: nil,
                                    userInfo: ["sceneId": sceneId, "resumeTime": resumeTime]
                                )
                            }
                        }
                    }
                } else {
                    // Just notify with existing resume time (no save needed)
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SceneResumeTimeUpdated"),
                        object: nil,
                        userInfo: ["sceneId": sceneId, "resumeTime": resumeTime]
                    )
                }
            }
        }
        .onChange(of: isMuted) { _, newValue in
            player?.isMuted = newValue
        }
        .onReceive(timer) { _ in
            // Periodically save progress while playing
            if isDeleting { return }
            if let player = player, player.timeControlStatus == .playing {
                let currentTime = player.currentTime().seconds
                if currentTime > 0 {
                    viewModel.updateSceneResumeTime(sceneId: activeScene.id, resumeTime: currentTime)
                }
            }
        }
    }

    private func startPlayback(resume: Bool) {
        guard let videoURL = activeScene.videoURL else { return }
        
        if player == nil {
            print("🎬 Player initializing with URL: \(videoURL.absoluteString)")
            player = createPlayer(for: videoURL)
            player?.isMuted = isMuted
            
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
        player?.rate = Float(playbackSpeed)
        
        if !hasAddedPlay {
            viewModel.addScenePlay(sceneId: activeScene.id)
            hasAddedPlay = true
        }
    }

    private func deleteSceneWithFiles() {
        isDeleting = true
        viewModel.deleteSceneWithFiles(scene: activeScene) { success in
            if success {
                print("🎉 Scene and files completely removed!")
                self.dismiss()
            } else {
                isDeleting = false
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
    var thumbnailURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return URL(string: "\(config.baseURL)/performer/\(id)/image")
    }

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
