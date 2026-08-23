//
//  SessionTimelineLoader.swift
//  stashy
//
//  Timeline from Stash server data only: scene play_history, o_history, and markers.
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

    func withThumbnail(_ path: String?) -> TimelineSceneSnapshot {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return self }
        return TimelineSceneSnapshot(
            id: id,
            title: title,
            thumbnailPath: trimmed,
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

    var studioName: String? {
        let name = studio?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    var thumbnailURL: URL? { asScene.thumbnailURL }

    var asHeatmapItem: OCountHeatmapItem {
        OCountHeatmapItem(
            kind: .scene,
            stashID: id,
            title: title,
            thumbnailPath: thumbnailPath,
            previewPath: nil,
            imagePath: nil,
            visualFiles: nil,
            performers: performers.map {
                GalleryPerformer(id: $0.id, name: $0.name, image_path: nil)
            },
            studio: studio,
            rating100: rating100,
            countOnDay: 1
        )
    }

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

enum TimelineKind: String, CaseIterable, Identifiable, Hashable {
    case watch
    case oCount
    case marker

    var id: String { rawValue }

    var label: String {
        switch self {
        case .watch: return "Watch"
        case .oCount: return "O-Count"
        case .marker: return "Markers"
        }
    }

    private static let filterDefaultsKey = "stashy_timeline_kind_filter"

    static func savedFilter() -> Set<TimelineKind> {
        guard let stored = UserDefaults.standard.array(forKey: filterDefaultsKey) as? [String] else {
            return Set(allCases)
        }
        let kinds = Set(stored.compactMap(TimelineKind.init(rawValue:)))
        return kinds.isEmpty ? Set(allCases) : kinds
    }

    static func saveFilter(_ kinds: Set<TimelineKind>) {
        let stored = kinds.isEmpty ? allCases.map(\.rawValue) : kinds.map(\.rawValue)
        UserDefaults.standard.set(stored, forKey: filterDefaultsKey)
    }
}

struct TimelineVisit: Identifiable, Equatable {
    let id: String
    let scene: TimelineSceneSnapshot
    let startedAt: Date
    let watchedSeconds: TimeInterval
    let sceneStartSeconds: TimeInterval?
    let oCountTimes: [Date]
    let isPlayback: Bool
    var isMarkerAction: Bool = false
    var markerTitle: String? = nil

    var oCount: Int { oCountTimes.count }

    var timelineKind: TimelineKind {
        if isMarkerAction { return .marker }
        if isPlayback { return .watch }
        return .oCount
    }

    func withWatchedSeconds(_ seconds: TimeInterval) -> TimelineVisit {
        TimelineVisit(
            id: id,
            scene: scene,
            startedAt: startedAt,
            watchedSeconds: seconds,
            sceneStartSeconds: sceneStartSeconds,
            oCountTimes: oCountTimes,
            isPlayback: isPlayback,
            isMarkerAction: isMarkerAction,
            markerTitle: markerTitle
        )
    }
}

struct TimelineSession: Identifiable, Equatable {
    let id: String
    let startedAt: Date
    let endedAt: Date
    let visits: [TimelineVisit]

    var sceneCount: Int { visits.count }
    var oCount: Int { visits.reduce(0) { $0 + $1.oCount } }
    var markerCount: Int { visits.reduce(0) { $0 + ($1.isMarkerAction ? 1 : 0) } }
    var watchedSeconds: TimeInterval { visits.reduce(0) { $0 + $1.watchedSeconds } }
    var sessionSeconds: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    func filtered(to kinds: Set<TimelineKind>) -> TimelineSession? {
        let kept = visits.filter { kinds.contains($0.timelineKind) }
        guard !kept.isEmpty else { return nil }
        let start = kept.last?.startedAt ?? startedAt
        let last = kept.first
        let end = last.map { $0.startedAt.addingTimeInterval($0.watchedSeconds) } ?? start
        return TimelineSession(
            id: id,
            startedAt: start,
            endedAt: max(end, start),
            visits: kept
        )
    }
}

@MainActor
final class SessionTimelineLoader: ObservableObject {
    static let shared = SessionTimelineLoader()

    nonisolated static let windowSeconds: TimeInterval = 24 * 60 * 60
    nonisolated static let maxLookbackSeconds: TimeInterval = 90 * 24 * 60 * 60
    nonisolated static let sessionGapSeconds: TimeInterval = 30 * 60

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
    /// Scene `o_history` stamps for the full lookback; filtered per 24h window when building.
    private var oStampsCache: [TimelineOStamp] = []
    private var liveReloadTask: Task<Void, Never>?
    /// Pending live reload should refetch O-history (OR’d across debounced notifications).
    private var pendingLiveRefreshOHistory = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reset() }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ScenePlayAdded"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleLiveReload(refreshOHistory: false) }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SceneMarkerCreated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleLiveReload(refreshOHistory: false) }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SceneOCounterUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleLiveReload(refreshOHistory: true) }
        }
    }

    /// Debounced live refresh so rapid O-taps / plays do not stack full pipeline runs.
    private func scheduleLiveReload(refreshOHistory: Bool) {
        if refreshOHistory {
            pendingLiveRefreshOHistory = true
        }
        liveReloadTask?.cancel()
        liveReloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            let refreshO = self.pendingLiveRefreshOHistory
            self.pendingLiveRefreshOHistory = false
            await self.reload(refreshOHistory: refreshO)
        }
    }

    /// Full reload of the latest 24h window. Pass `refreshOHistory: false` for play/marker live updates.
    func reload(refreshOHistory: Bool = true) async {
        liveReloadTask?.cancel()
        liveReloadTask = nil
        pendingLiveRefreshOHistory = false
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
        let shouldRefreshOHistory = refreshOHistory || oStampsCache.isEmpty
        if shouldRefreshOHistory {
            oStampsCache = []
        }

        // Unstructured so SwiftUI cancelling `.refreshable` does not abort the fetch.
        let work = Task { @MainActor in
            await self.loadNextWindow(
                isInitial: true,
                generation: generation,
                refreshOHistory: shouldRefreshOHistory
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
            await loadNextWindow(isInitial: false, generation: generation, refreshOHistory: false)
        }
        guard generation == fetchGeneration else { return }
        isLoadingMore = false
    }

    func reset() {
        liveReloadTask?.cancel()
        liveReloadTask = nil
        pendingLiveRefreshOHistory = false
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
        oStampsCache = []
    }

    private func mergeWindow(_ built: [TimelineSession]) {
        var visits = sessions.flatMap(\.visits)
        let existing = Set(visits.map(\.id))
        for visit in built.flatMap(\.visits) where !existing.contains(visit.id) {
            visits.append(visit)
        }
        sessions = Self.groupedSessions(from: visits)
    }

    private func loadNextWindow(isInitial: Bool, generation: Int, refreshOHistory: Bool) async {
        guard generation == fetchGeneration, let windowEnd = nextWindowEnd else { return }
        let windowStart = windowEnd.addingTimeInterval(-Self.windowSeconds)
        let earliest = Date().addingTimeInterval(-Self.maxLookbackSeconds)
        if windowEnd <= earliest {
            hasMore = false
            return
        }

        do {
            let lookbackStart = Date().addingTimeInterval(-Self.maxLookbackSeconds)
            let eventRange = windowStart..<windowEnd
            async let raw = fetchScenes(from: windowStart)
            async let markerRows = fetchMarkers(from: windowStart)
            if isInitial, refreshOHistory || oStampsCache.isEmpty {
                oStampsCache = await fetchSceneOStamps(from: lookbackStart)
            }
            let rows = try await raw
            let fetchedMarkers = await markerRows
            guard generation == fetchGeneration else { return }

            let built = Self.makeSessions(
                from: rows,
                oStamps: oStampsCache.filter { eventRange.contains($0.date) },
                fetchedMarkers: fetchedMarkers.filter { eventRange.contains($0.date) },
                in: eventRange
            )
            if isInitial {
                sessions = built
            } else {
                mergeWindow(built)
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
                AppLog.error("⚠️ Session timeline cancelled")
                return
            }
            AppLog.error("❌ Session timeline: \(error)")
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

    private func fetchScenes(from start: Date) async throws -> [TimelineSceneRow] {
        var lastError: Error?
        for variant in QueryVariant.allCases {
            do {
                return try await fetchScenes(from: start, variant: variant)
            } catch {
                if Self.isCancellation(error) { throw error }
                lastError = error
                AppLog.error("⚠️ Session timeline query \(variant) failed: \(error)")
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

    /// All scene O-count action times from Stash `o_history` (independent of play windows).
    private func fetchSceneOStamps(from start: Date) async -> [TimelineOStamp] {
        let query = """
        query FindSceneOHistory($filter: FindFilterType, $scene_filter: SceneFilterType) {
          findScenes(filter: $filter, scene_filter: $scene_filter) {
            count
            scenes {
              id
              title
              o_history
              rating100
              paths { screenshot }
              studio { id name }
              performers { id name }
            }
          }
        }
        """
        var page = 1
        let perPage = 200
        var total = Int.max
        var stamps: [TimelineOStamp] = []

        do {
            while (page - 1) * perPage < total {
                let response: TimelineOHistoryResponse = try await GraphQLClient.shared.execute(
                    query: query,
                    variables: [
                        "filter": [
                            "page": page,
                            "per_page": perPage,
                            "sort": "o_counter",
                            "direction": "DESC"
                        ],
                        "scene_filter": [
                            "o_counter": [
                                "value": 0,
                                "modifier": "GREATER_THAN"
                            ]
                        ]
                    ]
                )
                if let errors = response.errors, !errors.isEmpty,
                   response.data?.findScenes?.scenes == nil {
                    let message = errors.compactMap(\.message).joined(separator: "; ")
                    AppLog.error("⚠️ Session timeline o_history: \(message)")
                    return stamps
                }
                let scenes = response.data?.findScenes?.scenes ?? []
                total = response.data?.findScenes?.count ?? scenes.count
                for scene in scenes {
                    guard let snapshot = scene.snapshot else { continue }
                    for date in (scene.o_history ?? []).compactMap(\.date) where date >= start {
                        stamps.append(TimelineOStamp(scene: snapshot, date: date))
                    }
                }
                if scenes.count < perPage { break }
                page += 1
                if page > 100 { break }
            }
        } catch {
            if Self.isCancellation(error) { return stamps }
            AppLog.error("⚠️ Session timeline o_history failed: \(error)")
        }
        return stamps
    }

    private func fetchMarkers(from start: Date) async -> [TimelineFetchedMarker] {
        var page = 1
        let perPage = 100
        var total = Int.max
        var rows: [TimelineFetchedMarker] = []
        let query = """
        query TimelineMarkers($filter: FindFilterType, $scene_marker_filter: SceneMarkerFilterType) {
          findSceneMarkers(filter: $filter, scene_marker_filter: $scene_marker_filter) {
            count
            scene_markers {
              id
              title
              screenshot
              created_at
              scene {
                id
                title
                paths { screenshot }
                studio { id name }
              }
            }
          }
        }
        """

        do {
            while (page - 1) * perPage < total {
                let response: TimelineMarkersResponse = try await GraphQLClient.shared.execute(
                    query: query,
                    variables: [
                        "filter": [
                            "page": page,
                            "per_page": perPage,
                            "sort": "created_at",
                            "direction": "DESC"
                        ],
                        "scene_marker_filter": [
                            "created_at": [
                                "modifier": "GREATER_THAN",
                                "value": Self.isoString(start)
                            ]
                        ]
                    ]
                )
                if let errors = response.errors, !errors.isEmpty,
                   response.data?.findSceneMarkers?.scene_markers == nil {
                    let message = errors.compactMap(\.message).joined(separator: "; ")
                    AppLog.error("⚠️ Session timeline markers: \(message)")
                    return rows
                }
                let pageRows = (response.data?.findSceneMarkers?.scene_markers ?? [])
                    .compactMap(TimelineFetchedMarker.init)
                total = response.data?.findSceneMarkers?.count ?? pageRows.count
                rows.append(contentsOf: pageRows)
                if pageRows.count < perPage { break }
                page += 1
                if page > 30 { break }
            }
        } catch {
            if Self.isCancellation(error) { return rows }
            AppLog.error("⚠️ Session timeline markers failed: \(error)")
        }
        return rows
    }

    private static func makeSessions(
        from rows: [TimelineSceneRow],
        oStamps: [TimelineOStamp],
        fetchedMarkers: [TimelineFetchedMarker],
        in range: Range<Date>
    ) -> [TimelineSession] {
        var visits: [TimelineVisit] = []
        var snapshots: [String: TimelineSceneSnapshot] = [:]
        var playDurationByScene: [String: Double] = [:]
        var playCountByScene: [String: Int] = [:]
        var durationByScene: [String: Double] = [:]

        for row in rows {
            guard let snapshot = row.snapshot else { continue }
            snapshots[snapshot.id] = snapshot
            let allPlays = playTimes(for: row)
            playDurationByScene[snapshot.id] = row.play_duration ?? 0
            playCountByScene[snapshot.id] = max(row.play_count ?? 0, allPlays.count, 1)
            if let duration = snapshot.duration, duration > 0 {
                durationByScene[snapshot.id] = duration
            }

            let plays = allPlays.filter { range.contains($0) }.sorted()
            let os = (row.o_history ?? []).compactMap(\.date).filter { range.contains($0) }.sorted()

            if plays.isEmpty {
                for stamp in os {
                    visits.append(
                        TimelineVisit(
                            id: "\(snapshot.id)-o-\(stamp.timeIntervalSince1970)",
                            scene: snapshot,
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
                let attachUntil = nextPlay ?? start.addingTimeInterval(30 * 60)
                let windowEnd = min(attachUntil, start.addingTimeInterval(30 * 60 + 120))
                let attached = os.filter { $0 >= start && $0 <= windowEnd }
                visits.append(
                    TimelineVisit(
                        id: "\(snapshot.id)-\(start.timeIntervalSince1970)",
                        scene: snapshot,
                        startedAt: start,
                        watchedSeconds: 0,
                        sceneStartSeconds: nil,
                        oCountTimes: attached,
                        isPlayback: true
                    )
                )
            }

            let attached = Set(
                visits.filter { $0.scene.id == snapshot.id }.flatMap(\.oCountTimes)
            )
            for stamp in os where !attached.contains(stamp) {
                visits.append(
                    TimelineVisit(
                        id: "\(snapshot.id)-o-\(stamp.timeIntervalSince1970)",
                        scene: snapshot,
                        startedAt: stamp,
                        watchedSeconds: 0,
                        sceneStartSeconds: nil,
                        oCountTimes: [stamp],
                        isPlayback: false
                    )
                )
            }
        }

        Self.mergeOStamps(oStamps, into: &visits, snapshots: &snapshots)
        Self.mergeFetchedMarkers(fetchedMarkers, into: &visits, snapshots: snapshots)
        Self.applyWatchedDurations(
            &visits,
            playDurationByScene: playDurationByScene,
            playCountByScene: playCountByScene,
            durationByScene: durationByScene
        )
        Self.applyResumeStartEstimates(&visits)
        return Self.groupedSessions(from: visits)
    }

    private static func mergeOStamps(
        _ stamps: [TimelineOStamp],
        into visits: inout [TimelineVisit],
        snapshots: inout [String: TimelineSceneSnapshot]
    ) {
        var seen = Set(
            visits.flatMap { visit in
                visit.oCountTimes.map { "\(visit.scene.id)-\(Int($0.timeIntervalSince1970))" }
            }
        )
        for stamp in stamps {
            let key = "\(stamp.scene.id)-\(Int(stamp.date.timeIntervalSince1970))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let snapshot = snapshots[stamp.scene.id] ?? stamp.scene
            snapshots[stamp.scene.id] = snapshot
            visits.append(
                TimelineVisit(
                    id: "\(stamp.scene.id)-o-\(stamp.date.timeIntervalSince1970)",
                    scene: snapshot,
                    startedAt: stamp.date,
                    watchedSeconds: 0,
                    sceneStartSeconds: nil,
                    oCountTimes: [stamp.date],
                    isPlayback: false
                )
            )
        }
    }

    private static func applyWatchedDurations(
        _ visits: inout [TimelineVisit],
        playDurationByScene: [String: Double],
        playCountByScene: [String: Int],
        durationByScene: [String: Double]
    ) {
        let orderedIndexes = visits.indices.sorted { visits[$0].startedAt < visits[$1].startedAt }
        for (position, index) in orderedIndexes.enumerated() {
            let visit = visits[index]
            guard visit.isPlayback else { continue }
            let sceneId = visit.scene.id
            let cap = durationByScene[sceneId]

            if position + 1 < orderedIndexes.count {
                let next = visits[orderedIndexes[position + 1]].startedAt
                let gap = next.timeIntervalSince(visit.startedAt)
                if gap >= 15, gap <= sessionGapSeconds {
                    visits[index] = visit.withWatchedSeconds(min(gap, cap ?? gap))
                    continue
                }
            }

            let total = playDurationByScene[sceneId] ?? 0
            let count = max(1, playCountByScene[sceneId] ?? 1)
            let share = total / Double(count)
            guard share >= 15 else { continue }
            visits[index] = visit.withWatchedSeconds(min(share, cap ?? share))
        }
    }

    private static func groupedSessions(from visits: [TimelineVisit]) -> [TimelineSession] {
        let ordered = visits.sorted { $0.startedAt > $1.startedAt }
        guard !ordered.isEmpty else { return [] }

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

    private static func mergeFetchedMarkers(
        _ markers: [TimelineFetchedMarker],
        into visits: inout [TimelineVisit],
        snapshots: [String: TimelineSceneSnapshot]
    ) {
        var seen = Set(visits.compactMap { $0.isMarkerAction ? $0.id : nil })
        for marker in markers {
            let visitId = "marker-\(marker.id)"
            guard !seen.contains(visitId) else { continue }
            seen.insert(visitId)
            let scene = markerScene(
                sceneId: marker.sceneId,
                sceneTitle: marker.sceneTitle,
                thumbnailPath: marker.thumbnailPath,
                studio: marker.studio,
                snapshots: snapshots,
                visits: visits
            )
            visits.append(
                TimelineVisit(
                    id: visitId,
                    scene: scene,
                    startedAt: marker.date,
                    watchedSeconds: 0,
                    sceneStartSeconds: nil,
                    oCountTimes: [],
                    isPlayback: false,
                    isMarkerAction: true,
                    markerTitle: marker.title
                )
            )
        }
    }

    private static func markerScene(
        sceneId: String,
        sceneTitle: String?,
        thumbnailPath: String?,
        studio: SceneStudio?,
        snapshots: [String: TimelineSceneSnapshot],
        visits: [TimelineVisit]
    ) -> TimelineSceneSnapshot {
        if let snapshot = snapshots[sceneId] {
            return snapshot.withThumbnail(thumbnailPath)
        }
        if let existing = visits.map(\.scene).first(where: { $0.id == sceneId }) {
            return existing.withThumbnail(thumbnailPath)
        }
        let trimmed = sceneTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return TimelineSceneSnapshot(
            id: sceneId,
            title: trimmed.isEmpty ? "Untitled" : trimmed,
            thumbnailPath: thumbnailPath,
            duration: nil,
            resumeTime: nil,
            studio: studio,
            tags: [],
            performers: [],
            rating100: nil
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

    /// Estimate in-scene start from Stash `resume_time − watched` on the newest play per scene.
    private static func applyResumeStartEstimates(_ visits: inout [TimelineVisit]) {
        var latestIndexByScene: [String: Int] = [:]
        for index in visits.indices where visits[index].isPlayback {
            let sceneId = visits[index].scene.id
            if let existing = latestIndexByScene[sceneId] {
                if visits[index].startedAt > visits[existing].startedAt {
                    latestIndexByScene[sceneId] = index
                }
            } else {
                latestIndexByScene[sceneId] = index
            }
        }
        for index in latestIndexByScene.values {
            let visit = visits[index]
            guard let resume = visit.scene.resumeTime, resume > 5, visit.watchedSeconds >= 15 else { continue }
            let estimated = max(0, resume - visit.watchedSeconds)
            guard estimated >= 5 else { continue }
            visits[index] = TimelineVisit(
                id: visit.id,
                scene: visit.scene,
                startedAt: visit.startedAt,
                watchedSeconds: visit.watchedSeconds,
                sceneStartSeconds: estimated,
                oCountTimes: visit.oCountTimes,
                isPlayback: visit.isPlayback,
                isMarkerAction: visit.isMarkerAction,
                markerTitle: visit.markerTitle
            )
        }
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

    nonisolated static func rating100(from userInfo: [AnyHashable: Any]?) -> Int? {
        if let value = userInfo?["rating100"] as? Int { return value }
        if let value = userInfo?["rating100"] as? NSNumber { return value.intValue }
        return nil
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

    var usesLastPlayedFilter: Bool { self != .recentUpdated }

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
              play_count
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

private struct TimelineOStamp {
    let scene: TimelineSceneSnapshot
    let date: Date
}

private struct TimelineOHistoryResponse: Decodable {
    let data: DataPayload?
    let errors: [GraphQLErrorMessage]?

    struct DataPayload: Decodable {
        let findScenes: FindScenes?
    }

    struct FindScenes: Decodable {
        let count: Int?
        let scenes: [Row]?
    }

    struct Row: Decodable {
        let id: String?
        let title: String?
        let o_history: [FlexibleJSONTime]?
        let rating100: Int?
        let paths: Paths?
        let studio: Studio?
        let performers: [NamedPerformer]?

        struct Paths: Decodable {
            let screenshot: String?
        }

        struct Studio: Decodable {
            let id: String?
            let name: String?
        }

        struct NamedPerformer: Decodable {
            let id: String?
            let name: String?
        }

        var snapshot: TimelineSceneSnapshot? {
            guard let id else { return nil }
            let studioModel: SceneStudio? = {
                guard let sid = studio?.id, let name = studio?.name, !name.isEmpty else { return nil }
                return SceneStudio(id: sid, name: name, updatedAt: nil)
            }()
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
                duration: nil,
                resumeTime: nil,
                studio: studioModel,
                tags: [],
                performers: performerModels,
                rating100: rating100
            )
        }
    }

    struct GraphQLErrorMessage: Decodable {
        let message: String?
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

private struct TimelineMarkersResponse: Decodable {
    let data: DataPayload?
    let errors: [GraphQLErrorMessage]?

    struct DataPayload: Decodable {
        let findSceneMarkers: FindMarkers?
    }

    struct FindMarkers: Decodable {
        let count: Int?
        let scene_markers: [Row]?
    }

    struct Row: Decodable {
        let id: String?
        let title: String?
        let screenshot: String?
        let created_at: FlexibleJSONTime?
        let scene: Scene?
    }

    struct Scene: Decodable {
        let id: String?
        let title: String?
        let paths: Paths?
        let studio: Studio?
    }

    struct Studio: Decodable {
        let id: String?
        let name: String?
    }

    struct Paths: Decodable {
        let screenshot: String?
    }

    struct GraphQLErrorMessage: Decodable {
        let message: String?
    }
}

private struct TimelineFetchedMarker {
    let id: String
    let sceneId: String
    let date: Date
    let title: String?
    let sceneTitle: String?
    let thumbnailPath: String?
    let studio: SceneStudio?

    init?(row: TimelineMarkersResponse.Row) {
        guard let id = row.id, !id.isEmpty,
              let sceneId = row.scene?.id, !sceneId.isEmpty,
              let date = row.created_at?.date else { return nil }
        self.id = id
        self.sceneId = sceneId
        self.date = date
        let markerTitle = row.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = (markerTitle?.isEmpty == false) ? markerTitle : nil
        let sceneTitle = row.scene?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sceneTitle = (sceneTitle?.isEmpty == false) ? sceneTitle : nil
        let shot = row.screenshot?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sceneShot = row.scene?.paths?.screenshot?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.thumbnailPath = (shot?.isEmpty == false) ? shot : sceneShot
        if let sid = row.scene?.studio?.id, let name = row.scene?.studio?.name, !name.isEmpty {
            self.studio = SceneStudio(id: sid, name: name, updatedAt: nil)
        } else {
            self.studio = nil
        }
    }
}

private struct TimelineSceneRow: Decodable {
    let id: String?
    let title: String?
    let last_played_at: FlexibleJSONTime?
    let play_duration: Double?
    let play_count: Int?
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
