
#if !os(tvOS)
import SwiftUI
import Combine

struct HomeSceneCardView: View {
    let scene: Scene
    var isLarge: Bool = false
    /// Only the hero card (`isLarge`) sizes itself from this.
    var screenWidth: CGFloat = 0
    /// Hero Autoplay: this is the hero row's focused card, so its preview plays on its own.
    var autoplaysPreview: Bool = false
    @ObservedObject var appearanceManager = AppearanceManager.shared

    @StateObject private var previewPlayer = AetherPreviewPlayer()
    @State private var isPreviewing = false
    /// This card's long-press preview holds the hero back until it ends.
    @State private var holdsHero = false
    @ObservedObject private var hero = HomeHeroPreview.shared

    /// The hero's own preview: it lives outside the card, so scrolling Home away and back
    /// (which rebuilds the lazy row) neither stops nor restarts it.
    private var showsHeroPreview: Bool {
        autoplaysPreview && hero.sceneId == scene.id && !hero.isBlocked
    }

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

                if showsHeroPreview && !isPreviewing {
                    AetherPreviewSurface(player: hero.player, fill: true)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                } else if isPreviewing {
                    AetherPreviewSurface(player: previewPlayer, fill: true)
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
                // The release always ends a preview: a swipe that started on this card can
                // make it the hero card mid-gesture, and the hero hold must not outlive it.
                if !pressing { stopPreview() } else if !autoplaysPreview { startPreview() }
            }, perform: {})

            LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                .frame(height: 60)
                .frame(maxHeight: .infinity, alignment: .bottom)

            VStack {
                HStack(alignment: .top) {
                    if let studio = scene.studio {
                        SceneStudioBadge(
                            studio: studio,
                            logoHeight: isLarge ? 14 : 12,
                            maxLogoWidth: isLarge ? 130 : 100,
                            font: .system(size: isLarge ? 9 : 8),
                            fontWeight: .bold,
                            uppercased: true
                        )
                    }
                    Spacer()
                    if let duration = scene.files?.first?.duration ?? scene.sceneDuration {
                        Text(formatDuration(duration))
                            .font(.system(size: isLarge ? 10 : 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .stashyGlass(shape: Capsule())
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
                Text(scene.displayTitle ?? "Untitled Scene")
                    // Small cards match the Channels card titles (12pt bold); the hero row
                    // keeps its larger type.
                    .font(isLarge ? .subheadline : .system(size: 12, weight: .bold))
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
                        .frame(width: cardWidth * PlaybackFraction.cgFloat(resumeTime, in: duration), height: 5)
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .onDisappear { stopPreview() }
        .onChange(of: autoplaysPreview, initial: true) { _, autoplay in
            guard autoplay else { return }
            stopPreview()
            hero.play(scene)
        }
    }

    private func startPreview() {
        guard let url = scene.previewURL else { return }
        // A long-press preview elsewhere takes over while it runs, like the mini player.
        if !autoplaysPreview && !holdsHero {
            holdsHero = true
            HomeHeroPreview.shared.setPressPreview(true)
        }
        previewPlayer.start(url: url)
        withAnimation(.easeIn(duration: 0.2)) { isPreviewing = true }
    }

    private func stopPreview() {
        withAnimation(.easeOut(duration: 0.2)) { isPreviewing = false }
        previewPlayer.stop(release: true)
        if holdsHero {
            holdsHero = false
            HomeHeroPreview.shared.setPressPreview(false)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Hero Autoplay's player. Kept outside the card: Home's rows are lazy, so the card is torn
/// down when it scrolls out of sight; the preview keeps running and looping meanwhile and is
/// still where it was when the card comes back. Home pauses it while it is off screen.
@MainActor
final class HomeHeroPreview: ObservableObject {
    static let shared = HomeHeroPreview()
    let player = AetherPreviewPlayer()
    @Published private(set) var sceneId: String?
    /// A long-press preview on another card runs: the hero waits until it ends.
    @Published private(set) var isBlockedByPress = false
    /// The mini player holds a scene: the hero stays still beside it.
    @Published private(set) var isBlockedByMiniPlayer = false
    var isBlocked: Bool { isBlockedByPress || isBlockedByMiniPlayer }
    private var isHomeVisible = true
    private var miniPlayerWatch: AnyCancellable?

    private init() {
        miniPlayerWatch = MiniPlayerStore.shared.$session
            .map { $0 != nil && MiniPlayerStore.shared.isEnabled }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] blocked in self?.setBlockedByMiniPlayer(blocked) }
    }

    private var canPlay: Bool {
        isHomeVisible && !isBlocked && TabManager.shared.dashboardHeroAutoplay
    }

    private func setBlockedByMiniPlayer(_ blocked: Bool) {
        isBlockedByMiniPlayer = blocked
        applyBlock()
    }

    func setPressPreview(_ active: Bool) {
        guard isBlockedByPress != active else { return }
        isBlockedByPress = active
        applyBlock()
    }

    private func applyBlock() {
        if isBlocked {
            player.stop(release: true)
        } else if let currentURL, canPlay {
            player.start(url: currentURL)
        }
    }

    /// Makes `scene` the playing hero; a no-op for the scene already playing.
    func play(_ scene: Scene) {
        guard let url = scene.previewURL else { return }
        if sceneId != scene.id {
            player.stop(release: true)
            sceneId = scene.id
        }
        currentURL = url
        if canPlay { player.start(url: url) }
    }

    /// Home left (a pushed page, another tab) or came back.
    func setHomeVisible(_ visible: Bool) {
        isHomeVisible = visible
        if visible {
            if let currentURL, canPlay { player.start(url: currentURL) }
        } else {
            player.stop(release: false)
        }
    }

    /// Setting switched off.
    func stop() {
        player.stop(release: true)
        sceneId = nil
        currentURL = nil
    }

    private var currentURL: URL?

    /// Horizontal positions of Home rows, by row id. A lazy row is rebuilt after scrolling
    /// out of sight, and a refresh rebuilds its scroll view; either way it starts at the first
    /// card again while the hero preview kept playing the one the user had swiped to.
    private var rowPositions: [String: String] = [:]

    func remember(_ id: String?, row: String) { rowPositions[row] = id }

    /// The row's focused card: the scroll position, else the remembered one while the row
    /// still holds it, else the first. Pass the row's `@State` position: reading it is what
    /// redraws the row when the user swipes (the remembered one is not observed).
    func focusedID(row: String, current: String?, in ids: [String]) -> String? {
        if let current, ids.contains(current) { return current }
        if let id = rowPositions[row], ids.contains(id) { return id }
        return ids.first
    }

    /// The remembered card to scroll back to, or nil for the first card.
    fileprivate func restoreTarget(row: String, in ids: [String]) -> String? {
        guard let id = rowPositions[row] else { return nil }
        guard ids.contains(id) else {
            rowPositions[row] = nil
            return nil
        }
        return id == ids.first ? nil : id
    }
}

/// Keeps a Home row on the card the user swiped to (see `HomeHeroPreview.rowPositions`).
private struct HomeRowPositionKeeper: ViewModifier {
    @Binding var scrollID: String?
    let row: String
    let ids: [String]

    func body(content: Content) -> some View {
        content
            .scrollPosition(id: Binding(
                get: { scrollID },
                set: { id in
                    scrollID = id
                    HomeHeroPreview.shared.remember(id, row: row)
                }
            ), anchor: .leading)
            .onAppear(perform: restore)
            .onChange(of: ids) { restore() }
    }

    /// A rebuilt scroll view ignores a position it already had, so it goes through nil.
    private func restore() {
        guard let target = HomeHeroPreview.shared.restoreTarget(row: row, in: ids) else { return }
        scrollID = nil
        DispatchQueue.main.async {
            scrollID = target
            HomeHeroPreview.shared.remember(target, row: row)
        }
    }
}

extension View {
    func homeRowPosition(_ scrollID: Binding<String?>, row: String, ids: [String]) -> some View {
        modifier(HomeRowPositionKeeper(scrollID: scrollID, row: row, ids: ids))
    }
}
#endif
