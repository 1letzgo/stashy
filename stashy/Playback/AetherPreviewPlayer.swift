//
//  AetherPreviewPlayer.swift
//  stashy
//
//  Muted, looping card previews on the engine. Every grid, row and hero on
//  screen would otherwise build its own decoder, so the players share a
//  small pool: a new one evicts the least recently started.
//

#if canImport(AetherEngine)

import Foundation
import Combine
import SwiftUI
import AVFoundation
import AetherEngine

/// Caps how many preview engines decode at once. Previews are decoration, so the newest
/// one always wins and the least recently started is stopped outright.
@MainActor
final class AetherPreviewPool {

    static let shared = AetherPreviewPool()

    /// Concurrent preview engines. Deliberately tiny — a preview is never the main event.
    #if os(tvOS)
    let maxConcurrent = 1
    #else
    let maxConcurrent = 2
    #endif

    /// Least recently started first.
    private var owners: [WeakOwner] = []

    private struct WeakOwner {
        weak var player: AetherPreviewPlayer?
    }

    private init() {}

    /// Builds an engine for `owner`, evicting the least recently started preview when the
    /// pool is full. Returns nil when the engine cannot be created at all.
    func acquire(owner: AetherPreviewPlayer) -> AetherSceneEngine? {
        compact()
        owners.removeAll { $0.player === owner }

        while owners.count >= maxConcurrent, let oldest = owners.first?.player {
            owners.removeFirst()
            oldest.stop(release: true)
            compact()
        }

        let engine: AetherSceneEngine
        do {
            engine = try AetherSceneEngine()
        } catch {
            AppLog.error("AetherPreviewPool: engine init failed: \(error.localizedDescription)")
            return nil
        }
        owners.append(WeakOwner(player: owner))
        return engine
    }

    func release(owner: AetherPreviewPlayer) {
        owners.removeAll { $0.player === owner || $0.player == nil }
    }

    private func compact() {
        owners.removeAll { $0.player == nil }
    }
}

/// A muted, looping preview. `start` is idempotent for the same URL, `stop(release:)` either
/// pauses or gives the engine (and its pool slot) back.
@MainActor
final class AetherPreviewPlayer: ObservableObject {

    @Published private(set) var hasFirstFrame: Bool = false

    /// Non-nil only while this player holds a pool slot. Published so a surface can appear
    /// the moment the engine does.
    @Published private(set) var engine: AetherSceneEngine?

    private var currentURL: URL?
    private var cancellable: AnyCancellable?

    init() {}

    /// Starts (or resumes) the preview. A second call with the same URL just plays.
    func start(url: URL) {
        if let engine, currentURL == url {
            engine.play()
            return
        }

        if engine == nil {
            guard let acquired = AetherPreviewPool.shared.acquire(owner: self) else { return }
            configure(acquired)
            engine = acquired
        }
        guard let engine else { return }

        currentURL = url
        hasFirstFrame = false
        Task { @MainActor in
            await engine.load(url: url, startAt: nil, autoplay: true) { options in
                // A preview must never renegotiate the display mode, and it only needs a
                // shallow read-ahead: it is a few seconds of decoration.
                options.suppressDisplayCriteria = true
                options.forwardBufferSegments = 4
            }
        }
    }

    /// Pauses the preview. `release: true` also tears the engine down and frees the pool slot —
    /// that is what every `onDisappear` wants.
    func stop(release: Bool) {
        guard let engine else {
            if release { AetherPreviewPool.shared.release(owner: self) }
            return
        }
        if release {
            cancellable = nil
            engine.stop()
            self.engine = nil
            currentURL = nil
            hasFirstFrame = false
            AetherPreviewPool.shared.release(owner: self)
        } else {
            engine.pause()
        }
    }

    private func configure(_ engine: AetherSceneEngine) {
        engine.isMuted = true
        engine.loopsAtEnd = true
        engine.audioSessionPolicy = .ambient
        cancellable = engine.$hasFirstFrame
            .receive(on: RunLoop.main)
            .sink { [weak self] ready in self?.hasFirstFrame = ready }
    }
}

/// Draws whatever the preview player currently has, black until there is an engine.
@MainActor
struct AetherPreviewSurface: View {

    @ObservedObject var player: AetherPreviewPlayer

    /// `true` crops to fill the frame, `false` fits the whole picture inside it.
    var fill: Bool = true

    /// Where an aspect-fill crop sits. `.top` matches the card look, `.center` the default.
    var alignment: Alignment = .center

    var body: some View {
        ZStack {
            Color.black
            if let engine = player.engine {
                AetherVideoSurface(engine: engine,
                                   videoGravity: fill ? .resizeAspectFill : .resizeAspect,
                                   topAlignAspectFill: fill && alignment == .top)
            }
        }
    }
}

#endif
