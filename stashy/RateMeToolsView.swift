//
//  RateMeToolsView.swift
//  stashy
//
//  RateMe: random unrated Scenes / Images with star rating (Match-style UI).
//  Performers stay in Match.
//

#if !os(tvOS)
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

    /// What a round draws from. Random is the old behaviour; the rest narrow it so a round has a
    /// point ("all unrated scenes of this performer").
    enum Theme: Equatable, Identifiable {
        case random
        case newest
        case mostPlayed
        case performer(FilterEntityOption)
        case studio(FilterEntityOption)
        case tag(FilterEntityOption)

        var id: String {
            switch self {
            case .random: return "random"
            case .newest: return "newest"
            case .mostPlayed: return "mostPlayed"
            case .performer(let o): return "performer-\(o.id)"
            case .studio(let o): return "studio-\(o.id)"
            case .tag(let o): return "tag-\(o.id)"
            }
        }

        var label: String {
            switch self {
            case .random: return "Random"
            case .newest: return "Newest"
            case .mostPlayed: return "Most played"
            case .performer(let o), .studio(let o), .tag(let o): return o.name
            }
        }

        var icon: String {
            switch self {
            case .random: return "shuffle"
            case .newest: return "sparkles"
            case .mostPlayed: return "play.circle"
            case .performer: return "person.fill"
            case .studio: return "building.2.fill"
            case .tag: return "tag.fill"
            }
        }
    }

    /// One rated item of the running round, kept for the summary.
    struct RatedEntry: Identifiable {
        let item: Item
        let rating100: Int
        var id: String { item.id }
        var stars: Int { min(5, max(1, Int((Double(rating100) / 20).rounded()))) }
    }

    struct Session {
        var rated: [RatedEntry] = []
        var skipped = 0

        /// Highest rating of the round; the first one wins a tie.
        var topPick: RatedEntry? {
            rated.max { lhs, rhs in lhs.rating100 < rhs.rating100 }
        }

        func count(stars: Int) -> Int { rated.filter { $0.stars == stars }.count }
    }

    static let sessionLengthOptions = [10, 20, 50]

    private static let modeDefaultsKey = "stashy.rateMe.mode"
    private static let imageMediaKindDefaultsKey = "stashy.rateMe.imageMediaKind"
    private static let sessionLengthDefaultsKey = "stashy.rateMe.sessionLength"
    private static let dayDefaultsKey = "stashy.rateMe.lastDay"
    private static let todayCountDefaultsKey = "stashy.rateMe.todayCount"
    private static let streakDefaultsKey = "stashy.rateMe.streak"
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
    @Published var errorMessage: String?
    @Published var remainingHint: Int?

    @Published var theme: Theme = .random
    @Published var sessionLength: Int = 10 {
        didSet { UserDefaults.standard.set(sessionLength, forKey: Self.sessionLengthDefaultsKey) }
    }
    @Published private(set) var session = Session()
    /// Round finished (or the theme ran dry mid-round): the summary replaces the card.
    @Published var showsSummary = false
    /// Everything in the current theme, rated or not — the denominator of the progress readout.
    @Published private(set) var scopeTotal: Int?
    @Published private(set) var ratedToday = 0
    @Published private(set) var streakDays = 0

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
        let storedLength = UserDefaults.standard.integer(forKey: Self.sessionLengthDefaultsKey)
        sessionLength = Self.sessionLengthOptions.contains(storedLength) ? storedLength : 10
        refreshDailyStats()
    }

    /// Themes that make sense for the current mode — images have no play count.
    var availableFixedThemes: [Theme] {
        mode == .scenes ? [.random, .newest, .mostPlayed] : [.random, .newest]
    }

    /// Fresh round on the current theme: counters reset, progress denominator refetched.
    func startNewSession() async {
        session = Session()
        showsSummary = false
        if mode == .images, theme == .mostPlayed { theme = .random }
        async let total: Void = refreshScopeTotal()
        await loadNext(resetSkip: true)
        await total
        #if DEBUG
        // `-stashyDebugRateMeSummary YES`: a filled round on the loaded item, nothing written to
        // the server — for checking the summary layout without rating ten real scenes.
        if UserDefaults.standard.bool(forKey: "stashyDebugRateMeSummary"), let current = item {
            session.rated = [100, 80, 80, 40, 60].map { RatedEntry(item: current, rating100: $0) }
            session.skipped = 3
            showsSummary = true
        }
        #endif
    }

    func selectTheme(_ newTheme: Theme) async {
        guard newTheme != theme else { return }
        theme = newTheme
        await startNewSession()
    }

    /// Share of the theme that carries a rating, 0…1.
    var ratedShare: Double? {
        guard let total = scopeTotal, total > 0, let remaining = remainingHint else { return nil }
        return min(1, max(0, Double(total - remaining) / Double(total)))
    }

    // MARK: Daily stats

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func refreshDailyStats() {
        let defaults = UserDefaults.standard
        let today = Self.dayString(Date())
        let yesterday = Self.dayString(Date().addingTimeInterval(-86_400))
        let last = defaults.string(forKey: Self.dayDefaultsKey)
        ratedToday = last == today ? defaults.integer(forKey: Self.todayCountDefaultsKey) : 0
        // A streak survives today until the first rating; it is gone once a whole day is missed.
        streakDays = (last == today || last == yesterday) ? defaults.integer(forKey: Self.streakDefaultsKey) : 0
    }

    private func recordDailyRating() {
        let defaults = UserDefaults.standard
        let today = Self.dayString(Date())
        let yesterday = Self.dayString(Date().addingTimeInterval(-86_400))
        let last = defaults.string(forKey: Self.dayDefaultsKey)
        var count = defaults.integer(forKey: Self.todayCountDefaultsKey)
        var streak = defaults.integer(forKey: Self.streakDefaultsKey)
        if last == today {
            count += 1
        } else {
            count = 1
            streak = last == yesterday ? streak + 1 : 1
        }
        defaults.set(today, forKey: Self.dayDefaultsKey)
        defaults.set(count, forKey: Self.todayCountDefaultsKey)
        defaults.set(streak, forKey: Self.streakDefaultsKey)
        ratedToday = count
        streakDays = streak
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
                errorMessage = "No unrated \(mode.label.lowercased()) left in \(theme.label)."
                if !session.rated.isEmpty { showsSummary = true }
            }
        } catch {
            item = nil
            errorMessage = error.localizedDescription
        }
    }

    func skip() async {
        if let id = item?.id {
            skipIDs.insert(id)
            session.skipped += 1
        }
        await loadNext()
    }

    /// `holdsSelection`: the star row keeps the picked stars on screen for a moment; a swipe has
    /// already thrown the card away, so it advances immediately.
    func submitRating(_ rating100: Int?, holdsSelection: Bool = true) async {
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
            if let rating100 {
                session.rated.append(RatedEntry(item: current, rating100: rating100))
                recordDailyRating()
                if let remaining = remainingHint { remainingHint = max(0, remaining - 1) }
            }
            // Keep the selected stars visible briefly before advancing.
            if holdsSelection {
                try? await Task.sleep(nanoseconds: Self.ratingHoldNanoseconds)
            }
            skipIDs.remove(current.id)
            if session.rated.count >= sessionLength {
                HapticManager.success()
                showsSummary = true
                return
            }
            await loadNext()
        } catch {
            errorMessage = error.localizedDescription
            draftRating100 = nil
        }
    }

    // MARK: Fetch

    /// `IntCriterionInput.value` is required by GraphQL even for IS_NULL (Stash ignores it in SQL).
    private var unratedFilter: [String: Any] {
        var filter = themeCriteria
        filter["rating100"] = ["modifier": "IS_NULL", "value": 0]
        return filter
    }

    private var unratedImageFilter: [String: Any] {
        var filter = unratedFilter
        if let path = imageMediaKind.pathCriterion {
            filter["path"] = path
        }
        return filter
    }

    /// The theme's narrowing, merged into the unrated / media-kind criteria.
    private var themeCriteria: [String: Any] {
        switch theme {
        case .random, .newest, .mostPlayed:
            return [:]
        case .performer(let o):
            return ["performers": ["value": [o.id], "modifier": "INCLUDES"]]
        case .studio(let o):
            return ["studios": ["value": [o.id], "modifier": "INCLUDES", "depth": 0]]
        case .tag(let o):
            return ["tags": ["value": [o.id], "modifier": "INCLUDES", "depth": 0]]
        }
    }

    /// Stash expects `random_<seed>` (not bare `random`). A page of 20, not 1: with a fixed sort
    /// (Newest, Most played) the first row is the same every time, so skipped items have to be
    /// stepped over inside the page.
    private var pageFilter: [String: Any] {
        let sort: (String, String)
        switch theme {
        case .newest: sort = ("created_at", "DESC")
        case .mostPlayed: sort = ("play_count", "DESC")
        default: sort = ("random_\(Int.random(in: 0...99_999_999))", "ASC")
        }
        return ["per_page": 20, "sort": sort.0, "direction": sort.1]
    }

    private func refreshScopeTotal() async {
        var criteria = themeCriteria
        do {
            switch mode {
            case .scenes:
                let query = GraphQLQueries.loadQuery(named: "findScenesCompact")
                let res: RateMeSceneFindResponse = try await client.execute(
                    query: query,
                    variables: ["filter": ["per_page": 1], "scene_filter": criteria]
                )
                scopeTotal = res.data?.findScenes.count
            case .images:
                if let path = imageMediaKind.pathCriterion { criteria["path"] = path }
                let query = GraphQLQueries.queryWithFragments("findImages")
                let res: RateMeImageFindResponse = try await client.execute(
                    query: query,
                    variables: ["filter": ["per_page": 1], "image_filter": criteria]
                )
                scopeTotal = res.data?.findImages.count
            }
        } catch {
            scopeTotal = nil
        }
    }

    private func fetchUnratedScene() async throws -> Item? {
        let query = GraphQLQueries.loadQuery(named: "findScenesCompact")
        for _ in 0..<4 {
            let variables: [String: Any] = [
                "filter": pageFilter,
                "scene_filter": unratedFilter
            ]
            let res: RateMeSceneFindResponse = try await client.execute(query: query, variables: variables)
            remainingHint = res.data?.findScenes.count
            let page = res.data?.findScenes.scenes ?? []
            guard !page.isEmpty else { return nil }
            guard let scene = page.first(where: { !skipIDs.contains($0.id) }) else {
                // Everything on this page was skipped. A fixed sort would return it again.
                if theme == .newest || theme == .mostPlayed { skipIDs.removeAll() }
                continue
            }
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
        for _ in 0..<4 {
            let variables: [String: Any] = [
                "filter": pageFilter,
                "image_filter": unratedImageFilter
            ]
            let res: RateMeImageFindResponse = try await client.execute(query: query, variables: variables)
            remainingHint = res.data?.findImages.count
            let page = res.data?.findImages.images ?? []
            guard !page.isEmpty else { return nil }
            guard let image = page.first(where: { !skipIDs.contains($0.id) }) else {
                if theme == .newest { skipIDs.removeAll() }
                continue
            }

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
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Media

private struct RateMeMediaView: View {
    let item: RateMeViewModel.Item

    @StateObject private var previewPlayer = AetherPreviewPlayer()
    @State private var isPreviewing = false
    @State private var autoplayTask: Task<Void, Never>?

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

            if isPreviewing {
                // Fit: the media box already carries the item's aspect ratio.
                AetherPreviewSurface(player: previewPlayer, fill: false)
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
        // The preview player loops on its own (`loopsAtEnd`).
        previewPlayer.start(url: url)
        withAnimation(.easeIn(duration: 0.2)) {
            isPreviewing = true
        }
    }

    private func stopPreview(releasePlayer: Bool) {
        autoplayTask?.cancel()
        autoplayTask = nil
        isPreviewing = false
        previewPlayer.stop(release: releasePlayer)
    }
}

// MARK: - UI

struct RateMeToolsView: View {
    @StateObject private var model = RateMeViewModel()
    @ObservedObject private var appearance = AppearanceManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Avoids reloading when returning from `NavigationLink` (Watch Scene): `.task` restarts after disappear/reappear.
    @State private var didRunInitialRateMeLoad = false
    /// Swipe card state: the drag offset, and the intent last announced with a haptic tick.
    @State private var dragOffset: CGSize = .zero
    @State private var announcedIntent: SwipeIntent?
    @State private var themePicker: ThemePickerKind?
    /// The swipe legend under the card stays until the gestures have been used a few times.
    @AppStorage("stashy.rateMe.swipesDone") private var swipesDone = 0

    enum ThemePickerKind: String, Identifiable {
        case performer, studio, tag
        var id: String { rawValue }
        var title: String {
            switch self {
            case .performer: return "Performer"
            case .studio: return "Studio"
            case .tag: return "Tag"
            }
        }
        var icon: String {
            switch self {
            case .performer: return "person.fill"
            case .studio: return "building.2.fill"
            case .tag: return "tag.fill"
            }
        }
    }

    /// Right 5 ★ (the "like"), up 4 ★, left 2 ★, down skip — the only way to rate here.
    enum SwipeIntent: Equatable {
        case five, four, two, skip

        static let commitDistance: CGFloat = 110

        init?(translation t: CGSize, minimum: CGFloat) {
            guard max(abs(t.width), abs(t.height)) >= minimum else { return nil }
            if abs(t.width) > abs(t.height) {
                self = t.width > 0 ? .five : .two
            } else {
                self = t.height < 0 ? .four : .skip
            }
        }

        var rating100: Int? {
            switch self {
            case .five: return 100
            case .four: return 80
            case .two: return 40
            case .skip: return nil
            }
        }

        var title: String {
            switch self {
            case .five: return "★★★★★"
            case .four: return "★★★★"
            case .two: return "★★"
            case .skip: return "Skip"
            }
        }

        var color: Color {
            switch self {
            case .five: return .yellow
            case .four: return .green
            case .two: return .orange
            case .skip: return .gray
            }
        }

        /// Where the card flies when the swipe commits.
        var flyOut: CGSize {
            switch self {
            case .five: return CGSize(width: 700, height: 0)
            case .four: return CGSize(width: 0, height: -900)
            case .two: return CGSize(width: -700, height: 0)
            case .skip: return CGSize(width: 0, height: 900)
            }
        }
    }

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

            // Pills as wide as their text, not stretched to equal widths.
            HStack(spacing: 8) {
                ForEach(RateMeViewModel.Mode.allCases) { mode in
                    themeChip(title: mode.label, icon: mode.emptyIcon, selected: model.mode == mode) {
                        model.mode = mode
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Tools.contentPadding)
            .padding(.vertical, 8)
            .disabled(model.isSubmitting)

            themeChips
                .padding(.bottom, 8)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .onAppear {
            guard !didRunInitialRateMeLoad else { return }
            didRunInitialRateMeLoad = true
            Task { await model.startNewSession() }
        }
        .onChange(of: model.mode) { _, _ in
            Task { await model.startNewSession() }
        }
        .onChange(of: model.imageMediaKind) { _, _ in
            guard model.mode == .images else { return }
            Task { await model.startNewSession() }
        }
        // A failed save must not leave the card thrown off screen.
        .onChange(of: model.errorMessage) { _, message in
            if message != nil { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragOffset = .zero } }
        }
        .sheet(item: $themePicker) { kind in
            RateMeThemePickerSheet(kind: kind, mode: model.mode) { option in
                themePicker = nil
                let theme: RateMeViewModel.Theme
                switch kind {
                case .performer: theme = .performer(option)
                case .studio: theme = .studio(option)
                case .tag: theme = .tag(option)
                }
                Task { await model.selectTheme(theme) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 12) {
            if model.mode == .images {
                imageMediaKindChrome
            }

            if model.showsSummary {
                ScrollView {
                    summaryView
                        .frame(maxWidth: isRegular ? 720 : .infinity)
                        .frame(maxWidth: .infinity)
                }
            } else if model.isLoading && model.item == nil {
                StandardLoadingView(message: "Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let item = model.item {
                sessionBar

                swipeCard(item)
                    .layoutPriority(1)
                    .frame(maxWidth: isRegular ? 720 : .infinity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if swipesDone < 5 { swipeLegend }

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

    // MARK: Themes

    private var themeChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.availableFixedThemes) { theme in
                        themeChip(title: theme.label, icon: theme.icon, selected: model.theme == theme) {
                            Task { await model.selectTheme(theme) }
                        }
                        .id(theme.id)
                    }
                    ForEach([ThemePickerKind.performer, .studio, .tag]) { kind in
                        let picked = pickedTheme(for: kind)
                        themeChip(title: picked?.label ?? "\(kind.title)…", icon: kind.icon, selected: picked != nil) {
                            themePicker = kind
                        }
                        .id(kind.rawValue)
                    }
                }
                .padding(.horizontal, DesignTokens.Tools.contentPadding)
            }
            // A picked performer / studio / tag sits at the far end; bring its chip into view.
            .onChange(of: model.theme) { _, theme in
                let target: String
                switch theme {
                case .performer: target = ThemePickerKind.performer.rawValue
                case .studio: target = ThemePickerKind.studio.rawValue
                case .tag: target = ThemePickerKind.tag.rawValue
                default: target = theme.id
                }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
            }
        }
        .disabled(model.isSubmitting)
    }

    private func pickedTheme(for kind: ThemePickerKind) -> RateMeViewModel.Theme? {
        switch (kind, model.theme) {
        case (.performer, .performer), (.studio, .studio), (.tag, .tag): return model.theme
        default: return nil
        }
    }

    private func themeChip(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule(style: .continuous).fill(selected ? appearance.tintColor : Color.secondaryAppBackground))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Session

    private var sessionBar: some View {
        HStack(spacing: 10) {
            Text("\(model.session.rated.count)/\(model.sessionLength)")
                .font(.caption.weight(.bold).monospacedDigit())
            ProgressView(value: Double(model.session.rated.count), total: Double(model.sessionLength))
                .tint(appearance.tintColor)
            if model.streakDays > 1 {
                Label("\(model.streakDays)", systemImage: "flame.fill")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .accessibilityLabel("\(model.streakDays) day streak")
            }
            Menu {
                Picker("Round", selection: $model.sessionLength) {
                    ForEach(RateMeViewModel.sessionLengthOptions, id: \.self) { n in
                        Text("\(n) per round").tag(n)
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 24)
            }
            .accessibilityLabel("Round length")
        }
        .frame(maxWidth: isRegular ? 720 : .infinity)
    }

    private var summaryView: some View {
        let session = model.session
        let maxBucket = max(1, (1...5).map { session.count(stars: $0) }.max() ?? 1)
        return VStack(spacing: 14) {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(appearance.tintColor)
                Text(model.item == nil ? "\(model.theme.label) done" : "Round complete")
                    .font(.title2.weight(.bold))
                Text(model.theme.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            HStack(spacing: 10) {
                summaryTile(value: "\(session.rated.count)", label: "Rated", icon: "star.fill")
                summaryTile(value: "\(session.skipped)", label: "Skipped", icon: "forward.fill")
            }

            VStack(spacing: 6) {
                ForEach((1...5).reversed(), id: \.self) { stars in
                    let count = session.count(stars: stars)
                    HStack(spacing: 8) {
                        Text(String(repeating: "★", count: stars))
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .frame(width: 70, alignment: .leading)
                        GeometryReader { geo in
                            Capsule()
                                .fill(appearance.tintColor.opacity(count == 0 ? 0.15 : 0.85))
                                .frame(width: max(6, geo.size.width * CGFloat(count) / CGFloat(maxBucket)))
                        }
                        .frame(height: 10)
                        Text("\(count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }
            .padding(12)
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))

            if let top = session.topPick {
                HStack(spacing: 12) {
                    CustomAsyncImage(url: top.item.thumbnailURL) { loader in
                        if let image = loader.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.black.opacity(0.1)
                        }
                    }
                    .frame(width: 96, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Top pick")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(top.item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text(String(repeating: "★", count: top.stars))
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.secondaryAppBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            }

            VStack(alignment: .leading, spacing: 8) {
                if let share = model.ratedShare {
                    HStack {
                        Text("\(Int((share * 100).rounded())) % of \(progressScopeLabel) rated")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    ProgressView(value: share)
                        .tint(appearance.tintColor)
                }
                HStack(spacing: 16) {
                    Label("\(model.ratedToday) today", systemImage: "calendar")
                    if model.streakDays > 0 {
                        Label("\(model.streakDays) day streak", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))

            if model.item != nil || model.errorMessage == nil {
                Button {
                    HapticManager.light()
                    Task { await model.startNewSession() }
                } label: {
                    Label("Next round", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.tintColor)
            }
            Text("Or pick another theme above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
    }

    /// "all scenes" for the unscoped themes (the whole library is the denominator), the name for
    /// a performer / studio / tag.
    private var progressScopeLabel: String {
        switch model.theme {
        case .random, .newest, .mostPlayed: return "all \(model.mode.label.lowercased())"
        case .performer(let o), .studio(let o), .tag(let o): return o.name
        }
    }

    private func summaryTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(appearance.tintColor)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    // MARK: Swipe

    private var swipeLegend: some View {
        HStack(spacing: 12) {
            legendItem("arrow.right", "5★")
            legendItem("arrow.up", "4★")
            legendItem("arrow.left", "2★")
            legendItem("arrow.down", "Skip")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private func legendItem(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
    }

    private func swipeCard(_ item: RateMeViewModel.Item) -> some View {
        let live = SwipeIntent(translation: dragOffset, minimum: 36)
        let committed = SwipeIntent(translation: dragOffset, minimum: SwipeIntent.commitDistance)
        return mediaCard(item)
            .overlay {
                if let live {
                    Text(live.title)
                        .font(.system(size: live == .skip ? 30 : 34, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(live.color.opacity(committed == nil ? 0.55 : 0.9)))
                        .scaleEffect(committed == nil ? 0.9 : 1.05)
                        .allowsHitTesting(false)
                }
            }
            .offset(dragOffset)
            .rotationEffect(.degrees(Double(dragOffset.width / 22)))
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard !model.isSubmitting, !model.isLoading else { return }
                        dragOffset = value.translation
                        let intent = SwipeIntent(translation: value.translation, minimum: SwipeIntent.commitDistance)
                        if intent != announcedIntent {
                            if intent != nil { HapticManager.selection() }
                            announcedIntent = intent
                        }
                    }
                    .onEnded { value in
                        announcedIntent = nil
                        // A quick flick counts even if the finger stopped short of the line.
                        let reach = CGSize(
                            width: value.translation.width + (value.predictedEndTranslation.width - value.translation.width) * 0.35,
                            height: value.translation.height + (value.predictedEndTranslation.height - value.translation.height) * 0.35
                        )
                        guard !model.isSubmitting, !model.isLoading,
                              let intent = SwipeIntent(translation: reach, minimum: SwipeIntent.commitDistance) else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragOffset = .zero }
                            return
                        }
                        commitSwipe(intent)
                    }
            )
            .onChange(of: item.id) { _, _ in
                // New card: back in the middle, without animating in from where the last one flew.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { dragOffset = .zero }
            }
    }

    private func commitSwipe(_ intent: SwipeIntent) {
        swipesDone += 1
        if intent == .five { HapticManager.success() } else { HapticManager.medium() }
        withAnimation(.easeIn(duration: 0.2)) { dragOffset = intent.flyOut }
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let rating = intent.rating100 {
                await model.submitRating(rating, holdsSelection: false)
            } else {
                await model.skip()
            }
        }
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
            interactive: nil
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

    private var imageMediaKindChrome: some View {
        HStack(spacing: 8) {
            ForEach(ImageListMediaKind.allCases) { kind in
                imageMediaKindChip(kind)
            }
            Spacer(minLength: 0)
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
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
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

// MARK: - Theme picker

/// Performer / studio / tag for a RateMe theme, from the shared filter picker store (most used
/// first, name search for the long tail).
private struct RateMeThemePickerSheet: View {
    let kind: RateMeToolsView.ThemePickerKind
    let mode: RateMeViewModel.Mode
    let onPick: (FilterEntityOption) -> Void

    @ObservedObject private var store = FilterPickerOptionsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var storeKind: FilterPickerOptionsStore.Kind {
        switch (kind, mode) {
        case (.performer, _): return .performers
        case (.studio, .scenes): return .studios
        case (.studio, .images): return .imageStudios
        case (.tag, .scenes): return .tags
        case (.tag, .images): return .imageTags
        }
    }

    private var options: [FilterEntityOption] {
        let all = store.availableOptions(storeKind)
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(term) }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.isLoading(storeKind) && options.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                }
                ForEach(options) { option in
                    Button {
                        HapticManager.selection()
                        onPick(option)
                    } label: {
                        Text(option.name)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if store.isSearching(storeKind) {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                }
            }
            .searchable(text: $query, prompt: "Search \(kind.title.lowercased())s")
            .onChange(of: query) { _, newValue in
                store.search(storeKind, query: newValue)
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { store.load(storeKind) }
        }
        .presentationDetents([.medium, .large])
    }
}

#endif
