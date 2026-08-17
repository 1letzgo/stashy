//
//  OCountHeatmapLoader.swift
//  stashy
//
//  Loads scene `o_history` plus image `o_counter` from Stash and buckets them by local day.
//

import Combine
import Foundation

struct OCountHeatmapItem: Identifiable {
    enum Kind: Equatable {
        case scene
        case image
    }

    var id: String { "\(kindLabel)-\(stashID)" }
    let kind: Kind
    let stashID: String
    let title: String
    let thumbnailPath: String?
    let previewPath: String?
    let imagePath: String?
    let visualFiles: [ImageFile]?
    let performers: [GalleryPerformer]
    let studio: SceneStudio?
    let rating100: Int?
    var countOnDay: Int

    private var kindLabel: String {
        switch kind {
        case .scene: return "scene"
        case .image: return "image"
        }
    }

    var displayTitle: String {
        if title != "Untitled" { return title }
        let names = performers.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? title : names.joined(separator: ", ")
    }

    var performerNamesLine: String {
        performers.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var kindTitle: String {
        switch kind {
        case .scene: return "Scene"
        case .image: return asImage.isVideo ? "Video" : "Image"
        }
    }

    var rowSubtitle: String {
        switch kind {
        case .scene:
            let name = studio?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? kindTitle : name
        case .image:
            return kindTitle
        }
    }

    func mergingListMetadata(from scene: Scene) -> OCountHeatmapItem {
        OCountHeatmapItem(
            kind: kind,
            stashID: stashID,
            title: scene.title ?? title,
            thumbnailPath: thumbnailPath,
            previewPath: previewPath,
            imagePath: imagePath,
            visualFiles: visualFiles,
            performers: performers,
            studio: scene.studio ?? studio,
            rating100: scene.rating100 ?? rating100,
            countOnDay: countOnDay
        )
    }

    var placeholderSystemImage: String {
        switch kind {
        case .scene: return "film"
        case .image: return asImage.isVideo ? "video" : "photo"
        }
    }

    var thumbnailURL: URL? {
        switch kind {
        case .scene: return asScene.thumbnailURL
        case .image: return asImage.thumbnailURL ?? asImage.previewURL ?? asImage.imageURL
        }
    }

    var asScene: Scene {
        Scene(
            id: stashID,
            title: title,
            details: nil,
            date: nil,
            duration: nil,
            studio: studio,
            performers: [],
            files: nil,
            tags: nil,
            galleries: nil,
            organized: nil,
            resumeTime: nil,
            playCount: nil,
            oCounter: countOnDay,
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

    var asImage: StashImage {
        StashImage(
            id: stashID,
            title: displayTitle,
            rating100: rating100,
            o_counter: countOnDay,
            organized: nil,
            date: nil,
            createdAt: nil,
            updatedAt: nil,
            paths: ImagePaths(
                thumbnail: thumbnailPath,
                preview: previewPath,
                image: imagePath
            ),
            visual_files: visualFiles,
            performers: performers.isEmpty ? nil : performers,
            studio: nil,
            galleries: nil,
            tags: nil
        )
    }
}

@MainActor
final class OCountHeatmapLoader: ObservableObject {
    static let shared = OCountHeatmapLoader()

    @Published private(set) var countsByDay: [String: Int] = [:]
    @Published private(set) var itemsByDay: [String: [OCountHeatmapItem]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var didFail = false

    private var loadedServerID: UUID?
    private var hasLoaded = false

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

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
            forName: NSNotification.Name("SceneOCounterUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let sceneId = notification.userInfo?["sceneId"] as? String else { return }
            Task { @MainActor in
                self?.applyLiveOIncrement(kind: .scene, stashID: sceneId)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ImageOCounterUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let imageId = notification.userInfo?["imageId"] as? String else { return }
            Task { @MainActor in
                self?.applyLiveOIncrement(kind: .image, stashID: imageId)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SceneUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = Scene.fromListMetadataNotification(notification) else { return }
            Task { @MainActor in
                self?.applyLiveSceneMetadata(scene)
            }
        }
    }

    func loadIfNeeded() async {
        let serverID = ServerConfigManager.shared.activeConfig?.id
        if hasLoaded, loadedServerID == serverID { return }
        await reload()
    }

    func reload() async {
        let serverID = ServerConfigManager.shared.activeConfig?.id
        isLoading = true
        didFail = false
        defer { isLoading = false }

        do {
            let buckets = try await fetchCountsByDay()
            countsByDay = buckets.counts
            itemsByDay = buckets.items
            loadedServerID = serverID
            hasLoaded = true
            didFail = false
        } catch {
            print("❌ O-Count heatmap: \(error)")
            didFail = true
            countsByDay = [:]
            itemsByDay = [:]
            loadedServerID = nil
            hasLoaded = false
        }
    }

    func latestMonthStart() -> Date? {
        let dates = countsByDay.compactMap { key, value -> Date? in
            guard value > 0 else { return nil }
            return Self.parseDayKey(key, calendar: calendar)
        }
        guard let latest = dates.max() else { return nil }
        return calendar.date(from: calendar.dateComponents([.year, .month], from: latest))
    }

    func count(onDayKey key: String) -> Int {
        countsByDay[key, default: 0]
    }

    func items(onDayKey key: String) -> [OCountHeatmapItem] {
        (itemsByDay[key] ?? []).sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .scene }
            if lhs.countOnDay != rhs.countOnDay { return lhs.countOnDay > rhs.countOnDay }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func earliestMonthStart() -> Date? {
        let dates = countsByDay.compactMap { key, value -> Date? in
            guard value > 0 else { return nil }
            return Self.parseDayKey(key, calendar: calendar)
        }
        guard let earliest = dates.min() else { return nil }
        return calendar.date(from: calendar.dateComponents([.year, .month], from: earliest))
    }

    func monthHeatmap(forMonthContaining date: Date) -> OCountMonthHeatmap {
        let globalMax = countsByDay.values.max() ?? 0
        return OCountMonthHeatmap.build(
            countsByDay: countsByDay,
            monthContaining: date,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            globalMax: globalMax
        )
    }

    private func reset() {
        countsByDay = [:]
        itemsByDay = [:]
        hasLoaded = false
        loadedServerID = nil
        didFail = false
    }

    private func applyLiveOIncrement(kind: OCountHeatmapItem.Kind, stashID: String) {
        let today = Self.dayKey(Date(), calendar: calendar)
        countsByDay[today, default: 0] += 1
        var list = itemsByDay[today] ?? []
        if let idx = list.firstIndex(where: { $0.kind == kind && $0.stashID == stashID }) {
            list[idx].countOnDay += 1
        } else if let source = itemsByDay.values.flatMap({ $0 }).first(where: { $0.kind == kind && $0.stashID == stashID }) {
            list.append(
                OCountHeatmapItem(
                    kind: source.kind,
                    stashID: source.stashID,
                    title: source.title,
                    thumbnailPath: source.thumbnailPath,
                    previewPath: source.previewPath,
                    imagePath: source.imagePath,
                    visualFiles: source.visualFiles,
                    performers: source.performers,
                    studio: source.studio,
                    rating100: source.rating100,
                    countOnDay: 1
                )
            )
        }
        itemsByDay[today] = list
    }

    private func applyLiveSceneMetadata(_ scene: Scene) {
        var didChange = false
        var next = itemsByDay
        for (day, items) in next {
            var copy = items
            var dayChanged = false
            for index in copy.indices {
                guard copy[index].kind == .scene, copy[index].stashID == scene.id else { continue }
                copy[index] = copy[index].mergingListMetadata(from: scene)
                dayChanged = true
            }
            if dayChanged {
                next[day] = copy
                didChange = true
            }
        }
        if didChange {
            itemsByDay = next
        }
    }

    private func fetchCountsByDay() async throws -> OCountDayBuckets {
        async let scenes = fetchOptionally { try await fetchSceneCountsByDay() }
        async let images = fetchOptionally { try await fetchImageCountsByDay() }
        let (sceneBuckets, imageBuckets) = await (scenes, images)
        if sceneBuckets == nil, imageBuckets == nil {
            throw GraphQLNetworkError.graphQLError(message: "O-Count query failed")
        }
        var merged = sceneBuckets ?? OCountDayBuckets()
        if let imageBuckets {
            merged.merge(imageBuckets)
        }
        return merged
    }

    private func fetchOptionally(_ work: () async throws -> OCountDayBuckets) async -> OCountDayBuckets? {
        do {
            return try await work()
        } catch {
            print("❌ O-Count heatmap: \(error)")
            return nil
        }
    }

    private func fetchSceneCountsByDay() async throws -> OCountDayBuckets {
        let query = """
        query FindSceneOHistory($filter: FindFilterType, $scene_filter: SceneFilterType) {
          findScenes(filter: $filter, scene_filter: $scene_filter) {
            count
            scenes {
              id
              title
              o_counter
              o_history
              created_at
              paths { screenshot }
              studio { id name }
            }
          }
        }
        """
        var page = 1
        let perPage = 500
        var buckets = OCountDayBuckets()
        var total = Int.max

        while (page - 1) * perPage < total {
            let variables: [String: Any] = [
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
            let response: OHistoryResponse
            do {
                response = try await GraphQLClient.shared.execute(
                    query: query,
                    variables: variables
                )
            } catch {
                if page == 1 { return try await fetchCountsByDayWithoutHistory() }
                throw error
            }
            if let errors = response.errors, !errors.isEmpty {
                let message = errors.compactMap(\.message).joined(separator: "; ")
                if message.contains("o_history") {
                    return try await fetchCountsByDayWithoutHistory()
                }
                if response.data?.findScenes?.scenes == nil {
                    throw GraphQLNetworkError.graphQLError(message: message.isEmpty ? "Query failed" : message)
                }
            }
            let scenes = response.data?.findScenes?.scenes ?? []
            total = response.data?.findScenes?.count ?? scenes.count
            for scene in scenes {
                guard let id = scene.id else { continue }
                var perDay: [String: Int] = [:]
                for stamp in scene.o_history ?? [] {
                    guard let date = stamp.date else { continue }
                    perDay[Self.dayKey(date, calendar: calendar), default: 0] += 1
                }
                if perDay.isEmpty, (scene.o_counter ?? 0) > 0,
                   let created = scene.created_at.flatMap(Self.parseTimestamp) {
                    perDay[Self.dayKey(created, calendar: calendar), default: 0] += scene.o_counter ?? 0
                }
                for (key, amount) in perDay {
                    buckets.add(
                        kind: .scene,
                        stashID: id,
                        title: scene.title,
                        thumbnailPath: scene.paths?.screenshot,
                        studio: scene.studio?.asSceneStudio,
                        dayKey: key,
                        amount: amount
                    )
                }
            }
            if scenes.isEmpty { break }
            page += 1
            if page > 200 { break }
        }
        return buckets
    }

    private func fetchCountsByDayWithoutHistory() async throws -> OCountDayBuckets {
        let query = """
        query FindSceneOCounters($filter: FindFilterType, $scene_filter: SceneFilterType) {
          findScenes(filter: $filter, scene_filter: $scene_filter) {
            count
            scenes {
              id
              title
              o_counter
              created_at
              updated_at
              paths { screenshot }
              studio { id name }
            }
          }
        }
        """
        var page = 1
        let perPage = 500
        var buckets = OCountDayBuckets()
        var total = Int.max

        while (page - 1) * perPage < total {
            let variables: [String: Any] = [
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
            let response: OCounterFallbackResponse = try await GraphQLClient.shared.execute(
                query: query,
                variables: variables
            )
            let scenes = response.data?.findScenes?.scenes ?? []
            total = response.data?.findScenes?.count ?? scenes.count
            for scene in scenes {
                guard let id = scene.id else { continue }
                let stamp = scene.created_at ?? scene.updated_at
                guard let date = stamp.flatMap(Self.parseTimestamp) else { continue }
                buckets.add(
                    kind: .scene,
                    stashID: id,
                    title: scene.title,
                    thumbnailPath: scene.paths?.screenshot,
                    studio: scene.studio?.asSceneStudio,
                    dayKey: Self.dayKey(date, calendar: calendar),
                    amount: scene.o_counter ?? 0
                )
            }
            if scenes.isEmpty { break }
            page += 1
            if page > 200 { break }
        }
        return buckets
    }

    private func fetchImageCountsByDay() async throws -> OCountDayBuckets {
        let query = """
        query FindImageOCounters($filter: FindFilterType, $image_filter: ImageFilterType) {
          findImages(filter: $filter, image_filter: $image_filter) {
            count
            images {
              id
              title
              o_counter
              rating100
              created_at
              updated_at
              paths { thumbnail preview image }
              visual_files {
                ... on BaseFile { __typename path basename }
                ... on ImageFile { __typename path height width basename }
                ... on VideoFile { __typename path height width duration basename }
              }
              performers { id name image_path }
            }
          }
        }
        """
        var page = 1
        let perPage = 500
        var buckets = OCountDayBuckets()
        var total = Int.max

        while (page - 1) * perPage < total {
            let variables: [String: Any] = [
                "filter": [
                    "page": page,
                    "per_page": perPage,
                    "sort": "o_counter",
                    "direction": "DESC"
                ],
                "image_filter": [
                    "o_counter": [
                        "value": 0,
                        "modifier": "GREATER_THAN"
                    ]
                ]
            ]
            let response: ImageOCounterResponse = try await GraphQLClient.shared.execute(
                query: query,
                variables: variables
            )
            if let errors = response.errors, !errors.isEmpty {
                let message = errors.compactMap(\.message).joined(separator: "; ")
                throw GraphQLNetworkError.graphQLError(message: message.isEmpty ? "Query failed" : message)
            }
            let images = response.data?.findImages?.images ?? []
            total = response.data?.findImages?.count ?? images.count
            for image in images {
                guard let id = image.id else { continue }
                let stamp = image.created_at ?? image.updated_at
                guard let date = stamp.flatMap(Self.parseTimestamp) else { continue }
                buckets.add(
                    kind: .image,
                    stashID: id,
                    title: image.title,
                    thumbnailPath: image.paths?.thumbnail ?? image.paths?.preview ?? image.paths?.image,
                    previewPath: image.paths?.preview,
                    imagePath: image.paths?.image,
                    visualFiles: image.visual_files?.compactMap(\.asImageFile),
                    performers: image.performers?.compactMap(\.asGalleryPerformer) ?? [],
                    rating100: image.rating100,
                    dayKey: Self.dayKey(date, calendar: calendar),
                    amount: image.o_counter ?? 0
                )
            }
            if images.isEmpty { break }
            page += 1
            if page > 200 { break }
        }
        return buckets
    }

    nonisolated static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    nonisolated static func parseDayKey(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    nonisolated static func parseTimestamp(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let value = Double(trimmed), value > 1_000_000_000 {
            let seconds = value > 1_000_000_000_000 ? value / 1000 : value
            return Date(timeIntervalSince1970: seconds)
        }

        if let date = OCountTimestamp.fractional.date(from: trimmed) { return date }
        if let date = OCountTimestamp.plain.date(from: trimmed) { return date }

        if let collapsed = OCountTimestamp.collapseFractionalSeconds(trimmed) {
            if let date = OCountTimestamp.fractional.date(from: collapsed) { return date }
            if let date = OCountTimestamp.plain.date(from: collapsed) { return date }
            for formatter in OCountTimestamp.posixFormatters {
                if let date = formatter.date(from: collapsed) { return date }
            }
        }

        for formatter in OCountTimestamp.posixFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }

        if trimmed.count >= 10 {
            let prefix = String(trimmed.prefix(10))
            if let date = OCountTimestamp.dayOnly.date(from: prefix) { return date }
        }
        return nil
    }
}

private struct OCountDayBuckets {
    var counts: [String: Int] = [:]
    var items: [String: [OCountHeatmapItem]] = [:]

    mutating func add(
        kind: OCountHeatmapItem.Kind,
        stashID: String,
        title: String?,
        thumbnailPath: String?,
        previewPath: String? = nil,
        imagePath: String? = nil,
        visualFiles: [ImageFile]? = nil,
        performers: [GalleryPerformer] = [],
        studio: SceneStudio? = nil,
        rating100: Int? = nil,
        dayKey: String,
        amount: Int
    ) {
        guard amount > 0, !stashID.isEmpty else { return }
        counts[dayKey, default: 0] += amount
        var list = items[dayKey] ?? []
        if let idx = list.firstIndex(where: { $0.kind == kind && $0.stashID == stashID }) {
            list[idx].countOnDay += amount
        } else {
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            list.append(
                OCountHeatmapItem(
                    kind: kind,
                    stashID: stashID,
                    title: trimmed.isEmpty ? "Untitled" : trimmed,
                    thumbnailPath: thumbnailPath,
                    previewPath: previewPath,
                    imagePath: imagePath,
                    visualFiles: visualFiles,
                    performers: performers,
                    studio: studio,
                    rating100: rating100,
                    countOnDay: amount
                )
            )
        }
        items[dayKey] = list
    }

    mutating func merge(_ other: OCountDayBuckets) {
        for (dayKey, list) in other.items {
            for item in list {
                add(
                    kind: item.kind,
                    stashID: item.stashID,
                    title: item.title,
                    thumbnailPath: item.thumbnailPath,
                    previewPath: item.previewPath,
                    imagePath: item.imagePath,
                    visualFiles: item.visualFiles,
                    performers: item.performers,
                    studio: item.studio,
                    rating100: item.rating100,
                    dayKey: dayKey,
                    amount: item.countOnDay
                )
            }
        }
    }
}

private enum OCountTimestamp {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func posixFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    static let dayOnly: DateFormatter = {
        posixFormatter("yyyy-MM-dd")
    }()

    static let posixFormatters: [DateFormatter] = [
        posixFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSSXXXXX"),
        posixFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"),
        posixFormatter("yyyy-MM-dd'T'HH:mm:ssXXXXX"),
        posixFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSSZ"),
        posixFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSZ"),
        posixFormatter("yyyy-MM-dd'T'HH:mm:ssZ"),
        posixFormatter("yyyy-MM-dd HH:mm:ss"),
        posixFormatter("yyyy-MM-dd")
    ]

    static func collapseFractionalSeconds(_ raw: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\.(\\d+)"),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let fracRange = Range(match.range(at: 1), in: raw),
              let fullRange = Range(match.range(at: 0), in: raw) else {
            return nil
        }
        let digits = String(raw[fracRange].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        var normalized = raw
        normalized.replaceSubrange(fullRange, with: ".\(digits)")
        return normalized
    }
}

struct OCountMonthHeatmap {
    struct Cell: Identifiable {
        let id: String
        let column: Int
        let row: Int
        let day: Int
        let isInDisplayedMonth: Bool
        let count: Int
        let colorLevel: Int
        let accessibilityLabel: String
    }

    let year: Int
    let month: Int
    let monthTitle: String
    let rowCount: Int
    let columnCount: Int
    let daysWithOCount: Int
    let totalInMonth: Int
    let cells: [Cell]

    static let empty = OCountMonthHeatmap(
        year: 0,
        month: 0,
        monthTitle: "",
        rowCount: 6,
        columnCount: 7,
        daysWithOCount: 0,
        totalInMonth: 0,
        cells: []
    )

    func cell(column: Int, row: Int) -> Cell? {
        cells.first { $0.column == column && $0.row == row }
    }

    static func build(
        countsByDay: [String: Int],
        monthContaining date: Date,
        calendar: Calendar,
        locale: Locale,
        globalMax: Int
    ) -> OCountMonthHeatmap {
        var cal = calendar
        cal.locale = locale
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: date)),
              let dayCount = cal.range(of: .day, in: .month, for: monthStart)?.count else {
            return .empty
        }

        let year = cal.component(.year, from: monthStart)
        let month = cal.component(.month, from: monthStart)
        let leading = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        let rowCount = (leading + dayCount + 6) / 7
        let slotCount = rowCount * 7

        let monthFormatter = DateFormatter()
        monthFormatter.locale = locale
        monthFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        let prettyFormatter = DateFormatter()
        prettyFormatter.locale = locale
        prettyFormatter.dateStyle = .medium
        prettyFormatter.timeStyle = .none

        var staged: [(col: Int, row: Int, key: String, date: Date, day: Int, count: Int, inMonth: Bool)] = []

        for slot in 0..<slotCount {
            let dayOffset = slot - leading
            guard let cellDate = cal.date(byAdding: .day, value: dayOffset, to: monthStart) else { continue }
            let inMonth = dayOffset >= 0 && dayOffset < dayCount
            let key = OCountHeatmapLoader.dayKey(cellDate, calendar: cal)
            let count = inMonth ? countsByDay[key, default: 0] : 0
            staged.append((slot % 7, slot / 7, key, cellDate, cal.component(.day, from: cellDate), count, inMonth))
        }

        let maxValue = max(globalMax, staged.map(\.count).max() ?? 0)
        var daysWithOCount = 0
        var totalInMonth = 0
        var cells: [Cell] = []
        cells.reserveCapacity(staged.count)

        for item in staged {
            if item.inMonth {
                if item.count > 0 { daysWithOCount += 1 }
                totalInMonth += item.count
            }
            let level = colorLevel(count: item.inMonth ? item.count : 0, maxValue: maxValue)
            let pretty = prettyFormatter.string(from: item.date)
            let a11y: String
            if !item.inMonth {
                a11y = "\(pretty), outside month"
            } else if item.count > 0 {
                a11y = "\(pretty), \(item.count) O-Count"
            } else {
                a11y = "\(pretty), no O-Count"
            }
            cells.append(
                Cell(
                    id: item.key,
                    column: item.col,
                    row: item.row,
                    day: item.day,
                    isInDisplayedMonth: item.inMonth,
                    count: item.count,
                    colorLevel: level,
                    accessibilityLabel: a11y
                )
            )
        }

        return OCountMonthHeatmap(
            year: year,
            month: month,
            monthTitle: monthFormatter.string(from: monthStart),
            rowCount: rowCount,
            columnCount: 7,
            daysWithOCount: daysWithOCount,
            totalInMonth: totalInMonth,
            cells: cells
        )
    }

    private static func colorLevel(count: Int, maxValue: Int) -> Int {
        guard count > 0, maxValue > 0 else { return 0 }
        if maxValue <= 1 { return 4 }
        let ratio = log(Double(count) + 1) / log(Double(maxValue) + 1)
        return min(4, max(1, Int(ceil(ratio * 4.0))))
    }
}

private struct OHistoryResponse: Decodable {
    let data: DataPayload?
    let errors: [GraphQLErrorMessage]?

    struct DataPayload: Decodable {
        let findScenes: FindScenes?
    }

    struct FindScenes: Decodable {
        let count: Int?
        let scenes: [SceneOHistory]?
    }

    struct SceneOHistory: Decodable {
        let id: String?
        let title: String?
        let o_counter: Int?
        let created_at: String?
        let o_history: [FlexibleJSONTime]?
        let paths: OCountPathsPayload?
        let studio: OCountStudioPayload?
    }

    struct GraphQLErrorMessage: Decodable {
        let message: String?
    }
}

private struct OCounterFallbackResponse: Decodable {
    let data: DataPayload?

    struct DataPayload: Decodable {
        let findScenes: FindScenes?
    }

    struct FindScenes: Decodable {
        let count: Int?
        let scenes: [SceneOCounter]?
    }

    struct SceneOCounter: Decodable {
        let id: String?
        let title: String?
        let o_counter: Int?
        let created_at: String?
        let updated_at: String?
        let paths: OCountPathsPayload?
        let studio: OCountStudioPayload?
    }
}

private struct ImageOCounterResponse: Decodable {
    let data: DataPayload?
    let errors: [OHistoryResponse.GraphQLErrorMessage]?

    struct DataPayload: Decodable {
        let findImages: FindImages?
    }

    struct FindImages: Decodable {
        let count: Int?
        let images: [ImageOCounter]?
    }

    struct ImageOCounter: Decodable {
        let id: String?
        let title: String?
        let o_counter: Int?
        let rating100: Int?
        let created_at: String?
        let updated_at: String?
        let paths: OCountPathsPayload?
        let visual_files: [OCountVisualFile]?
        let performers: [OCountPerformerPayload]?
    }
}

private struct OCountStudioPayload: Decodable {
    let id: String?
    let name: String?

    var asSceneStudio: SceneStudio? {
        guard let id, let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return SceneStudio(id: id, name: trimmed, updatedAt: nil)
    }
}

private struct OCountPerformerPayload: Decodable {
    let id: String?
    let name: String?
    let image_path: String?

    var asGalleryPerformer: GalleryPerformer? {
        guard let id, let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return GalleryPerformer(id: id, name: trimmed, image_path: image_path)
    }
}

private struct OCountVisualFile: Decodable {
    let path: String?
    let height: Int?
    let width: Int?
    let duration: Double?
    let basename: String?

    var asImageFile: ImageFile? {
        guard let path, !path.isEmpty else { return nil }
        return ImageFile(
            path: path,
            height: height,
            width: width,
            duration: duration,
            basename: basename
        )
    }
}

private struct OCountPathsPayload: Decodable {
    let screenshot: String?
    let thumbnail: String?
    let preview: String?
    let image: String?
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
