//
//  TVSimilarScenes.swift
//  stashyTV
//
//  stashy+ — Similar Scenes on Apple TV: the "Similar Scenes" row on the scene detail page
//  and the "Up Next" offer when a normally played scene ends. Both run on the shared
//  `SimilarScenesFinder`, gated exactly like iOS (`finder.isActive` = stashy+ unlocked; tvOS
//  has no Suggestions toggle, so the finder defaults to enabled there).
//

#if canImport(AetherEngine)

import SwiftUI
import Combine

@MainActor
final class TVSimilarScenesModel: ObservableObject {
    /// Similar scenes for the scene the detail page shows.
    @Published private(set) var scenes: [Scene] = []
    @Published private(set) var isLoading = false

    /// The scene the player is on — the page's own scene, or one Up Next switched to.
    @Published private(set) var nowPlaying: Scene?
    /// Offered when playback reaches the end; non-nil while the overlay is up.
    @Published private(set) var upNext: Scene?
    @Published private(set) var countdown = 0

    static let countdownSeconds = 10

    private weak var player: TVAetherPlaybackModel?
    private weak var viewModel: StashDBViewModel?
    /// Everything played in this player session — Up Next never offers a scene twice.
    private var playedIds: Set<String> = []
    private var detailSignature: String?
    private var countdownTask: Task<Void, Never>?
    private var lookupTask: Task<Void, Never>?

    var isActive: Bool { SimilarScenesFinder.shared.isActive }

    // MARK: - Detail row

    /// Mirrors iOS `loadSimilarScenes`: keyed on the scene's metadata signature, keeps the
    /// current row while a fuller version of the same scene is ranked again.
    func load(for scene: Scene) async {
        guard isActive else {
            scenes = []
            isLoading = false
            return
        }
        let signature = SimilarScenesFinder.signature(for: scene)
        detailSignature = signature
        if scenes.isEmpty { isLoading = true }
        let found = await SimilarScenesFinder.shared.similarScenes(for: scene)
        guard detailSignature == signature else { return }
        scenes = found
        isLoading = false
    }

    // MARK: - Up Next

    /// Called by the detail page whenever it starts playback of its own scene.
    func beginPlayback(of scene: Scene, player: TVAetherPlaybackModel, viewModel: StashDBViewModel) {
        cancelUpNext()
        self.player = player
        self.viewModel = viewModel
        nowPlaying = scene
        playedIds = [scene.id]
        player.onPlaybackEnded = { [weak self] in
            self?.playbackEnded()
        }
    }

    /// The player cover is gone — forget the session.
    func endSession() {
        cancelUpNext()
        player?.onPlaybackEnded = nil
        player = nil
        nowPlaying = nil
        playedIds = []
    }

    private func playbackEnded() {
        guard isActive, upNext == nil, let current = nowPlaying else { return }
        lookupTask?.cancel()
        lookupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // The detail row already holds the answer for the page's own scene.
            let candidates: [Scene]
            if SimilarScenesFinder.signature(for: current) == self.detailSignature, !self.scenes.isEmpty {
                candidates = self.scenes
            } else {
                candidates = await SimilarScenesFinder.shared.similarScenes(for: current)
            }
            guard !Task.isCancelled, self.nowPlaying?.id == current.id, self.player != nil else { return }
            guard let next = candidates.first(where: { !self.playedIds.contains($0.id) && $0.aetherVideoURL != nil })
            else { return }
            self.offer(next)
        }
    }

    private func offer(_ scene: Scene) {
        upNext = scene
        countdown = Self.countdownSeconds
        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            while let self, self.countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, self.upNext?.id == scene.id else { return }
                self.countdown -= 1
            }
            guard !Task.isCancelled, let self, self.upNext?.id == scene.id else { return }
            self.playUpNext()
        }
    }

    func playUpNext() {
        guard let scene = upNext, let url = scene.aetherVideoURL,
              let player, let viewModel else {
            cancelUpNext()
            return
        }
        countdownTask?.cancel()
        countdownTask = nil
        upNext = nil
        nowPlaying = scene
        playedIds.insert(scene.id)
        // Same engine, next item — the channel hand-over, so the display mode stays put.
        player.playNext(url: url,
                        sceneId: scene.id,
                        viewModel: viewModel,
                        title: scene.displayTitle,
                        subtitle: scene.studio?.name,
                        artworkURL: scene.thumbnailURL,
                        fallbackSources: scene.transcodeFallbackURLs,
                        fallbackDeclaredDuration: scene.sceneDuration,
                        scene: scene)
    }

    func cancelUpNext() {
        lookupTask?.cancel()
        lookupTask = nil
        countdownTask?.cancel()
        countdownTask = nil
        upNext = nil
        countdown = 0
    }
}

// MARK: - Detail row

/// "Similar Scenes" row for `TVSceneDetailView`. Hidden while stashy+ is locked or nothing
/// similar was found, like the iOS card.
struct TVSimilarScenesSection: View {
    let scene: Scene
    @ObservedObject var model: TVSimilarScenesModel
    @ObservedObject private var stashyPlus = StashyPlusManager.shared

    private static let cardWidth: CGFloat = 410
    private static let cardHeight: CGFloat = 230

    var body: some View {
        // Always present (empty when hidden) so the `.task` keeps running.
        VStack(alignment: .leading, spacing: 16) {
            if stashyPlus.isUnlocked, model.isLoading || !model.scenes.isEmpty {
                heading

                if !model.scenes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 30) {
                            ForEach(model.scenes) { similar in
                                VStack(alignment: .leading, spacing: 10) {
                                    TVNavButton(value: TVSceneLink(sceneId: similar.id)) {
                                        TVSceneCardView(scene: similar,
                                                        width: Self.cardWidth,
                                                        height: Self.cardHeight)
                                    }
                                    TVSceneCardTitleView(scene: similar)
                                }
                                .frame(width: Self.cardWidth)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 30)
                    }
                    .focusSection()
                }
            }
        }
        .task(id: "\(SimilarScenesFinder.signature(for: scene))|\(stashyPlus.isUnlocked)") {
            await model.load(for: scene)
        }
    }

    private var heading: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.title3)
                .foregroundColor(AppearanceManager.shared.tintColor)
            Text("Similar Scenes")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            if model.isLoading {
                ProgressView()
                    .padding(.leading, 8)
            } else {
                Text("\(model.scenes.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Up Next overlay

/// Shown over the finished player. Play Now (default focus) switches right away, Cancel or
/// Menu stays on the ended scene; otherwise the countdown plays the suggestion.
struct TVUpNextOverlay: View {
    @ObservedObject var model: TVSimilarScenesModel

    private enum Focus: Hashable { case play, cancel }
    @FocusState private var focus: Focus?

    var body: some View {
        if let scene = model.upNext {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: [.clear, .black.opacity(0.85)],
                               startPoint: .leading,
                               endPoint: .trailing)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 22) {
                    Text("Up Next · Similar Scene")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    // Card without focus preview: the ended engine is still alive behind it.
                    TVSceneCardView(scene: scene, width: 560, height: 315, showsFocusPreview: false)

                    Text(scene.displayTitle ?? "Untitled Scene")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .frame(width: 560, alignment: .leading)

                    if let studio = scene.studio?.name {
                        Text(studio)
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    HStack(spacing: 24) {
                        Button {
                            model.playUpNext()
                        } label: {
                            Label("Play Now · \(model.countdown)", systemImage: "play.fill")
                                .monospacedDigit()
                        }
                        .focused($focus, equals: .play)

                        Button {
                            model.cancelUpNext()
                        } label: {
                            Text("Cancel")
                        }
                        .focused($focus, equals: .cancel)
                    }
                    .padding(.top, 8)
                }
                .padding(.trailing, 90)
                .padding(.bottom, 90)
                .focusSection()
            }
            .onExitCommand { model.cancelUpNext() }
            .onAppear {
                // After the insertion — an assignment during it does not take.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if focus == nil { focus = .play }
                }
            }
            .transition(.opacity)
        }
    }
}

#endif
