
#if !os(tvOS)
import SwiftUI
import AVKit

struct HomeSceneCardView: View {
    let scene: Scene
    var isLarge: Bool = false
    let screenWidth: CGFloat
    @ObservedObject var appearanceManager = AppearanceManager.shared

    @State private var previewPlayer: AVPlayer?
    @State private var isPreviewing = false

    private var cardWidth: CGFloat {
        isLarge ? homeHeroCardWidth(screenWidth: screenWidth) : 125 * 16 / 9
    }
    private var cardHeight: CGFloat {
        isLarge ? cardWidth * 9 / 16 : 125
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                Rectangle().fill(Color.gray.opacity(0.1))

                if let url = scene.thumbnailURL {
                    CustomAsyncImage(url: url) { loader in
                        if loader.isLoading {
                            ProgressView()
                        } else if let image = loader.image {
                            image.resizable().scaledToFill()
                                .frame(width: cardWidth, height: cardHeight)
                                .clipped()
                        } else {
                            Image(systemName: "film").foregroundColor(.secondary)
                        }
                    }
                } else {
                    Image(systemName: "film").foregroundColor(.secondary)
                }

                if isPreviewing, let player = previewPlayer {
                    AspectFillVideoPlayer(player: player)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipped()
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in
                if pressing { startPreview() } else { stopPreview() }
            }, perform: {})

            LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                .frame(height: 60)
                .frame(maxHeight: .infinity, alignment: .bottom)

            VStack {
                HStack(alignment: .top) {
                    if let studio = scene.studio {
                        Text(studio.name.uppercased())
                            .font(.system(size: isLarge ? 9 : 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if let duration = scene.files?.first?.duration {
                        Text(formatDuration(duration))
                            .font(.system(size: isLarge ? 10 : 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
                            .clipShape(Capsule())
                    }
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
                Text(scene.title ?? "Untitled Scene")
                    .font(isLarge ? .subheadline : .caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
            }
            .padding(8)
            .padding(.bottom, 4)
        }
        .overlay(alignment: .bottom) {
            if let resumeTime = scene.resumeTime, resumeTime > 0, let duration = scene.sceneDuration {
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.2)).frame(height: 5)
                    Rectangle()
                        .fill(appearanceManager.tintColor)
                        .frame(width: cardWidth * CGFloat(min(resumeTime, duration) / duration), height: 5)
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .onDisappear { stopPreview() }
    }

    private func startPreview() {
        guard let url = scene.previewURL else { return }
        if previewPlayer == nil { previewPlayer = createMutedPreviewPlayer(for: url) }
        withAnimation(.easeIn(duration: 0.2)) { isPreviewing = true }
        previewPlayer?.play()
    }

    private func stopPreview() {
        withAnimation(.easeOut(duration: 0.2)) { isPreviewing = false }
        previewPlayer?.pause()
        previewPlayer?.seek(to: .zero)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
#endif
