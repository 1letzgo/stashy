//
//  TVSceneDetailView.swift
//  stashyTV
//
//  Scene detail for tvOS — Netflix/Prime style
//

import SwiftUI
import AVKit
import Combine
import KSPlayer

struct TVSceneDetailView: View {
    let sceneId: String

    @ObservedObject private var configManager = ServerConfigManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @StateObject private var playerViewModel = TVPlayerViewModel()
    @State private var sceneDetail: Scene?
    @State private var sceneStreams: [SceneStream] = []
    @State private var isLoadingDetail = true
    @State private var isLoadingStreams = true
    @State private var hasAddedPlay = false
    @Namespace private var focusNS
    @Environment(\.resetFocus) private var resetFocus

    /// Same idea as iOS `ScenesView`: list/detail only treat transport/config as “connection” errors.
    private var hasValidActiveServer: Bool {
        guard let config = configManager.activeConfig else { return false }
        return config.hasValidConfig
    }

    private var shouldShowConnectionFailure: Bool {
        let msg = viewModel.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !msg.isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()
            
            // Full Screen Hero Background
            if let scene = sceneDetail {
                heroBackground(scene: scene)
            }
            
            ScrollView(showsIndicators: false) {
                if !hasValidActiveServer {
                    TVConnectionErrorView(
                        title: "Server not reachable",
                        subtitle: "Add a server in Settings.",
                        onRetry: retryConnectionAndReload
                    )
                } else if isLoadingDetail {
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
                } else if shouldShowConnectionFailure {
                    TVConnectionErrorView(
                        title: "Server not reachable",
                        subtitle: viewModel.errorMessage,
                        onRetry: retryConnectionAndReload
                    )
                } else {
                    sceneNotFoundView
                }
            }
        }
        .navigationTitle("")
        .onAppear {
            if hasValidActiveServer {
                loadData()
            } else {
                isLoadingDetail = false
                isLoadingStreams = false
            }
        }
        .onPlayPauseCommand {
            if sceneDetail != nil {
                if let playerLayer = playerViewModel.ksCoordinator.playerLayer {
                    if playerLayer.player.isPlaying {
                        playerLayer.pause()
                    } else {
                        playerLayer.play()
                    }
                }
            }
        }
        .focusScope(focusNS)
        .fullScreenCover(isPresented: $playerViewModel.isShowingPlayer, onDismiss: {
            playerViewModel.clear()
            loadData(silent: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                resetFocus(in: focusNS)
            }
        }) {
            TVVideoPlayerView(
                playerViewModel: playerViewModel,
                isPresented: $playerViewModel.isShowingPlayer,
                sceneTitle: sceneDetail?.title,
                vttURLString: sceneDetail?.paths?.vtt,
                spriteURLString: sceneDetail?.paths?.sprite
            )
        }
    }

    /// Scene missing or GraphQL returned null without a network error (e.g. deleted on server).
    private var sceneNotFoundView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 300)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.12))
            Text("Failed to load scene details")
                .font(.title2)
                .foregroundColor(.white.opacity(0.4))
            Button("Retry") {
                retryConnectionAndReload()
            }
            .font(.title3)
            Spacer(minLength: 300)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data Loading

    /// Re-test reachability then reload — mirrors iOS list screens calling `performSearch` after `ConnectionErrorView`.
    private func retryConnectionAndReload() {
        viewModel.testConnection()
        loadData()
    }

    private func loadData(silent: Bool = false) {
        guard hasValidActiveServer else {
            if !silent {
                isLoadingDetail = false
                isLoadingStreams = false
            }
            return
        }

        if !silent {
            isLoadingDetail = true
            isLoadingStreams = true
        }

        viewModel.fetchSceneDetails(sceneId: sceneId) { scene in
            self.sceneDetail = scene
            if !silent { self.isLoadingDetail = false }
        }

        if !silent {
            viewModel.fetchSceneStreams(sceneId: sceneId) { streams in
                self.sceneStreams = streams
                self.isLoadingStreams = false
            }
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
                .prefersDefaultFocus(in: focusNS)

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
        
        let quality = ServerConfigManager.shared.activeConfig?.defaultQuality ?? .original

        // KSPlayer handles all container formats (MKV, AVI, etc.) natively via FFmpeg,
        // so no format-gating is needed. Just respect the user's quality preference.
        let sceneWithStreams = scene.withStreams(sceneStreams)
        if let streamURL = sceneWithStreams.bestStream(for: quality) {
            playerViewModel.setupPlayer(url: streamURL, sceneId: scene.id, viewModel: viewModel, startAt: startTime)
            return
        }

        if let directPath = scene.paths?.stream {
            let fullURL: String
            if directPath.starts(with: "http://") || directPath.starts(with: "https://") {
                fullURL = directPath
            } else if let config = ServerConfigManager.shared.activeConfig {
                fullURL = "\(config.baseURL)\(directPath)"
            } else {
                return
            }
            if let url = URL(string: fullURL) {
                playerViewModel.setupPlayer(url: url, sceneId: scene.id, viewModel: viewModel, startAt: startTime)
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
                        NavigationLink(destination: TVPerformerDetailView(performerId: performer.id, performerName: performer.name).tvExitDismissable()) {
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

            NavigationLink(destination: TVStudioDetailView(studioId: studio.id, studioName: studio.name).tvExitDismissable()) {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        TVStudioImageView(studioId: studio.id, studioName: studio.name, contentMode: .fit)
                            .padding(25)
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
                        NavigationLink(destination: TVTagDetailView(tagId: tag.id, tagName: tag.name).tvExitDismissable()) {
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
            // tvOS focus: make this row a separate focus section so the user can move up/down
            // from any tag (not only after returning to the first item).
            .focusSection()
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
    @Published var playbackURL: URL?
    @Published var startSeconds: Double = 0
    @Published var isShowingPlayer = false
    @Published var error: Error?

    let ksCoordinator = KSVideoPlayer.Coordinator()
    private var progressTimer: AnyCancellable?
    private var sceneId: String?
    private var viewModel: StashDBViewModel?

    func setupPlayer(url: URL, sceneId: String, viewModel: StashDBViewModel, startAt timestamp: Double = 0) {
        let authenticatedURL = signedURL(url) ?? url
        self.sceneId = sceneId
        self.viewModel = viewModel
        self.startSeconds = max(0, timestamp)
        self.playbackURL = authenticatedURL
        self.isShowingPlayer = true

        progressTimer = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.saveProgress()
            }
    }

    func saveProgress() {
        guard let sceneId, let viewModel else { return }
        let currentTime = ksCoordinator.playerLayer?.player.currentPlaybackTime ?? 0
        if currentTime > 0 {
            viewModel.updateSceneResumeTime(sceneId: sceneId, resumeTime: currentTime)
        }
    }

    func clear() {
        saveProgress()
        progressTimer = nil
        ksCoordinator.resetPlayer()
        playbackURL = nil
        sceneId = nil
        viewModel = nil
    }
}

// MARK: - Embedded Video Player for tvOS Full Screen Cover

struct TVVideoPlayerView: View {
    @ObservedObject var playerViewModel: TVPlayerViewModel
    @ObservedObject private var timeModel: ControllerTimeModel
    @Binding var isPresented: Bool
    var sceneTitle: String?
    var vttURLString: String?
    var spriteURLString: String?

    init(playerViewModel: TVPlayerViewModel, isPresented: Binding<Bool>, sceneTitle: String? = nil, vttURLString: String? = nil, spriteURLString: String? = nil) {
        self.playerViewModel = playerViewModel
        self._timeModel = ObservedObject(wrappedValue: playerViewModel.ksCoordinator.timemodel)
        self._isPresented = isPresented
        self.sceneTitle = sceneTitle
        self.vttURLString = vttURLString
        self.spriteURLString = spriteURLString
    }

    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var seekTargetTime: Double = 0
    @State private var panAnchorTime: Double = 0
    @StateObject private var spritePreview = SpritePreviewManager()

    private var coordinator: KSVideoPlayer.Coordinator { playerViewModel.ksCoordinator }
    private var isPlaying: Bool {
        let s = coordinator.state
        return s == .buffering || s == .bufferFinished
    }
    private var currentPlaybackTime: Double {
        coordinator.playerLayer?.player.currentPlaybackTime ?? Double(timeModel.currentTime)
    }

    var body: some View {
        if let url = playerViewModel.playbackURL {
            ZStack {
                KSVideoPlayer(coordinator: coordinator, url: url, options: tvKSOptions())
                    .onStateChanged { playerLayer, state in
                        if state == .readyToPlay, playerViewModel.startSeconds > 0.25 {
                            let seekTo = playerViewModel.startSeconds
                            playerViewModel.startSeconds = 0
                            playerLayer.seek(time: seekTo, autoPlay: true) { _ in }
                        }
                        if state == .bufferFinished {
                            scheduleHide()
                        }
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                TVRemoteInputView(
                    onSelect: { handleSelectOrPlayPause() },
                    onPlayPause: { handleSelectOrPlayPause() },
                    onLeft: { handleHorizontal(scrubDelta: -20, skipInterval: -20) },
                    onRight: { handleHorizontal(scrubDelta: 20, skipInterval: 20) },
                    onUp: {
                        if isPlaying {
                            coordinator.skip(interval: 180)
                            flashControls()
                        }
                    },
                    onDown: {
                        if isPlaying {
                            coordinator.skip(interval: -180)
                            flashControls()
                        }
                    },
                    onMenu: {
                        if isScrubbing {
                            cancelScrub()
                        } else if showControls {
                            showControls = false
                        } else {
                            isPresented = false
                        }
                    },
                    onPan: { translation, state in
                        handleScrubPan(translation: translation, state: state)
                    }
                )

                if showControls {
                    transportOverlay
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showControls)
            .animation(.easeInOut(duration: 0.2), value: isScrubbing)
            .onAppear {
                spritePreview.load(vttURLString: vttURLString, spriteURLString: spriteURLString)
            }
            .onDisappear {
                hideTask?.cancel()
            }
        }
    }

    // MARK: - Transport Overlay

    @ViewBuilder
    private var transportOverlay: some View {
        let currentActual = Double(timeModel.currentTime)
        let total = Double(max(timeModel.totalTime, 1))
        let displayTime = isScrubbing ? seekTargetTime : currentActual
        let fraction = min(max(displayTime / total, 0), 1)

        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .init(x: 0.5, y: 0.5),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                if let title = sceneTitle, !title.isEmpty {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }

                GeometryReader { geo in
                    let barHeight: CGFloat = 8
                    let playedWidth = geo.size.width * fraction

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.15))
                            .overlay { Capsule().fill(.ultraThinMaterial) }
                            .environment(\.colorScheme, .dark)
                            .frame(height: barHeight)

                        if isScrubbing {
                            let currentFraction = min(max(currentActual / total, 0), 1)
                            Capsule()
                                .fill(Color.white.opacity(0.4))
                                .frame(width: max(geo.size.width * currentFraction, barHeight), height: barHeight)
                        }

                        Capsule()
                            .fill(Color.white)
                            .shadow(color: .white.opacity(0.5), radius: 4, x: 0, y: 0)
                            .frame(width: max(playedWidth, barHeight), height: barHeight)
                            .animation(.easeOut(duration: 0.3), value: playedWidth)
                    }
                    .overlay(alignment: .bottom) {
                        if isScrubbing {
                            spriteSeekPreview(seekTime: seekTargetTime, barWidth: geo.size.width, fraction: fraction)
                                .offset(y: -20)
                        }
                    }
                }
                .frame(height: 8)

                HStack(spacing: 8) {
                    Text(formatTime(displayTime))
                        .monospacedDigit()
                    Image(systemName: isPlaying ? "play.circle.fill" : "pause.circle.fill")
                        .font(.callout)

                    Spacer()

                    Text("-\(formatTime(max(0, total - displayTime)))")
                        .monospacedDigit()
                }
                .font(.callout)
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Sprite Seek Preview

    @ViewBuilder
    private func spriteSeekPreview(seekTime: Double, barWidth: CGFloat, fraction: Double) -> some View {
        let thumbWidth: CGFloat = 280
        let thumbHeight: CGFloat = 158
        let halfThumb = thumbWidth / 2
        let centerX = barWidth * fraction
        let clampedX = min(max(centerX, halfThumb), barWidth - halfThumb)

        VStack(spacing: 6) {
            if let frame = spritePreview.frameImage(at: seekTime) {
                Image(uiImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .overlay(
                        Text(formatTime(seekTime))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )
            }
        }
        .fixedSize()
        .position(x: clampedX, y: -(thumbHeight / 2))
    }

    // MARK: - Scrubbing

    private func handleSelectOrPlayPause() {
        if isScrubbing {
            commitScrub()
        } else {
            togglePlayPause()
            flashControls()
        }
    }

    private func handleHorizontal(scrubDelta: Double, skipInterval: Int) {
        if !isPlaying {
            enterOrContinueScrub(delta: scrubDelta)
        } else {
            coordinator.skip(interval: skipInterval)
            flashControls()
        }
    }

    private func enterOrContinueScrub(delta: Double) {
        let total = Double(timeModel.totalTime)
        guard total > 0 else { return }

        let base = isScrubbing ? seekTargetTime : currentPlaybackTime
        seekTargetTime = max(0, min(base + delta, total))
        if !isScrubbing { isScrubbing = true }
        showControls = true
        hideTask?.cancel()
    }

    private func commitScrub() {
        guard isScrubbing, let layer = coordinator.playerLayer else { return }
        isScrubbing = false
        layer.seek(time: seekTargetTime, autoPlay: true) { _ in }
        flashControls()
    }

    private func cancelScrub() {
        isScrubbing = false
        flashControls()
    }

    private func handleScrubPan(translation: CGFloat, state: UIGestureRecognizer.State) {
        guard !isPlaying else { return }
        let total = Double(timeModel.totalTime)
        guard total > 0 else { return }

        switch state {
        case .began:
            panAnchorTime = isScrubbing ? seekTargetTime : currentPlaybackTime
            if !isScrubbing { isScrubbing = true }
            showControls = true
            hideTask?.cancel()
        case .changed:
            let offset = Double(translation / 1600) * total
            seekTargetTime = max(0, min(panAnchorTime + offset, total))
        default:
            break
        }
    }

    // MARK: - Helpers

    private func togglePlayPause() {
        if let layer = coordinator.playerLayer {
            if isPlaying {
                layer.pause()
            } else {
                layer.play()
            }
        }
    }

    private func flashControls() {
        showControls = true
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            if isPlaying && !isScrubbing {
                showControls = false
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }

    private func tvKSOptions() -> KSOptions {
        let o = KSOptions()
        o.preferredForwardBufferDuration = 2
        if let key = ServerConfigManager.shared.activeConfig?.secureApiKey, !key.isEmpty {
            o.appendHeader(["ApiKey": key])
        }
        return o
    }
}

// MARK: - Focus-owning UIKit view for Siri Remote input

struct TVRemoteInputView: UIViewRepresentable {
    var onSelect: () -> Void
    var onPlayPause: () -> Void
    var onLeft: () -> Void
    var onRight: () -> Void
    var onUp: () -> Void
    var onDown: () -> Void
    var onMenu: () -> Void
    var onPan: ((CGFloat, UIGestureRecognizer.State) -> Void)?

    func makeUIView(context: Context) -> TVRemoteInputUIView {
        let view = TVRemoteInputUIView()
        view.onSelect = onSelect
        view.onPlayPause = onPlayPause
        view.onLeft = onLeft
        view.onRight = onRight
        view.onUp = onUp
        view.onDown = onDown
        view.onMenu = onMenu
        view.onPan = onPan
        return view
    }

    func updateUIView(_ uiView: TVRemoteInputUIView, context: Context) {
        uiView.onSelect = onSelect
        uiView.onPlayPause = onPlayPause
        uiView.onLeft = onLeft
        uiView.onRight = onRight
        uiView.onUp = onUp
        uiView.onDown = onDown
        uiView.onMenu = onMenu
        uiView.onPan = onPan
    }
}

final class TVRemoteInputUIView: UIView {
    var onSelect: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onMenu: (() -> Void)?
    var onPan: ((CGFloat, UIGestureRecognizer.State) -> Void)?

    private var repeatTimer: Timer?
    private var panRecognizer: UIPanGestureRecognizer?

    override var canBecomeFocused: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
            if panRecognizer == nil {
                let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
                addGestureRecognizer(pan)
                panRecognizer = pan
            }
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self).x
        onPan?(translation, recognizer.state)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first else {
            super.pressesBegan(presses, with: event)
            return
        }
        switch press.type {
        case .select:
            onSelect?()
        case .playPause:
            onPlayPause?()
        case .leftArrow:
            onLeft?()
            startRepeat { [weak self] in self?.onLeft?() }
        case .rightArrow:
            onRight?()
            startRepeat { [weak self] in self?.onRight?() }
        case .upArrow:
            onUp?()
            startRepeat { [weak self] in self?.onUp?() }
        case .downArrow:
            onDown?()
            startRepeat { [weak self] in self?.onDown?() }
        case .menu:
            onMenu?()
        default:
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        stopRepeat()
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        stopRepeat()
        super.pressesCancelled(presses, with: event)
    }

    private func startRepeat(_ action: @escaping () -> Void) {
        stopRepeat()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            action()
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}
