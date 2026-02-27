

#if !os(tvOS)
import SwiftUI
import AVKit

struct SceneVideoPlayerCard: View {
    @Binding var activeScene: Scene
    @Binding var player: AVPlayer?
    @Binding var isPlaybackStarted: Bool
    @Binding var isFullscreen: Bool
    @Binding var isPreviewing: Bool
    @Binding var isHeaderExpanded: Bool
    @Binding var showingAddMarkerSheet: Bool
    @Binding var capturedMarkerTime: Double
    @Binding var playbackSpeed: Double
    
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var handyManager = HandyManager.shared
    @ObservedObject var buttplugManager = ButtplugManager.shared
    @ObservedObject var loveSpouseManager = LoveSpouseManager.shared
    
    // Preview state
    @State private var previewPlayer: AVPlayer?
    @State private var isPressing = false
    
    // Closure for externally handled actions like seeking and playback start
    var onSeek: (Double) -> Void
    var onStartPlayback: (Bool) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            videoPlayerArea
            infoSection
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
        .overlay(expandToggleOverlay, alignment: .bottomTrailing)
    }

    @ViewBuilder
    private var videoPlayerArea: some View {
        VStack(spacing: 0) {
            if activeScene.videoURL != nil {
                if isPlaybackStarted, let player = player {
                    VideoPlayerView(player: player, isFullscreen: $isFullscreen)
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 12,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 12
                            )
                        )
                } else {
                    thumbnailWithOverlay
                }
            } else {
                videoUnavailablePlaceholder
            }
        }
    }

    @ViewBuilder
    private var thumbnailWithOverlay: some View {
        ZStack {
            // Background / Thumbnail
            GeometryReader { geo in
                if let url = activeScene.thumbnailURL {
                    CustomAsyncImage(url: url) { @MainActor loader in
                        if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .skeleton()
                        }
                    }
                } else {
                    Rectangle()
                        .fill(Color.black.opacity(0.9))
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 50))
                                .foregroundColor(.gray.opacity(0.5))
                        )
                }
            }
            
            // Video Preview Overlay
            if isPreviewing, let previewPlayer = previewPlayer {
                GeometryReader { geo in
                    AspectFillVideoPlayer(player: previewPlayer)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            
            // Play Buttons Overlay
            if !isPreviewing {
                if let resumeTime = activeScene.resumeTime, resumeTime > 0 {
                    resumeButtons
                } else {
                    largePlayButton
                }
                
                if let resumeTime = activeScene.resumeTime, resumeTime > 0, let duration = activeScene.sceneDuration, duration > 0 {
                    ProgressView(value: resumeTime, total: duration)
                        .progressViewStyle(LinearProgressViewStyle(tint: appearanceManager.tintColor))
                        .frame(height: 4)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16/9, contentMode: .fit)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 12
            )
        )
        .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in
            isPressing = pressing
            if pressing { startPreview() } else { stopPreview() }
        }, perform: {})
    }

    @ViewBuilder
    private var resumeButtons: some View {
        VStack(spacing: 16) {
            Button(action: { onStartPlayback(true) }) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Resume from \(formatTime(activeScene.resumeTime ?? 0))")
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(appearanceManager.tintColor)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.3), radius: 5)
            }
            
            Button(action: { onStartPlayback(false) }) {
                Text("Start from beginning")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(appearanceManager.tintColor)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 3)
            }
        }
    }

    @ViewBuilder
    private var largePlayButton: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(DesignTokens.Opacity.medium))
                .frame(width: 70, height: 70)
                .blur(radius: 1)
            
            Image(systemName: "play.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .offset(x: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { onStartPlayback(false) }
    }

    @ViewBuilder
    private var videoUnavailablePlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .aspectRatio(16/9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 12
                )
            )
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Video not available")
                        .foregroundColor(.secondary)
                }
            )
    }

    @ViewBuilder
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(activeScene.title ?? "Unbekannter Titel")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(2)

            markerScrollView
            metadataSwipeBar
            
            if let details = activeScene.details, !details.isEmpty {
                Text(details)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(isHeaderExpanded ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .padding(.bottom, (activeScene.details?.isEmpty ?? true) ? 0 : 20)
        .background(Color(UIColor.systemBackground))
    }

    @ViewBuilder
    private var markerScrollView: some View {
        if let markers = activeScene.sceneMarkers, !markers.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(markers.sorted { $0.seconds < $1.seconds }) { marker in
                        Button(action: { onSeek(marker.seconds) }) {
                            markerThumbnail(marker)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.horizontal, -12)
        }
    }

    @ViewBuilder
    private var metadataSwipeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // O-Counter
                Button(action: {
                    HapticManager.light()
                    viewModel.incrementOCounter(sceneId: activeScene.id) { newCount in
                        if let count = newCount {
                            DispatchQueue.main.async { activeScene = activeScene.withOCounter(count) }
                        }
                    }
                }) {
                    infoPill(icon: AppearanceManager.shared.oCounterIconFilled, text: "\(activeScene.oCounter ?? 0)", color: .red)
                }
                .buttonStyle(.plain)
                
                // Add Marker Button
                Button(action: {
                    capturedMarkerTime = player?.currentTime().seconds ?? 0
                    showingAddMarkerSheet = true
                }) {
                    infoPill(icon: "plus.square.fill.on.square.fill", text: "Marker", color: .green)
                }
                .buttonStyle(.plain)
                
                // Audio Sync - Always shown to allow manual override
                audioSyncButton
                
                ratingMenu
                playbackSpeedMenu
                qualityMenu

                if DownloadManager.shared.isDownloaded(id: activeScene.id) {
                    infoPill(icon: "checkmark.circle.fill", text: "Downloaded", color: .green)
                }
                

                if activeScene.organized == true {
                    infoPill(icon: "checkmark.seal.fill", text: "Organized", color: .green)
                }
                if let date = activeScene.date {
                    infoPill(icon: "calendar", text: date)
                }
                if let duration = activeScene.sceneDuration {
                    infoPill(icon: "clock", text: formatTime(duration))
                }
                if let playCount = activeScene.playCount, playCount > 0 {
                    infoPill(icon: "play.circle", text: "\(playCount) plays")
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, -12)
    }

    @ViewBuilder
    private var ratingMenu: some View {
        Menu {
            Section("Rate Scene") {
                ForEach((1...5).reversed(), id: \.self) { starCount in
                    Button(action: {
                        let newRating = starCount * 20
                        viewModel.updateSceneRating(sceneId: activeScene.id, rating100: newRating) { success in
                            if success {
                                DispatchQueue.main.async { activeScene = activeScene.withRating(newRating) }
                            }
                        }
                    }) {
                        Label("\(starCount) Stars", systemImage: "star.fill")
                    }
                }
                
                Button(role: .destructive, action: {
                    viewModel.updateSceneRating(sceneId: activeScene.id, rating100: nil) { success in
                        if success {
                            DispatchQueue.main.async { activeScene = activeScene.withRating(nil) }
                        }
                    }
                }) {
                    Label("No Rating", systemImage: "star.slash")
                }
            }
        } label: {
            let stars = Double(activeScene.rating100 ?? 0) / 20.0
            infoPill(
                icon: activeScene.rating100 == nil ? "star" : "star.fill",
                text: activeScene.rating100 == nil ? "Rate" : String(format: "%.1f", stars),
                color: activeScene.rating100 == nil ? .secondary : .orange
            )
        }
    }

    @ViewBuilder
    private var playbackSpeedMenu: some View {
        Menu {
            Section("Playback Speed") {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Button(action: {
                        playbackSpeed = speed
                        if player?.timeControlStatus == .playing {
                            player?.rate = Float(speed)
                        }
                    }) {
                        HStack {
                            Text(String(format: "%.2fx", speed))
                            if playbackSpeed == speed { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            infoPill(icon: "speedometer", text: String(format: "%.2fx", playbackSpeed), color: .purple)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var qualityMenu: some View {
        if let streams = activeScene.streams, !streams.isEmpty {
            Menu {
                ForEach(streams.filter { $0.mime_type == "application/vnd.apple.mpegurl" }.sorted(by: { s1, s2 in 
                    let r1 = Int(s1.label.lowercased().replacingOccurrences(of: "p", with: "")) ?? 0
                    let r2 = Int(s2.label.lowercased().replacingOccurrences(of: "p", with: "")) ?? 0
                    return r1 > r2
                }), id: \.url) { stream in
                    Button(action: {
                        if let url = URL(string: stream.url) {
                            let currentTime = player?.currentTime() ?? .zero
                            let wasPlaying = player?.rate ?? 0 > 0
                            let authenticatedURL = signedURL(url) ?? url
                            let asset = AVURLAsset(url: authenticatedURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["ApiKey": ServerConfigManager.shared.activeConfig?.secureApiKey ?? ""]])
                            let newItem = AVPlayerItem(asset: asset)
                            player?.replaceCurrentItem(with: newItem)
                            player?.seek(to: currentTime)
                            player?.rate = Float(playbackSpeed)
                            if wasPlaying { player?.play() }
                        }
                    }) {
                        HStack {
                            Text(stream.label)
                            if let urlAsset = player?.currentItem?.asset as? AVURLAsset, urlAsset.url.absoluteString == stream.url {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let currentLabel: String = {
                    if let asset = player?.currentItem?.asset as? AVURLAsset,
                       let activeStream = streams.first(where: { $0.url == asset.url.absoluteString }) {
                        return activeStream.label
                    }
                    if let firstFile = activeScene.files?.first, let height = firstFile.height {
                        return height >= 2160 ? "4K" : (height >= 1080 ? "1080p" : (height >= 720 ? "720p" : "\(height)p"))
                    }
                    return "Quality"
                }()
                infoPill(icon: "video.fill", text: currentLabel, color: .blue)
            }
        } else if let firstFile = activeScene.files?.first, let height = firstFile.height {
            let res = height >= 2160 ? "4K" : (height >= 1080 ? "1080p" : (height >= 720 ? "720p" : "\(height)p"))
            infoPill(icon: "video.fill", text: res, color: .blue)
        }
    }

    @ViewBuilder
    private var expandToggleOverlay: some View {
        if let details = activeScene.details, !details.isEmpty {
            Button(action: {
                withAnimation(.spring()) { isHeaderExpanded.toggle() }
            }) {
                Image(systemName: isHeaderExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(appearanceManager.tintColor)
                    .padding(6)
                    .background(appearanceManager.tintColor.opacity(0.1))
                    .clipShape(Circle())
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func markerThumbnail(_ marker: SceneMarker) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                if let url = marker.thumbnailURL {
                    CustomAsyncImage(url: url) { @MainActor loader in
                        if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 45)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .frame(width: 80, height: 45)
                                .skeleton()
                        }
                    }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 45)
                        .overlay(Image(systemName: "bookmark").foregroundColor(.secondary))
                }
                
                // Timestamp label
                Text(formatTime(marker.seconds))
                    .font(.system(size: 8))
                    .fontWeight(.bold)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            
            // Marker Title
            Text(marker.title ?? "Marker at \(formatTime(marker.seconds))")
                .font(.system(size: 10))
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: 80, alignment: .leading)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    @ViewBuilder
    private func infoPill(icon: String, text: String, color: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .clipShape(Capsule())
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
        previewPlayer?.seek(to: CMTime.zero)
    }

    private var audioSyncButton: some View {
        Button {
            withAnimation {
                let targetState = !handyManager.isAudioMode
                handyManager.isAudioMode = targetState
                buttplugManager.isAudioMode = targetState
                loveSpouseManager.isAudioMode = targetState
                
                // Automatically activate analysis when showing the card
                if targetState {
                    AudioAnalysisManager.shared.isActive = true
                } else {
                    AudioAnalysisManager.shared.stop()
                }
            }
            HapticManager.medium()
        } label: {
            let isAudioActive = handyManager.isAudioMode
            infoPill(icon: isAudioActive ? "waveform.and.mic" : "waveform", 
                     text: isAudioActive ? "Sync ON" : "Audio Sync", 
                     color: isAudioActive ? .purple : .secondary)
        }
    }
}
#endif
