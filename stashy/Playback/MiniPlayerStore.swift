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

import Combine
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
    /// The scene the full view shows. Its scene-page player takes the engine while open, so the
    /// view keys on this rather than on `session`.
    @Published var nowPlayingScene: Scene?
    /// "Now Playing": the scene last started, on the watchlist or not. One entry, never a growing
    /// history; the + on its row adds it to the watchlist.
    @Published private(set) var playingQueue: [Scene] = []
    private static let playingQueueLimit = 1
    /// Deleted since the last server switch: a page still showing one (Now Playing closing
    /// over it) must not hand its engine to the bar.
    private var deletedSceneIds = Set<String>()

    /// Resume time and play duration keep syncing while only the bar shows the video.
    private let tracker = ScenePlaybackActivityTracker()
    /// Time actually watched in the bar, same rule as the scene page's play count.
    private var playCountClock = PlayCountWatchClock()
    private lazy var viewModel = StashDBViewModel()

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // The old server's session stays saved for when it is active again.
                self?.close(forget: false)
                self?.playingQueue = []
                self?.deletedSceneIds = []
                self?.restoreLastSessionIfNeeded()
            }
        }
        // A deleted scene leaves every mini-player surface: its scene page opened from the bar
        // (that `dismiss()` cannot close the cover), the bar, Now Playing and the watchlist.
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SceneDeleted"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let sceneId = note.userInfo?["sceneId"] as? String else { return }
            Task { @MainActor in self?.sceneDeleted(sceneId) }
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
    /// stashy+ feature, like the watchlist behind it.
    var isEnabled: Bool { TabManager.shared.isMiniPlayerEnabled && StashyPlusManager.isUnlockedNow }

    /// Takes over `engine` from a scene page that is going away. Any other mini session ends.
    func adopt(scene: Scene, engine: AetherSceneEngine, playRegistered: Bool) {
        // Now Playing switched to another scene: the page it replaced hands over late (its
        // teardown is deferred), after the new page already started its own engine. Taking it
        // would leave a second, still playing video behind the sheet.
        if (showsNowPlaying && nowPlayingScene.map({ $0.id != scene.id }) == true)
            || deletedSceneIds.contains(scene.id) {
            engine.stop()
            return
        }
        if let current = session, current.engine !== engine {
            close()
        }
        engine.onTime = { [weak self] seconds, duration in
            self?.handleTime(seconds, duration: duration)
        }
        engine.onPlayingChanged = { [weak self, weak engine] playing in
            guard let self else { return }
            if playing { self.tracker.start() } else { self.tracker.stop() }
            // Paused: the exact spot is worth one write; while playing it is saved sparingly.
            if !playing, let engine { self.saveSession(position: engine.currentTime) }
        }
        // The watchlist plays on in the bar: the next entry starts when one ends.
        engine.onReachedEnd = { [weak self] in
            self?.playNext()
        }
        // AI Motion, captions and transcode toasts belong to the page; the bar only plays.
        engine.onAnalysisItemChanged = nil
        engine.onTranscodeFallback = nil

        tracker.reset()
        playCountClock = PlayCountWatchClock()
        configureTracker(sceneId: scene.id)
        let duration = engine.duration > 0 ? engine.duration : (scene.sceneDuration ?? 0)
        tracker.setPosition(currentTime: engine.currentTime, duration: duration)
        if engine.isPlaying { tracker.start() }

        withAnimation(DesignTokens.Animation.quick) {
            session = Session(scene: scene, engine: engine, playRegistered: playRegistered)
        }
        notePlaying(scene)
        saveSession(position: engine.currentTime)
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
        playCountClock = PlayCountWatchClock()
        configureTracker(sceneId: scene.id)

        engine.fallbackSources = scene.transcodeFallbackURLs
        engine.fallbackDeclaredDuration = scene.sceneDuration
        session = Session(scene: scene, engine: engine, playRegistered: false)
        notePlaying(scene)
        saveSession(position: scene.resumeTime ?? 0)
        let resume: Double? = {
            guard let time = scene.resumeTime, time > 0 else { return nil }
            // Watched to the end before: start over instead of landing on the credits.
            if let total = scene.sceneDuration, total > 0, time >= total * 0.95 { return nil }
            return time
        }()
        Task { await engine.load(url: url, startAt: resume, autoplay: true) }
    }

    // MARK: - Queue

    /// A scene started playing: on top of "Now Playing".
    func notePlaying(_ scene: Scene) {
        guard playingQueue.first?.id != scene.id else { return }
        var queue = playingQueue.filter { $0.id != scene.id }
        queue.insert(scene, at: 0)
        playingQueue = Array(queue.prefix(Self.playingQueueLimit))
    }

    /// The scene now on screen: the full view's while it is open, else the bar's.
    var currentSceneId: String? {
        showsNowPlaying ? nowPlayingScene?.id : session?.scene.id
    }

    /// What follows `sceneId`: the next watchlist entry when it is on the watchlist; after a
    /// scene started with Play, the watchlist from the top (it is the "up next" list).
    func nextScene(after sceneId: String) -> Scene? {
        let watchlist = WatchlistStore.shared
        if watchlist.contains(sceneId) { return watchlist.next(after: sceneId) }
        return watchlist.scenes.first { $0.id != sceneId }
    }

    func previousScene(before sceneId: String) -> Scene? {
        WatchlistStore.shared.previous(before: sceneId)
    }

    /// The + on a "Now Playing" row: onto the watchlist (at its end).
    func addToWatchlist(_ scene: Scene) {
        WatchlistStore.shared.add(scene)
    }

    /// Swipe on a "Now Playing" row. The scene on screen stays: closing it is the bar's ×.
    func removeFromPlaying(_ sceneId: String) {
        guard sceneId != currentSceneId else { return }
        playingQueue.removeAll { $0.id == sceneId }
    }

    /// Taken off the watchlist: the scene on screen keeps playing (it stays in "Now Playing").
    fileprivate func watchlistRemoved(_ scene: Scene) {
        guard scene.id == currentSceneId, !playingQueue.contains(where: { $0.id == scene.id }) else { return }
        notePlaying(scene)
    }

    /// Fresh copies from the server (titles, covers, resume times) for both lists.
    fileprivate func refreshPlaying(with fresh: [String: Scene]) {
        guard playingQueue.contains(where: { fresh[$0.id] != nil }) else { return }
        playingQueue = playingQueue.map { fresh[$0.id] ?? $0 }
    }

    /// Resume tracking plus the play count, which the page would otherwise have counted.
    private func handleTime(_ seconds: Double, duration: Double) {
        guard let current = session, seconds >= 0 else { return }
        // Every save rewrites the whole UserDefaults plist (the scene snapshot is in it); every
        // 5 s that added up to iOS "excessive disk writes" reports. Pausing saves the exact spot.
        if abs(seconds - lastSavedPosition) >= 30 { saveSession(position: seconds) }
        tracker.setPosition(currentTime: seconds, duration: duration > 0 ? duration : (current.scene.sceneDuration ?? 0))
        playCountClock.sample(playhead: seconds, isPlaying: current.engine.isPlaying)
        if !current.playRegistered, playCountClock.watchedSeconds >= max(0, TabManager.shared.playCountPlayerSeconds) {
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
        guard let scene = session?.scene else { return }
        nowPlayingScene = scene
        showsNowPlaying = true
    }

    /// Play on a scene page while the mini player is on: the scene plays in the full view (and
    /// is listed on the watchlist) instead of on the page. `startAt` nil resumes where it was left.
    func openNowPlaying(_ scene: Scene, startAt: Double?) {
        notePlaying(scene)
        // The bar already runs it: the full view takes that engine as is, so jump it here.
        if let startAt, let current = session, current.scene.id == scene.id {
            Task { await current.engine.seek(to: startAt) }
        }
        nowPlayingScene = startAt.map { scene.withResumeTime($0) } ?? scene
        showsNowPlaying = true
    }

    /// Switches the full view to `scene` (row tap, previous / next, end of a scene).
    func showNowPlaying(_ scene: Scene) {
        notePlaying(scene)
        nowPlayingScene = scene
    }

    /// The full view's player reached the end: on to what comes next.
    func advanceNowPlaying() {
        guard showsNowPlaying, let current = nowPlayingScene,
              let next = nextScene(after: current.id) else { return }
        showNowPlaying(next)
    }

    /// Deleted in the app, or found missing on the server: gone from every surface.
    func sceneDeleted(_ sceneId: String) {
        deletedSceneIds.insert(sceneId)
        if expandedScene?.id == sceneId { expandedScene = nil }
        if session?.scene.id == sceneId { close() }
        if nowPlayingScene?.id == sceneId { showsNowPlaying = false; nowPlayingScene = nil }
        playingQueue.removeAll { $0.id == sceneId }
        if WatchlistStore.shared.contains(sceneId) { WatchlistStore.shared.remove(sceneId) }
    }

    /// From the full view to the scene page (metadata, markers, editing). The page takes the
    /// engine; leaving it hands the video back to the bar.
    func openSceneDetails() {
        guard let scene = nowPlayingScene ?? session?.scene else { return }
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
        return nextScene(after: current.scene.id) != nil
    }

    /// The bar's video ended (or Next): on to what comes next.
    func playNext() {
        guard let current = session, let next = nextScene(after: current.scene.id) else { return }
        play(next)
    }

    /// Saves the position and stops the engine.
    func close(forget: Bool = true) {
        guard let current = session else { return }
        if forget { forgetLastSession() }
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

    // MARK: - Last session (restored on launch)

    private struct SavedSession: Codable {
        let scene: Scene
        let position: Double
    }

    private var lastSavedPosition: Double = -10

    private var savedSessionKey: String? {
        ServerConfigManager.shared.activeConfig.map { "mini_player_last_\($0.id.uuidString)" }
    }

    private func saveSession(position: Double) {
        guard let current = session, let key = savedSessionKey else { return }
        lastSavedPosition = position
        if let data = try? JSONEncoder().encode(SavedSession(scene: current.scene, position: position)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Dropped when the bar is closed, or when a page stops this scene without handing it over.
    func forgetLastSession(sceneId: String? = nil) {
        guard let key = savedSessionKey else { return }
        if let sceneId,
           let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(SavedSession.self, from: data),
           saved.scene.id != sceneId {
            return
        }
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// App start: the bar comes back with the last scene, paused at its position.
    func restoreLastSessionIfNeeded() {
        guard session == nil, isEnabled, let key = savedSessionKey,
              let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(SavedSession.self, from: data),
              let url = saved.scene.aetherVideoURL,
              let engine = try? AetherSceneEngine() else { return }
        engine.isMuted = ScenePlayerMute.initialValue()
        engine.fallbackSources = saved.scene.transcodeFallbackURLs
        engine.fallbackDeclaredDuration = saved.scene.sceneDuration
        adopt(scene: saved.scene, engine: engine, playRegistered: false)
        let start = saved.position > 1 ? saved.position : nil
        Task { await engine.load(url: url, startAt: start, autoplay: false) }
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
/// order; the scene page and the "Now Playing" rows add entries. Scenes started with Play are
/// not added here (they sit in `MiniPlayerStore.playingQueue`).
@MainActor
final class WatchlistStore: ObservableObject {
    static let shared = WatchlistStore()

    @Published private(set) var scenes: [Scene] = []
    private var loadedServerId: String?
    private var lastServerCheck: Date?
    private var serverCheckTask: Task<Void, Never>?

    private init() {
        reload()
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
                self?.checkAgainstServer(force: true)
            }
        }
        // Scenes deleted on the server (web UI, another device) leave the lists the next time
        // the app comes to the front.
        #if os(macOS)
        let becameActive = NSApplication.didBecomeActiveNotification
        #else
        let becameActive = UIApplication.didBecomeActiveNotification
        #endif
        NotificationCenter.default.addObserver(forName: becameActive, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkAgainstServer() }
        }
    }

    private var storageKey: String? {
        loadedServerId.map { "scene_watchlist_\($0)" }
    }

    private func reload() {
        serverCheckTask?.cancel()
        lastServerCheck = nil
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
            add(scene)
        }
    }

    /// Appends `scene` (no-op when listed).
    func add(_ scene: Scene) {
        guard !contains(scene.id) else { return }
        scenes.append(scene)
        persist()
    }

    /// Removing never stops playback.
    func remove(_ sceneId: String) {
        guard let scene = scenes.first(where: { $0.id == sceneId }) else { return }
        scenes.removeAll { $0.id == sceneId }
        persist()
        MiniPlayerStore.shared.watchlistRemoved(scene)
    }

    func remove(atOffsets offsets: IndexSet) {
        let removed = offsets.compactMap { scenes.indices.contains($0) ? scenes[$0] : nil }
        scenes.remove(atOffsets: offsets)
        persist()
        removed.forEach { MiniPlayerStore.shared.watchlistRemoved($0) }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        scenes.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Empties the watchlist; what plays keeps playing.
    func clear() {
        let removed = scenes
        scenes = []
        persist()
        removed.forEach { MiniPlayerStore.shared.watchlistRemoved($0) }
    }

    /// One step up (`-1`) or down (`+1`); the context-menu fallback for dragging.
    func shift(_ sceneId: String, by delta: Int) {
        guard let index = scenes.firstIndex(where: { $0.id == sceneId }) else { return }
        let target = index + delta
        guard scenes.indices.contains(target) else { return }
        scenes.swapAt(index, target)
        persist()
    }

    /// Moves `sceneId` right behind the playing scene, so it plays next.
    func moveAfter(_ sceneId: String, currentId: String?) {
        guard let index = scenes.firstIndex(where: { $0.id == sceneId }), sceneId != currentId else { return }
        let scene = scenes.remove(at: index)
        let anchor = currentId.flatMap { id in scenes.firstIndex(where: { $0.id == id }) }
        scenes.insert(scene, at: anchor.map { $0 + 1 } ?? 0)
        persist()
    }

    /// The entry after `sceneId`; the first one when `sceneId` is not on the list.
    func next(after sceneId: String) -> Scene? {
        guard let index = scenes.firstIndex(where: { $0.id == sceneId }) else { return scenes.first }
        let nextIndex = scenes.index(after: index)
        return nextIndex < scenes.endIndex ? scenes[nextIndex] : nil
    }

    /// The entry before `sceneId`; nil at the top or when `sceneId` is not on the list.
    func previous(before sceneId: String) -> Scene? {
        guard let index = scenes.firstIndex(where: { $0.id == sceneId }), index > scenes.startIndex else { return nil }
        return scenes[scenes.index(before: index)]
    }

    // MARK: - Server check

    private struct ScenesByIdsResponse: Decodable {
        struct Payload: Decodable { let findScenes: FindScenesResult? }
        let data: Payload?
    }

    /// Looks up every listed scene (watchlist, "Now Playing", the bar's) on the server. Missing ones
    /// were deleted elsewhere and leave every surface; found ones refresh their snapshot.
    /// Throttled to once a minute unless `force`; a failed request changes nothing.
    func checkAgainstServer(force: Bool = false) {
        let player = MiniPlayerStore.shared
        var ids: [String] = []
        var seen = Set<String>()
        for id in scenes.map(\.id) + player.playingQueue.map(\.id) + [player.session?.scene.id, player.nowPlayingScene?.id].compactMap({ $0 })
        where seen.insert(id).inserted {
            ids.append(id)
        }
        guard !ids.isEmpty, serverCheckTask == nil else { return }
        if !force, let last = lastServerCheck, Date().timeIntervalSince(last) < 60 { return }
        lastServerCheck = Date()
        let serverId = loadedServerId

        serverCheckTask = Task { @MainActor [weak self] in
            defer { self?.serverCheckTask = nil }
            var found: [String: Scene] = [:]
            var start = 0
            while start < ids.count {
                let chunk = Array(ids[start..<min(start + 100, ids.count)])
                start += 100
                do {
                    let response: ScenesByIdsResponse = try await GraphQLClient.shared.execute(
                        query: GraphQLQueries.queryWithFragments("findScenesByIds"),
                        variables: ["ids": chunk, "filter": ["per_page": -1]]
                    )
                    // No result block at all: unknown state, never treat that as "deleted".
                    guard let result = response.data?.findScenes else { return }
                    for scene in result.scenes { found[scene.id] = scene }
                } catch {
                    AppLog.debug("Watchlist server check failed: \(error)")
                    return
                }
            }
            guard let self, !Task.isCancelled, self.loadedServerId == serverId else { return }
            for id in ids where found[id] == nil {
                MiniPlayerStore.shared.sceneDeleted(id)
            }
            let refreshed = self.scenes.map { found[$0.id] ?? $0 }
            if refreshed.contains(where: { found[$0.id] != nil }) {
                self.scenes = refreshed
                self.persist()
            }
            MiniPlayerStore.shared.refreshPlaying(with: found)
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

/// The scene page's marker row: thumbnail, timestamp and title; a tap seeks there.
struct SceneMarkerStrip: View {
    let markers: [SceneMarker]
    var onSeek: (Double) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(markers.sorted { $0.seconds < $1.seconds }) { marker in
                    Button {
                        HapticManager.light()
                        onSeek(marker.seconds)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .bottomTrailing) {
                                CustomAsyncImage(url: marker.thumbnailURL) { loader in
                                    if let image = loader.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Rectangle().fill(Color.gray.opacity(0.2))
                                            .overlay(Image(systemName: "bookmark").foregroundColor(.secondary))
                                    }
                                }
                                .frame(width: 80, height: 45)
                                .clipped()
                                Text(Self.time(marker.seconds))
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.black.opacity(0.6))
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                    .padding(2)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(marker.title ?? "Marker at \(Self.time(marker.seconds))")
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .frame(width: 80, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private static func time(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600, m = (Int(seconds) % 3600) / 60, s = Int(seconds) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Tools → Watchlist: the list when nothing plays. A row opens and plays its scene; leaving
/// the page hands it to the mini player, which plays on through the list.
struct WatchlistToolsView: View {
    @ObservedObject private var watchlist = WatchlistStore.shared
    @ObservedObject private var player = MiniPlayerStore.shared
    @ObservedObject private var appearance = AppearanceManager.shared
    @State private var confirmReset = false
    @State private var openedScene: Scene?
    @State private var showsScene = false
    /// Sorting shows the drag handles; outside it, swipe left removes a row.
    @State private var sortMode: EditMode = .inactive

    var body: some View {
        Group {
            if watchlist.scenes.isEmpty {
                ContentUnavailableView(
                    "Watchlist is empty",
                    systemImage: "text.badge.plus",
                    description: Text("Add scenes with \"Add to watchlist\" on a scene. They play one after another in the mini player.")
                )
            } else {
                List {
                    Section {
                        HStack(spacing: StashyExpandingDock.itemSpacing) {
                            Button {
                                HapticManager.light()
                                openedScene = watchlist.scenes.first
                                showsScene = openedScene != nil
                            } label: {
                                Label("Play all", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: StashyExpandingDock.activeHeight)
                                    .stashyChromeFill(shape: Capsule(style: .continuous), activeColor: appearance.tintColor)
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) { confirmReset = true } label: {
                                Text("Clear")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.red)
                                    .padding(.horizontal, 18)
                                    .frame(height: StashyExpandingDock.activeHeight)
                                    .stashyChromeFill(shape: Capsule(style: .continuous), activeColor: nil)
                            }
                            .buttonStyle(.plain)
                            Button {
                                withAnimation { sortMode = sortMode.isEditing ? .inactive : .active }
                            } label: {
                                Text(sortMode.isEditing ? "Done" : "Sort")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(sortMode.isEditing ? Color.white : Color.primary.opacity(0.85))
                                    .padding(.horizontal, 18)
                                    .frame(height: StashyExpandingDock.activeHeight)
                                    .stashyChromeFill(
                                        shape: Capsule(style: .continuous),
                                        activeColor: sortMode.isEditing ? appearance.tintColor : nil
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    Section {
                        ForEach(watchlist.scenes) { scene in
                            Button {
                                HapticManager.light()
                                openedScene = scene
                                showsScene = true
                            } label: {
                                WatchlistSceneRow(scene: scene, isCurrent: player.session?.scene.id == scene.id)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Color.primary.opacity(0.08))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        HapticManager.light()
                                        watchlist.remove(scene.id)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            .contextMenu {
                                if watchlist.scenes.first?.id != scene.id {
                                    Button { watchlist.shift(scene.id, by: -1) } label: {
                                        Label("Move up", systemImage: "arrow.up")
                                    }
                                }
                                if watchlist.scenes.last?.id != scene.id {
                                    Button { watchlist.shift(scene.id, by: 1) } label: {
                                        Label("Move down", systemImage: "arrow.down")
                                    }
                                }
                                Button(role: .destructive) { watchlist.remove(scene.id) } label: {
                                    Label("Remove from watchlist", systemImage: "trash")
                                }
                            }
                        }
                        .onMove { watchlist.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, $sortMode)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationDestination(isPresented: $showsScene) {
            if let openedScene {
                SceneDetailView(scene: openedScene, autoPlay: true)
            }
        }
        .alert("Clear watchlist?", isPresented: $confirmReset) {
            Button("Clear", role: .destructive) { watchlist.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All scenes are removed from the watchlist.")
        }
        .onAppear { watchlist.checkAgainstServer() }
    }
}

/// Thumbnail, title and performers; the playing one tinted with a speaker badge.
struct WatchlistSceneRow: View {
    let scene: Scene
    var isCurrent: Bool = false
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
#if !os(tvOS)
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
    /// Not observed: the engine publishes its clock many times a second, and rebuilding the bar
    /// (inside the tab bar's Liquid Glass) at that rate crashed SwiftUI's async glass renderer.
    /// The bar mirrors only what it draws, and the progress line ticks once a second.
    let engine: AetherSceneEngine
    @ObservedObject private var appearance = AppearanceManager.shared
    @ObservedObject private var watchlist = WatchlistStore.shared
    @ObservedObject private var store = MiniPlayerStore.shared
    @GestureState private var dragOffset: CGFloat = 0
    @State private var isPlaying = false
    @State private var hasPresentedFrame = false

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
                    AetherVideoSurface(engine: engine, videoGravity: .resizeAspectFill, showsTranscodeTag: false)
                        .overlay {
                            // Restored on launch (paused, no frame decoded yet): show the cover.
                            if !hasPresentedFrame {
                                CustomAsyncImage(url: session.scene.thumbnailURL) { loader in
                                    if let image = loader.image {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Color.black
                                    }
                                }
                            }
                        }
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
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
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
            MiniPlayerProgressLine(engine: engine, tint: appearance.tintColor)
                .padding(.horizontal, 12)
                .allowsHitTesting(false)
        }
        .onReceive(engine.$isPlaying.removeDuplicates()) { isPlaying = $0 }
        .onReceive(engine.$hasPresentedFrame.removeDuplicates()) { hasPresentedFrame = $0 }
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
/// The bar's 2 pt progress line, refreshed once a second from the engine clock.
private struct MiniPlayerProgressLine: View {
    let engine: AetherSceneEngine
    let tint: Color
    @State private var progress: Double = 0

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(tint)
                .frame(width: geo.size.width * progress, height: 2)
        }
        .frame(height: 2)
        .onReceive(
            engine.$currentTime
                .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
        ) { time in
            let duration = engine.duration
            let value = duration > 0 && time.isFinite ? min(max(time / duration, 0), 1) : 0
            if abs(value - progress) > 0.001 { progress = value }
        }
    }
}

/// The mini player's own full view: the scene page's player module 1:1 (fullscreen, volume
/// keys, markers, subtitles, PiP, menus), the metadata card, credits and the watchlist.
struct NowPlayingView: View {
    @ObservedObject private var player = MiniPlayerStore.shared

    var body: some View {
        Group {
            if let scene = player.nowPlayingScene {
                // Keyed by scene: switching scenes rebuilds the scene-page player for it.
                NowPlayingContent(scene: scene)
                    .id(scene.id)
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
    let scene: Scene


    init(scene: Scene) {
        self.scene = scene
        _displayedScene = State(initialValue: scene)
    }
    @ObservedObject private var player = MiniPlayerStore.shared
    @ObservedObject private var watchlist = WatchlistStore.shared
    @ObservedObject private var appearance = AppearanceManager.shared
    @State private var confirmReset = false
    /// Sorting shows the drag handles; outside it, swipe left removes a row.
    @State private var sortMode: EditMode = .inactive
    /// Local copy for the metadata card: rating / O-count edits show at once.
    @State private var displayedScene: Scene
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Toolbar (minimize · Details), then the player with a slim side margin; it stays put
        // while the watchlist scrolls.
        NavigationStack {
        // Pinned to the sheet's width, like the scene page: a long title or description must
        // wrap, never widen the content (the whole sheet then slid off to the side).
        GeometryReader { proxy in
        VStack(spacing: 0) {
            // The scene page itself in player-only mode: it takes the engine from the mini
            // player and hands it back when the view closes.
            SceneDetailView(scene: scene, autoPlay: true)
                .environment(\.stashyScenePlayerOnly, true)
                .frame(maxWidth: .infinity)
                // Same gap under the chrome as the scene page (`mainContentView`).
                .padding(.horizontal, 16)
                .padding(.top, 16)

            List {
                Section {
                    infoRow
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                // Always the scene in the player above, whatever started it (Play, a watchlist
                // row, next, the bar) — never a separately kept list that could drift.
                Section {
                    queueRow(scene, onWatchlist: false)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        // Sorting is for the watchlist only.
                        .moveDisabled(true)
                } header: {
                    sectionHeader("Now Playing") { EmptyView() }
                }
                Section {
                    if watchlist.scenes.isEmpty {
                        Text("Add scenes with + on a playing scene or the watchlist button on a scene page. They play here one after another.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(watchlist.scenes) { entry in
                            queueRow(entry, onWatchlist: true)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(Color.primary.opacity(0.08))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        HapticManager.light()
                                        watchlist.remove(entry.id)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    if entry.id != scene.id {
                                        Button {
                                            watchlist.moveAfter(entry.id, currentId: scene.id)
                                        } label: {
                                            Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                        }
                                    }
                                    if watchlist.scenes.first?.id != entry.id {
                                        Button {
                                            watchlist.shift(entry.id, by: -1)
                                        } label: {
                                            Label("Move up", systemImage: "arrow.up")
                                        }
                                    }
                                    if watchlist.scenes.last?.id != entry.id {
                                        Button {
                                            watchlist.shift(entry.id, by: 1)
                                        } label: {
                                            Label("Move down", systemImage: "arrow.down")
                                        }
                                    }
                                    Button(role: .destructive) {
                                        watchlist.remove(entry.id)
                                    } label: {
                                        Label("Remove from watchlist", systemImage: "trash")
                                    }
                                }
                        }
                        .onMove { watchlist.move(fromOffsets: $0, toOffset: $1) }
                    }
                } header: {
                    sectionHeader("Watchlist") {
                        if !watchlist.scenes.isEmpty {
                            Button("Clear", role: .destructive) { confirmReset = true }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.red)
                                .padding(.trailing, 14)
                            sortToggle
                        }
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, $sortMode)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            // Full sheet width always: a long title must wrap, not widen the list.
            .frame(maxWidth: .infinity)
        }
        .frame(width: proxy.size.width)
        }
        .background(Color.appBackground.ignoresSafeArea())
        // Standard chrome: Minimize like Back on the left, Details on the right.
        .hideSystemNavigationBarForCustomChrome()
        .stashyCustomChromeInset(spacing: 0) {
            StashyDetailTopBar(
                backTitle: "Minimize",
                backIcon: "chevron.down",
                trailingAction: ("Details", "info.circle", { player.openSceneDetails() }),
                onBack: { dismiss() }
            )
        }
        }
        .alert("Clear watchlist?", isPresented: $confirmReset) {
            Button("Clear", role: .destructive) { watchlist.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All scenes are removed from the watchlist. What plays keeps playing.")
        }
        .onAppear {
            loadDetailsIfNeeded()
            watchlist.checkAgainstServer()
        }
    }

    private func sectionHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
            trailing()
        }
        .textCase(nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets())
        .background(Color.appBackground)
    }

    /// List and watchlist snapshots often lack markers / captions: fetch the full scene once.
    private func loadDetailsIfNeeded() {
        let scene = displayedScene
        guard scene.sceneMarkers == nil || scene.tags == nil else { return }
        viewModel.fetchSceneDetails(sceneId: scene.id) { updated in
            guard let updated else { return }
            DispatchQueue.main.async {
                guard displayedScene.id == updated.id else { return }
                displayedScene = updated
            }
        }
    }

    /// Performers · studio as links, and previous / next when the watchlist has them.
    private var infoRow: some View {
        HStack(alignment: .center, spacing: 6) {
            creditLinks
            Spacer(minLength: 4)
            if let previous = player.previousScene(before: scene.id) {
                iconButton("backward.end.fill", label: "Previous") { player.showNowPlaying(previous) }
            }
            if let next = player.nextScene(after: scene.id) {
                iconButton("forward.end.fill", label: "Next") { player.showNowPlaying(next) }
            }
        }
    }

    /// Performers and studio as links: the sheet closes and the page opens on Home.
    @ViewBuilder
    private var creditLinks: some View {
        let performers = Array(scene.performers.prefix(4))
        let studio = scene.studio
        if !performers.isEmpty || studio != nil {
            FlowLayout(spacing: 6) {
                ForEach(performers, id: \.id) { performer in
                    creditPill(icon: "person.fill", text: performer.name) {
                        open { coordinator.openPerformer(performer.toPerformer()) }
                    }
                }
                if let studio {
                    creditPill(icon: "building.2.fill", text: studio.name) {
                        open { coordinator.openStudio(studio.toStudio()) }
                    }
                }
            }
        }
    }

    /// Same look as the scene page's metadata pills (accent tint, 28 pt capsule).
    private func creditPill(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(text)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.pillAccent.opacity(0.1))
            .foregroundColor(Color.pillAccent)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the page")
    }

    /// Closes the sheet first; navigating under a presented sheet does not show.
    private func open(_ navigate: @escaping () -> Void) {
        HapticManager.light()
        player.showsNowPlaying = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: navigate)
    }

    private var sortToggle: some View {
        Button(sortMode.isEditing ? "Done" : "Sort") {
            withAnimation { sortMode = sortMode.isEditing ? .inactive : .active }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundColor(appearance.tintColor)
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.85))
                .frame(width: StashyExpandingDock.circleSize, height: StashyExpandingDock.circleSize)
                .background(Circle().fill(Color.secondaryAppBackground))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// A "Now Playing" or watchlist row: tap plays it here. "Now Playing" rows carry a + that
    /// puts the scene on the watchlist (hidden once it is there).
    private func queueRow(_ entry: Scene, onWatchlist: Bool) -> some View {
        HStack(spacing: 8) {
            queueRowButton(entry)
            // Once on the watchlist the + just goes away; the row stays.
            if !onWatchlist, !watchlist.contains(entry.id) {
                Button {
                    HapticManager.light()
                    withAnimation(DesignTokens.Animation.quick) { player.addToWatchlist(entry) }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(appearance.tintColor)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add to watchlist")
            }
        }
    }

    private func queueRowButton(_ entry: Scene) -> some View {
        let isCurrent = entry.id == scene.id
        let scene = entry
        return Button {
            HapticManager.light()
            player.showNowPlaying(entry)
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#endif

#endif
