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
        ScrollView {
            if isLoadingDetail {
                VStack {
                    Spacer(minLength: 200)
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer(minLength: 200)
                }
                .frame(maxWidth: .infinity)
            } else if let scene = sceneDetail {
                VStack(spacing: 40) {
                    heroSection(scene: scene)

                    if let markers = scene.sceneMarkers, !markers.isEmpty {
                        markersSection(markers: markers, scene: scene)
                    }

                    if let details = scene.details, !details.isEmpty {
                        detailsSection(details: details)
                    }

                    metadataRow(scene: scene)

                    if !scene.performers.isEmpty || scene.studio != nil {
                        performersAndStudioSection(performers: scene.performers, studio: scene.studio)
                    }

                    if let tags = scene.tags, !tags.isEmpty {
                        tagsSection(tags: tags)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 24) {
                    Spacer(minLength: 200)
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 56))
                        .foregroundColor(.white.opacity(0.12))
                    Text("Failed to load scene details")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.4))
                    Button("Retry") {
                        loadData()
                    }
                    .font(.title3)
                    Spacer(minLength: 200)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.black)
        .navigationTitle("Scene")
        .onAppear {
            loadData()
        }
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
                // Poster thumbnail
                if let thumbnailURL = scene.thumbnailURL {
                    CustomAsyncImage(url: thumbnailURL) { loader in
                        if loader.isLoading {
                            Rectangle()
                                .fill(Color.gray.opacity(0.08))
                                .aspectRatio(16/9, contentMode: .fit)
                                .overlay(ProgressView().scaleEffect(1.2))
                        } else if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 500)
                                .clipped()
                        } else {
                            placeholderPoster
                        }
                    }
                } else {
                    placeholderPoster
                }

                // Resume progress bar
                if let resumeTime = scene.resumeTime, resumeTime > 0, let duration = scene.sceneDuration, duration > 0 {
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.2)).frame(height: 4)
                                Rectangle().fill(AppearanceManager.shared.tintColor).frame(width: geo.size.width * CGFloat(resumeTime / duration), height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }

                // Gradient overlay
                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.7), .black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 280)
                .allowsHitTesting(false)

                // Title + play info
                VStack(alignment: .leading, spacing: 8) {
                    Text(scene.title ?? "Untitled Scene")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    HStack(spacing: 20) {
                        if let date = scene.date {
                            Text(date)
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        if isWaiting && !hasStream {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else if hasStream {
                            HStack(spacing: 10) {
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
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .buttonStyle(.card)
        .padding(.horizontal, -60)
        .disabled(!hasStream || (isWaiting && !hasStream))
    }

    private var placeholderPoster: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.08))
            .frame(height: 500)
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 64))
                    .foregroundColor(.white.opacity(0.12))
            )
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
                        Button {
                            startPlayback(for: scene, at: marker.seconds)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
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
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                
                                Text(marker.title ?? "Untitled Marker")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                                    .frame(width: 260, alignment: .leading)
                            }
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Performers & Studio Section

    @ViewBuilder
    private func performersAndStudioSection(performers: [ScenePerformer], studio: SceneStudio?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            let totalCount = performers.count + (studio != nil ? 1 : 0)
            sectionHeading(icon: "person.2.fill", title: "Cast & Studio", count: totalCount)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    // Studio
                    if let studio = studio {
                        NavigationLink(destination: TVStudioDetailView(studioId: studio.id, studioName: studio.name)) {
                            VStack(alignment: .leading, spacing: 8) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.08))
                                    .frame(width: 280, height: 158)
                                    .overlay(
                                        Image(systemName: "building.2.fill")
                                            .font(.system(size: 36))
                                            .foregroundColor(.white.opacity(0.12))
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                Text(studio.name)
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .frame(width: 280, alignment: .leading)
                            }
                        }
                        .buttonStyle(.card)
                        
                        if !performers.isEmpty {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 1, height: 120)
                        }
                    }

                    // Performers
                    ForEach(performers) { performer in
                        NavigationLink(destination: TVPerformerDetailView(performerId: performer.id, performerName: performer.name)) {
                            VStack(alignment: .leading, spacing: 8) {
                                performerThumbnail(performer: performer)
                                    .frame(width: 160, height: 240)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                Text(performer.name)
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .frame(width: 160, alignment: .leading)
                            }
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 20)
            }
        }
    }

    private func performerThumbnail(performer: ScenePerformer) -> some View {
        // ScenePerformer only has id/name — no thumbnail URL
        // Full image loads on the performer detail page
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
                HStack(spacing: 12) {
                    ForEach(tags) { tag in
                        Text(tag.name)
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Details Section

    @ViewBuilder
    private func detailsSection(details: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(icon: "text.alignleft", title: "Details")

            Text(details)
                .font(.body)
                .foregroundColor(.white.opacity(0.5))
                .lineSpacing(4)
                .lineLimit(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
