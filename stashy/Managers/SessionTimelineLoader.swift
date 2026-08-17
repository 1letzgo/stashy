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
    let studio: SceneStudio?
    let tags: [Tag]
    let performers: [ScenePerformer]

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
            resumeTime: nil,
            playCount: nil,
            oCounter: nil,
            rating100: nil,
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

struct TimelineVisit: Identifiable, Equatable {
    let id: String
    let scene: TimelineSceneSnapshot
    let startedAt: Date
    let watchedSeconds: TimeInterval
    let oCountTimes: [Date]

    var oCount: Int { oCountTimes.count }
}

struct TimelineSession: Identifiable, Equatable {
    let id: String
    let startedAt: Date
    let endedAt: Date
    let visits: [TimelineVisit]

    var sceneCount: Int { visits.count }
    var oCount: Int { visits.reduce(0) { $0 + $1.oCount } }
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
                await self?.reload()
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

    func reload() async {
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
        await loadNextWindow(isInitial: true, generation: generation)
        guard generation == fetchGeneration else { return }
        isLoading = false
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

    private func loadNextWindow(isInitial: Bool, generation: Int) async {
        guard generation == fetchGeneration, let windowEnd = nextWindowEnd else { return }
        let windowStart = windowEnd.addingTimeInterval(-Self.windowSeconds)
        let earliest = Date().addingTimeInterval(-Self.maxLookbackSeconds)
        if windowEnd <= earliest {
            hasMore = false
            return
        }

        do {
            let raw = try await fetchScenes(from: windowStart, to: windowEnd)
            guard generation == fetchGeneration else { return }
            let built = Self.makeSessions(from: raw, in: windowStart..<windowEnd)
            if isInitial {
                sessions = built
            } else if !built.isEmpty {
                sessions.append(contentsOf: built)
            }
            if built.isEmpty {
                consecutiveEmptyWindows += 1
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

    private static func makeSessions(from rows: [TimelineSceneRow], in range: Range<Date>) -> [TimelineSession] {
        var visits: [TimelineVisit] = []
        for row in rows {
            guard let snapshot = row.snapshot else { continue }
            let plays = playTimes(for: row).filter { range.contains($0) }.sorted()
            let os = (row.o_history ?? []).compactMap(\.date).filter { range.contains($0) }.sorted()

            if plays.isEmpty {
                for stamp in os {
                    visits.append(
                        TimelineVisit(
                            id: "\(snapshot.id)-o-\(stamp.timeIntervalSince1970)",
                            scene: snapshot,
                            startedAt: stamp,
                            watchedSeconds: 60,
                            oCountTimes: [stamp]
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
                        scene: snapshot,
                        startedAt: start,
                        watchedSeconds: watched,
                        oCountTimes: attached
                    )
                )
            }

            let attached = Set(visits.filter { $0.scene.id == snapshot.id }.flatMap(\.oCountTimes))
            for stamp in os where !attached.contains(stamp) {
                visits.append(
                    TimelineVisit(
                        id: "\(snapshot.id)-o-\(stamp.timeIntervalSince1970)",
                        scene: snapshot,
                        startedAt: stamp,
                        watchedSeconds: 60,
                        oCountTimes: [stamp]
                    )
                )
            }
        }

        let ordered = visits.sorted { $0.startedAt > $1.startedAt }
        guard !ordered.isEmpty else { return [] }

        // Group newest-first into sessions, then keep sessions newest-first with visits oldest-first.
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

    private static func session(from newestFirst: [TimelineVisit]) -> TimelineSession {
        let chronological = Array(newestFirst.reversed())
        let start = chronological.first?.startedAt ?? Date()
        let last = chronological.last
        let end = last.map { $0.startedAt.addingTimeInterval($0.watchedSeconds) } ?? start
        return TimelineSession(
            id: "\(start.timeIntervalSince1970)-\(chronological.count)",
            startedAt: start,
            endedAt: max(end, start),
            visits: chronological
        )
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
            studio: studioModel,
            tags: tagModels,
            performers: performerModels
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
