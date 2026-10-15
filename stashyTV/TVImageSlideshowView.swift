//
//  TVImageSlideshowView.swift
//  stashyTV
//
//  Full-screen image slideshow for galleries and image lists: auto-advance with a
//  crossfade and a subtle Ken Burns drift, driven entirely by the Siri Remote.
//
//  Play/Pause pauses, Left/Right steps, Click cycles the interval, Menu exits.
//  Stills only — the callers hand over the same GIF/video-free list as their grids.
//

import SwiftUI
import UIKit

enum TVSlideshowSettings {
    /// Seconds per image, remembered across launches (not per server).
    static let intervalKey = "tv_slideshow_interval"
    static let intervals: [Double] = [3, 5, 10]
    static let defaultInterval: Double = 5

    static func label(for interval: Double) -> String {
        "\(Int(interval)) s"
    }
}

/// Item for `fullScreenCover(item:)` — the image the slideshow starts on.
struct TVSlideshowStart: Identifiable {
    let id = UUID()
    let index: Int
}

/// "Slideshow" card button for list and gallery headers, styled like the sort/filter chrome.
struct TVSlideshowButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.on.rectangle")
                Text("Slideshow")
            }
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .buttonStyle(.card)
    }
}

struct TVImageSlideshowView: View {
    /// Viewable stills, in the order of the list the slideshow was started from.
    let images: [StashImage]
    let startIndex: Int
    /// Asks the owner of the list for its next page; the list arrives through `images`.
    var onLoadMore: (() -> Void)? = nil
    var hasMore: Bool = false
    /// Reports where the slideshow stopped, so a viewer underneath can stay on that image.
    var onFinish: ((_ imageId: String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage(TVSlideshowSettings.intervalKey) private var interval: Double = TVSlideshowSettings.defaultInterval

    @State private var index = 0
    @State private var isPaused = false
    @State private var showHUD = true
    @State private var hudWork: DispatchWorkItem?
    @State private var advanceTask: Task<Void, Never>?
    /// Loaders for the previous, current and next image. Holding the next one is the preload:
    /// by the time the crossfade starts its bitmap is decoded and the fade never shows a spinner.
    @State private var loaders: [String: ImageLoader] = [:]
    @State private var didStart = false
    @State private var isClosing = false
    @FocusState private var isFocused: Bool

    private static let fadeDuration: Double = 1.0
    private static let hudDelay: Double = 3
    /// How long an auto-advance waits for a slow next image before moving on anyway.
    private static let preloadTimeout: Double = 8

    private var currentImage: StashImage? {
        images.indices.contains(index) ? images[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = currentImage, let loader = loaders[image.id] {
                TVSlideshowSlide(
                    loader: loader,
                    driftDuration: interval + Self.fadeDuration,
                    variant: index,
                    isPaused: isPaused
                )
                .id(image.id)
                .transition(.opacity)
            } else if images.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo")
                        .font(.system(size: 64))
                    Text("No images")
                        .font(.title2)
                }
                .foregroundStyle(.secondary)
            }

            if showHUD || isPaused {
                hud
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        // One focus target for the whole screen, like the image viewer: the remote's
        // commands land here and nothing else can take focus away.
        .focusable()
        .focused($isFocused)
        .onTapGesture { cycleInterval() }
        .onMoveCommand { direction in
            switch direction {
            case .left: step(by: -1)
            case .right: step(by: 1)
            default: revealHUD()
            }
        }
        .onPlayPauseCommand { togglePause() }
        .onExitCommand { close() }
        .interactiveDismissDisabled()
        .animation(.easeInOut(duration: 0.3), value: showHUD || isPaused)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
        .onChange(of: images.map(\.id)) { _, _ in
            imagesChanged()
        }
        .onChange(of: isPaused) { _, paused in
            UIApplication.shared.isIdleTimerDisabled = !paused
        }
    }

    // MARK: - HUD

    private var hud: some View {
        VStack {
            HStack(alignment: .firstTextBaseline) {
                Text(currentImage?.displayTitle ?? "")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                if !images.isEmpty {
                    Text("\(index + 1) / \(images.count)")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 80)
            .padding(.top, 50)
            .padding(.bottom, 30)
            .background(
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
            )

            Spacer()

            HStack(spacing: 28) {
                Label(isPaused ? "Paused" : "Playing", systemImage: isPaused ? "pause.fill" : "play.fill")
                    .foregroundStyle(.white)
                Text("Every \(TVSlideshowSettings.label(for: interval))")
                    .foregroundStyle(.white.opacity(0.85))
                Text("◀ ▶ Browse · ⏯ Pause · Click: Speed · Menu: Exit")
                    .foregroundStyle(.white.opacity(0.55))
            }
            .font(.system(size: 24, weight: .medium))
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.6), in: Capsule())
            .padding(.bottom, 60)
        }
        .allowsHitTesting(false)
    }

    private func revealHUD() {
        showHUD = true
        hudWork?.cancel()
        let work = DispatchWorkItem { showHUD = false }
        hudWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hudDelay, execute: work)
    }

    // MARK: - Lifecycle

    private func start() {
        isFocused = true
        guard !didStart else { return }
        didStart = true
        if !TVSlideshowSettings.intervals.contains(interval) {
            interval = TVSlideshowSettings.defaultInterval
        }
        index = images.isEmpty ? 0 : min(max(startIndex, 0), images.count - 1)
        UIApplication.shared.isIdleTimerDisabled = true
        refreshLoaders()
        revealHUD()
        scheduleAdvance()
    }

    private func stop() {
        advanceTask?.cancel()
        advanceTask = nil
        hudWork?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        stop()
        if let image = currentImage { onFinish?(image.id) }
        dismiss()
    }

    /// More pages arrived (or the list was replaced): stay on the same image if it is still there.
    private func imagesChanged() {
        guard !images.isEmpty else { return }
        if !images.indices.contains(index) {
            index = images.count - 1
        }
        refreshLoaders()
    }

    // MARK: - Controls

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            advanceTask?.cancel()
            advanceTask = nil
        } else {
            scheduleAdvance()
        }
        revealHUD()
    }

    private func cycleInterval() {
        let options = TVSlideshowSettings.intervals
        let current = options.firstIndex(of: interval) ?? 0
        interval = options[(current + 1) % options.count]
        revealHUD()
        scheduleAdvance()
    }

    /// Manual steps never wait for the next image — the user asked for it now.
    private func step(by delta: Int) {
        revealHUD()
        move(by: delta)
        scheduleAdvance()
    }

    private func move(by delta: Int) {
        guard !images.isEmpty else { return }
        var target = index + delta
        if target >= images.count {
            if hasMore, let onLoadMore {
                // The next page is on its way; stay put and let the next tick try again.
                onLoadMore()
                return
            }
            target = 0
        } else if target < 0 {
            target = hasMore ? 0 : images.count - 1
        }
        guard target != index else { return }
        // Neighbours first, outside the animation: the target is normally preloaded already.
        refreshLoaders(around: target)
        withAnimation(.easeInOut(duration: Self.fadeDuration)) {
            // The image id is the slide's identity — changing it crossfades old into new.
            index = target
        }
        if hasMore, index >= images.count - 3 {
            onLoadMore?()
        }
    }

    private func scheduleAdvance() {
        advanceTask?.cancel()
        guard !isPaused, images.count > 1 || hasMore else {
            advanceTask = nil
            return
        }
        let wait = interval
        advanceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await waitForNextImage()
            guard !Task.isCancelled, !isPaused else { return }
            move(by: 1)
            scheduleAdvance()
        }
    }

    /// Holds the auto-advance until the preloaded next image is decoded, so the crossfade
    /// goes from picture to picture. Gives up after `preloadTimeout` and advances anyway.
    private func waitForNextImage() async {
        guard images.indices.contains(index + 1),
              let loader = loaders[images[index + 1].id] else { return }
        let deadline = Date().addingTimeInterval(Self.preloadTimeout)
        while loader.isLoading, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    // MARK: - Preloading

    /// Keeps loaders for the neighbours of the current image and drops everything else, so
    /// a long slideshow holds three full-size bitmaps at most.
    private func refreshLoaders(around center: Int? = nil) {
        let index = center ?? self.index
        guard !images.isEmpty else {
            loaders = [:]
            return
        }
        var wanted: [StashImage] = []
        for offset in [0, 1, -1] {
            let i = index + offset
            if images.indices.contains(i) {
                wanted.append(images[i])
            } else if offset == 1, !hasMore, images.count > 1 {
                wanted.append(images[0]) // wraps around at the end
            }
        }
        var next: [String: ImageLoader] = [:]
        for image in wanted {
            next[image.id] = loaders[image.id] ?? ImageLoader(url: image.imageURL ?? image.thumbnailURL)
        }
        loaders = next
    }
}

// MARK: - Slide

private struct TVSlideshowSlide: View {
    @ObservedObject var loader: ImageLoader
    /// Covers the time on screen plus the outgoing fade, so the drift never stops visibly.
    let driftDuration: Double
    let variant: Int
    let isPaused: Bool

    @State private var drifted = false

    /// Ken Burns: a slow 6 % zoom toward a different corner on every slide.
    private static let anchors: [UnitPoint] = [
        UnitPoint(x: 0.35, y: 0.35),
        UnitPoint(x: 0.65, y: 0.6),
        UnitPoint(x: 0.6, y: 0.35),
        UnitPoint(x: 0.4, y: 0.65)
    ]

    private var anchor: UnitPoint {
        Self.anchors[abs(variant) % Self.anchors.count]
    }

    var body: some View {
        ZStack {
            if let image = loader.image {
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(drifted ? 1.06 : 1.0, anchor: anchor)
                    .onAppear(perform: startDrift)
            } else if loader.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func startDrift() {
        // A paused slideshow shows the picture still; stepping while paused should not drift.
        guard !isPaused, !drifted else { return }
        withAnimation(.linear(duration: driftDuration)) {
            drifted = true
        }
    }
}
