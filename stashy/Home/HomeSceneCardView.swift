
#if !os(tvOS)
import SwiftUI
import AVKit

struct HomeSceneCardView: View {
    let scene: Scene
    var isLarge: Bool = false
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var tabManager = TabManager.shared
    
    // Preview Video State
    @State private var previewPlayer: AVPlayer?
    @State private var isPreviewing = false
    @State private var isPressing = false

    
    private var cardWidth: CGFloat {
        if isLarge {
            if tabManager.dashboardHeroSize == .big {
                return UIScreen.main.bounds.width - 20
            } else {
                return 280
            }
        }
        return 200
    }
    
    var body: some View {
        let isBigHero = isLarge && tabManager.dashboardHeroSize == .big
        
        ZStack(alignment: .bottomLeading) {
            // Image
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.1)) // Subtle, non-transparent background
                
                if let thumbnailURL = scene.thumbnailURL {
                    CustomAsyncImage(url: thumbnailURL) { loader in
                        if loader.isLoading {
                            ProgressView()
                        } else if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: cardWidth, height: cardWidth * 9 / 16)
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
                        .frame(width: cardWidth, height: cardWidth * 9 / 16)
                        .clipped()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: cardWidth, height: cardWidth * 9 / 16)
            .clipped() // Hard clip for the container
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in
                isPressing = pressing
                if pressing {
                    startPreview()
                } else {
                    stopPreview()
                }
            }, perform: {})
            .contentShape(Rectangle()) // Ensure tap area matches card bounds
            
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
                            .font(.system(size: isBigHero ? 11 : 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    // Duration Badge (Top Right, moved from bottom)
                    if let duration = scene.files?.first?.duration {
                        Text(formatDuration(duration))
                            .font(.system(size: isBigHero ? 12 : 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
                            .clipShape(Capsule())
                    }
                    
                    // Download Indicator
                    if DownloadManager.shared.isDownloaded(id: scene.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                }
                
                Spacer()
                
                // Bottom Row
                VStack(alignment: .leading, spacing: 4) {
                    // Title (Bottom Left)
                    Text(scene.title ?? "Untitled Scene")
                    .font(isBigHero ? .headline : (isLarge ? .subheadline : .caption))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                }
            }
            .padding(isBigHero ? 16 : 8)
            .padding(.bottom, isBigHero ? 8 : 4) // Space for progress bar
        }
        .overlay(alignment: .bottom) {
            // Resume Progress at absolute bottom
            if let resumeTime = scene.resumeTime, resumeTime > 0, let duration = scene.sceneDuration {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 5)
                    
                    Rectangle()
                        .fill(appearanceManager.tintColor)
                        .frame(width: cardWidth * CGFloat(min(resumeTime, duration) / duration), height: 5)
                }
            }
        }
        .frame(width: cardWidth, height: cardWidth * 9 / 16)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .shadow(color: .black.opacity(isBigHero ? 0.35 : 0), radius: 12, x: 0, y: 8)
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
#endif
