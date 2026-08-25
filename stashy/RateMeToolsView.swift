//
//  RateMeToolsView.swift
//  stashy
//
//  RateMe: random unrated Scenes / Images with star rating (Match-style UI).
//  Performers stay in Match.
//

#if !os(tvOS)
import AVKit
import SwiftUI

// MARK: - DTOs

private struct RateMeSceneFindResponse: Codable {
    let data: RateMeSceneFindData?
}

private struct RateMeSceneFindData: Codable {
    let findScenes: RateMeSceneFindResult
}

private struct RateMeSceneFindResult: Codable {
    let count: Int?
    let scenes: [RateMeSceneDTO]
}

private struct RateMeSceneDTO: Codable {
    let id: String
    let title: String?
    let rating100: Int?
    let o_counter: Int?
    let paths: RateMeScenePaths?
    let performers: [RateMePerformerDTO]?
}

private struct RateMeScenePaths: Codable {
    let screenshot: String?
    let preview: String?
}

private struct RateMePerformerDTO: Codable {
    let id: String
    let name: String?
}

private struct RateMeImageFindResponse: Codable {
    let data: RateMeImageFindData?
}

private struct RateMeImageFindData: Codable {
    let findImages: RateMeImageFindResult
}

private struct RateMeImageFindResult: Codable {
    let count: Int?
    let images: [RateMeImageDTO]
}

private struct RateMeImageDTO: Codable {
    let id: String
    let title: String?
    let rating100: Int?
    let o_counter: Int?
    let paths: RateMeImagePaths?
    let visual_files: [RateMeImageFile]?
    let performers: [RateMePerformerDTO]?
}

private struct RateMeImagePaths: Codable {
    let image: String?
    let preview: String?
    let thumbnail: String?
}

private struct RateMeImageFile: Codable {
    let path: String?
    let basename: String?
    let width: Int?
    let height: Int?
    let duration: Double?
}

private struct RateMeMutationResponse: Codable {
    let data: RateMeMutationData?
}

private struct RateMeMutationData: Codable {
    let sceneUpdate: RateMeUpdated?
    let imageUpdate: RateMeUpdated?
}

private struct RateMeUpdated: Codable {
    let id: String
    let rating100: Int?
}

private struct RateMeIncrementOResponse: Codable {
    let data: RateMeIncrementOData?
}

private struct RateMeIncrementOData: Codable {
    let sceneIncrementO: Int?
    let imageIncrementO: Int?
}

private struct RateMeDestroyResponse: Codable {
    let data: RateMeDestroyData?
}

private struct RateMeDestroyData: Codable {
    let sceneDestroy: Bool?
    let imageDestroy: Bool?
}

// MARK: - ViewModel

@MainActor
private final class RateMeViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case scenes
        case images

        var id: String { rawValue }

        var label: String {
            switch self {
            case .scenes: return "Scenes"
            case .images: return "Images"
            }
        }

        var emptyIcon: String {
            switch self {
            case .scenes: return "film"
            case .images: return "photo"
            }
        }
    }

    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        /// Still thumbnail (scene screenshot / image thumbnail).
        let thumbnailURL: URL?
        /// Scene preview clip (`paths.preview`), when present.
        let previewURL: URL?
        /// Full image media — used for image videos (`paths.image`).
        let videoURL: URL?
        let isVideo: Bool
        /// width ÷ height when known (images); scenes always render 16:9.
        let aspectRatio: CGFloat?
        /// Joined performer names.
        let performerNames: String?
        var oCounter: Int
        let mode: Mode
        /// Minimal ``StashImage`` for opening ``FullScreenImageView`` (images mode).
        let openableImage: StashImage?

        var playbackURL: URL? {
            switch mode {
            case .scenes: return previewURL
            case .images: return isVideo ? videoURL : nil
            }
        }
    }

    private static let modeDefaultsKey = "stashy.rateMe.mode"
    private static let imageMediaKindDefaultsKey = "stashy.rateMe.imageMediaKind"
    private static let ratingHoldNanoseconds: UInt64 = 750_000_000

    @Published var mode: Mode = .scenes {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeDefaultsKey) }
    }
    /// Images mode: Any / still images / videos only.
    @Published var imageMediaKind: ImageListMediaKind = .all {
        didSet { UserDefaults.standard.set(imageMediaKind.rawValue, forKey: Self.imageMediaKindDefaultsKey) }
    }
    @Published var item: Item?
    @Published var draftRating100: Int?
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var isIncrementingO = false
    @Published var isDeleting = false
    @Published var errorMessage: String?
    @Published var remainingHint: Int?

    private let client = GraphQLClient.shared
    private var skipIDs: Set<String> = []

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.modeDefaultsKey),
           let restored = Mode(rawValue: raw) {
            mode = restored
        }
        if let raw = UserDefaults.standard.string(forKey: Self.imageMediaKindDefaultsKey),
           let restored = ImageListMediaKind(rawValue: raw) {
            imageMediaKind = restored
        }
    }

    func loadNext(resetSkip: Bool = false) async {
        if resetSkip { skipIDs.removeAll() }
        isLoading = true
        errorMessage = nil
        draftRating100 = nil
        defer { isLoading = false }

        do {
            switch mode {
            case .scenes:
                item = try await fetchUnratedScene()
            case .images:
                item = try await fetchUnratedImage()
            }
            if item == nil {
                errorMessage = "No unrated \(mode.label.lowercased()) left."
            }
        } catch {
            item = nil
            errorMessage = error.localizedDescription
        }
    }

    func skip() async {
        if let id = item?.id {
            skipIDs.insert(id)
        }
        await loadNext()
    }

    func submitRating(_ rating100: Int?) async {
        guard let current = item else { return }
        isSubmitting = true
        draftRating100 = rating100
        defer { isSubmitting = false }

        do {
            let ok = try await mutateRating(id: current.id, mode: current.mode, rating100: rating100)
            guard ok else {
                errorMessage = "Failed to save rating."
                draftRating100 = nil
                return
            }
            HapticManager.success()
            switch current.mode {
            case .scenes:
                NotificationCenter.default.post(
                    name: NSNotification.Name("SceneRatingUpdated"),
                    object: nil,
                    userInfo: {
                        var info: [String: Any] = [
                            "sceneId": current.id,
                            "title": current.title
                        ]
                        if let rating100 { info["rating100"] = rating100 }
                        return info
                    }()
                )
            case .images:
                var userInfo: [String: Any] = [
                    "imageId": current.id,
                    "title": current.title
                ]
                if let rating100 {
                    userInfo["rating100"] = rating100
                }
                if let thumb = current.openableImage?.paths?.thumbnail
                    ?? current.openableImage?.paths?.preview
                    ?? current.openableImage?.paths?.image {
                    userInfo["thumbnailPath"] = thumb
                }
                NotificationCenter.default.post(
                    name: NSNotification.Name("ImageRatingUpdated"),
                    object: nil,
                    userInfo: userInfo
                )
            }
            // Keep the selected stars visible briefly before advancing.
            try? await Task.sleep(nanoseconds: Self.ratingHoldNanoseconds)
            skipIDs.remove(current.id)
            await loadNext()
        } catch {
            errorMessage = error.localizedDescription
            draftRating100 = nil
        }
    }

    func incrementOCounter() async {
        guard var current = item, !isIncrementingO else { return }
        isIncrementingO = true
        let previous = current.oCounter
        current.oCounter = previous + 1
        item = current
        defer { isIncrementingO = false }

        do {
            let newCount = try await mutateIncrementO(id: current.id, mode: current.mode)
            current.oCounter = newCount ?? (previous + 1)
            item = current
            HapticManager.success()
            switch current.mode {
            case .scenes:
                NotificationCenter.default.post(
                    name: NSNotification.Name("SceneOCounterUpdated"),
                    object: nil,
                    userInfo: ["sceneId": current.id, "oCounter": current.oCounter]
                )
            case .images:
                NotificationCenter.default.post(
                    name: NSNotification.Name("ImageOCounterUpdated"),
                    object: nil,
                    userInfo: ["imageId": current.id, "oCounter": current.oCounter]
                )
            }
        } catch {
            current.oCounter = previous
            item = current
            errorMessage = error.localizedDescription
        }
    }

    func deleteCurrent() async {
        guard let current = item, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            let ok = try await mutateDestroy(id: current.id, mode: current.mode)
            guard ok else {
                errorMessage = current.mode == .scenes ? "Failed to delete scene." : "Failed to delete image."
                return
            }
            HapticManager.success()
            ToastManager.shared.show(
                current.mode == .scenes ? "Scene deleted" : "Image deleted",
                icon: "trash",
                style: .success
            )
            skipIDs.remove(current.id)
            await loadNext()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Fetch

    /// `IntCriterionInput.value` is required by GraphQL even for IS_NULL (Stash ignores it in SQL).
    private var unratedFilter: [String: Any] {
        ["rating100": ["modifier": "IS_NULL", "value": 0]]
    }

    private var unratedImageFilter: [String: Any] {
        var filter = unratedFilter
        if let path = imageMediaKind.pathCriterion {
            filter["path"] = path
        }
        return filter
    }

    /// Stash expects `random_<seed>` (not bare `random`).
    private var pageFilter: [String: Any] {
        [
            "per_page": 1,
            "sort": "random_\(Int.random(in: 0...99_999_999))"
        ]
    }

    private func fetchUnratedScene() async throws -> Item? {
        let query = GraphQLQueries.loadQuery(named: "findScenesCompact")
        for _ in 0..<8 {
            let variables: [String: Any] = [
                "filter": pageFilter,
                "scene_filter": unratedFilter
            ]
            let res: RateMeSceneFindResponse = try await client.execute(query: query, variables: variables)
            remainingHint = res.data?.findScenes.count
            guard let scene = res.data?.findScenes.scenes.first else { return nil }
            if skipIDs.contains(scene.id) { continue }
            let preview = signedMediaURL(scene.paths?.preview)
            let performers = (scene.performers ?? [])
                .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                .joined(separator: ", ")
            return Item(
                id: scene.id,
                title: scene.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled scene",
                thumbnailURL: signedMediaURL(scene.paths?.screenshot),
                previewURL: preview,
                videoURL: nil,
                isVideo: preview != nil,
                aspectRatio: 16.0 / 9.0,
                performerNames: performers.nilIfEmpty,
                oCounter: scene.o_counter ?? 0,
                mode: .scenes,
                openableImage: nil
            )
        }
        return nil
    }

    private func fetchUnratedImage() async throws -> Item? {
        let query = GraphQLQueries.queryWithFragments("findImages")
        for _ in 0..<8 {
            let variables: [String: Any] = [
                "filter": pageFilter,
                "image_filter": unratedImageFilter
            ]
            let res: RateMeImageFindResponse = try await client.execute(query: query, variables: variables)
            remainingHint = res.data?.findImages.count
            guard let image = res.data?.findImages.images.first else { return nil }
            if skipIDs.contains(image.id) { continue }

            let isVideo = Self.isVideoImage(image)
            let thumb = signedMediaURL(image.paths?.thumbnail)
                ?? signedMediaURL(image.paths?.preview)
            let media = signedMediaURL(image.paths?.image)
            let aspect: CGFloat? = {
                if let w = image.visual_files?.first?.width,
                   let h = image.visual_files?.first?.height,
                   w > 0, h > 0 {
                    return CGFloat(w) / CGFloat(h)
                }
                return isVideo ? (16.0 / 9.0) : 1
            }()

            let performers = (image.performers ?? [])
                .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                .joined(separator: ", ")
            let galleryPerformers: [GalleryPerformer]? = image.performers?.compactMap { p in
                guard let name = p.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return nil }
                return GalleryPerformer(id: p.id, name: name, image_path: nil)
            }
            let visualFiles: [ImageFile]? = image.visual_files?.compactMap { file in
                guard let path = file.path, !path.isEmpty else { return nil }
                return ImageFile(
                    path: path,
                    height: file.height,
                    width: file.width,
                    duration: file.duration,
                    basename: file.basename
                )
            }
            let openable = StashImage(
                id: image.id,
                title: image.title,
                rating100: image.rating100,
                o_counter: image.o_counter,
                organized: nil,
                date: nil,
                createdAt: nil,
                updatedAt: nil,
                paths: ImagePaths(
                    thumbnail: image.paths?.thumbnail,
                    preview: image.paths?.preview,
                    image: image.paths?.image
                ),
                visual_files: visualFiles,
                performers: galleryPerformers,
                studio: nil,
                galleries: nil,
                tags: nil
            )
            return Item(
                id: image.id,
                title: image.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled image",
                thumbnailURL: thumb ?? media,
                previewURL: nil,
                videoURL: isVideo ? media : nil,
                isVideo: isVideo,
                aspectRatio: aspect,
                performerNames: performers.nilIfEmpty,
                oCounter: image.o_counter ?? 0,
                mode: .images,
                openableImage: openable
            )
        }
        return nil
    }

    private static func isVideoImage(_ image: RateMeImageDTO) -> Bool {
        let videoExtensions: Set<String> = ["MP4", "MOV", "M4V", "WEBM", "MKV"]
        let candidates = [
            image.visual_files?.first?.basename,
            image.visual_files?.first?.path,
            image.paths?.image
        ].compactMap { $0 }
        for candidate in candidates {
            let clean = (candidate.components(separatedBy: "?").first ?? candidate)
            let ext = (clean as NSString).pathExtension.uppercased()
            if videoExtensions.contains(ext) { return true }
        }
        return false
    }

    private func signedMediaURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return signedURL(URL(string: path))
        }
        guard let config = ServerConfigManager.shared.loadConfig(), config.hasValidConfig else { return nil }
        return signedURL(URL(string: "\(config.baseURL)\(path.hasPrefix("/") ? "" : "/")\(path)"))
    }

    // MARK: Mutate

    private func mutateRating(id: String, mode: Mode, rating100: Int?) async throws -> Bool {
        let mutation: String
        let field: String
        switch mode {
        case .scenes:
            field = "sceneUpdate"
            mutation = """
            mutation RateMeSceneUpdate($input: SceneUpdateInput!) {
              sceneUpdate(input: $input) { id rating100 }
            }
            """
        case .images:
            field = "imageUpdate"
            mutation = """
            mutation RateMeImageUpdate($input: ImageUpdateInput!) {
              imageUpdate(input: $input) { id rating100 }
            }
            """
        }

        var input: [String: Any] = ["id": id]
        input["rating100"] = rating100.map { $0 as Any } ?? NSNull()
        let variables: [String: Any] = ["input": input]
        let res: RateMeMutationResponse = try await client.execute(query: mutation, variables: variables)
        switch field {
        case "sceneUpdate": return res.data?.sceneUpdate != nil
        case "imageUpdate": return res.data?.imageUpdate != nil
        default: return false
        }
    }

    private func mutateIncrementO(id: String, mode: Mode) async throws -> Int? {
        let mutation: String
        switch mode {
        case .scenes:
            mutation = """
            mutation RateMeSceneIncrementO($id: ID!) {
              sceneIncrementO(id: $id)
            }
            """
        case .images:
            mutation = """
            mutation RateMeImageIncrementO($id: ID!) {
              imageIncrementO(id: $id)
            }
            """
        }
        let res: RateMeIncrementOResponse = try await client.execute(
            query: mutation,
            variables: ["id": id]
        )
        switch mode {
        case .scenes: return res.data?.sceneIncrementO
        case .images: return res.data?.imageIncrementO
        }
    }

    private func mutateDestroy(id: String, mode: Mode) async throws -> Bool {
        let mutation: String
        switch mode {
        case .scenes:
            mutation = """
            mutation RateMeSceneDestroy($input: SceneDestroyInput!) {
              sceneDestroy(input: $input)
            }
            """
        case .images:
            mutation = """
            mutation RateMeImageDestroy($input: ImageDestroyInput!) {
              imageDestroy(input: $input)
            }
            """
        }
        let variables: [String: Any] = [
            "input": [
                "id": id,
                "delete_file": true,
                "delete_generated": true
            ]
        ]
        let res: RateMeDestroyResponse = try await client.execute(query: mutation, variables: variables)
        switch mode {
        case .scenes: return res.data?.sceneDestroy == true
        case .images: return res.data?.imageDestroy == true
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Media

/// Video preview that fits inside the media box (never wider/taller than the card slot).
private struct RateMeAspectFitVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

private struct RateMeMediaView: View {
    let item: RateMeViewModel.Item

    @State private var player: AVPlayer?
    @State private var isPreviewing = false
    @State private var autoplayTask: Task<Void, Never>?
    @State private var loopObserver: NSObjectProtocol?

    private var aspect: CGFloat {
        item.aspectRatio ?? (item.mode == .scenes ? (16.0 / 9.0) : 1)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.08)

            if let url = item.thumbnailURL {
                CustomAsyncImage(url: url) { loader in
                    if loader.isLoading {
                        InlineSpinner(tint: .secondary)
                    } else if let image = loader.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        placeholderIcon
                    }
                }
            } else {
                placeholderIcon
            }

            if isPreviewing, let player {
                RateMeAspectFitVideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if item.playbackURL != nil && !isPreviewing {
                Image(systemName: "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.black.opacity(DesignTokens.Opacity.medium))
                    .clipShape(Circle())
            }
        }
        // Flexible proposal first, then aspect-fit so the layout height shrinks to the media.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .aspectRatio(aspect, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous))
        .onAppear { scheduleAutoplay() }
        .onDisappear { stopPreview(releasePlayer: true) }
        .onChange(of: item.id) { _, _ in
            stopPreview(releasePlayer: true)
            scheduleAutoplay()
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: item.mode.emptyIcon)
            .font(.system(size: 48))
            .foregroundStyle(.secondary)
    }

    private func scheduleAutoplay() {
        autoplayTask?.cancel()
        autoplayTask = nil
        guard item.playbackURL != nil else {
            stopPreview(releasePlayer: true)
            return
        }
        autoplayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            startPreview()
        }
    }

    private func startPreview() {
        guard let url = item.playbackURL else { return }
        if player == nil {
            let newPlayer = createMutedPreviewPlayer(for: url)
            player = newPlayer
            if let observer = loopObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem,
                queue: .main
            ) { [weak newPlayer] _ in
                newPlayer?.seek(to: .zero)
                newPlayer?.play()
            }
        }
        withAnimation(.easeIn(duration: 0.2)) {
            isPreviewing = true
        }
        player?.play()
    }

    private func stopPreview(releasePlayer: Bool) {
        autoplayTask?.cancel()
        autoplayTask = nil
        isPreviewing = false
        player?.pause()
        player?.seek(to: .zero)
        if releasePlayer {
            if let observer = loopObserver {
                NotificationCenter.default.removeObserver(observer)
                loopObserver = nil
            }
            player = nil
        }
    }
}

// MARK: - UI

struct RateMeToolsView: View {
    @StateObject private var model = RateMeViewModel()
    @ObservedObject private var appearance = AppearanceManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Avoids reloading when returning from `NavigationLink` (Watch Scene): `.task` restarts after disappear/reappear.
    @State private var didRunInitialRateMeLoad = false
    @State private var showDeleteConfirmation = false

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack(spacing: 0) {
            if let err = model.errorMessage, model.item == nil {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignTokens.Tools.contentPadding)
            }

            ToolsPillMenuRow(
                items: RateMeViewModel.Mode.allCases.map {
                    ToolsPillMenuRow.Item(id: $0.rawValue, title: $0.label)
                },
                selectionID: model.mode.rawValue,
                accessibilityLabel: "RateMe section"
            ) { id in
                if let mode = RateMeViewModel.Mode(rawValue: id) {
                    model.mode = mode
                }
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .onAppear {
            guard !didRunInitialRateMeLoad else { return }
            didRunInitialRateMeLoad = true
            Task { await model.loadNext(resetSkip: true) }
        }
        .onChange(of: model.mode) { _, _ in
            Task { await model.loadNext(resetSkip: true) }
        }
        .onChange(of: model.imageMediaKind) { _, _ in
            guard model.mode == .images else { return }
            Task { await model.loadNext(resetSkip: true) }
        }
        .alert(deleteConfirmationTitle, isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await model.deleteCurrent() }
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var deleteConfirmationTitle: String {
        model.mode == .scenes ? "Really delete scene and files?" : "Really delete image and files?"
    }

    private var deleteConfirmationMessage: String {
        let name = model.item?.title ?? (model.mode == .scenes ? "this scene" : "this image")
        return "‘\(name)’ and all associated files will be permanently deleted. This action cannot be undone."
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 12) {
            if model.mode == .images {
                imageMediaKindChrome
            }

            if model.isLoading && model.item == nil {
                StandardLoadingView(message: "Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let item = model.item {
                mediaCard(item)
                    .layoutPriority(1)
                    .frame(maxWidth: isRegular ? 720 : .infinity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                detailsAndActions(item)
            } else {
                ContentUnavailableView(
                    "Nothing to rate",
                    systemImage: model.mode.emptyIcon,
                    description: Text(model.errorMessage ?? "All \(model.mode.label.lowercased()) already have a rating.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolsHorizontalPadding(horizontalSizeClass)
        .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func detailsAndActions(_ item: RateMeViewModel.Item) -> some View {
        detailsCard(item)
        ratingRow(item)

        if let remaining = model.remainingHint {
            Text("\(remaining) unrated \(model.mode.label.lowercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }

        if item.mode == .scenes {
            watchSceneButton(for: item)
        } else if item.mode == .images {
            openImageButton(for: item)
        }

        Button {
            Task { await model.skip() }
        } label: {
            Label("Skip", systemImage: "forward.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .disabled(model.isSubmitting || model.isLoading)
    }

    private func mediaCard(_ item: RateMeViewModel.Item) -> some View {
        RateMeMediaView(item: item)
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .cardShadow()
            .opacity(model.isSubmitting ? 0.85 : 1)
    }

    private func watchSceneButton(for item: RateMeViewModel.Item) -> some View {
        NavigationLink {
            SceneDetailView(scene: Self.stubScene(from: item))
        } label: {
            Label("Watch Scene", systemImage: "play.rectangle.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(appearance.tintColor)
        .simultaneousGesture(TapGesture().onEnded { HapticManager.light() })
        .disabled(model.isSubmitting || model.isLoading)
        .accessibilityLabel("Watch Scene")
        .accessibilityHint("Opens this scene; Back returns to RateMe")
    }

    private func openImageButton(for item: RateMeViewModel.Item) -> some View {
        Group {
            if let image = item.openableImage {
                NavigationLink {
                    FullScreenImageView(images: .constant([image]), selectedImageId: image.id)
                } label: {
                    Label("Open Image", systemImage: "photo.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.tintColor)
                .simultaneousGesture(TapGesture().onEnded { HapticManager.light() })
                .disabled(model.isSubmitting || model.isLoading)
                .accessibilityLabel("Open Image")
                .accessibilityHint("Opens this image; Back returns to RateMe")
            }
        }
    }

    /// Minimal ``Scene`` for deep-link; ``SceneDetailView`` loads full details on appear.
    private static func stubScene(from item: RateMeViewModel.Item) -> Scene {
        Scene(
            id: item.id,
            title: item.title,
            details: nil,
            date: nil,
            duration: nil,
            studio: nil,
            performers: [],
            files: nil,
            tags: nil,
            galleries: nil,
            organized: nil,
            resumeTime: nil,
            playCount: nil,
            oCounter: item.oCounter,
            rating100: nil,
            createdAt: nil,
            updatedAt: nil,
            paths: nil,
            sceneMarkers: nil,
            interactive: nil,
            streams: nil
        )
    }

    private func detailsCard(_ item: RateMeViewModel.Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let performers = item.performerNames {
                Text(performers)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .opacity(model.isSubmitting ? 0.85 : 1)
    }

    private func ratingRow(_ item: RateMeViewModel.Item) -> some View {
        HStack(alignment: .center, spacing: 10) {
            StarRatingView(
                rating100: model.draftRating100,
                isInteractive: !model.isSubmitting && !model.isDeleting,
                size: 24,
                spacing: 4
            ) { newRating in
                Task { await model.submitRating(newRating) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await model.incrementOCounter() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: item.oCounter > 0
                          ? appearance.oCounterIconFilled
                          : appearance.oCounterIcon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(item.oCounter > 0 ? appearance.tintColor : .secondary)
                    Text("\(item.oCounter)")
                        .font(.body.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(Color.appBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.isSubmitting || model.isIncrementingO || model.isDeleting)
            .accessibilityLabel("O-Counter \(item.oCounter), tap to increment")

            Button {
                HapticManager.light()
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
                    .background(Color.appBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.isSubmitting || model.isDeleting || model.isLoading)
            .accessibilityLabel("Delete")
            .accessibilityHint("Deletes this item and its files after confirmation")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .opacity(model.isSubmitting ? 0.85 : 1)
    }

    private var imageMediaKindChrome: some View {
        HStack(spacing: StashyExpandingDock.itemSpacing) {
            ForEach(ImageListMediaKind.allCases) { kind in
                imageMediaKindChip(kind)
            }
        }
    }

    private func imageMediaKindChip(_ kind: ImageListMediaKind) -> some View {
        let selected = model.imageMediaKind == kind
        let title: String = {
            switch kind {
            case .all: return "Any"
            case .stillImage: return "Image"
            case .video: return "Video"
            }
        }()
        return Button {
            HapticManager.selection()
            model.imageMediaKind = kind
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? appearance.tintColor : Color.secondaryAppBackground)
                        .shadow(
                            color: selected ? appearance.tintColor.opacity(0.35) : .clear,
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                )
                .clipShape(Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .accessibilityLabel("\(title)\(selected ? ", selected" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#endif
