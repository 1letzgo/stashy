
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
    
    // Preview state
    @State private var previewPlayer: AVPlayer?
    @State private var isPressing = false
    
    // Closure for externally handled actions like seeking and playback start
    var onSeek: (Double) -> Void
    var onStartPlayback: (Bool) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. Video Player Area (Top Rounded)
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
                        // Preview/Poster state with Play Button
                        ZStack {
                            // Background / Thumbnail - constrained to 16:9
                            GeometryReader { geo in
                                if let url = activeScene.thumbnailURL {
                                    CustomAsyncImage(url: url) { loader in
                                        if let image = loader.image {
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: geo.size.width, height: geo.size.height)
                                                .clipped()
                                        } else {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.1))
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
                            
                            // Play Buttons Overlay (Hide when previewing)
                            if !isPreviewing {
                                if let resumeTime = activeScene.resumeTime, resumeTime > 0 {
                                    VStack(spacing: 16) {
                                        Button(action: { onStartPlayback(true) }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "clock.arrow.circlepath")
                                                Text("Resume from \(formatTime(resumeTime))")
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
                                } else {
                                    // Large Play Button Overlay
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.4))
                                            .frame(width: 70, height: 70)
                                            .blur(radius: 1)
                                        
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 30, weight: .bold))
                                            .foregroundColor(.white)
                                            .offset(x: 2) // Visually center the play triangle
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onStartPlayback(false)
                                    }
                                }
                                
                                // Persistent Progress Bar at the bottom of the thumbnail area
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
                            if pressing {
                                startPreview()
                            } else {
                                stopPreview()
                            }
                        }, perform: {})
                    }
                } else {
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
            }

            // 2. Info Section (Title + Markers + Details)
            VStack(alignment: .leading, spacing: 12) {
                // Title
                HStack(alignment: .top) {
                    Text(activeScene.title ?? "Unbekannter Titel")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Spacer()
                }

                // Markers Area (Moved below Title)
                if let markers = activeScene.sceneMarkers, !markers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(markers.sorted { $0.seconds < $1.seconds }) { marker in
                                Button(action: {
                                    onSeek(marker.seconds)
                                }) {
                                    markerThumbnail(marker)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.horizontal, -12) // Allow edge-to-edge scrolling
                }

                // Metadata Line (Scrollable swipebar)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // O-Counter
                        Button(action: {
                            viewModel.incrementOCounter(sceneId: activeScene.id) { newCount in
                                if let count = newCount {
                                    DispatchQueue.main.async {
                                        activeScene = activeScene.withOCounter(count)
                                    }
                                }
                            }
                        }) {
                            infoPill(icon: "heart.fill", text: "\(activeScene.oCounter ?? 0)", color: .red)
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
                        
                        // Rating
                        Menu {
                            Section("Rate Scene") {
                                ForEach((1...5).reversed(), id: \.self) { starCount in
                                    Button(action: {
                                        let newRating = starCount * 20
                                        viewModel.updateSceneRating(sceneId: activeScene.id, rating100: newRating) { success in
                                            if success {
                                                DispatchQueue.main.async {
                                                    activeScene = activeScene.withRating(newRating)
                                                }
                                            }
                                        }
                                    }) {
                                        Label("\(starCount) Stars", systemImage: "star.fill")
                                    }
                                }
                                
                                Button(role: .destructive, action: {
                                    viewModel.updateSceneRating(sceneId: activeScene.id, rating100: nil) { success in
                                        if success {
                                            DispatchQueue.main.async {
                                                activeScene = activeScene.withRating(nil)
                                            }
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
                        
                        // Playback Speed
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
                                            if playbackSpeed == speed {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            infoPill(icon: "speedometer", text: String(format: "%.2fx", playbackSpeed), color: .purple)
                        }
                        .buttonStyle(.plain)

                        // Resolution
                        if let firstFile = activeScene.files?.first,
                           let height = firstFile.height {
                            let res = height >= 2160 ? "4K" : (height >= 1080 ? "1080p" : (height >= 720 ? "720p" : "\(height)p"))
                            infoPill(icon: "video.fill", text: res, color: .blue)
                        }

                        // Organized Status
                        if activeScene.organized == true {
                            infoPill(icon: "checkmark.seal.fill", text: "Organized", color: .green)
                        }

                        // Date
                        if let date = activeScene.date {
                            infoPill(icon: "calendar", text: date)
                        }
                        
                        // Duration
                        if let duration = activeScene.sceneDuration {
                            infoPill(icon: "clock", text: formatTime(duration))
                        }
                        
                        // Play Count
                        if let playCount = activeScene.playCount, playCount > 0 {
                            infoPill(icon: "play.circle", text: "\(playCount) plays")
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.horizontal, -12)
                
                // Description
                if let details = activeScene.details, !details.isEmpty {
                    Text(details)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(isHeaderExpanded ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .padding(.bottom, (activeScene.details?.isEmpty ?? true) ? 0 : 20) // Extra space for toggle pill
            .background(Color(UIColor.systemBackground))
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(
            Group {
                if let details = activeScene.details, !details.isEmpty {
                    Button(action: {
                        withAnimation(.spring()) {
                            isHeaderExpanded.toggle()
                        }
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
            },
            alignment: .bottomTrailing
        )
    }
    
    @ViewBuilder
    private func markerThumbnail(_ marker: SceneMarker) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Marker Image
            ZStack(alignment: .bottomTrailing) {
                if let url = marker.thumbnailURL {
                    CustomAsyncImage(url: url) { loader in
                        if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 45)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
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
                    .background(Color.black.opacity(0.6))
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
        previewPlayer?.seek(to: .zero)
    }
}
