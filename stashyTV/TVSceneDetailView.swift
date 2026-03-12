//
//  TVSceneDetailView.swift
//  stashyTV
//
//  Scene detail for tvOS — Netflix/Prime style
//

import SwiftUI
import AVKit
import Combine

struct TVSceneDetailView: View {
    let sceneId: String

    @StateObject private var viewModel = StashDBViewModel()
    @StateObject private var playerViewModel = TVPlayerViewModel()
    @State private var sceneDetail: Scene?
    @State private var sceneStreams: [SceneStream] = []
    @State private var isLoadingDetail = true
    @State private var isLoadingStreams = true
    @State private var hasAddedPlay = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()
            
            // Full Screen Hero Background
            if let scene = sceneDetail {
                heroBackground(scene: scene)
            }
            
            ScrollView(showsIndicators: false) {
                if isLoadingDetail {
                    VStack {
                        Spacer(minLength: 400)
                        ProgressView().scaleEffect(1.5)
                        Spacer(minLength: 400)
                    }
                    .frame(maxWidth: .infinity)
                } else if let scene = sceneDetail {
                    VStack(alignment: .leading, spacing: 50) {
                        
                        // Hero Content Overlay (Title, Metadata, Actions)
                        heroContent(scene: scene)
                            .padding(.top, 120) // Push content down over the background
                        
                        // Markers
                        if let markers = scene.sceneMarkers, !markers.isEmpty {
                            markersSection(markers: markers, scene: scene)
                        }

                        // Metadata Tags
                        if let tags = scene.tags, !tags.isEmpty {
                            tagsSection(tags: tags)
                        }

                        // Performers (Cast)
                        if !scene.performers.isEmpty {
                            performersSection(performers: scene.performers)
                        }

                        // Studio
                        if let studio = scene.studio {
                            studioSection(studio: studio)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 60)
                    .padding(.bottom, 100)
                } else {
                    errorView
                }
            }
        }
        .navigationTitle("")
        .onAppear { loadData() }
        .onPlayPauseCommand {
            if sceneDetail != nil {
                if playerViewModel.player?.rate == 0 {
                    playerViewModel.player?.play()
                } else {
                    playerViewModel.player?.pause()
                }
            }
        }
        .fullScreenCover(isPresented: $playerViewModel.isShowingPlayer, onDismiss: {
            playerViewModel.clear()
            loadData()
        }) {
            if let player = playerViewModel.player {
                TVVideoPlayerView(player: player, isPresented: $playerViewModel.isShowingPlayer)
            }
        }
    }

    private var errorView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 300)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.12))
            Text("Failed to load scene details")
                .font(.title2)
                .foregroundColor(.white.opacity(0.4))
            Button("Retry") {
                loadData()
            }
            .font(.title3)
            Spacer(minLength: 300)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data Loading

    private func loadData() {
        isLoadingDetail = true
        isLoadingStreams = true

        viewModel.fetchSceneDetails(sceneId: sceneId) { scene in
            self.sceneDetail = scene
            self.isLoadingDetail = false
        }

        viewModel.fetchSceneStreams(sceneId: sceneId) { streams in
            self.sceneStreams = streams
            self.isLoadingStreams = false
        }
    }

    // MARK: - Hero Sections

    @ViewBuilder
    private func heroBackground(scene: Scene) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                if let thumbnailURL = scene.thumbnailURL {
                    CustomAsyncImage(url: thumbnailURL) { loader in
                        if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        } else {
                            Color.appBackground
                        }
                    }
                } else {
                     Color.appBackground
                }

                // Subtle overall darkening
                Color.black.opacity(0.1)

                // Complex Gradient Overlay to fade into the black background and side
                LinearGradient(
                    colors: [Color.appBackground.opacity(0.9), Color.appBackground.opacity(0.5), .clear, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                
                // Bottom linear gradient to ground the content
                LinearGradient(
                    colors: [Color.appBackground.opacity(0.9), Color.appBackground.opacity(0.4), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func heroContent(scene: Scene) -> some View {
        let hasStream = !sceneStreams.isEmpty || scene.paths?.stream != nil
        let isWaiting = isLoadingDetail || isLoadingStreams
        let hasProgress = (scene.resumeTime ?? 0) > 0
        
        VStack(alignment: .leading, spacing: 16) {
            
            // 1. Studio/Category (Optional top line)
            if let studio = scene.studio {
                Text(studio.name.uppercased())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .tracking(2)
            }

            // 2. Main Title
            Text(scene.title ?? "Untitled Scene")
                .font(.system(size: 80, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 5)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 3. Synopsis / Details (Optional, below title)
            if let details = scene.details, !details.isEmpty {
                Text(details)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(3)
                    .frame(maxWidth: 1000, alignment: .leading)
            }

            // 4. Metadata Line (Duration, Res) + Progress Bar
            HStack(spacing: 24) {
                if let duration = scene.sceneDuration, duration > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text(formattedDuration(duration))
                    }
                    .font(.headline)
                }

                if let resolution = resolutionString(for: scene) {
                    HStack(spacing: 6) {
                        Image(systemName: "tv")
                        Text(resolution)
                    }
                    .font(.headline)
                }

                // Rating Pill
                if let rating100 = scene.rating100, rating100 > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", Double(rating100) / 20.0))
                    }
                    .font(.headline)
                }

                // O-Count Pill
                if let oCounter = scene.oCounter, oCounter > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.circle")
                        Text("\(oCounter)")
                    }
                    .font(.headline)
                }
                
                // Progress Bar inline with metadata
                if let resumeTime = scene.resumeTime, resumeTime > 0, let duration = scene.sceneDuration, duration > 0 {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                        
                        Text("\(Int(resumeTime / duration * 100))%")
                            .font(.headline)
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.3))
                                Rectangle().fill(AppearanceManager.shared.tintColor)
                                    .frame(width: geo.size.width * CGFloat(resumeTime / duration))
                            }
                        }
                        .frame(width: 200, height: 4)
                        .clipShape(Capsule())
                    }
                }
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.top, 8)

            // 5. Action Buttons & Info Pills Row
            HStack(spacing: 20) {
                // Play Action
                Button {
                    startPlayback(for: scene)
                } label: {
                    HStack(spacing: 12) {
                        if isWaiting && !hasStream {
                            ProgressView()
                            Text("Loading")
                        } else if hasStream {
                            Image(systemName: "play.fill")
                            Text(hasProgress ? "Resume" : "Play")
                        } else {
                            Image(systemName: "xmark.circle")
                            Text("No Stream")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .disabled(!hasStream || (isWaiting && !hasStream))

                // Restart Action
                if hasProgress {
                    Button {
                        startPlayback(for: scene, at: 0)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Restart")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resolutionString(for scene: Scene) -> String? {
        guard let file = scene.files?.first, let h = file.height else { return nil }
        if h >= 2160 { return "4K" }
        if h >= 1080 { return "HD" }
        if h >= 720 { return "720p" }
        return "SD"
    }

    // MARK: - Metadata Row

    @ViewBuilder
    private func metadataRow(scene: Scene) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                // Duration
                if let duration = scene.sceneDuration, duration > 0 {
                    metadataPill(icon: "clock", text: formattedDuration(duration))
                }

                // Rating
                if let rating100 = scene.rating100, rating100 > 0 {
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { index in
                            let starValue = Double(index + 1) * 20.0
                            let rating = Double(rating100)
                            Image(systemName: rating >= starValue ? "star.fill" :
                                  (rating >= starValue - 10 ? "star.leadinghalf.filled" : "star"))
                                .font(.title3)
                                .foregroundColor(.yellow)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Play Count
                if let playCount = scene.playCount, playCount > 0 {
                    metadataPill(icon: "play.circle", text: "\(playCount) views")
                }

                // O-Counter
                if let oCounter = scene.oCounter, oCounter > 0 {
                    metadataPill(icon: "heart.circle", text: "\(oCounter)")
                }

                // Resolution
                if let file = scene.files?.first, let w = file.width, let h = file.height {
                    metadataPill(icon: "aspectratio", text: "\(w)×\(h)")
                }
            }
        }
    }

    private func metadataPill(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(AppearanceManager.shared.tintColor)
            Text(text)
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Playback

    private func startPlayback(for scene: Scene, at timestamp: Double? = nil) {
        let startTime = timestamp ?? scene.resumeTime ?? 0
        print("🎬 TV: Starting playback for scene: \(scene.title ?? "Untitled") (ID: \(scene.id)) at \(startTime)s")
        
        if !hasAddedPlay {
            viewModel.addScenePlay(sceneId: scene.id) { newCount in
                if let count = newCount {
                    DispatchQueue.main.async {
                        if var updatedScene = sceneDetail {
                            updatedScene = updatedScene.withPlayCount(count)
                            self.sceneDetail = updatedScene
                        }
                    }
                }
            }
            hasAddedPlay = true
        }
        
        // Prefer HLS stream
        if let hlsStream = sceneStreams.first(where: { $0.mime_type == "application/vnd.apple.mpegurl" }) {
            playerViewModel.setupPlayer(url: URL(string: hlsStream.url)!, sceneId: scene.id, viewModel: viewModel, startAt: startTime)
            return
        }

        // Fallback to MP4
        if let mp4Stream = sceneStreams.first(where: { $0.mime_type == "video/mp4" }) {
            playerViewModel.setupPlayer(url: URL(string: mp4Stream.url)!, sceneId: scene.id, viewModel: viewModel, startAt: startTime)
            return
        }

        // Fallback to direct stream
        if let directPath = scene.paths?.stream {
            if directPath.starts(with: "http://") || directPath.starts(with: "https://") {
                playerViewModel.setupPlayer(url: URL(string: directPath)!, sceneId: scene.id, viewModel: viewModel, startAt: startTime)
            } else if let config = ServerConfigManager.shared.loadConfig() {
                let fullURL = "\(config.baseURL)\(directPath)"
                playerViewModel.setupPlayer(url: URL(string: fullURL)!, sceneId: scene.id, viewModel: viewModel, startAt: startTime)
            }
        }
    }

    // MARK: - Markers Section

    @ViewBuilder
    private func markersSection(markers: [SceneMarker], scene: Scene) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(icon: "bookmark.fill", title: "Markers", count: markers.count)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(markers.sorted { $0.seconds < $1.seconds }) { marker in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                startPlayback(for: scene, at: marker.seconds)
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    if let url = marker.thumbnailURL {
                                        CustomAsyncImage(url: url) { loader in
                                            if let image = loader.image {
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 260, height: 146)
                                                    .clipped()
                                            } else {
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.08))
                                                    .frame(width: 260, height: 146)
                                                    .overlay(ProgressView().scaleEffect(0.8))
                                            }
                                        }
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.08))
                                            .frame(width: 260, height: 146)
                                            .overlay(Image(systemName: "bookmark")
                                                .font(.largeTitle)
                                                .foregroundColor(.white.opacity(0.12)))
                                    }
                                
                                    // Timestamp
                                    Text(formattedDuration(marker.seconds))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                        .padding(8)
                                }
                            }
                            .buttonStyle(.card)
                            
                            Text(marker.title ?? "Untitled Marker")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                                .frame(width: 260, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
            }
        }
    }

    // MARK: - Performers & Studio Section

    @ViewBuilder
    private func performersSection(performers: [ScenePerformer]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(icon: "person.2.fill", title: "Cast", count: performers.count)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(performers) { performer in
                        NavigationLink(value: TVPerformerLink(id: performer.id, name: performer.name)) {
                            VStack(alignment: .leading, spacing: 12) {
                                performerThumbnail(performer: performer)
                                    .frame(width: 180, height: 270)
                                    .clipped()

                                Text(performer.name)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .padding(.top, 4)
                            }
                            .frame(width: 180)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
            }
        }
    }

    @ViewBuilder
    private func studioSection(studio: SceneStudio) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(icon: "building.2.fill", title: "Studio")

            NavigationLink(value: TVStudioLink(id: studio.id, name: studio.name)) {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        if let url = studio.thumbnailURL {
                            CustomAsyncImage(url: url) { loader in
                                if let image = loader.image {
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .padding(25)
                                } else {
                                    studioPlaceholder
                                }
                            }
                        } else {
                            studioPlaceholder
                        }
                    }
                    .frame(width: 320, height: 180)

                    Text(studio.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.top, 4)
                }
                .frame(width: 320)
            }
            .buttonStyle(.card)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }

    private var studioPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.08))
            .overlay(
                Image(systemName: "building.2.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.12))
            )
    }

    @ViewBuilder
    private func performerThumbnail(performer: ScenePerformer) -> some View {
        if let url = performer.thumbnailURL {
            CustomAsyncImage(url: url) { loader in
                if let image = loader.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    performerPlaceholder
                }
            }
        } else {
            performerPlaceholder
        }
    }

    private var performerPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.08))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.12))
            )
    }

    // MARK: - Tags Section

    @ViewBuilder
    private func tagsSection(tags: [Tag]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(icon: "tag.fill", title: "Tags", count: tags.count)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(tags) { tag in
                        NavigationLink(value: TVTagLink(id: tag.id, name: tag.name)) {
                            Text(tag.name)
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 40)
            }
        }
    }


    // MARK: - Reusable Section Heading

    private func sectionHeading(icon: String, title: String, count: Int? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(AppearanceManager.shared.tintColor)
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            if let count = count {
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Helpers

    private func formattedDuration(_ duration: Double) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Player View Model

class TVPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isShowingPlayer = false
    @Published var error: Error?

    private var statusObserver: NSKeyValueObservation?
    private var progressTimer: AnyCancellable?
    private var sceneId: String?
    private var viewModel: StashDBViewModel?

    func setupPlayer(url: URL, sceneId: String, viewModel: StashDBViewModel, startAt timestamp: Double = 0) {
        print("🚀 TV PLAYER VM: Setting up player for URL: \(url.absoluteString) at \(timestamp)s")
        self.sceneId = sceneId
        self.viewModel = viewModel
        
        let newPlayer = createPlayer(for: url)
        
        if timestamp > 0 {
            newPlayer.seek(to: CMTime(seconds: timestamp, preferredTimescale: 600))
        }
        
        statusObserver = newPlayer.currentItem?.observe(\.status, options: [.new, .initial]) { [weak self] item, change in
            DispatchQueue.main.async {
                if item.status == .failed {
                    self?.error = item.error
                    print("❌ TV PLAYER VM: Playback FAILED: \(item.error?.localizedDescription ?? "Unknown error")")
                    if let error = item.error as NSError? {
                        print("❌ TV PLAYER VM: Error domain: \(error.domain), code: \(error.code)")
                        print("❌ TV PLAYER VM: Error user info: \(error.userInfo)")
                    }
                } else if item.status == .readyToPlay {
                    print("✅ TV PLAYER VM: Player item READY to play")
                }
            }
        }
        
        self.player = newPlayer
        self.isShowingPlayer = true
        
        progressTimer = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.saveProgress()
            }
    }

    func saveProgress() {
        guard let player = player,
              let sceneId = sceneId,
              let viewModel = viewModel else { return }
        
        let currentTime = player.currentTime().seconds
        if currentTime > 0 {
            print("💾 TV PLAYER VM: Saving progress: \(currentTime)s for \(sceneId)")
            viewModel.updateSceneResumeTime(sceneId: sceneId, resumeTime: currentTime)
        }
    }

    func clear() {
        saveProgress()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        progressTimer = nil
        statusObserver = nil
        player = nil
        sceneId = nil
        viewModel = nil
    }
}

// MARK: - Embedded Video Player for tvOS Full Screen Cover

struct TVVideoPlayerView: View {
    let player: AVPlayer
    @Binding var isPresented: Bool

    @State private var isPlaying = true

    var body: some View {
        VideoPlayer(player: player) {
            // Empty overlay - VideoPlayer provides native tvOS controls
        }
        .ignoresSafeArea()
        .onAppear {
            player.play()
        }
        .onDisappear {
            // Final progress save handled by VM clear
        }
    }
}
