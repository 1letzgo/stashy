//
//  TVSceneDetailView.swift
//  stashyTV
//
//  Created for tvOS on 08.02.26.
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
        ScrollView {
            if isLoadingDetail {
                VStack {
                    Spacer(minLength: 200)
                    ProgressView("Loading scene details...")
                        .font(.title2)
                    Spacer(minLength: 200)
                }
                .frame(maxWidth: .infinity)
            } else if let scene = sceneDetail {
                VStack(spacing: 40) {
                    // MARK: - Hero Image / Poster
                    heroSection(scene: scene)

                    // MARK: - Markers Section
                    if let markers = scene.sceneMarkers, !markers.isEmpty {
                        markersSection(markers: markers, scene: scene)
                    }

                    // MARK: - Details Text
                    if let details = scene.details, !details.isEmpty {
                        detailsSection(details: details)
                    }

                    // MARK: - Metadata Row
                    metadataRow(scene: scene)

                    // MARK: - Performers & Studio Section
                    if !scene.performers.isEmpty || scene.studio != nil {
                        performersAndStudioSection(performers: scene.performers, studio: scene.studio)
                    }

                    // MARK: - Tags Section
                    if let tags = scene.tags, !tags.isEmpty {
                        tagsSection(tags: tags)
                    }


                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 20) {
                    Spacer(minLength: 200)
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Failed to load scene details")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        loadData()
                    }
                    .font(.title3)
                    Spacer(minLength: 200)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            loadData()
        }
        .fullScreenCover(isPresented: $playerViewModel.isShowingPlayer, onDismiss: {
            playerViewModel.clear()
            // Refresh detail to show updated resume progress
            loadData()
        }) {
            if let player = playerViewModel.player {
                TVVideoPlayerView(player: player, isPresented: $playerViewModel.isShowingPlayer)
            }
        }
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

    // MARK: - Hero Section

    @ViewBuilder
    private func heroSection(scene: Scene) -> some View {
        let hasStream = !sceneStreams.isEmpty || scene.paths?.stream != nil
        let isWaiting = isLoadingDetail || isLoadingStreams
        
        Button {
            startPlayback(for: scene)
        } label: {
            ZStack(alignment: .bottomLeading) {
                // Large poster / thumbnail
                if let thumbnailURL = scene.thumbnailURL {
                    CustomAsyncImage(url: thumbnailURL) { loader in
                        if loader.isLoading {
                            Rectangle()
                                .fill(Color.gray.opacity(0.15))
                                .aspectRatio(16/9, contentMode: .fit)
                                .overlay(ProgressView())
                        } else if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 450)
                                .clipped()
                        } else {
                            placeholderPoster
                        }
                    }
                } else {
                    placeholderPoster
                }

                // Progress bar for resume time (absolute bottom)
                if let resumeTime = scene.resumeTime, resumeTime > 0, let duration = scene.sceneDuration, duration > 0 {
                    ProgressView(value: resumeTime, total: duration)
                        .progressViewStyle(LinearProgressViewStyle(tint: AppearanceManager.shared.tintColor))
                        .frame(height: 6)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }

                // Gradient overlay
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 250)
                .allowsHitTesting(false)

                // Title overlay
                VStack(alignment: .leading, spacing: 8) {
                    Text(scene.title ?? "Untitled Scene")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    HStack(spacing: 20) {
                        if let date = scene.date {
                            Text(date)
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        if isWaiting && !hasStream {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else if hasStream {
                            HStack(spacing: 12) {
                                Image(systemName: "play.fill")
                                if let resumeTime = scene.resumeTime, resumeTime > 0 {
                                    Text("Resume from \(formattedDuration(resumeTime))")
                                } else {
                                    Text("Play")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                        } else {
                            Text("No Stream")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .buttonStyle(.card)
        .padding(.horizontal, -60) // Let it span wider
        .disabled(!hasStream || (isWaiting && !hasStream))
    }

    private var placeholderPoster: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .frame(height: 450)
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 72))
                    .foregroundColor(.secondary)
            )
    }

    // MARK: - Metadata Row

    @ViewBuilder
    private func metadataRow(scene: Scene) -> some View {
        HStack(spacing: 40) {
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
                            .font(.title2)
                            .foregroundColor(.yellow)
                    }
                    Text("(\(rating100)/100)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
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
                metadataPill(icon: "aspectratio", text: "\(w)x\(h)")
            }

        }
    }

    private func metadataPill(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
            Text(text)
                .font(.title3)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }


    private func startPlayback(for scene: Scene, at timestamp: Double? = nil) {
        let startTime = timestamp ?? scene.resumeTime ?? 0
        print("🎬 TV: Starting playback for scene: \(scene.title ?? "Untitled") (ID: \(scene.id)) at \(startTime)s")
        
        // Increment play count (only once per view session)
        if !hasAddedPlay {
            viewModel.addScenePlay(sceneId: scene.id) { newCount in
                if let count = newCount {
                    DispatchQueue.main.async {
                        // Reflect the new count in the UI immediately
                        if var updatedScene = sceneDetail {
                            updatedScene = updatedScene.withPlayCount(count)
                            self.sceneDetail = updatedScene
                        }
                    }
                }
            }
            hasAddedPlay = true
        }
        
        // Prefer HLS stream (Best for tvOS)
        if let hlsStream = sceneStreams.first(where: { $0.mime_type == "application/vnd.apple.mpegurl" }) {
            playerViewModel.setupPlayer(url: URL(string: hlsStream.url)!, sceneId: scene.id, viewModel: viewModel, startAt: startTime)
            return
        }

        // Fallback to first MP4 transcode stream
        if let mp4Stream = sceneStreams.first(where: { $0.mime_type == "video/mp4" }) {
            playerViewModel.setupPlayer(url: URL(string: mp4Stream.url)!, sceneId: scene.id, viewModel: viewModel, startAt: startTime)
            return
        }

        // Fallback to direct stream path
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
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(markers.sorted { $0.seconds < $1.seconds }) { marker in
                        Button {
                            startPlayback(for: scene, at: marker.seconds)
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                // Marker Thumbnail
                                ZStack(alignment: .bottomTrailing) {
                                    if let url = marker.thumbnailURL {
                                        CustomAsyncImage(url: url) { loader in
                                            if let image = loader.image {
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 240, height: 135) // 16:9 aspect ratio
                                                    .clipped()
                                            } else {
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.15))
                                                    .frame(width: 240, height: 135)
                                                    .overlay(ProgressView())
                                            }
                                        }
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.15))
                                            .frame(width: 240, height: 135)
                                            .overlay(Image(systemName: "bookmark")
                                                .font(.largeTitle)
                                                .foregroundColor(.secondary))
                                    }
                                
                                    // Timestamp Badge
                                    Text(formattedDuration(marker.seconds))
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.black.opacity(0.7))
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .padding(6)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                // Marker Title
                                Text(marker.title ?? "Untitled Marker")
                                    .font(.callout)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .frame(width: 240, alignment: .leading)
                            }
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 30) // Increased padding for focus expansion
            }
        }
    }

    // MARK: - Performers & Studio Section

    @ViewBuilder
    private func performersAndStudioSection(performers: [ScenePerformer], studio: SceneStudio?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Performers & Studio")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 40) {
                    // Studio (Optional)
                    if let studio = studio {
                        NavigationLink(destination: TVStudioDetailView(studioId: studio.id, studioName: studio.name)) {
                            StudioButtonContent(studio: studio)
                        }
                        .buttonStyle(.plain)
                        
                        if !performers.isEmpty {
                            Divider()
                                .frame(height: 120)
                                .background(Color.secondary.opacity(0.3))
                        }
                    }

                    // Performers
                    ForEach(performers) { performer in
                        NavigationLink(destination: TVPerformerDetailView(performerId: performer.id, performerName: performer.name)) {
                            PerformerButtonContent(performer: performer)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 4)
            }
        }
    }

    struct StudioButtonContent: View {
        let studio: SceneStudio
        @Environment(\.isFocused) var isFocused
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    // Background for the inset
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isFocused ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.ultraThinMaterial))
                        .scaleEffect(isFocused ? 1.1 : 1.0)

                    CustomAsyncImage(url: studio.thumbnailURL) { loader in
                        if let image = loader.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .overlay(Image(systemName: "building.2.fill").font(.system(size: 40)).foregroundColor(.secondary))
                        }
                    }
                    .frame(width: 320 - 16, height: 180 - 16)
                    .cornerRadius(8)
                    .padding(8)
                    .scaleEffect(isFocused ? 1.1 : 1.0)
                    .clipped()
                }
                .frame(width: 320, height: 180)
                .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 10, y: 10)
                
                Text(studio.name)
                    .font(.headline)
                    .foregroundColor(isFocused ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: 320, alignment: .leading)
                    .scaleEffect(isFocused ? 1.05 : 1.0)
            }
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.3), value: isFocused)
        }
    }

    struct PerformerButtonContent: View {
        let performer: ScenePerformer
        @Environment(\.isFocused) var isFocused
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    // Background for the inset
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isFocused ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.ultraThinMaterial))
                        .scaleEffect(isFocused ? 1.1 : 1.0)

                    CustomAsyncImage(url: performer.thumbnailURL) { loader in
                        if let image = loader.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .overlay(Image(systemName: "person.fill").font(.system(size: 40)).foregroundColor(.secondary))
                        }
                    }
                    .frame(width: 200 - 12, height: 300 - 12)
                    .cornerRadius(8)
                    .padding(6)
                    .scaleEffect(isFocused ? 1.1 : 1.0)
                    .clipped()
                }
                .frame(width: 200, height: 300)
                .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 10, y: 10)

                Text(performer.name)
                    .font(.headline)
                    .foregroundColor(isFocused ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: 200, alignment: .leading)
                    .scaleEffect(isFocused ? 1.05 : 1.0)
            }
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.3), value: isFocused)
        }
    }

    // MARK: - Tags Section

    @ViewBuilder
    private func tagsSection(tags: [Tag]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Tags")
                .font(.title2)
                .fontWeight(.bold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(tags) { tag in
                        Text(tag.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 30) // Increased padding for focus expansion
            }
        }
    }

    // MARK: - Details Section

    @ViewBuilder
    private func detailsSection(details: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.title2)
                .fontWeight(.bold)

            Text(details)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
        
        // Observe player item status for errors
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
        
        // Setup periodic progress updates
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

// Note: TVPerformerDetailView is in TVPerformerDetailView.swift
// Note: TVStudioDetailView is in TVStudioDetailView.swift
