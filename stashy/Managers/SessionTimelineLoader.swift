//
//  SessionTimelineLoader.swift
//  stashy
//
//  Rebuilds watch sessions from Stash `play_history` + `o_history`, one 24h window at a time.
//

#if !os(tvOS)
import Combine
import Foundation

struct TimelineSceneSnapshot: Equatable {
    let id: String
    let title: String
    let thumbnailPath: String?
    let duration: Double?
    let resumeTime: Double?
    let studio: SceneStudio?
    let tags: [Tag]
    let performers: [ScenePerformer]
    let rating100: Int?

    func withRating(_ rating100: Int?) -> TimelineSceneSnapshot {
        TimelineSceneSnapshot(
            id: id,
            title: title,
            thumbnailPath: thumbnailPath,
            duration: duration,
            resumeTime: resumeTime,
            studio: studio,
            tags: tags,
            performers: performers,
            rating100: rating100
        )
    }

    var displayTitle: String {
        if title != "Untitled", !title.isEmpty { return title }
        let names = performers.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? title : names.joined(separator: ", ")
    }

    var thumbnailURL: URL? { asScene.thumbnailURL }

    var asScene: Scene {
        Scene(
            id: id,
            title: title,
            details: nil,
            date: nil,
            duration: duration,
            studio: studio,
            performers: performers,
            files: nil,
            tags: tags.isEmpty ? nil : tags,
            galleries: nil,
            organized: nil,
            resumeTime: resumeTime,
            playCount: nil,
            oCounter: nil,
            rating100: rating100,
            createdAt: nil,
            updatedAt: nil,
            paths: ScenePaths(
                screenshot: thumbnailPath,
                preview: nil,
                stream: nil,
                webp: nil,
                vtt: nil,
                sprite: nil,
                funscript: nil,
                interactive_heatmap: nil,
                caption: nil
            ),
            sceneMarkers: nil,
            interactive: nil
        )
    }
}

enum TimelineVisitMedia: Equatable {
    case scene(TimelineSceneSnapshot)
    case image(OCountHeatmapItem)

    var displayTitle: String {
        switch self {
        case .scene(let scene): return scene.displayTitle
        case .image(let item): return item.displayTitle
        }
    }

    var subtitle: String? {
        switch self {
        case .scene(let scene):
            let name = scene.studio?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? nil : name
        case .image(let item):
            return item.rowSubtitle
        }
    }

    var thumbnailURL: URL? {
        switch self {
        case .scene(let scene): return scene.thumbnailURL
        case .image(let item): return item.thumbnailURL
        }
    }

    /// Width ÷ height. Scenes stay 16:9; images use the file’s pixel size.
    var thumbnailAspectRatio: CGFloat {
        switch self {
        case .scene:
            return 16.0 / 9.0
        case .image(let item):
            if let size = item.asImage.pixelSize, size.height > 0 {
                return size.width / size.height
            }
            return item.asImage.isVideo ? (16.0 / 9.0) : 1
        }
    }

    var placeholderSystemImage: String {
        switch self {
        case .scene: return "film"
        case .image(let item): return item.placeholderSystemImage
        }
    }

    var rating100: Int? {
        switch self {
        case .scene(let scene): return scene.rating100
        case .image(let item): return item.rating100
        }
    }

    func withRating(_ rating100: Int?) -> TimelineVisitMedia {
        switch self {
        case .scene(let scene): return .scene(scene.withRating(rating100))
        case .image(let item): return .image(item.withRating(rating100))
        }
    }

    var asHeatmapItem: OCountHeatmapItem {
        switch self {
        case .scene(let scene):
            return OCountHeatmapItem(
                kind: .scene,
                stashID: scene.id,
                title: scene.title,
                thumbnailPath: scene.thumbnailPath,
                previewPath: nil,
                imagePath: nil,
                visualFiles: nil,
                performers: scene.performers.map {
                    GalleryPerformer(id: $0.id, name: $0.name, image_path: nil)
                },
                studio: scene.studio,
                rating100: scene.rating100,
                countOnDay: 1
            )
        case .image(let item):
            return item
        }
    }
}

struct TimelineVisit: Identifiable, Equatable {
    let id: String
    let media: TimelineVisitMedia
    let startedAt: Date
    let watchedSeconds: TimeInterval
    let sceneStartSeconds: TimeInterval?
    let oCountTimes: [Date]
    let isPlayback: Bool
    /// Set when this visit is a rating action (Stash has no rating history).
    var ratingAction: Int? = nil

    var oCount: Int { oCountTimes.count }
    var isRatingAction: Bool { ratingAction != nil }
    /// Image O-counts and ratings are stored on-device; Stash has no history for them.
    var isLocal: Bool {
        if isRatingAction { return true }
        if !isPlayback, case .image = media { return true }
        return false
    }
    var scene: TimelineSceneSnapshot? {
        if case .scene(let scene) = media { return scene }
        return nil
    }
}

/// In-scene playhead when Stashy recorded a play. Stash `play_history` is wall-clock only.
enum TimelinePlayStartStore {
    private struct Entry: Codable {
        let sceneId: String
        let playedAt: TimeInterval
        let startSeconds: Double
    }

    static func record(sceneId: String, startSeconds: Double, at date: Date = Date()) {
        guard startSeconds.isFinite, startSeconds >= 0 else { return }
        var entries = load()
        entries.append(Entry(sceneId: sceneId, playedAt: date.timeIntervalSince1970, startSeconds: startSeconds))
        let cutoff = Date().addingTimeInterval(-SessionTimelineLoader.maxLookbackSeconds).timeIntervalSince1970
        entries.removeAll { $0.playedAt < cutoff }
        save(entries)
    }

    static func startSeconds(sceneId: String, playedAt: Date) -> Double? {
        let target = playedAt.timeIntervalSince1970
        let match = load()
            .filter { $0.sceneId == sceneId }
            .min { abs($0.playedAt - target) < abs($1.playedAt - target) }
        guard let match, abs(match.playedAt - target) <= 120 else { return nil }
        return match.startSeconds
    }

    private static func defaultsKey() -> String {
        let id = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
        return "stashy_timeline_play_starts_\(id)"
    }

    private static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey()) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func save(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey())
    }
}

/// Local rating actions. Stash has no rating history.
enum TimelineRatingActionStore {
    struct Entry: Codable {
        let kind: String
        let stashID: String
        let at: TimeInterval
        let rating100: Int
        var title: String?
        var thumbnailPath: String?

        var itemKind: OCountHeatmapItem.Kind { kind == "image" ? .image : .scene }

        var date: Date { Date(timeIntervalSince1970: at) }
    }

    static func record(
        kind: OCountHeatmapItem.Kind,
        stashID: String,
        rating100: Int,
        at date: Date = Date(),
        title: String? = nil,
        thumbnailPath: String? = nil
    ) {
        guard !stashID.isEmpty, rating100 > 0 else { return }
        var entries = load()
        entries.append(
            Entry(
                kind: kind == .image ? "image" : "scene",
                stashID: stashID,
                at: date.timeIntervalSince1970,
                rating100: rating100,
                title: title,
                thumbnailPath: thumbnailPath
            )
        )
        let cutoff = Date().addingTimeInterval(-SessionTimelineLoader.maxLookbackSeconds).timeIntervalSince1970
        entries.removeAll { $0.at < cutoff }
        save(entries)
    }

    static func events(in range: Range<Date>) -> [Entry] {
        all().filter { range.contains($0.date) }
    }

    static func all() -> [Entry] {
        let cutoff = Date().addingTimeInterval(-SessionTimelineLoader.maxLookbackSeconds).timeIntervalSince1970
        return load().filter { $0.at >= cutoff }
    }

    private static func defaultsKey() -> String {
        let id = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
        return "stashy_timeline_rating_actions_\(id)"
    }

    private static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey()) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func save(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey())
    }
}

struct TimelineSession: Identifiable, Equatable {
    let id: String
    let startedAt: Date
    let endedAt: Date
    let visits: [TimelineVisit]

    var sceneCount: Int {
        visits.reduce(0) { count, visit in
            if case .scene = visit.media { return count + 1 }
            return count
        }
    }
    var oCount: Int { visits.reduce(0) { $0 + $1.oCount } }
    var ratingCount: Int { visits.reduce(0) { $0 + ($1.isRatingAction ? 1 : 0) } }
    var watchedSeconds: TimeInterval { visits.reduce(0) { $0 + $1.watchedSeconds } }
    var sessionSeconds: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

@MainActor
final class SessionTimelineLoader: ObservableObject {
    static let shared = SessionTimelineLoader()

    static let windowSeconds: TimeInterval = 24 * 60 * 60
    static let maxLookbackSeconds: TimeInterval = 90 * 24 * 60 * 60
    static let sessionGapSeconds: TimeInterval = 30 * 60

    @Published private(set) var sessions: [TimelineSession] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var didFail = false
    @Published private(set) var hasMore = true
    @Published private(set) var loadedWindowStart: Date?

    private var loadedServerID: UUID?
    private var nextWindowEnd: Date?
    private var consecutiveEmptyWindows = 0
    private var fetchGeneration = 0

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reset()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ScenePlayAdded"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.reload()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SceneOCounterUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await Task.yield()
                self?.ingestOCounts()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ImageOCounterUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await Task.yield()
                self?.ingestOCounts()
                try? await Task.sleep(nanoseconds: 400_000_000)
                self?.ingestOCounts()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SceneRatingUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let sceneId = notification.userInfo?["sceneId"] as? String else { return }
            let rating = notification.userInfo?["rating100"] as? Int
            Task { @MainActor in
                self?.applyLiveRatingAction(
                    kind: .scene,
                    stashID: sceneId,
                    rating100: rating,
                    title: notification.userInfo?["title"] as? String,
                    thumbnailPath: notification.userInfo?["thumbnailPath"] as? String
                )
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ImageRatingUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let imageId = notification.userInfo?["imageId"] as? String else { return }
            let rating = notification.userInfo?["rating100"] as? Int
            Task { @MainActor in
                self?.applyLiveRatingAction(
                    kind: .image,
                    stashID: imageId,
                    rating100: rating,
                    title: notification.userInfo?["title"] as? String,
                    thumbnailPath: notification.userInfo?["thumbnailPath"] as? String
                )
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ImageOCountHydrated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let imageId = notification.userInfo?["imageId"] as? String else { return }
            Task { @MainActor in
                self?.applyLiveImageMetadata(imageId: imageId)
            }
        }
    }

    func loadIfNeeded() async {
        let serverID = ServerConfigManager.shared.activeConfig?.id
        if loadedServerID != serverID {
            reset()
        }
        guard sessions.isEmpty, !isLoading else { return }
        await reload()
    }

    func reload(refreshOCounts: Bool = false) async {
        fetchGeneration += 1
        let generation = fetchGeneration
        loadedServerID = ServerConfigManager.shared.activeConfig?.id
        isLoading = true
        isLoadingMore = false
        didFail = false
        hasMore = true
        consecutiveEmptyWindows = 0
        nextWindowEnd = Date()
        loadedWindowStart = nil

        // Unstructured so SwiftUI cancelling `.refreshable` does not abort the fetch.
        let work = Task { @MainActor in
            await self.loadNextWindow(
                isInitial: true,
                generation: generation,
                refreshOCounts: refreshOCounts
            )
            guard generation == self.fetchGeneration else { return }
            self.isLoading = false
        }

        while isLoading, fetchGeneration == generation, !work.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if Task.isCancelled { break }
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        let generation = fetchGeneration
        isLoadingMore = true
        let before = sessions.count
        while hasMore, sessions.count == before, generation == fetchGeneration {
            await loadNextWindow(isInitial: false, generation: generation)
        }
        guard generation == fetchGeneration else { return }
        isLoadingMore = false
    }

    func reset() {
        fetchGeneration += 1
        sessions = []
        isLoading = false
        isLoadingMore = false
        didFail = false
        hasMore = true
        loadedWindowStart = nil
        nextWindowEnd = nil
        loadedServerID = nil
        consecutiveEmptyWindows = 0
    }

    private func ingestOCounts() {
        let end = Date().addingTimeInterval(120)
        let start = Date().addingTimeInterval(-Self.maxLookbackSeconds)
        var visits = sessions.flatMap(\.visits)
        var snapshots: [String: TimelineSceneSnapshot] = [:]
        for visit in visits {
            if let scene = visit.scene { snapshots[scene.id] = scene }
        }
        Self.mergeCalendarOCounts(
            OCountHeatmapLoader.shared.events(in: start..<end, actionsOnly: true),
            into: &visits,
            snapshots: snapshots
        )
        Self.mergeRatingActions(
            TimelineRatingActionStore.events(in: start..<end),
            into: &visits,
            snapshots: snapshots
        )
        sessions = Self.groupedSessions(from: visits)
    }

    private func applyLiveRatingAction(
        kind: OCountHeatmapItem.Kind,
        stashID: String,
        rating100: Int?,
        title: String? = nil,
        thumbnailPath: String? = nil
    ) {
        guard let rating100, rating100 > 0 else { return }
        let media = mediaForRating(
            kind: kind,
            stashID: stashID,
            title: title,
            thumbnailPath: thumbnailPath
        )
        TimelineRatingActionStore.record(
            kind: kind,
            stashID: stashID,
            rating100: rating100,
            title: media.displayTitle == "Untitled" ? title : media.displayTitle,
            thumbnailPath: thumbnailPath ?? {
                switch media {
                case .scene(let scene): return scene.thumbnailPath
                case .image(let item): return item.thumbnailPath ?? item.previewPath ?? item.imagePath
                }
            }()
        )
        ingestOCounts()
        if case .image(let item) = media, item.isPlaceholder {
            Task { await OCountHeatmapLoader.shared.hydrateImageIfNeeded(stashID) }
        }
    }

    private func mediaForRating(
        kind: OCountHeatmapItem.Kind,
        stashID: String,
        title: String?,
        thumbnailPath: String?
    ) -> TimelineVisitMedia {
        for visit in sessions.flatMap(\.visits) {
            switch (kind, visit.media) {
            case (.scene, .scene(let scene)) where scene.id == stashID:
                return visit.media
            case (.image, .image(let item)) where item.stashID == stashID && !item.isPlaceholder:
                return visit.media
            default:
                break
            }
        }
        if kind == .image, let item = OCountHeatmapLoader.shared.imageItem(stashID: stashID) {
            return .image(item)
        }
        let resolvedTitle = {
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Untitled" : trimmed
        }()
        switch kind {
        case .scene:
            return .scene(
                TimelineSceneSnapshot(
                    id: stashID,
                    title: resolvedTitle,
                    thumbnailPath: thumbnailPath,
                    duration: nil,
                    resumeTime: nil,
                    studio: nil,
                    tags: [],
                    performers: [],
                    rating100: nil
                )
            )
        case .image:
            if resolvedTitle != "Untitled" || thumbnailPath != nil {
                return .image(
                    OCountHeatmapItem(
                        kind: .image,
                        stashID: stashID,
                        title: resolvedTitle,
                        thumbnailPath: thumbnailPath,
                        previewPath: nil,
                        imagePath: nil,
                        visualFiles: nil,
                        performers: [],
                        studio: nil,
                        rating100: nil,
                        countOnDay: 1
                    )
                )
            }
            return .image(OCountHeatmapItem.stub(kind: .image, stashID: stashID))
        }
    }

    private func applyLiveImageMetadata(imageId: String) {
        guard let item = OCountHeatmapLoader.shared.imageItem(stashID: imageId) else { return }
        var visits = sessions.flatMap(\.visits)
        var changed = false
        for index in visits.indices {
            guard case .image(let current) = visits[index].media, current.stashID == imageId else { continue }
            guard current.isPlaceholder || current.thumbnailURL == nil || current.title == "Untitled" else { continue }
            let existing = visits[index]
            visits[index] = TimelineVisit(
                id: existing.id,
                media: .image(item),
                startedAt: existing.startedAt,
                watchedSeconds: existing.watchedSeconds,
                sceneStartSeconds: existing.sceneStartSeconds,
                oCountTimes: existing.oCountTimes,
                isPlayback: existing.isPlayback,
                ratingAction: existing.ratingAction
            )
            changed = true
        }
        if changed {
            sessions = Self.groupedSessions(from: visits)
        } else {
            ingestOCounts()
        }
    }

    private func mergeWindow(_ built: [TimelineSession]) {
        var visits = sessions.flatMap(\.visits)
        let existing = Set(visits.map(\.id))
        for visit in built.flatMap(\.visits) where !existing.contains(visit.id) {
            visits.append(visit)
        }
        sessions = Self.groupedSessions(from: visits)
    }

    private func loadNextWindow(isInitial: Bool, generation: Int, refreshOCounts: Bool = false) async {
        guard generation == fetchGeneration, let windowEnd = nextWindowEnd else { return }
        let windowStart = windowEnd.addingTimeInterval(-Self.windowSeconds)
        let earliest = Date().addingTimeInterval(-Self.maxLookbackSeconds)
        if windowEnd <= earliest {
            hasMore = false
            return
        }

        do {
            async let raw = fetchScenes(from: windowStart, to: windowEnd)
            if OCountHeatmapLoader.shared.isReady {
                await OCountHeatmapLoader.shared.loadIfNeeded()
            } else {
                let generationAtStart = generation
                Task { @MainActor in
                    await OCountHeatmapLoader.shared.loadIfNeeded()
                    guard generationAtStart == self.fetchGeneration else { return }
                    self.ingestOCounts()
                }
            }
            if refreshOCounts {
                Task { @MainActor in
                    await OCountHeatmapLoader.shared.reload()
                    guard generation == self.fetchGeneration else { return }
                    self.ingestOCounts()
                }
            }
            let rows = try await raw
            guard generation == fetchGeneration else { return }
            let lookbackStart = Date().addingTimeInterval(-Self.maxLookbackSeconds)
            let oEvents: [OCountTimelineEvent]
            if isInitial {
                oEvents = OCountHeatmapLoader.shared.events(in: lookbackStart..<windowEnd, actionsOnly: true)
            } else {
                oEvents = OCountHeatmapLoader.shared.events(in: windowStart..<windowEnd, actionsOnly: true)
            }
            let built = Self.makeSessions(
                from: rows,
                oEvents: oEvents,
                ratingEvents: TimelineRatingActionStore.events(
                    in: isInitial ? lookbackStart..<windowEnd : windowStart..<windowEnd
                ),
                in: windowStart..<windowEnd
            )
            if isInitial {
                sessions = built
            } else {
                mergeWindow(built)
            }
            if built.isEmpty {
                if OCountHeatmapLoader.shared.isReady {
                    consecutiveEmptyWindows += 1
                }
            } else {
                consecutiveEmptyWindows = 0
            }
            nextWindowEnd = windowStart
            loadedWindowStart = windowStart
            hasMore = windowStart > earliest && consecutiveEmptyWindows < 3
        } catch {
            guard generation == fetchGeneration else { return }
            if Self.isCancellation(error) {
                print("⚠️ Session timeline cancelled")
                return
            }
            print("❌ Session timeline: \(error)")
            if isInitial, sessions.isEmpty {
                didFail = true
                hasMore = false
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError || Task.isCancelled { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let gqlError = error as? GraphQLNetworkError {
            if case .networkError(let inner) = gqlError {
                return isCancellation(inner)
            }
        }
        return false
    }

    private func fetchScenes(from start: Date, to end: Date) async throws -> [TimelineSceneRow] {
        var lastError: Error?
        for variant in QueryVariant.allCases {
            do {
            return try await fetchScenes(from: start, variant: variant)
            } catch {
                if Self.isCancellation(error) { throw error }
                lastError = error
                print("⚠️ Session timeline query \(variant) failed: \(error)")
            }
        }
        throw lastError ?? GraphQLNetworkError.graphQLError(message: "Query failed")
    }

    private func fetchScenes(from start: Date, variant: QueryVariant) async throws -> [TimelineSceneRow] {
        var page = 1
        let perPage = 100
        var total = Int.max
        var rows: [TimelineSceneRow] = []

        while (page - 1) * perPage < total {
            let response: TimelineScenesResponse = try await GraphQLClient.shared.execute(
                query: variant.query,
                variables: Self.variables(page: page, perPage: perPage, start: start, variant: variant)
            )
            if let errors = response.errors, !errors.isEmpty, response.data?.findScenes?.scenes == nil {
                let message = errors.compactMap(\.message).joined(separator: "; ")
                throw GraphQLNetworkError.graphQLError(message: message.isEmpty ? "Query failed" : message)
            }
            let pageRows = response.data?.findScenes?.scenes ?? []
            total = response.data?.findScenes?.count ?? pageRows.count
            rows.append(contentsOf: pageRows)
            if pageRows.count < perPage { break }
            page += 1
            if page > 30 { break }
        }
        return rows
    }

    private static func makeSessions(
        from rows: [TimelineSceneRow],
        oEvents: [OCountTimelineEvent],
        ratingEvents: [TimelineRatingActionStore.Entry],
        in range: Range<Date>
    ) -> [TimelineSession] {
        var visits: [TimelineVisit] = []
        var snapshots: [String: TimelineSceneSnapshot] = [:]
        for row in rows {
            guard let snapshot = row.snapshot else { continue }
            snapshots[snapshot.id] = snapshot
            let plays = playTimes(for: row).filter { range.contains($0) }.sorted()
            let os = (row.o_history ?? []).compactMap(\.date).filter { range.contains($0) }.sorted()

            let latestPlay = playTimes(for: row).sorted().last ?? row.last_played_at?.date
            let resume = row.resume_time ?? 0

            if plays.isEmpty {
                for stamp in os {
                    visits.append(
                        TimelineVisit(
                            id: "\(snapshot.id)-o-\(stamp.timeIntervalSince1970)",
                            media: .scene(snapshot),
                            startedAt: stamp,
                            watchedSeconds: 0,
                            sceneStartSeconds: nil,
                            oCountTimes: [stamp],
                            isPlayback: false
                        )
                    )
                }
                continue
            }

            for (index, start) in plays.enumerated() {
                let nextPlay = index + 1 < plays.count ? plays[index + 1] : nil
                var watched = nextPlay.map { $0.timeIntervalSince(start) } ?? min(snapshot.duration ?? 180, 5 * 60)
                if let cap = snapshot.duration, cap > 0 {
                    watched = min(watched, cap)
                }
                watched = max(15, watched)
                let windowEnd = start.addingTimeInterval(watched + 120)
                let attached = os.filter { $0 >= start && $0 <= windowEnd }
                visits.append(
                    TimelineVisit(
                        id: "\(snapshot.id)-\(start.timeIntervalSince1970)",
                        media: .scene(snapshot),
                        startedAt: start,
                        watchedSeconds: watched,
                        sceneStartSeconds: Self.sceneStartSeconds(
                            sceneId: snapshot.id,
                            playedAt: start,
                            watchedSeconds: watched,
                            resumeTime: resume,
                            isLatestPlay: latestPlay.map { abs($0.timeIntervalSince(start)) < 2 } ?? false
                        ),
                        oCountTimes: attached,
                        isPlayback: true
                    )
                )
            }

            let attached = Set(visits.filter { $0.scene?.id == snapshot.id }.flatMap(\.oCountTimes))
            for stamp in os where !attached.contains(stamp) {
                visits.append(
                    TimelineVisit(
                        id: "\(snapshot.id)-o-\(stamp.timeIntervalSince1970)",
                        media: .scene(snapshot),
                        startedAt: stamp,
                        watchedSeconds: 0,
                        sceneStartSeconds: nil,
                        oCountTimes: [stamp],
                        isPlayback: false
                    )
                )
            }
        }

        Self.mergeCalendarOCounts(oEvents, into: &visits, snapshots: snapshots)
        Self.mergeRatingActions(ratingEvents, into: &visits, snapshots: snapshots)
        return Self.groupedSessions(from: visits)
    }

    private static func groupedSessions(from visits: [TimelineVisit]) -> [TimelineSession] {
        let ordered = visits.sorted { $0.startedAt > $1.startedAt }
        guard !ordered.isEmpty else { return [] }

        // Group newest-first into sessions; keep visits newest-first so the latest card is on top.
        var sessions: [TimelineSession] = []
        var bucket: [TimelineVisit] = []
        for visit in ordered {
            if let last = bucket.last, last.startedAt.timeIntervalSince(visit.startedAt) > sessionGapSeconds {
                sessions.append(session(from: bucket))
                bucket = [visit]
            } else {
                bucket.append(visit)
            }
        }
        if !bucket.isEmpty {
            sessions.append(session(from: bucket))
        }
        return sessions
    }

    private static func mergeCalendarOCounts(
        _ events: [OCountTimelineEvent],
        into visits: inout [TimelineVisit],
        snapshots: [String: TimelineSceneSnapshot]
    ) {
        func key(kind: OCountHeatmapItem.Kind, id: String, date: Date) -> String {
            let label = kind == .scene ? "scene" : "image"
            return "\(label)-\(id)-\(Int(date.timeIntervalSince1970))"
        }

        var seen = Set(visits.flatMap { visit -> [String] in
            switch visit.media {
            case .scene(let scene):
                return visit.oCountTimes.map { key(kind: .scene, id: scene.id, date: $0) }
            case .image(let item):
                return visit.oCountTimes.map { key(kind: .image, id: item.stashID, date: $0) }
            }
        })

        for event in events where event.item.kind != .image || event.isActionTime {
            let stampKey = key(kind: event.item.kind, id: event.item.stashID, date: event.date)
            if seen.contains(stampKey) {
                if event.item.kind == .image, !event.item.isPlaceholder,
                   let index = visits.firstIndex(where: {
                       if case .image(let item) = $0.media {
                           return item.stashID == event.item.stashID
                               && abs($0.startedAt.timeIntervalSince(event.date)) < 2
                       }
                       return false
                   }) {
                    let current = visits[index]
                    if case .image(let existing) = current.media,
                       existing.isPlaceholder || existing.thumbnailURL == nil || existing.title == "Untitled" {
                        visits[index] = TimelineVisit(
                            id: current.id,
                            media: .image(event.item),
                            startedAt: current.startedAt,
                            watchedSeconds: current.watchedSeconds,
                            sceneStartSeconds: current.sceneStartSeconds,
                            oCountTimes: current.oCountTimes,
                            isPlayback: current.isPlayback,
                            ratingAction: current.ratingAction
                        )
                    }
                }
                continue
            }
            if event.item.kind == .image, event.item.isPlaceholder {
                continue
            }
            seen.insert(stampKey)

            let times = Array(repeating: event.date, count: max(1, event.count))
            switch event.item.kind {
            case .scene:
                let snapshot = snapshots[event.item.stashID] ?? Self.sceneSnapshot(from: event.item)
                visits.append(
                    TimelineVisit(
                        id: "\(event.item.stashID)-o-\(event.date.timeIntervalSince1970)",
                        media: .scene(snapshot),
                        startedAt: event.date,
                        watchedSeconds: 0,
                        sceneStartSeconds: nil,
                        oCountTimes: times,
                        isPlayback: false
                    )
                )
            case .image:
                visits.append(
                    TimelineVisit(
                        id: "image-\(event.item.stashID)-o-\(event.date.timeIntervalSince1970)",
                        media: .image(event.item),
                        startedAt: event.date,
                        watchedSeconds: 0,
                        sceneStartSeconds: nil,
                        oCountTimes: times,
                        isPlayback: false
                    )
                )
            }
        }
    }

    private static func mergeRatingActions(
        _ entries: [TimelineRatingActionStore.Entry],
        into visits: inout [TimelineVisit],
        snapshots: [String: TimelineSceneSnapshot]
    ) {
        var seen = Set(
            visits.compactMap { visit -> String? in
                guard visit.isRatingAction else { return nil }
                switch visit.media {
                case .scene(let scene):
                    return "scene-\(scene.id)-r-\(Int(visit.startedAt.timeIntervalSince1970))"
                case .image(let item):
                    return "image-\(item.stashID)-r-\(Int(visit.startedAt.timeIntervalSince1970))"
                }
            }
        )
        for entry in entries where entry.rating100 > 0 {
            let label = entry.kind == "image" ? "image" : "scene"
            let stampKey = "\(label)-\(entry.stashID)-r-\(Int(entry.at))"
            guard !seen.contains(stampKey) else { continue }
            seen.insert(stampKey)
            let media = ratingMedia(for: entry, snapshots: snapshots, visits: visits)
            if case .image(let item) = media, item.isPlaceholder { continue }
            visits.append(
                TimelineVisit(
                    id: "\(label)-\(entry.stashID)-r-\(entry.at)",
                    media: media,
                    startedAt: entry.date,
                    watchedSeconds: 0,
                    sceneStartSeconds: nil,
                    oCountTimes: [],
                    isPlayback: false,
                    ratingAction: entry.rating100
                )
            )
        }
    }

    private static func ratingMedia(
        for entry: TimelineRatingActionStore.Entry,
        snapshots: [String: TimelineSceneSnapshot],
        visits: [TimelineVisit]
    ) -> TimelineVisitMedia {
        let trimmed = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = trimmed.isEmpty ? "Untitled" : trimmed
        switch entry.itemKind {
        case .scene:
            if let snapshot = snapshots[entry.stashID] { return .scene(snapshot) }
            if let existing = visits.compactMap(\.scene).first(where: { $0.id == entry.stashID }) {
                return .scene(existing)
            }
            return .scene(
                TimelineSceneSnapshot(
                    id: entry.stashID,
                    title: title,
                    thumbnailPath: entry.thumbnailPath,
                    duration: nil,
                    resumeTime: nil,
                    studio: nil,
                    tags: [],
                    performers: [],
                    rating100: entry.rating100
                )
            )
        case .image:
            if let item = OCountHeatmapLoader.shared.imageItem(stashID: entry.stashID) {
                return .image(item)
            }
            if let existing = visits.compactMap({ visit -> OCountHeatmapItem? in
                if case .image(let item) = visit.media, item.stashID == entry.stashID, !item.isPlaceholder {
                    return item
                }
                return nil
            }).first {
                return .image(existing)
            }
            if title != "Untitled" || entry.thumbnailPath != nil {
                return .image(
                    OCountHeatmapItem(
                        kind: .image,
                        stashID: entry.stashID,
                        title: title,
                        thumbnailPath: entry.thumbnailPath,
                        previewPath: nil,
                        imagePath: nil,
                        visualFiles: nil,
                        performers: [],
                        studio: nil,
                        rating100: entry.rating100,
                        countOnDay: 1
                    )
                )
            }
            return .image(OCountHeatmapItem.stub(kind: .image, stashID: entry.stashID))
        }
    }

    private static func sceneSnapshot(from item: OCountHeatmapItem) -> TimelineSceneSnapshot {
        TimelineSceneSnapshot(
            id: item.stashID,
            title: item.title,
            thumbnailPath: item.thumbnailPath,
            duration: nil,
            resumeTime: nil,
            studio: item.studio,
            tags: [],
            performers: [],
            rating100: item.rating100
        )
    }

    private static func session(from newestFirst: [TimelineVisit]) -> TimelineSession {
        let start = newestFirst.last?.startedAt ?? Date()
        let last = newestFirst.first
        let end = last.map { $0.startedAt.addingTimeInterval($0.watchedSeconds) } ?? start
        return TimelineSession(
            id: "\(start.timeIntervalSince1970)-\(newestFirst.count)",
            startedAt: start,
            endedAt: max(end, start),
            visits: newestFirst
        )
    }

    private static func sceneStartSeconds(
        sceneId: String,
        playedAt: Date,
        watchedSeconds: TimeInterval,
        resumeTime: Double,
        isLatestPlay: Bool
    ) -> TimeInterval? {
        if let stored = TimelinePlayStartStore.startSeconds(sceneId: sceneId, playedAt: playedAt), stored >= 5 {
            return stored
        }
        guard isLatestPlay, resumeTime > 5 else { return nil }
        let estimated = max(0, resumeTime - watchedSeconds)
        return estimated >= 5 ? estimated : nil
    }

    private static func playTimes(for row: TimelineSceneRow) -> [Date] {
        let history = (row.play_history ?? []).compactMap(\.date)
        if !history.isEmpty { return history }
        if let last = row.last_played_at?.date {
            return [last]
        }
        return []
    }

    private static func variables(page: Int, perPage: Int, start: Date, variant: QueryVariant) -> [String: Any] {
        var vars: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": variant.sortField,
                "direction": "DESC"
            ]
        ]
        if variant.usesLastPlayedFilter {
            vars["scene_filter"] = [
                "last_played_at": [
                    "modifier": "GREATER_THAN",
                    "value": isoString(start)
                ]
            ]
        }
        return vars
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private enum QueryVariant: CaseIterable {
    case full
    case withoutPlayHistory
    case minimal
    case recentUpdated

    var usesLastPlayedFilter: Bool {
        self != .recentUpdated
    }

    var sortField: String {
        self == .recentUpdated ? "updated_at" : "last_played_at"
    }

    var query: String {
        switch self {
        case .full:
            return Self.baseQuery(extraSceneFields: """
              play_history
              o_history
              files { duration }
              tags { id name }
              performers { id name }
            """)
        case .withoutPlayHistory:
            return Self.baseQuery(extraSceneFields: """
              o_history
              files { duration }
              tags { id name }
              performers { id name }
            """)
        case .minimal, .recentUpdated:
            return Self.baseQuery(extraSceneFields: "")
        }
    }

    private static func baseQuery(extraSceneFields: String) -> String {
        """
        query FindSessionTimeline($filter: FindFilterType, $scene_filter: SceneFilterType) {
          findScenes(filter: $filter, scene_filter: $scene_filter) {
            count
            scenes {
              id
              title
              last_played_at
              play_duration
              resume_time
              rating100
              paths { screenshot }
              studio { id name }
              \(extraSceneFields)
            }
          }
        }
        """
    }
}

private struct TimelineScenesResponse: Decodable {
    let data: DataPayload?
    let errors: [GraphQLErrorMessage]?

    struct DataPayload: Decodable {
        let findScenes: FindScenes?
    }

    struct FindScenes: Decodable {
        let count: Int?
        let scenes: [TimelineSceneRow]?
    }

    struct GraphQLErrorMessage: Decodable {
        let message: String?
    }
}

private struct TimelineSceneRow: Decodable {
    let id: String?
    let title: String?
    let last_played_at: FlexibleJSONTime?
    let play_duration: Double?
    let resume_time: Double?
    let rating100: Int?
    let play_history: [FlexibleJSONTime]?
    let o_history: [FlexibleJSONTime]?
    let files: [FileDuration]?
    let paths: Paths?
    let studio: Studio?
    let tags: [NamedTag]?
    let performers: [NamedPerformer]?

    struct FileDuration: Decodable {
        let duration: Double?
    }

    struct Paths: Decodable {
        let screenshot: String?
    }

    struct Studio: Decodable {
        let id: String?
        let name: String?
    }

    struct NamedTag: Decodable {
        let id: String?
        let name: String?
    }

    struct NamedPerformer: Decodable {
        let id: String?
        let name: String?
    }

    var snapshot: TimelineSceneSnapshot? {
        guard let id else { return nil }
        let duration = files?.compactMap(\.duration).max()
        let studioModel: SceneStudio? = {
            guard let sid = studio?.id, let name = studio?.name, !name.isEmpty else { return nil }
            return SceneStudio(id: sid, name: name, updatedAt: nil)
        }()
        let tagModels = (tags ?? []).compactMap { tag -> Tag? in
            guard let tid = tag.id, let name = tag.name else { return nil }
            return Tag(
                id: tid,
                name: name,
                description: nil,
                imagePath: nil,
                sceneCount: nil,
                imageCount: nil,
                galleryCount: nil,
                sceneMarkerCount: nil,
                performerCount: nil,
                favorite: nil,
                createdAt: nil,
                updatedAt: nil
            )
        }
        let performerModels = (performers ?? []).compactMap { performer -> ScenePerformer? in
            guard let pid = performer.id, let name = performer.name else { return nil }
            return ScenePerformer(
                id: pid,
                name: name,
                birthdate: nil,
                sceneCount: nil,
                galleryCount: nil,
                oCounter: nil,
                updatedAt: nil
            )
        }
        return TimelineSceneSnapshot(
            id: id,
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? title! : "Untitled",
            thumbnailPath: paths?.screenshot,
            duration: duration,
            resumeTime: resume_time,
            studio: studioModel,
            tags: tagModels,
            performers: performerModels,
            rating100: rating100
        )
    }
}

private enum FlexibleJSONTime: Decodable {
    case string(String)
    case unix(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let value = try? container.decode(Double.self) {
            self = .unix(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .unix(Double(value))
        } else {
            self = .string("")
        }
    }

    var date: Date? {
        switch self {
        case .string(let raw):
            return OCountHeatmapLoader.parseTimestamp(raw)
        case .unix(let value):
            let seconds = value > 1_000_000_000_000 ? value / 1000 : value
            return Date(timeIntervalSince1970: seconds)
        }
    }
}
#endif
