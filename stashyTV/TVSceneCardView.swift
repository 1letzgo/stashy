//
//  TVSceneCardView.swift
//  stashyTV
//
//  Scene card for tvOS — sized for 4 visible in row
//

import SwiftUI
import AVKit

struct TVSceneCardView: View {
    let scene: Scene
    var width: CGFloat = 410
    var height: CGFloat = 230
    @Environment(\.isFocused) var isFocused

    // Hover-to-preview state
    @State private var previewPlayer: AVPlayer?
    @State private var showPreview = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        // Thumbnail with overlays
        ZStack(alignment: .bottomLeading) {
            thumbnailView
                .aspectRatio(16/9, contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Video preview overlay (shown after hovering ~1s)
            if showPreview, let previewPlayer {
                TVPreviewPlayerView(player: previewPlayer)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // Gradient
            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(isFocused ? 0.3 : 1.0) // Lighten gradient on focus for pop effect

            // Top Labels (Studio Left, Duration Right)
            VStack {
                HStack(alignment: .top) {
                    if let studio = scene.studio {
                        Text(studio.name.uppercased())
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .tracking(1)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Spacer()
                    
                    if let duration = scene.sceneDuration ?? scene.duration, duration > 0 {
                        Text(formatDuration(duration))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(12)
                Spacer()
            }

            // Bottom Metadata Bar (inside thumbnail)
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Text(scene.title ?? "Untitled Scene")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Spacer(minLength: 12)
                    
                    if let rating = scene.rating100, rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", Double(rating) / 20.0))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(12)
            }

            // Resume progress bar
            if let resumeTime = scene.resumeTime, resumeTime > 0,
               let duration = scene.sceneDuration ?? scene.duration, duration > 0 {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 4)
                            Rectangle()
                                .fill(AppearanceManager.shared.tintColor)
                                .frame(width: geo.size.width * CGFloat(resumeTime / duration), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
        }
        .frame(width: width, height: height)
        .onChange(of: isFocused) { focused in
            if focused {
                startHoverPreview()
            } else {
                teardownPreview()
            }
        }
        .onDisappear {
            teardownPreview()
        }
    }

    // MARK: - Hover preview

    private func startHoverPreview() {
        hoverTask?.cancel()
        guard let previewURL = scene.previewURL else { return }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            let player = createMutedPreviewPlayer(for: previewURL)
            player.actionAtItemEnd = .none
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                player.play()
            }
            previewPlayer = player
            player.play()
            withAnimation(.easeIn(duration: 0.25)) {
                showPreview = true
            }
        }
    }

    private func teardownPreview() {
        hoverTask?.cancel()
        hoverTask = nil

        // Stop playback and detach the loop observer immediately so audio,
        // network, and the seek-to-start loop halt the moment focus leaves.
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        let departingPlayer = previewPlayer
        departingPlayer?.pause()

        guard showPreview else {
            // Nothing on screen yet (e.g. torn down before the 1s timer fired).
            previewPlayer = nil
            return
        }

        // Keep the player attached through the fade so .transition(.opacity)
        // can cross-fade back to the thumbnail, then release it once done.
        withAnimation(.easeOut(duration: 0.2)) {
            showPreview = false
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            // Skip if a new preview took over during the fade-out.
            if previewPlayer === departingPlayer {
                previewPlayer = nil
            }
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailURL = scene.thumbnailURL {
            AsyncImage(url: thumbnailURL) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.08))
                        .overlay(ProgressView().scaleEffect(0.8))
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderView
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.08))
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.12))
            )
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

struct TVSceneCardTitleView: View {
    let scene: Scene

    var body: some View {
        EmptyView()
    }
}

// Lightweight AVPlayerLayer-backed view for muted hover previews on tvOS.
struct TVPreviewPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        PlayerLayerView(player: player)
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.player !== player {
            uiView.player = player
        }
    }

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue }
        }

        init(player: AVPlayer) {
            super.init(frame: .zero)
            self.player = player
            playerLayer.videoGravity = .resizeAspectFill
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override var canBecomeFocused: Bool { false }
    }
}
