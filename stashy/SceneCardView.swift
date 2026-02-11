//
//  SceneCardView.swift
//  stashy
//
//  Created by Daniel Goletz on 15.01.26.
//

#if !os(tvOS)
import SwiftUI

import AVKit

// Card-based view for grid layout
struct SceneCardView: View {
    let scene: Scene
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    // Preview Video State
    @State private var player: AVPlayer?
    @State private var isPreviewing = false
    @State private var isPressing = false
    
    var body: some View {

        ZStack(alignment: .bottomLeading) {
            // Image - fills the entire card
            GeometryReader { geometry in
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))

                    if let thumbnailURL = scene.thumbnailURL {
                        CustomAsyncImage(url: thumbnailURL) { loader in
                            if loader.isLoading {
                                ProgressView()
                            } else if let image = loader.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .clipped()
                            } else {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    }
                    
                    // Video Preview Overlay
                    if isPreviewing, let player = player {
                        AspectFillVideoPlayer(player: player)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped() // Ensures video respects the card bounds
                            .allowsHitTesting(false) // Pass touches through
                            .transition(.opacity)
                    }
                }
            }
            .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in
                isPressing = pressing
                if pressing {
                    startPreview()
                } else {
                    stopPreview()
                }
            }, perform: {})
            
            // Ensure full height for the card
            // Aspect Ratio 16:9 forced by invisible color
            Color.clear
                .aspectRatio(16/9, contentMode: .fit) 
            
            // Top Overlay (Studio and Date)
            VStack {
                HStack(alignment: .top) {
                    // Studio - Top Left
                    if let studio = scene.studio {
                        Text(studio.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    // Date - Top Right (Moved slightly left if checkmark exists)
                    HStack(spacing: 8) {
                        if let date = scene.date {
                            Text(date)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                .clipShape(Capsule())
                        }
                        
                        if DownloadManager.shared.isDownloaded(id: scene.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.green)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(8)
                
                Spacer()
            }
            
            // Gradient Overlay (Bottom)
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
            
            // Bottom Content Overlay (Title)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 8) {
                    // Title
                    Text(scene.title ?? "Unknown Title")
                        .font(.headline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Duration - Bottom Right (Before Performers)
                    if let durationText = durationString {
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                            Text(durationText)
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                    }

                    // Performers Count - Bottom Right
                    if !scene.performers.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "person.2")
                            Text("\(scene.performers.count)")
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                    }

                }
                
                // Resume Progress
                if let resumeTime = scene.resumeTime, resumeTime > 0, let duration = scene.sceneDuration {
                    ProgressView(value: resumeTime, total: duration)
                        .progressViewStyle(LinearProgressViewStyle(tint: appearanceManager.tintColor))
                        .frame(height: 3)
                        .padding(.top, 2)
                }
            }
            .padding(12)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
        .onDisappear {
            stopPreview()
        }
    }
    
    private func startPreview() {
        guard let previewURL = scene.previewURL else { return }
        
        if player == nil {
            player = createMutedPreviewPlayer(for: previewURL)
        }
        
        withAnimation(.easeIn(duration: 0.2)) {
            isPreviewing = true
        }
        player?.play()
    }
    
    private func stopPreview() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPreviewing = false
        }
        player?.pause()
        // Optional: Seek to start or keep position? Usually previews loop or reset.
        player?.seek(to: .zero)
    }
    
    // Helper to format duration
    private var durationString: String? {
        guard let duration = scene.files?.first?.duration, duration > 0 else { return nil }
        
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

// Custom Video Player to force Aspect Fill
struct AspectFillVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill // Crucial for "filling" the card
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
#endif
