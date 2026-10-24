//
//  TVRateMeView.swift
//  stashyTV
//
//  RateMe for Apple TV. Same `RateMeViewModel` as iOS (`stashy/RateMeToolsView.swift`):
//  random / newest / most played unrated scenes or images, `sceneUpdate` / `imageUpdate`
//  `rating100` and the O-counter increment. One large item; the five stars are a focus row
//  (◀ / ▶ previews, select saves) and the next item loads on its own.
//
//  Not on tvOS: performer / studio / tag themes (iOS picks them in a search sheet) and
//  deleting the item with its files.
//

import SwiftUI

struct TVRateMeView: View {
    @StateObject private var model = RateMeViewModel()
    @ObservedObject private var appearance = AppearanceManager.shared
    @Environment(\.tvNavigationPath) private var path
    @Environment(\.tvContentWidth) private var contentWidth
    @State private var didRunInitialLoad = false
    @State private var presentedImage: StashImage?
    @FocusState private var focusedStar: Int?

    private static let horizontalPadding: CGFloat = 60

    private var modeOptions: [TVPickerOption<RateMeViewModel.Mode>] {
        RateMeViewModel.Mode.allCases.map { TVPickerOption($0, $0.label) }
    }

    private var themeOptions: [TVPickerOption<String>] {
        model.availableFixedThemes.map { TVPickerOption($0.id, $0.label) }
    }

    private var themeBinding: Binding<String> {
        Binding(
            get: { model.theme.id },
            set: { id in
                guard let theme = model.availableFixedThemes.first(where: { $0.id == id }) else { return }
                Task { await model.selectTheme(theme) }
            }
        )
    }

    private var mediaKindOptions: [TVPickerOption<ImageListMediaKind>] {
        ImageListMediaKind.allCases.map { kind in
            switch kind {
            case .all: return TVPickerOption(kind, "Any media")
            case .stillImage: return TVPickerOption(kind, "Images")
            case .video: return TVPickerOption(kind, "Videos")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            header
            content
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, 24)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Land on the middle star, not on the pickers in the header.
        .defaultFocus($focusedStar, 3)
        .background(Color.appBackground)
        .onAppear {
            guard !didRunInitialLoad else { return }
            didRunInitialLoad = true
            Task { await model.startNewSession() }
        }
        .onChange(of: model.mode) { _, _ in
            Task { await model.startNewSession() }
        }
        .onChange(of: model.imageMediaKind) { _, _ in
            guard model.mode == .images else { return }
            Task { await model.startNewSession() }
        }
        .dismissOnAppLock { presentedImage = nil }
        .fullScreenCover(item: $presentedImage) { image in
            TVImageDetailView(
                imageId: image.id,
                imageTitle: image.title ?? "Untitled",
                initialImages: [image]
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            Text("RateMe")
                .font(.largeTitle)
                .fontWeight(.bold)

            if let remaining = model.remainingHint, model.item != nil {
                Text("\(remaining) unrated")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            TVOptionPickerButton(
                title: "Rate",
                icon: model.mode.emptyIcon,
                options: modeOptions,
                selection: $model.mode
            )
            if model.mode == .images {
                TVOptionPickerButton(
                    title: "Media",
                    icon: "photo.on.rectangle",
                    options: mediaKindOptions,
                    selection: $model.imageMediaKind
                )
            }
            TVOptionPickerButton(
                title: "Theme",
                icon: model.theme.icon,
                options: themeOptions,
                selection: themeBinding
            )
        }
        .focusSection()
    }

    // MARK: - Content

    private var mediaWidth: CGFloat {
        let available = contentWidth - 2 * Self.horizontalPadding
        return max(800, available * 0.62)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.item == nil {
            VStack(spacing: 20) {
                ProgressView()
                Text("Loading…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let item = model.item {
            HStack(alignment: .top, spacing: 60) {
                TVRateMeMedia(item: item)
                    .frame(width: mediaWidth, height: mediaWidth * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .opacity(model.isSubmitting ? 0.85 : 1)
                    .focusable(false)

                sidePanel(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "Nothing to rate",
                systemImage: model.mode.emptyIcon,
                description: Text(model.errorMessage ?? "All \(model.mode.label.lowercased()) already have a rating.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sidePanel(_ item: RateMeViewModel.Item) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(3)
                if let performers = item.performerNames {
                    Text(performers)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if let err = model.errorMessage {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            starRow
                .focusSection()

            VStack(alignment: .leading, spacing: 20) {
                Button {
                    Task { await model.incrementOCounter() }
                } label: {
                    TVMatchActionLabel(
                        icon: item.oCounter > 0 ? appearance.oCounterIconFilled : appearance.oCounterIcon,
                        title: "\(item.oCounter)"
                    )
                }
                .buttonStyle(.card)
                .accessibilityLabel("O-Counter \(item.oCounter), select to increment")

                Button {
                    guard !model.isSubmitting, !model.isLoading else { return }
                    Task { await model.skip() }
                } label: {
                    TVMatchActionLabel(icon: "forward.fill", title: "Skip")
                }
                .buttonStyle(.card)

                openButton(item)
            }
            .focusSection()

            Spacer(minLength: 0)
        }
    }

    /// Five card stars. Focus previews the rating, select writes it; the next item loads after
    /// the same short hold as on iOS.
    private var starRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RATING")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 20) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        guard !model.isSubmitting, !model.isLoading else { return }
                        Task { await model.submitRating(star * 20) }
                    } label: {
                        Image(systemName: isStarFilled(star) ? "star.fill" : "star")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(isStarFilled(star) ? appearance.tintColor : Color.secondary)
                            .frame(width: 96, height: 96)
                    }
                    .buttonStyle(.card)
                    .focused($focusedStar, equals: star)
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                }
            }
        }
    }

    private func isStarFilled(_ star: Int) -> Bool {
        if let draft = model.draftRating100 {
            return star * 20 <= draft
        }
        if let focusedStar {
            return star <= focusedStar
        }
        return false
    }

    @ViewBuilder
    private func openButton(_ item: RateMeViewModel.Item) -> some View {
        switch item.mode {
        case .scenes:
            Button {
                path?.wrappedValue.append(TVSceneLink(sceneId: item.id))
            } label: {
                TVMatchActionLabel(icon: "play.fill", title: "Watch")
            }
            .buttonStyle(.card)
        case .images:
            // The tvOS image viewer shows stills only.
            if let image = item.openableImage, !item.isVideo {
                Button {
                    presentedImage = image
                } label: {
                    TVMatchActionLabel(icon: "arrow.up.left.and.arrow.down.right", title: "Open")
                }
                .buttonStyle(.card)
            }
        }
    }
}

// MARK: - Media

/// Large still with the muted preview clip (scenes, image videos) faded in on top.
private struct TVRateMeMedia: View {
    let item: RateMeViewModel.Item

    #if canImport(AetherEngine)
    @StateObject private var previewPlayer = AetherPreviewPlayer()
    @State private var autoplayTask: Task<Void, Never>?
    @State private var isPreviewing = false
    #endif

    /// Stills get the full image, not the small grid thumbnail.
    private var stillURL: URL? {
        if item.mode == .images, !item.isVideo,
           let raw = item.openableImage?.paths?.image,
           raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return signedURL(URL(string: raw)) ?? item.thumbnailURL
        }
        return item.thumbnailURL
    }

    var body: some View {
        ZStack {
            Color.black
            if let url = stillURL {
                CustomAsyncImage(url: url) { loader in
                    if let image = loader.image {
                        image.resizable().scaledToFit()
                    } else if loader.isLoading {
                        ProgressView()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }

            #if canImport(AetherEngine)
            if isPreviewing && previewPlayer.hasFirstFrame {
                AetherPreviewSurface(player: previewPlayer, fill: false)
                    .transition(.opacity)
            }
            #endif
        }
        #if canImport(AetherEngine)
        .animation(.easeInOut(duration: 0.25), value: isPreviewing && previewPlayer.hasFirstFrame)
        .onAppear { scheduleAutoplay() }
        .onDisappear { stopPreview() }
        .onChange(of: item.id) { _, _ in
            stopPreview()
            scheduleAutoplay()
        }
        #endif
    }

    private var placeholder: some View {
        Image(systemName: item.mode.emptyIcon)
            .font(.system(size: 96))
            .foregroundStyle(.secondary)
    }

    #if canImport(AetherEngine)
    private func scheduleAutoplay() {
        autoplayTask?.cancel()
        autoplayTask = nil
        guard let url = item.playbackURL else { return }
        autoplayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            previewPlayer.start(url: url)
            isPreviewing = true
        }
    }

    private func stopPreview() {
        autoplayTask?.cancel()
        autoplayTask = nil
        isPreviewing = false
        previewPlayer.stop(release: true)
    }
    #endif
}
