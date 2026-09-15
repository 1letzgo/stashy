//
//  TVFocusPreview.swift
//  stashyTV
//
//  Muted preview clip that fades in once the enclosing focusable (a card button) has held
//  focus for 2 seconds. Place it inside the button label, above the thumbnail.
//

#if canImport(AetherEngine)

import SwiftUI

struct TVFocusPreview: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 0

    @Environment(\.isFocused) private var isFocused

    /// The tvOS preview pool holds one engine, so focus moving on hands it to the next card.
    @StateObject private var player = AetherPreviewPlayer()
    @State private var task: Task<Void, Never>?
    @State private var isPreviewing = false

    private static let delayNanoseconds: UInt64 = 2_000_000_000

    var body: some View {
        ZStack {
            // Only once a frame is on screen, so focusing a card never flashes black.
            if isPreviewing && player.hasFirstFrame {
                AetherPreviewSurface(player: player, fill: true)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: isPreviewing && player.hasFirstFrame)
        .onChange(of: isFocused) { _, focused in
            if focused { schedule() } else { stop() }
        }
        .onAppear { if isFocused { schedule() } }
        .onDisappear { stop() }
    }

    private func schedule() {
        task?.cancel()
        guard let url else { return }
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.delayNanoseconds)
            guard !Task.isCancelled, isFocused else { return }
            // AetherPreviewPlayer is always muted and uses the ambient audio policy.
            player.start(url: url)
            isPreviewing = true
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        guard isPreviewing else { return }
        isPreviewing = false
        player.stop(release: true)
    }
}

#endif
