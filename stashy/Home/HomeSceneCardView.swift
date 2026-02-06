
import SwiftUI
import AVKit

struct HomeSceneCardView: View {
    let scene: Scene
    var isLarge: Bool = false
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    // Preview Video State
    @State private var previewPlayer: AVPlayer?
    @State private var isPreviewing = false
    @State private var isPressing = false

    
    private var cardWidth: CGFloat { isLarge ? 280 : 200 }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Image
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
                                Image(systemName: "film")
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Image(systemName: "film")
                            .foregroundColor(.secondary)
                    }
                    
                    // Video Preview Overlay
                    if isPreviewing, let previewPlayer = previewPlayer {
                        AspectFillVideoPlayer(player: previewPlayer)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .allowsHitTesting(false)
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
            
            // Gradient Overlay for Text Readability
            LinearGradient(
                colors: [.black.opacity(0.8), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 60)
            .frame(maxHeight: .infinity, alignment: .bottom)
            
            // Content Overlays
            VStack {
                // Top Row
                HStack(alignment: .top) {
                    // Studio Badge (Top Left)
                    if let studio = scene.studio {
                        Text(studio.name.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    Spacer()
                    
                    // Duration Badge (Top Right, moved from bottom)
                    if let duration = scene.files?.first?.duration {
                        Text(formatDuration(duration))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                
                Spacer()
                
                // Bottom Row
                VStack(alignment: .leading, spacing: 4) {
                    // Title (Bottom Left)
                    Text(scene.title ?? "Untitled Scene")
                    .font(isLarge ? .subheadline : .caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    
                    // Resume Progress
                    if let resumeTime = scene.resumeTime, resumeTime > 0, let duration = scene.sceneDuration {
                        ProgressView(value: min(resumeTime, duration), total: duration)
                            .progressViewStyle(LinearProgressViewStyle(tint: appearanceManager.tintColor))
                            .frame(height: 3)
                    }
                }
            }
            .padding(8)
        }
        .frame(width: cardWidth, height: cardWidth * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: 12)) // Updated to 12
        .overlay(
            // Optional: Add border if needed, but usually shadow is enough
            // RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            EmptyView()
        )
        .onDisappear {
            stopPreview()
        }
    }
    
    private func startPreview() {
        guard let previewURL = scene.previewURL else { return }
        
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
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
