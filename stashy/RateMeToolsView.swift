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
        } catch {
            current.oCounter = previous
            item = current
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
                mode: .scenes
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
                mode: .images
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
    private static let contentHorizontalPadding: CGFloat = 16

    @StateObject private var model = RateMeViewModel()
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if let err = model.errorMessage, model.item == nil {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Self.contentHorizontalPadding)
                    .padding(.top, 8)
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            modeChrome
        }
        .task {
            await model.loadNext(resetSkip: true)
        }
        .onChange(of: model.mode) { _, _ in
            Task { await model.loadNext(resetSkip: true) }
        }
        .onChange(of: model.imageMediaKind) { _, _ in
            guard model.mode == .images else { return }
            Task { await model.loadNext(resetSkip: true) }
        }
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
                    // Flex slot for sizing; card itself stays aspect-fitted and top-centered.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                detailsCard(item)

                if let remaining = model.remainingHint {
                    Text("\(remaining) unrated \(model.mode.label.lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
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
            } else {
                ContentUnavailableView(
                    "Nothing to rate",
                    systemImage: model.mode.emptyIcon,
                    description: Text(model.errorMessage ?? "All \(model.mode.label.lowercased()) already have a rating.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, Self.contentHorizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func detailsCard(_ item: RateMeViewModel.Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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

            // Full-width row: Rate 2/3 + O 1/3.
            GeometryReader { geo in
                let gap: CGFloat = 10
                let oWidth = max(0, (geo.size.width - gap) / 3)
                let rateWidth = max(0, geo.size.width - gap - oWidth)
                HStack(alignment: .center, spacing: gap) {
                    VStack(spacing: 14) {
                        Text("Rate")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        StarRatingView(
                            rating100: model.draftRating100,
                            isInteractive: !model.isSubmitting,
                            size: 28,
                            spacing: 6
                        ) { newRating in
                            Task { await model.submitRating(newRating) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(12)
                    .frame(width: rateWidth, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .leading)
                    .background(Color.appBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous))

                    Button {
                        Task { await model.incrementOCounter() }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: item.oCounter > 0
                                  ? appearance.oCounterIconFilled
                                  : appearance.oCounterIcon)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(item.oCounter > 0 ? appearance.tintColor : .secondary)
                            Text("\(item.oCounter)")
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: oWidth)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.appBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSubmitting || model.isIncrementingO)
                    .accessibilityLabel("O-Counter \(item.oCounter), tap to increment")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
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
        HStack(spacing: 8) {
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? appearance.tintColor : Color.secondary.opacity(0.15))
                )
                .clipShape(Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .accessibilityLabel("\(title)\(selected ? ", selected" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var modeChrome: some View {
        HStack(spacing: StashyExpandingDock.itemSpacing) {
            ForEach(RateMeViewModel.Mode.allCases) { mode in
                modeChip(mode)
            }
        }
        .padding(.horizontal, StashyExpandingDock.edgePadding)
        .padding(.bottom, DesignTokens.Chrome.fabBottomPadding)
    }

    private func modeChip(_ mode: RateMeViewModel.Mode) -> some View {
        let selected = model.mode == mode
        return Button {
            HapticManager.selection()
            model.mode = mode
        } label: {
            Text(mode.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: StashyExpandingDock.activeHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? appearance.tintColor : Color.secondary.opacity(0.15))
                        .shadow(
                            color: selected ? appearance.tintColor.opacity(0.35) : .clear,
                            radius: 6,
                            x: 0,
                            y: 3
                        )
                )
                .clipShape(Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .accessibilityLabel("\(mode.label)\(selected ? ", selected" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#endif
