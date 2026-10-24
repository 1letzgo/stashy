//
//  MiniPlayerStore.swift
//  stashy
//
//  Keeps a scene playing after its detail page is left. `SceneDetailView` hands its running
//  engine over instead of stopping it; the mini bar above the tab bar draws it, and reopening
//  the scene (from the bar, or by returning to the page) takes the same engine back, so the
//  video never reloads.
//

#if canImport(AetherEngine) && !os(tvOS)

import SwiftUI

@MainActor
final class MiniPlayerStore: ObservableObject {
    static let shared = MiniPlayerStore()

    struct Session {
        let scene: Scene
        let engine: AetherSceneEngine
        /// The page already counted this viewing as a play; the page taking it back must not again.
        let playRegistered: Bool
    }

    @Published private(set) var session: Session?
    /// A page that hides the tab bar (immersive image viewer) also hides the tab bar's
    /// accessory slot; the bar then floats on its own so the video never plays unseen.
    @Published private(set) var tabBarHiddenByPage = false
    /// Set by the bar's tap; `MainTabView` presents the scene page for it.
    @Published var expandedScene: Scene?

    /// Resume time and play duration keep syncing while only the bar shows the video.
    private let tracker = ScenePlaybackActivityTracker()
    private lazy var viewModel = StashDBViewModel()

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        // Feeds take over the screen: same rule as every other background player.
        NotificationCenter.default.addObserver(
            forName: .stashyPauseBackgroundPlayers,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.session?.engine.pause() }
        }
    }

    /// Whether a page being left should hand its playing engine over instead of stopping it.
    var isEnabled: Bool { TabManager.shared.isMiniPlayerEnabled }

    /// Takes over `engine` from a scene page that is going away. Any other mini session ends.
    func adopt(scene: Scene, engine: AetherSceneEngine, playRegistered: Bool) {
        if let current = session, current.engine !== engine {
            close()
        }
        engine.onTime = { [weak self] seconds, duration in
            guard let self, seconds >= 0 else { return }
            self.tracker.setPosition(currentTime: seconds, duration: duration > 0 ? duration : (scene.sceneDuration ?? 0))
        }
        engine.onPlayingChanged = { [weak self] playing in
            guard let self else { return }
            if playing { self.tracker.start() } else { self.tracker.stop() }
        }
        // AI Motion, captions and transcode toasts belong to the page; the bar only plays.
        engine.onAnalysisItemChanged = nil
        engine.onTranscodeFallback = nil

        tracker.reset()
        configureTracker(sceneId: scene.id)
        let duration = engine.duration > 0 ? engine.duration : (scene.sceneDuration ?? 0)
        tracker.setPosition(currentTime: engine.currentTime, duration: duration)
        if engine.isPlaying { tracker.start() }

        withAnimation(DesignTokens.Animation.quick) {
            session = Session(scene: scene, engine: engine, playRegistered: playRegistered)
        }
    }

    /// Hands the engine back to a page showing `sceneId`, or nil when the bar plays something else.
    func take(sceneId: String) -> Session? {
        guard let current = session, current.scene.id == sceneId else { return nil }
        tracker.stop()
        current.engine.onTime = nil
        current.engine.onPlayingChanged = nil
        session = nil
        return current
    }

    /// Ends the mini session if it plays a different scene than the one about to start.
    func yield(to sceneId: String) {
        if let current = session, current.scene.id != sceneId {
            close()
        }
    }

    func setTabBarHiddenByPage(_ hidden: Bool) {
        guard tabBarHiddenByPage != hidden else { return }
        tabBarHiddenByPage = hidden
    }

    func togglePlayPause() {
        session?.engine.togglePlayPause()
    }

    func expand() {
        expandedScene = session?.scene
    }

    /// Saves the position and stops the engine.
    func close() {
        guard let current = session else { return }
        let duration = current.engine.duration > 0 ? current.engine.duration : (current.scene.sceneDuration ?? 0)
        tracker.setPosition(currentTime: current.engine.currentTime, duration: duration)
        tracker.stop()
        current.engine.onTime = nil
        current.engine.onPlayingChanged = nil
        current.engine.stop()
        withAnimation(DesignTokens.Animation.quick) {
            session = nil
        }
    }

    /// Same save path as the scene page (`ensurePlaybackActivityConfigured`).
    private func configureTracker(sceneId: String) {
        let vm = viewModel
        tracker.updatesResumeTime = true
        tracker.onSave = { resumeTime, playDuration in
            vm.updateSceneResumeTime(
                sceneId: sceneId,
                resumeTime: resumeTime,
                playDuration: playDuration
            ) { success in
                guard success, let resumeTime else { return }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SceneResumeTimeUpdated"),
                        object: nil,
                        userInfo: ["sceneId": sceneId, "resumeTime": resumeTime]
                    )
                }
            }
        }
    }
}

extension View {
    /// Hides the tab bar like `.toolbar(_, for: .tabBar)` and tells the mini player, which
    /// otherwise sits in the (then hidden) tab bar accessory.
    func miniPlayerAwareTabBar(hidden: Bool) -> some View {
        self
            .toolbar(hidden ? .hidden : .automatic, for: .tabBar)
            .onAppear { MiniPlayerStore.shared.setTabBarHiddenByPage(hidden) }
            .onChange(of: hidden) { _, value in MiniPlayerStore.shared.setTabBarHiddenByPage(value) }
            .onDisappear { MiniPlayerStore.shared.setTabBarHiddenByPage(false) }
    }
}

#if os(iOS)
/// The bar above the tab bar: live picture, title, play/pause, close. Tap reopens the scene,
/// a swipe down closes it.
struct MiniPlayerBar: View {
    @ObservedObject private var store = MiniPlayerStore.shared

    var body: some View {
        if let session = store.session {
            MiniPlayerBarContent(session: session, engine: session.engine)
        }
    }
}

private struct MiniPlayerBarContent: View {
    let session: MiniPlayerStore.Session
    @ObservedObject var engine: AetherSceneEngine
    @ObservedObject private var appearance = AppearanceManager.shared
    @GestureState private var dragOffset: CGFloat = 0

    private var progress: Double {
        guard engine.duration > 0 else { return 0 }
        return min(max(engine.currentTime / engine.duration, 0), 1)
    }

    private var subtitle: String {
        let performers = session.scene.performers.prefix(2).map(\.name).joined(separator: ", ")
        if !performers.isEmpty { return performers }
        return session.scene.studio?.name ?? ""
    }

    var body: some View {
        HStack(spacing: 10) {
            AetherVideoSurface(engine: engine, videoGravity: .resizeAspectFill)
                .frame(width: 64, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.scene.title ?? "Scene")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button {
                HapticManager.light()
                MiniPlayerStore.shared.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
            Button {
                HapticManager.light()
                MiniPlayerStore.shared.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close mini player")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                Capsule()
                    .fill(appearance.tintColor)
                    .frame(width: geo.size.width * progress, height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 12)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .offset(y: max(dragOffset, 0))
        .opacity(1 - min(max(dragOffset, 0) / 80, 0.6))
        .onTapGesture {
            MiniPlayerStore.shared.expand()
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 40 || abs(value.translation.width) > 120 {
                        HapticManager.light()
                        MiniPlayerStore.shared.close()
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the scene")
    }
}
#endif

#endif
