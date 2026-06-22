//
//  TVImageDetailView.swift
//  stashyTV
//
//  Full-screen image viewer for tvOS with swipe navigation
//

import SwiftUI

struct TVImageDetailView: View {
    let imageId: String
    let imageTitle: String

    @StateObject private var viewModel = StashDBViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var images: [StashImage] = []
    @State private var hasLoaded: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if images.isEmpty {
                ProgressView()
                    .scaleEffect(1.5)
            } else {
                imageViewer
            }
        }
        .focusable()
        .onExitCommand {
            dismiss()
        }
        .onPlayPauseCommand {
            dismiss()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                if currentIndex > 0 { currentIndex -= 1 }
            case .right:
                if currentIndex < images.count - 1 { currentIndex += 1 }
            default:
                break
            }
        }
        .onAppear {
            loadImages()
        }
    }

    @ViewBuilder
    private var imageViewer: some View {
        if currentIndex < images.count {
            let image = images[currentIndex]
            CustomAsyncImage(url: image.imageURL ?? image.thumbnailURL) { loader in
                if let img = loader.image {
                    img
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if loader.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 64))
                        .foregroundColor(.white.opacity(0.12))
                }
            }
            .ignoresSafeArea()

            // Position indicator
            VStack {
                Spacer()
                if images.count > 1 {
                    Text("\(currentIndex + 1) / \(images.count)")
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 30)
                }
            }
        }
    }

    private func loadImages() {
        guard !hasLoaded else { return }
        hasLoaded = true

        if !viewModel.allImages.isEmpty {
            images = viewModel.allImages.filter { !$0.isAnimated }
            currentIndex = max(0, images.firstIndex(where: { $0.id == imageId }) ?? 0)
            return
        }

        if !viewModel.galleryImages.isEmpty {
            images = viewModel.galleryImages.filter { !$0.isAnimated }
            currentIndex = max(0, images.firstIndex(where: { $0.id == imageId }) ?? 0)
            return
        }

        viewModel.fetchImages(sortBy: .dateDesc, isInitialLoad: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.images = viewModel.allImages.filter { !$0.isAnimated }
            self.currentIndex = max(0, self.images.firstIndex(where: { $0.id == self.imageId }) ?? 0)
        }
    }
}
