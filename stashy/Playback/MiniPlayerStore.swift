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
        var playRegistered: Bool
    }

    @Published private(set) var session: Session?
    /// A page that hides the tab bar (immersive image viewer) also hides the tab bar's
    /// accessory slot; the bar then floats on its own so the video never plays unseen.
    @Published private(set) var tabBarHiddenByPage = false
    /// Set by the bar's tap; `MainTabView` presents the scene page for it.
    @Published var expandedScene: Scene?
    /// The bar's tap: `MainTabView` presents the mini player's own full view (`NowPlayingView`).
    @Published var showsNowPlaying = false

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
            self?.handleTime(seconds, duration: duration)
        }
        engine.onPlayingChanged = { [weak self] playing in
            guard let self else { return }
            if playing { self.tracker.start() } else { self.tracker.stop() }
        }
        // The watchlist plays on in the bar: the next entry starts when one ends.
        engine.onReachedEnd = { [weak self] in
            self?.playNextFromWatchlist()
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

    /// Switches the bar to `scene` on the same engine (watchlist tap, or the next entry).
    func play(_ scene: Scene) {
        guard let current = session else { return }
        if current.scene.id == scene.id {
            current.engine.play()
            return
        }
        guard let url = scene.aetherVideoURL else { return }
        let engine = current.engine
        // Save the one being left before the tracker moves on.
        let oldDuration = engine.duration > 0 ? engine.duration : (current.scene.sceneDuration ?? 0)
        tracker.setPosition(currentTime: engine.currentTime, duration: oldDuration)
        tracker.stop()
        tracker.reset()
        configureTracker(sceneId: scene.id)

        engine.fallbackSources = scene.transcodeFallbackURLs
        engine.fallbackDeclaredDuration = scene.sceneDuration
        session = Session(scene: scene, engine: engine, playRegistered: false)
        let resume: Double? = {
            guard let time = scene.resumeTime, time > 0 else { return nil }
            // Watched to the end before: start over instead of landing on the credits.
            if let total = scene.sceneDuration, total > 0, time >= total * 0.95 { return nil }
            return time
        }()
        Task { await engine.load(url: url, startAt: resume, autoplay: true) }
    }

    private func playNextFromWatchlist() {
        guard let current = session,
              let next = WatchlistStore.shared.next(after: current.scene.id) else { return }
        play(next)
    }

    /// Resume tracking plus the play count, which the page would otherwise have counted.
    private func handleTime(_ seconds: Double, duration: Double) {
        guard let current = session, seconds >= 0 else { return }
        tracker.setPosition(currentTime: seconds, duration: duration > 0 ? duration : (current.scene.sceneDuration ?? 0))
        if !current.playRegistered, seconds >= max(0, TabManager.shared.playCountPlayerSeconds) {
            session?.playRegistered = true
            let sceneId = current.scene.id
            viewModel.addScenePlay(sceneId: sceneId)
            NotificationCenter.default.post(
                name: NSNotification.Name("ScenePlayAdded"),
                object: nil,
                userInfo: ["sceneId": sceneId]
            )
        }
    }

    /// Hands the engine back to a page showing `sceneId`, or nil when the bar plays something else.
    func take(sceneId: String) -> Session? {
        guard let current = session, current.scene.id == sceneId else { return nil }
        tracker.stop()
        current.engine.onTime = nil
        current.engine.onPlayingChanged = nil
        current.engine.onReachedEnd = nil
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
        guard session != nil else { return }
        showsNowPlaying = true
    }

    /// From the full view to the scene page (metadata, markers, editing). The page takes the
    /// engine; leaving it hands the video back to the bar.
    func openSceneDetails() {
        guard let scene = session?.scene else { return }
        showsNowPlaying = false
        // Let the sheet finish dismissing before the cover presents.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.expandedScene = scene
        }
    }

    func seek(by delta: Double) {
        guard let engine = session?.engine else { return }
        let target = max(0, min(engine.currentTime + delta, max(engine.duration - 1, 0)))
        Task { await engine.seek(to: target) }
    }

    var hasNext: Bool {
        guard let current = session else { return false }
        return WatchlistStore.shared.next(after: current.scene.id) != nil
    }

    func playNext() {
        playNextFromWatchlist()
    }

    /// Saves the position and stops the engine.
    func close() {
        guard let current = session else { return }
        let duration = current.engine.duration > 0 ? current.engine.duration : (current.scene.sceneDuration ?? 0)
        tracker.setPosition(currentTime: current.engine.currentTime, duration: duration)
        tracker.stop()
        current.engine.onTime = nil
        current.engine.onPlayingChanged = nil
        current.engine.onReachedEnd = nil
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

// MARK: - Watchlist

/// Scenes queued for the mini player, per server, kept across launches. The bar plays them in
/// order; the scene page adds and removes entries.
@MainActor
final class WatchlistStore: ObservableObject {
    static let shared = WatchlistStore()

    @Published private(set) var scenes: [Scene] = []
    private var loadedServerId: String?

    private init() {
        reload()
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    private var storageKey: String? {
        loadedServerId.map { "scene_watchlist_\($0)" }
    }

    private func reload() {
        loadedServerId = ServerConfigManager.shared.activeConfig?.id.uuidString
        guard let key = storageKey, let data = UserDefaults.standard.data(forKey: key) else {
            scenes = []
            return
        }
        scenes = (try? JSONDecoder().decode([Scene].self, from: data)) ?? []
    }

    private func persist() {
        guard let key = storageKey else { return }
        if let data = try? JSONEncoder().encode(scenes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func contains(_ sceneId: String) -> Bool {
        scenes.contains { $0.id == sceneId }
    }

    func toggle(_ scene: Scene) {
        if contains(scene.id) {
            remove(scene.id)
        } else {
            scenes.append(scene)
            persist()
        }
    }

    func remove(_ sceneId: String) {
        scenes.removeAll { $0.id == sceneId }
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        scenes.remove(atOffsets: offsets)
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        scenes.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func clear() {
        scenes = []
        persist()
    }

    /// The entry after `sceneId`; the first one when `sceneId` is not on the list.
    func next(after sceneId: String) -> Scene? {
        guard let index = scenes.firstIndex(where: { $0.id == sceneId }) else { return scenes.first }
        let nextIndex = scenes.index(after: index)
        return nextIndex < scenes.endIndex ? scenes[nextIndex] : nil
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
    @ObservedObject private var watchlist = WatchlistStore.shared
    @ObservedObject private var store = MiniPlayerStore.shared
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
            Group {
                if store.showsNowPlaying {
                    // The full view draws the engine's layer now; it can live in one place only.
                    CustomAsyncImage(url: session.scene.thumbnailURL) { loader in
                        if let image = loader.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.black
                        }
                    }
                } else {
                    AetherVideoSurface(engine: engine, videoGravity: .resizeAspectFill)
                }
            }
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
                MiniPlayerStore.shared.expand()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        if watchlist.scenes.count > 0 {
                            Text("\(watchlist.scenes.count)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(appearance.tintColor, in: Capsule())
                                .offset(x: 2, y: 2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Watchlist")
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
/// The mini player's own full view: video, transport and the watchlist. Deliberately not the
/// scene page — that one stays reachable through "Details".
struct NowPlayingView: View {
    @ObservedObject private var player = MiniPlayerStore.shared

    var body: some View {
        Group {
            if let session = player.session {
                NowPlayingContent(session: session, engine: session.engine)
            } else {
                Color.appBackground.ignoresSafeArea()
                    .onAppear { player.showsNowPlaying = false }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
    }
}

private struct NowPlayingContent: View {
    let session: MiniPlayerStore.Session
    @ObservedObject var engine: AetherSceneEngine
    @ObservedObject private var player = MiniPlayerStore.shared
    @ObservedObject private var watchlist = WatchlistStore.shared
    @ObservedObject private var appearance = AppearanceManager.shared
    @State private var scrubTime: Double?
    @State private var confirmReset = false
    @Environment(\.dismiss) private var dismiss

    private var subtitle: String {
        let performers = session.scene.performers.prefix(3).map(\.name).joined(separator: ", ")
        let studio = session.scene.studio?.name ?? ""
        return [performers, studio].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    playerBlock
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    if watchlist.scenes.isEmpty {
                        Text("Add scenes with the watchlist button on a scene. They play here one after another.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .listRowBackground(Color.secondaryAppBackground)
                    } else {
                        ForEach(watchlist.scenes) { scene in
                            watchlistRow(scene)
                                .listRowBackground(Color.secondaryAppBackground)
                        }
                        .onDelete { watchlist.remove(atOffsets: $0) }
                        .onMove { watchlist.move(fromOffsets: $0, toOffset: $1) }
                    }
                } header: {
                    HStack {
                        Text("Watchlist")
                        Spacer()
                        if !watchlist.scenes.isEmpty {
                            Button("Reset", role: .destructive) { confirmReset = true }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.red)
                                .textCase(nil)
                                .padding(.trailing, 12)
                            EditButton()
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .alert("Reset watchlist?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { watchlist.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All scenes are removed from the watchlist. The playing scene keeps playing.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Minimize")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Details") { player.openSceneDetails() }
                }
            }
        }
    }

    private var playerBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            AetherVideoSurface(engine: engine)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                .contentShape(Rectangle())
                .onTapGesture { player.togglePlayPause() }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.scene.title ?? "Scene")
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            AetherTimeBar(
                currentTime: scrubTime ?? engine.currentTime,
                duration: engine.duration,
                isScrubbing: scrubTime != nil,
                isCompact: true,
                onScrubChanged: { scrubTime = $0 },
                onScrubEnded: { time in
                    scrubTime = nil
                    Task { await engine.seek(to: time) }
                }
            )

            HStack(spacing: 0) {
                transportButton("gobackward.10", label: "Back 10 seconds") { player.seek(by: -10) }
                transportButton(engine.isPlaying ? "pause.fill" : "play.fill",
                                label: engine.isPlaying ? "Pause" : "Play",
                                size: 34) { player.togglePlayPause() }
                transportButton("goforward.10", label: "Forward 10 seconds") { player.seek(by: 10) }
                transportButton("forward.end.fill", label: "Next in watchlist") { player.playNext() }
                    .disabled(!player.hasNext)
                    .opacity(player.hasNext ? 1 : 0.35)
            }
            WatchlistToggleRow(scene: session.scene)
        }
    }

    private func transportButton(_ systemImage: String, label: String, size: CGFloat = 22, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func watchlistRow(_ scene: Scene) -> some View {
        let isCurrent = session.scene.id == scene.id
        return Button {
            HapticManager.light()
            player.play(scene)
        } label: {
            HStack(spacing: 12) {
                CustomAsyncImage(url: scene.thumbnailURL) { loader in
                    if let image = loader.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.black.opacity(0.3)
                    }
                }
                .frame(width: 80, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if isCurrent {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.5), in: Circle())
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(scene.title ?? "Scene")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isCurrent ? appearance.tintColor : .primary)
                        .lineLimit(2)
                    let performers = scene.performers.prefix(2).map(\.name).joined(separator: ", ")
                    if !performers.isEmpty {
                        Text(performers)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "On watchlist" toggle for the scene playing in the full view.
private struct WatchlistToggleRow: View {
    let scene: Scene
    @ObservedObject private var watchlist = WatchlistStore.shared
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        let listed = watchlist.contains(scene.id)
        Button {
            HapticManager.light()
            watchlist.toggle(scene)
        } label: {
            Label(listed ? "On watchlist" : "Add to watchlist",
                  systemImage: listed ? "text.badge.checkmark" : "text.badge.plus")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(listed ? appearance.tintColor : .primary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Color.secondaryAppBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
#endif

#endif
