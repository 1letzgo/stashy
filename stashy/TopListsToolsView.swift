//
//  TopListsToolsView.swift
//  stashy
//
//  Statistics subviews: ranked Charts lists with infinite scroll.
//

#if !os(tvOS)
import SwiftUI

private protocol TopListsMetricLabel {
    var label: String { get }
}

private let topListPageSize = 25

private struct TopListPage {
    var nextPage: Int
    var hasMore: Bool

    static func afterFirstPage(count: Int, total: Int) -> TopListPage {
        TopListPage(nextPage: 2, hasMore: count > 0 && count < total)
    }

    static var exhausted: TopListPage { TopListPage(nextPage: 1, hasMore: false) }
}

enum SceneTopMetric: String, CaseIterable, Identifiable, TopListsMetricLabel {
    case views
    case oCount
    case watchTime
    case rating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .views: return "Views"
        case .oCount: return "O-Count"
        case .watchTime: return "Watch Time"
        case .rating: return "Rating"
        }
    }

    var sort: StashDBViewModel.SceneSortOption {
        switch self {
        case .views: return .playCountDesc
        case .oCount: return .oCounterDesc
        case .watchTime: return .playDurationDesc
        case .rating: return .ratingDesc
        }
    }
}

enum PerformerTopMetric: String, CaseIterable, Identifiable, TopListsMetricLabel {
    case oCount
    case scenes
    case rating
    case images
    case galleries

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oCount: return "O-Count"
        case .scenes: return "Scenes"
        case .rating: return "Rating"
        case .images: return "Images"
        case .galleries: return "Galleries"
        }
    }

    var sort: StashDBViewModel.PerformerSortOption {
        switch self {
        case .oCount: return .oCountDesc
        case .scenes: return .sceneCountDesc
        case .rating: return .ratingDesc
        case .images: return .imageCountDesc
        case .galleries: return .galleryCountDesc
        }
    }
}

enum StudioTopMetric: String, CaseIterable, Identifiable, TopListsMetricLabel {
    case scenes
    case galleries
    case rating
    case images

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scenes: return "Scenes"
        case .galleries: return "Galleries"
        case .rating: return "Rating"
        case .images: return "Images"
        }
    }

    var sort: StashDBViewModel.StudioSortOption {
        switch self {
        case .scenes: return .sceneCountDesc
        case .galleries: return .galleryCountDesc
        case .rating: return .ratingDesc
        case .images: return .imageCountDesc
        }
    }
}

enum TagTopMetric: String, CaseIterable, Identifiable, TopListsMetricLabel {
    case scenes
    case images
    case galleries
    case markers

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scenes: return "Scenes"
        case .images: return "Images"
        case .galleries: return "Galleries"
        case .markers: return "Markers"
        }
    }

    var sort: StashDBViewModel.TagSortOption {
        switch self {
        case .scenes: return .sceneCountDesc
        case .images: return .imageCountDesc
        case .galleries: return .galleryCountDesc
        case .markers: return .markerCountDesc
        }
    }
}

@MainActor
final class TopListsViewModel: ObservableObject {
    @Published var scenesByViews: [Scene] = []
    @Published var scenesByOCount: [Scene] = []
    @Published var scenesByWatchTime: [Scene] = []
    @Published var scenesByRating: [Scene] = []
    @Published var performersByOCount: [Performer] = []
    @Published var performersByScenes: [Performer] = []
    @Published var performersByRating: [Performer] = []
    @Published var performersByImages: [Performer] = []
    @Published var performersByGalleries: [Performer] = []
    @Published var studiosByScenes: [Studio] = []
    @Published var studiosByGalleries: [Studio] = []
    @Published var studiosByRating: [Studio] = []
    @Published var studiosByImages: [Studio] = []
    @Published var tagsByScenes: [Tag] = []
    @Published var tagsByImages: [Tag] = []
    @Published var tagsByGalleries: [Tag] = []
    @Published var tagsByMarkers: [Tag] = []
    @Published var sceneMetric: SceneTopMetric = .watchTime
    @Published var performerMetric: PerformerTopMetric = .oCount
    @Published var studioMetric: StudioTopMetric = .scenes
    @Published var tagMetric: TagTopMetric = .scenes
    @Published var isLoadingScenes = false
    @Published var isLoadingPerformers = false
    @Published var isLoadingStudios = false
    @Published var isLoadingTags = false
    @Published var isLoadingMoreScenes = false
    @Published var isLoadingMorePerformers = false
    @Published var isLoadingMoreStudios = false
    @Published var isLoadingMoreTags = false
    @Published var didFailScenes = false
    @Published var didFailPerformers = false
    @Published var didFailStudios = false
    @Published var didFailTags = false

    var hasScenesContent: Bool {
        !scenesByViews.isEmpty || !scenesByOCount.isEmpty
            || !scenesByWatchTime.isEmpty || !scenesByRating.isEmpty
    }

    var hasPerformersContent: Bool {
        !performersByOCount.isEmpty || !performersByScenes.isEmpty
            || !performersByRating.isEmpty || !performersByImages.isEmpty
            || !performersByGalleries.isEmpty
    }

    var hasStudiosContent: Bool {
        !studiosByScenes.isEmpty || !studiosByGalleries.isEmpty
            || !studiosByRating.isEmpty || !studiosByImages.isEmpty
    }

    var hasTagsContent: Bool {
        !tagsByScenes.isEmpty || !tagsByImages.isEmpty
            || !tagsByGalleries.isEmpty || !tagsByMarkers.isEmpty
    }

    var scenesForSelectedMetric: [Scene] {
        switch sceneMetric {
        case .views: return scenesByViews
        case .oCount: return scenesByOCount
        case .watchTime: return scenesByWatchTime
        case .rating: return scenesByRating
        }
    }

    var performersForSelectedMetric: [Performer] {
        switch performerMetric {
        case .oCount: return performersByOCount
        case .scenes: return performersByScenes
        case .rating: return performersByRating
        case .images: return performersByImages
        case .galleries: return performersByGalleries
        }
    }

    var studiosForSelectedMetric: [Studio] {
        switch studioMetric {
        case .scenes: return studiosByScenes
        case .galleries: return studiosByGalleries
        case .rating: return studiosByRating
        case .images: return studiosByImages
        }
    }

    var tagsForSelectedMetric: [Tag] {
        switch tagMetric {
        case .scenes: return tagsByScenes
        case .images: return tagsByImages
        case .galleries: return tagsByGalleries
        case .markers: return tagsByMarkers
        }
    }

    var hasMoreScenes: Bool { scenePaging[sceneMetric]?.hasMore ?? false }
    var hasMorePerformers: Bool { performerPaging[performerMetric]?.hasMore ?? false }
    var hasMoreStudios: Bool { studioPaging[studioMetric]?.hasMore ?? false }
    var hasMoreTags: Bool { tagPaging[tagMetric]?.hasMore ?? false }

    private let sceneRepository = SceneRepository()
    private let performerRepository = PerformerRepository()
    private let studioRepository = StudioRepository()
    private let tagRepository = TagRepository()
    private var scenePaging: [SceneTopMetric: TopListPage] = [:]
    private var performerPaging: [PerformerTopMetric: TopListPage] = [:]
    private var studioPaging: [StudioTopMetric: TopListPage] = [:]
    private var tagPaging: [TagTopMetric: TopListPage] = [:]
    private var sceneOCounterObserver: NSObjectProtocol?
    private var sceneUpdatedObserver: NSObjectProtocol?
    private var sceneCoverObserver: NSObjectProtocol?
    private var scenesFetchGeneration = 0
    private var performersFetchGeneration = 0
    private var studiosFetchGeneration = 0
    private var tagsFetchGeneration = 0

    init() {
        sceneOCounterObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SceneOCounterUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let sceneId = notification.userInfo?["sceneId"] as? String,
                  let oCounter = notification.userInfo?["oCounter"] as? Int else { return }
            Task { @MainActor in
                self?.patchSceneOCounter(sceneId: sceneId, oCounter: oCounter)
            }
        }
        sceneUpdatedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SceneUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = Scene.fromListMetadataNotification(notification) else { return }
            Task { @MainActor in
                self?.patchSceneMetadata(scene)
            }
        }
        sceneCoverObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SceneCoverUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let sceneId = notification.userInfo?["sceneId"] as? String,
                  let updatedAt = notification.userInfo?["updatedAt"] as? String else { return }
            Task { @MainActor in
                self?.patchSceneCover(sceneId: sceneId, updatedAt: updatedAt)
            }
        }
    }

    deinit {
        if let sceneOCounterObserver {
            NotificationCenter.default.removeObserver(sceneOCounterObserver)
        }
        if let sceneUpdatedObserver {
            NotificationCenter.default.removeObserver(sceneUpdatedObserver)
        }
        if let sceneCoverObserver {
            NotificationCenter.default.removeObserver(sceneCoverObserver)
        }
    }

    func reloadScenes() async {
        scenesFetchGeneration += 1
        let generation = scenesFetchGeneration
        isLoadingScenes = true
        didFailScenes = false
        defer {
            if generation == scenesFetchGeneration {
                isLoadingScenes = false
            }
        }

        async let viewed = fetchScenes(sortedBy: .playCountDesc)
        async let oScenes = fetchScenes(sortedBy: .oCounterDesc)
        async let watch = fetchScenes(sortedBy: .playDurationDesc)
        async let rating = fetchScenes(sortedBy: .ratingDesc)

        let viewedResult = await viewed
        let oScenesResult = await oScenes
        let watchResult = await watch
        let ratingResult = await rating
        guard generation == scenesFetchGeneration else { return }

        store(viewedResult, metric: .views, into: &scenesByViews, paging: &scenePaging)
        store(oScenesResult, metric: .oCount, into: &scenesByOCount, paging: &scenePaging)
        store(watchResult, metric: .watchTime, into: &scenesByWatchTime, paging: &scenePaging)
        store(ratingResult, metric: .rating, into: &scenesByRating, paging: &scenePaging)

        let anySuccess = viewedResult != nil || oScenesResult != nil
            || watchResult != nil || ratingResult != nil
        didFailScenes = !anySuccess
    }

    func reloadPerformers() async {
        performersFetchGeneration += 1
        let generation = performersFetchGeneration
        isLoadingPerformers = true
        didFailPerformers = false
        defer {
            if generation == performersFetchGeneration {
                isLoadingPerformers = false
            }
        }

        async let oCount = fetchPerformers(sortedBy: .oCountDesc)
        async let scenes = fetchPerformers(sortedBy: .sceneCountDesc)
        async let rating = fetchPerformers(sortedBy: .ratingDesc)
        async let images = fetchPerformers(sortedBy: .imageCountDesc)
        async let galleries = fetchPerformers(sortedBy: .galleryCountDesc)

        let oCountResult = await oCount
        let scenesResult = await scenes
        let ratingResult = await rating
        let imagesResult = await images
        let galleriesResult = await galleries
        guard generation == performersFetchGeneration else { return }

        store(oCountResult, metric: .oCount, into: &performersByOCount, paging: &performerPaging)
        store(scenesResult, metric: .scenes, into: &performersByScenes, paging: &performerPaging)
        store(ratingResult, metric: .rating, into: &performersByRating, paging: &performerPaging)
        store(imagesResult, metric: .images, into: &performersByImages, paging: &performerPaging)
        store(galleriesResult, metric: .galleries, into: &performersByGalleries, paging: &performerPaging)

        let anySuccess = oCountResult != nil || scenesResult != nil
            || ratingResult != nil || imagesResult != nil || galleriesResult != nil
        didFailPerformers = !anySuccess
    }

    func reloadStudios() async {
        studiosFetchGeneration += 1
        let generation = studiosFetchGeneration
        isLoadingStudios = true
        didFailStudios = false
        defer {
            if generation == studiosFetchGeneration {
                isLoadingStudios = false
            }
        }

        async let scenes = fetchStudios(sortedBy: .sceneCountDesc)
        async let galleries = fetchStudios(sortedBy: .galleryCountDesc)
        async let rating = fetchStudios(sortedBy: .ratingDesc)
        async let images = fetchStudios(sortedBy: .imageCountDesc)

        let scenesResult = await scenes
        let galleriesResult = await galleries
        let ratingResult = await rating
        let imagesResult = await images
        guard generation == studiosFetchGeneration else { return }

        store(scenesResult, metric: .scenes, into: &studiosByScenes, paging: &studioPaging)
        store(galleriesResult, metric: .galleries, into: &studiosByGalleries, paging: &studioPaging)
        store(ratingResult, metric: .rating, into: &studiosByRating, paging: &studioPaging)
        store(imagesResult, metric: .images, into: &studiosByImages, paging: &studioPaging)

        let anySuccess = scenesResult != nil || galleriesResult != nil
            || ratingResult != nil || imagesResult != nil
        didFailStudios = !anySuccess
    }

    func reloadTags() async {
        tagsFetchGeneration += 1
        let generation = tagsFetchGeneration
        isLoadingTags = true
        didFailTags = false
        defer {
            if generation == tagsFetchGeneration {
                isLoadingTags = false
            }
        }

        async let scenes = fetchTags(sortedBy: .sceneCountDesc)
        async let images = fetchTags(sortedBy: .imageCountDesc)
        async let galleries = fetchTags(sortedBy: .galleryCountDesc)
        async let markers = fetchTags(sortedBy: .markerCountDesc)

        let scenesResult = await scenes
        let imagesResult = await images
        let galleriesResult = await galleries
        let markersResult = await markers
        guard generation == tagsFetchGeneration else { return }

        store(scenesResult, metric: .scenes, into: &tagsByScenes, paging: &tagPaging)
        store(imagesResult, metric: .images, into: &tagsByImages, paging: &tagPaging)
        store(galleriesResult, metric: .galleries, into: &tagsByGalleries, paging: &tagPaging)
        store(markersResult, metric: .markers, into: &tagsByMarkers, paging: &tagPaging)

        let anySuccess = scenesResult != nil || imagesResult != nil
            || galleriesResult != nil || markersResult != nil
        didFailTags = !anySuccess
    }

    func loadMoreScenes() async {
        guard !isLoadingScenes, !isLoadingMoreScenes else { return }
        let metric = sceneMetric
        guard let paging = scenePaging[metric], paging.hasMore else { return }
        isLoadingMoreScenes = true
        defer { isLoadingMoreScenes = false }
        guard let result = await fetchScenes(sortedBy: metric.sort, page: paging.nextPage) else { return }
        switch metric {
        case .views: appendUnique(result.items, onto: &scenesByViews)
        case .oCount: appendUnique(result.items, onto: &scenesByOCount)
        case .watchTime: appendUnique(result.items, onto: &scenesByWatchTime)
        case .rating: appendUnique(result.items, onto: &scenesByRating)
        }
        scenePaging[metric] = TopListPage(
            nextPage: paging.nextPage + 1,
            hasMore: !result.items.isEmpty && scenesCount(for: metric) < result.total
        )
    }

    func loadMorePerformers() async {
        guard !isLoadingPerformers, !isLoadingMorePerformers else { return }
        let metric = performerMetric
        guard let paging = performerPaging[metric], paging.hasMore else { return }
        isLoadingMorePerformers = true
        defer { isLoadingMorePerformers = false }
        guard let result = await fetchPerformers(sortedBy: metric.sort, page: paging.nextPage) else { return }
        switch metric {
        case .oCount: appendUnique(result.items, onto: &performersByOCount)
        case .scenes: appendUnique(result.items, onto: &performersByScenes)
        case .rating: appendUnique(result.items, onto: &performersByRating)
        case .images: appendUnique(result.items, onto: &performersByImages)
        case .galleries: appendUnique(result.items, onto: &performersByGalleries)
        }
        performerPaging[metric] = TopListPage(
            nextPage: paging.nextPage + 1,
            hasMore: !result.items.isEmpty && performersCount(for: metric) < result.total
        )
    }

    func loadMoreStudios() async {
        guard !isLoadingStudios, !isLoadingMoreStudios else { return }
        let metric = studioMetric
        guard let paging = studioPaging[metric], paging.hasMore else { return }
        isLoadingMoreStudios = true
        defer { isLoadingMoreStudios = false }
        guard let result = await fetchStudios(sortedBy: metric.sort, page: paging.nextPage) else { return }
        switch metric {
        case .scenes: appendUnique(result.items, onto: &studiosByScenes)
        case .galleries: appendUnique(result.items, onto: &studiosByGalleries)
        case .rating: appendUnique(result.items, onto: &studiosByRating)
        case .images: appendUnique(result.items, onto: &studiosByImages)
        }
        studioPaging[metric] = TopListPage(
            nextPage: paging.nextPage + 1,
            hasMore: !result.items.isEmpty && studiosCount(for: metric) < result.total
        )
    }

    func loadMoreTags() async {
        guard !isLoadingTags, !isLoadingMoreTags else { return }
        let metric = tagMetric
        guard let paging = tagPaging[metric], paging.hasMore else { return }
        isLoadingMoreTags = true
        defer { isLoadingMoreTags = false }
        guard let result = await fetchTags(sortedBy: metric.sort, page: paging.nextPage) else { return }
        switch metric {
        case .scenes: appendUnique(result.items, onto: &tagsByScenes)
        case .images: appendUnique(result.items, onto: &tagsByImages)
        case .galleries: appendUnique(result.items, onto: &tagsByGalleries)
        case .markers: appendUnique(result.items, onto: &tagsByMarkers)
        }
        tagPaging[metric] = TopListPage(
            nextPage: paging.nextPage + 1,
            hasMore: !result.items.isEmpty && tagsCount(for: metric) < result.total
        )
    }

    func reset() {
        scenesFetchGeneration += 1
        performersFetchGeneration += 1
        studiosFetchGeneration += 1
        tagsFetchGeneration += 1
        scenePaging = [:]
        performerPaging = [:]
        studioPaging = [:]
        tagPaging = [:]
        scenesByViews = []
        scenesByOCount = []
        scenesByWatchTime = []
        scenesByRating = []
        performersByOCount = []
        performersByScenes = []
        performersByRating = []
        performersByImages = []
        performersByGalleries = []
        studiosByScenes = []
        studiosByGalleries = []
        studiosByRating = []
        studiosByImages = []
        tagsByScenes = []
        tagsByImages = []
        tagsByGalleries = []
        tagsByMarkers = []
        didFailScenes = false
        didFailPerformers = false
        didFailStudios = false
        didFailTags = false
        isLoadingScenes = false
        isLoadingPerformers = false
        isLoadingStudios = false
        isLoadingTags = false
        isLoadingMoreScenes = false
        isLoadingMorePerformers = false
        isLoadingMoreStudios = false
        isLoadingMoreTags = false
    }

    private func patchSceneOCounter(sceneId: String, oCounter: Int) {
        let performerIds = [scenesByViews, scenesByOCount, scenesByWatchTime, scenesByRating]
            .compactMap { $0.first(where: { $0.id == sceneId }) }
            .first?
            .performers
            .map(\.id) ?? []
        let previous = [scenesByViews, scenesByOCount, scenesByWatchTime, scenesByRating]
            .compactMap { $0.first(where: { $0.id == sceneId })?.oCounter }
            .first
        func patch(_ list: inout [Scene]) {
            guard let idx = list.firstIndex(where: { $0.id == sceneId }) else { return }
            guard list[idx].oCounter != oCounter else { return }
            list[idx] = list[idx].withOCounter(oCounter)
        }
        patch(&scenesByViews)
        patch(&scenesByOCount)
        patch(&scenesByWatchTime)
        patch(&scenesByRating)
        scenesByOCount.sort { ($0.oCounter ?? 0) > ($1.oCounter ?? 0) }

        let delta = oCounter - (previous ?? oCounter)
        guard delta != 0, !performerIds.isEmpty else { return }
        func bump(_ list: inout [Performer]) {
            for id in performerIds {
                guard let idx = list.firstIndex(where: { $0.id == id }) else { continue }
                list[idx] = list[idx].withOCounter((list[idx].oCounter ?? 0) + delta)
            }
        }
        bump(&performersByOCount)
        bump(&performersByScenes)
        bump(&performersByRating)
        bump(&performersByImages)
        bump(&performersByGalleries)
        performersByOCount.sort { ($0.oCounter ?? 0) > ($1.oCounter ?? 0) }
    }

    private func patchSceneMetadata(_ scene: Scene) {
        func patch(_ list: inout [Scene]) {
            guard let idx = list.firstIndex(where: { $0.id == scene.id }) else { return }
            list[idx] = list[idx].mergingListMetadata(from: scene)
        }
        patch(&scenesByViews)
        patch(&scenesByOCount)
        patch(&scenesByWatchTime)
        patch(&scenesByRating)
        scenesByRating.sort { ($0.rating100 ?? 0) > ($1.rating100 ?? 0) }
    }

    private func patchSceneCover(sceneId: String, updatedAt: String) {
        func patched(_ list: [Scene]) -> [Scene] {
            guard let idx = list.firstIndex(where: { $0.id == sceneId }) else { return list }
            guard list[idx].updatedAt != updatedAt else { return list }
            var copy = list
            copy[idx] = copy[idx].withUpdatedAt(updatedAt)
            return copy
        }
        let views = patched(scenesByViews)
        if views != scenesByViews { scenesByViews = views }
        let oCount = patched(scenesByOCount)
        if oCount != scenesByOCount { scenesByOCount = oCount }
        let watch = patched(scenesByWatchTime)
        if watch != scenesByWatchTime { scenesByWatchTime = watch }
        let rating = patched(scenesByRating)
        if rating != scenesByRating { scenesByRating = rating }
    }

    private func fetchScenes(sortedBy sort: StashDBViewModel.SceneSortOption, page: Int = 1) async -> (items: [Scene], total: Int)? {
        do {
            let result = try await sceneRepository.fetchScenes(
                page: page,
                perPage: topListPageSize,
                sortBy: sort,
                searchQuery: "",
                filter: nil
            )
            return (result.scenes, result.total)
        } catch {
            return nil
        }
    }

    private func fetchPerformers(sortedBy sort: StashDBViewModel.PerformerSortOption, page: Int = 1) async -> (items: [Performer], total: Int)? {
        do {
            let result = try await performerRepository.fetchPerformers(
                page: page,
                perPage: topListPageSize,
                sortBy: sort,
                searchQuery: "",
                filter: nil
            )
            return (result.performers, result.total)
        } catch {
            return nil
        }
    }

    private func fetchStudios(sortedBy sort: StashDBViewModel.StudioSortOption, page: Int = 1) async -> (items: [Studio], total: Int)? {
        do {
            let result = try await studioRepository.fetchStudios(
                page: page,
                perPage: topListPageSize,
                sortBy: sort,
                searchQuery: "",
                filter: nil
            )
            return (result.studios, result.total)
        } catch {
            return nil
        }
    }

    private func fetchTags(sortedBy sort: StashDBViewModel.TagSortOption, page: Int = 1) async -> (items: [Tag], total: Int)? {
        do {
            let result = try await tagRepository.fetchTags(
                page: page,
                perPage: topListPageSize,
                sortBy: sort,
                searchQuery: "",
                filter: nil
            )
            return (result.tags, result.total)
        } catch {
            return nil
        }
    }

    private func store<Item, Metric: Hashable>(
        _ result: (items: [Item], total: Int)?,
        metric: Metric,
        into list: inout [Item],
        paging: inout [Metric: TopListPage]
    ) {
        if let result {
            list = result.items
            paging[metric] = .afterFirstPage(count: result.items.count, total: result.total)
        } else {
            list = []
            paging[metric] = .exhausted
        }
    }

    private func appendUnique<Item: Identifiable>(_ incoming: [Item], onto list: inout [Item]) where Item.ID: Hashable {
        var seen = Set(list.map(\.id))
        for item in incoming where seen.insert(item.id).inserted {
            list.append(item)
        }
    }

    private func scenesCount(for metric: SceneTopMetric) -> Int {
        switch metric {
        case .views: return scenesByViews.count
        case .oCount: return scenesByOCount.count
        case .watchTime: return scenesByWatchTime.count
        case .rating: return scenesByRating.count
        }
    }

    private func performersCount(for metric: PerformerTopMetric) -> Int {
        switch metric {
        case .oCount: return performersByOCount.count
        case .scenes: return performersByScenes.count
        case .rating: return performersByRating.count
        case .images: return performersByImages.count
        case .galleries: return performersByGalleries.count
        }
    }

    private func studiosCount(for metric: StudioTopMetric) -> Int {
        switch metric {
        case .scenes: return studiosByScenes.count
        case .galleries: return studiosByGalleries.count
        case .rating: return studiosByRating.count
        case .images: return studiosByImages.count
        }
    }

    private func tagsCount(for metric: TagTopMetric) -> Int {
        switch metric {
        case .scenes: return tagsByScenes.count
        case .images: return tagsByImages.count
        case .galleries: return tagsByGalleries.count
        case .markers: return tagsByMarkers.count
        }
    }
}

struct TopListsToolsContainerView: View {
    @ObservedObject var viewModel: TopListsViewModel
    @State private var section: Section = .scenes

    private enum Section: String, CaseIterable {
        case scenes
        case performers
        case studios
        case tags

        var title: String {
            switch self {
            case .scenes: return "Scenes"
            case .performers: return "Performers"
            case .studios: return "Studios"
            case .tags: return "Tags"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolsPillMenuRow(
                items: Section.allCases.map { ToolsPillMenuRow.Item(id: $0.rawValue, title: $0.title) },
                selectionID: section.rawValue,
                accessibilityLabel: "Charts list"
            ) { id in
                if let next = Section(rawValue: id) {
                    section = next
                }
            }

            Group {
                switch section {
                case .scenes:
                    TopScenesToolsView(viewModel: viewModel)
                case .performers:
                    TopPerformersToolsView(viewModel: viewModel)
                case .studios:
                    TopStudiosToolsView(viewModel: viewModel)
                case .tags:
                    TopTagsToolsView(viewModel: viewModel)
                }
            }
            .id(section)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .popNavigationToRootOnChange(section.rawValue)
    }
}

struct TopScenesToolsView: View {
    @ObservedObject var viewModel: TopListsViewModel
    @ObservedObject private var configManager = ServerConfigManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView {
                    Task { await viewModel.reloadScenes() }
                }
            } else if viewModel.isLoadingScenes && !viewModel.hasScenesContent {
                StandardLoadingView(message: "Loading top scenes...")
            } else if viewModel.didFailScenes && !viewModel.hasScenesContent {
                ConnectionErrorView {
                    Task { await viewModel.reloadScenes() }
                }
            } else {
                scenesScroll
            }
        }
        .applyAppBackground()
        .task { await viewModel.reloadScenes() }
        .onChange(of: viewModel.sceneMetric) { _, _ in
            Task { await viewModel.reloadScenes() }
        }
        .onChange(of: configManager.activeConfig?.id) { _, _ in
            viewModel.reset()
            Task { await viewModel.reloadScenes() }
        }
    }

    private var scenesScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TopListsMetricChipRow(
                    metrics: SceneTopMetric.allCases,
                    selection: $viewModel.sceneMetric
                )

                let scenes = viewModel.scenesForSelectedMetric
                if scenes.isEmpty {
                    Text("No scenes yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    TopListsCardsGrid(
                        items: scenes,
                        isLoadingMore: viewModel.isLoadingMoreScenes,
                        hasMore: viewModel.hasMoreScenes,
                        loadMore: { Task { await viewModel.loadMoreScenes() } }
                    ) { index, scene in
                        NavigationLink(destination: SceneDetailView(scene: scene)) {
                            TopListsSceneCard(
                                scene: scene,
                                place: index + 1,
                                metric: viewModel.sceneMetric
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .toolsHorizontalPadding(horizontalSizeClass)
            .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
        }
    }
}

struct TopPerformersToolsView: View {
    @ObservedObject var viewModel: TopListsViewModel
    @ObservedObject private var configManager = ServerConfigManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView {
                    Task { await viewModel.reloadPerformers() }
                }
            } else if viewModel.isLoadingPerformers && !viewModel.hasPerformersContent {
                StandardLoadingView(message: "Loading top performers...")
            } else if viewModel.didFailPerformers && !viewModel.hasPerformersContent {
                ConnectionErrorView {
                    Task { await viewModel.reloadPerformers() }
                }
            } else {
                performersScroll
            }
        }
        .applyAppBackground()
        .task { await viewModel.reloadPerformers() }
        .onChange(of: viewModel.performerMetric) { _, _ in
            Task { await viewModel.reloadPerformers() }
        }
        .onChange(of: configManager.activeConfig?.id) { _, _ in
            viewModel.reset()
            Task { await viewModel.reloadPerformers() }
        }
    }

    private var performersScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TopListsMetricChipRow(
                    metrics: PerformerTopMetric.allCases,
                    selection: $viewModel.performerMetric
                )

                let performers = viewModel.performersForSelectedMetric
                if performers.isEmpty {
                    Text("No performers yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    TopListsCardsGrid(
                        items: performers,
                        isLoadingMore: viewModel.isLoadingMorePerformers,
                        hasMore: viewModel.hasMorePerformers,
                        loadMore: { Task { await viewModel.loadMorePerformers() } }
                    ) { index, performer in
                        NavigationLink(destination: PerformerDetailView(performer: performer)) {
                            TopListsPerformerCard(
                                performer: performer,
                                place: index + 1,
                                metric: viewModel.performerMetric
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .toolsHorizontalPadding(horizontalSizeClass)
            .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
        }
    }
}

struct TopStudiosToolsView: View {
    @ObservedObject var viewModel: TopListsViewModel
    @ObservedObject private var configManager = ServerConfigManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView {
                    Task { await viewModel.reloadStudios() }
                }
            } else if viewModel.isLoadingStudios && !viewModel.hasStudiosContent {
                StandardLoadingView(message: "Loading top studios...")
            } else if viewModel.didFailStudios && !viewModel.hasStudiosContent {
                ConnectionErrorView {
                    Task { await viewModel.reloadStudios() }
                }
            } else {
                studiosScroll
            }
        }
        .applyAppBackground()
        .task { await viewModel.reloadStudios() }
        .onChange(of: viewModel.studioMetric) { _, _ in
            Task { await viewModel.reloadStudios() }
        }
        .onChange(of: configManager.activeConfig?.id) { _, _ in
            viewModel.reset()
            Task { await viewModel.reloadStudios() }
        }
    }

    private var studiosScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TopListsMetricChipRow(
                    metrics: StudioTopMetric.allCases,
                    selection: $viewModel.studioMetric
                )

                let studios = viewModel.studiosForSelectedMetric
                if studios.isEmpty {
                    Text("No studios yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    TopListsCardsGrid(
                        items: studios,
                        isLoadingMore: viewModel.isLoadingMoreStudios,
                        hasMore: viewModel.hasMoreStudios,
                        loadMore: { Task { await viewModel.loadMoreStudios() } }
                    ) { index, studio in
                        NavigationLink(destination: StudioDetailView(studio: studio)) {
                            TopListsStudioCard(
                                studio: studio,
                                place: index + 1,
                                metric: viewModel.studioMetric
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .toolsHorizontalPadding(horizontalSizeClass)
            .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
        }
    }
}

struct TopTagsToolsView: View {
    @ObservedObject var viewModel: TopListsViewModel
    @ObservedObject private var configManager = ServerConfigManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView {
                    Task { await viewModel.reloadTags() }
                }
            } else if viewModel.isLoadingTags && !viewModel.hasTagsContent {
                StandardLoadingView(message: "Loading top tags...")
            } else if viewModel.didFailTags && !viewModel.hasTagsContent {
                ConnectionErrorView {
                    Task { await viewModel.reloadTags() }
                }
            } else {
                tagsScroll
            }
        }
        .applyAppBackground()
        .task { await viewModel.reloadTags() }
        .onChange(of: viewModel.tagMetric) { _, _ in
            Task { await viewModel.reloadTags() }
        }
        .onChange(of: configManager.activeConfig?.id) { _, _ in
            viewModel.reset()
            Task { await viewModel.reloadTags() }
        }
    }

    private func tagDetailTab(for metric: TagTopMetric) -> TagDetailView.DetailTab? {
        switch metric {
        case .scenes: return .scenes
        case .images: return .images
        case .galleries: return .galleries
        case .markers: return nil
        }
    }

    private var tagsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TopListsMetricChipRow(
                    metrics: TagTopMetric.allCases,
                    selection: $viewModel.tagMetric
                )

                let tags = viewModel.tagsForSelectedMetric
                if tags.isEmpty {
                    Text("No tags yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    TopListsCardsGrid(
                        items: tags,
                        isLoadingMore: viewModel.isLoadingMoreTags,
                        hasMore: viewModel.hasMoreTags,
                        loadMore: { Task { await viewModel.loadMoreTags() } }
                    ) { index, tag in
                        NavigationLink(destination: TagDetailView(selectedTag: tag, initialTab: tagDetailTab(for: viewModel.tagMetric))) {
                            TopListsTagCard(
                                tag: tag,
                                place: index + 1,
                                metric: viewModel.tagMetric
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .toolsHorizontalPadding(horizontalSizeClass)
            .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
        }
    }
}

private struct TopListsCardsGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    let isLoadingMore: Bool
    let hasMore: Bool
    let loadMore: () -> Void
    @ViewBuilder var card: (Int, Item) -> Card
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: DesignTokens.Tools.rankedColumns(for: horizontalSizeClass, compact: 1, regular: 1), spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    card(index, item)
                }
            }
            TopListsPaginationFooter(
                isLoadingMore: isLoadingMore,
                hasMore: hasMore,
                loadMore: loadMore
            )
        }
    }
}

private struct TopListsPaginationFooter: View {
    let isLoadingMore: Bool
    let hasMore: Bool
    let loadMore: () -> Void

    var body: some View {
        if isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
        } else if hasMore {
            Color.clear
                .frame(height: 1)
                .onAppear(perform: loadMore)
        }
    }
}

// MARK: - Metric chips

private struct TopListsMetricChipRow<Metric: Identifiable & Hashable & TopListsMetricLabel>: View {
    let metrics: [Metric]
    @Binding var selection: Metric
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        HStack(spacing: StashyExpandingDock.itemSpacing) {
            ForEach(metrics) { metric in
                let selected = selection == metric
                Button {
                    HapticManager.selection()
                    selection = metric
                } label: {
                    Text(metric.label)
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
                .accessibilityLabel("\(metric.label)\(selected ? ", selected" : "")")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: - Cards (Match / Charts layout)

private struct TopListsSceneCard: View {
    let scene: Scene
    let place: Int
    let metric: SceneTopMetric

    private static let thumbWidth: CGFloat = 128

    var body: some View {
        TopListsLeaderboardCard(
            title: scene.title ?? "Untitled",
            place: place,
            thumbWidth: Self.thumbWidth,
            thumbAspectRatio: 16 / 9,
            titleLineLimit: 1,
            thumbnailURL: scene.thumbnailURL,
            placeholderSystemImage: "film"
        ) {
            HStack(alignment: .top, spacing: 4) {
                TopListsStatColumn(
                    title: "Views",
                    value: TopListsFormat.count(scene.playCount ?? 0),
                    emphasized: metric == .views
                )
                TopListsStatColumn(
                    title: "O-Count",
                    value: TopListsFormat.count(scene.oCounter ?? 0),
                    emphasized: metric == .oCount
                )
                TopListsStatColumn(
                    title: "Watch",
                    value: TopListsFormat.duration(scene.playDuration ?? 0),
                    emphasized: metric == .watchTime
                )
                TopListsStatColumn(
                    title: "Rating",
                    value: scene.rating100.map { "\($0)" } ?? "—",
                    emphasized: metric == .rating
                )
            }
        }
    }
}

private struct TopListsPerformerCard: View {
    let performer: Performer
    let place: Int
    let metric: PerformerTopMetric

    private static let thumbWidth: CGFloat = 68

    var body: some View {
        TopListsLeaderboardCard(
            title: performer.name,
            place: place,
            thumbWidth: Self.thumbWidth,
            thumbnailURL: performer.thumbnailURL,
            thumbnailAlignment: .top,
            placeholderSystemImage: "person.fill"
        ) {
            HStack(alignment: .top, spacing: 4) {
                TopListsStatColumn(
                    title: "O-Count",
                    value: TopListsFormat.count(performer.oCounter ?? 0),
                    emphasized: metric == .oCount
                )
                TopListsStatColumn(
                    title: "Scenes",
                    value: TopListsFormat.count(performer.sceneCount),
                    emphasized: metric == .scenes
                )
                TopListsStatColumn(
                    title: "Rating",
                    value: performer.rating100.map { "\($0)" } ?? "—",
                    emphasized: metric == .rating
                )
                TopListsStatColumn(
                    title: "Images",
                    value: TopListsFormat.count(performer.imageCount ?? 0),
                    emphasized: metric == .images
                )
                TopListsStatColumn(
                    title: "Galleries",
                    value: TopListsFormat.count(performer.galleryCount ?? 0),
                    emphasized: metric == .galleries
                )
            }
        }
    }
}

private struct TopListsStudioCard: View {
    let studio: Studio
    let place: Int
    let metric: StudioTopMetric

    private static let thumbWidth: CGFloat = 128

    var body: some View {
        TopListsLeaderboardCard(
            title: studio.name,
            place: place,
            thumbWidth: Self.thumbWidth,
            thumbAspectRatio: 16 / 9,
            thumbnailURL: nil,
            placeholderSystemImage: "building.2",
            studio: studio
        ) {
            HStack(alignment: .top, spacing: 4) {
                TopListsStatColumn(
                    title: "Scenes",
                    value: TopListsFormat.count(studio.sceneCount),
                    emphasized: metric == .scenes
                )
                TopListsStatColumn(
                    title: "Galleries",
                    value: TopListsFormat.count(studio.galleryCount ?? 0),
                    emphasized: metric == .galleries
                )
                TopListsStatColumn(
                    title: "Rating",
                    value: studio.rating100.map { "\($0)" } ?? "—",
                    emphasized: metric == .rating
                )
                TopListsStatColumn(
                    title: "Images",
                    value: TopListsFormat.count(studio.imageCount ?? 0),
                    emphasized: metric == .images
                )
            }
        }
    }
}

private struct TopListsTagCard: View {
    let tag: Tag
    let place: Int
    let metric: TagTopMetric

    private static let thumbWidth: CGFloat = 128

    var body: some View {
        TopListsLeaderboardCard(
            title: tag.name,
            place: place,
            thumbWidth: Self.thumbWidth,
            thumbAspectRatio: 16 / 9,
            thumbnailURL: tag.thumbnailURL,
            placeholderSystemImage: "tag"
        ) {
            HStack(alignment: .top, spacing: 4) {
                TopListsStatColumn(
                    title: "Scenes",
                    value: TopListsFormat.count(tag.sceneCount ?? 0),
                    emphasized: metric == .scenes
                )
                TopListsStatColumn(
                    title: "Images",
                    value: TopListsFormat.count(tag.imageCount ?? 0),
                    emphasized: metric == .images
                )
                TopListsStatColumn(
                    title: "Galleries",
                    value: TopListsFormat.count(tag.galleryCount ?? 0),
                    emphasized: metric == .galleries
                )
                TopListsStatColumn(
                    title: "Markers",
                    value: TopListsFormat.count(tag.sceneMarkerCount ?? 0),
                    emphasized: metric == .markers
                )
            }
        }
    }
}

private struct TopListsCardRowLayout: Layout {
    var thumbWidth: CGFloat
    var thumbAspectRatio: CGFloat?
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let proposedWidth = proposal.width

        func contentSize(forThumbWidth thumbW: CGFloat) -> CGSize {
            let contentWidth = proposedWidth.map { max(0, $0 - thumbW - spacing) }
            return subviews[1].sizeThatFits(ProposedViewSize(width: contentWidth, height: proposal.height))
        }

        if let ratio = thumbAspectRatio, ratio > 0 {
            var thumbW = thumbWidth
            var content = contentSize(forThumbWidth: thumbW)
            thumbW = content.height * ratio
            content = contentSize(forThumbWidth: thumbW)
            let width = proposedWidth ?? (thumbW + spacing + content.width)
            return CGSize(width: width, height: content.height)
        }

        let content = contentSize(forThumbWidth: thumbWidth)
        let width = proposedWidth ?? (thumbWidth + spacing + content.width)
        return CGSize(width: width, height: content.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let height = bounds.height
        let thumbW: CGFloat
        if let ratio = thumbAspectRatio, ratio > 0 {
            thumbW = height * ratio
        } else {
            thumbW = thumbWidth
        }
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: thumbW, height: height)
        )
        let contentX = bounds.minX + thumbW + spacing
        subviews[1].place(
            at: CGPoint(x: contentX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: max(0, bounds.maxX - contentX), height: height)
        )
    }
}

private struct TopListsLeaderboardCard<Stats: View>: View {
    let title: String
    let place: Int
    let thumbWidth: CGFloat
    var thumbAspectRatio: CGFloat? = nil
    var titleLineLimit: Int = 2
    let thumbnailURL: URL?
    var thumbnailAlignment: Alignment = .center
    let placeholderSystemImage: String
    var studio: Studio? = nil
    @ViewBuilder var stats: () -> Stats
    @ObservedObject private var appearance = AppearanceManager.shared

    private var thumbCornerRadius: CGFloat { DesignTokens.CornerRadius.card }

    var body: some View {
        TopListsCardRowLayout(thumbWidth: thumbWidth, thumbAspectRatio: thumbAspectRatio, spacing: 12) {
            thumbnailWithRank
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(titleLineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)

                stats()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .contentShape(Rectangle())
    }

    private var thumbnailClip: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: thumbCornerRadius,
            bottomLeadingRadius: thumbCornerRadius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        )
    }

    private var thumbnailWithRank: some View {
        ZStack(alignment: .bottomTrailing) {
            thumbnailClip
                .fill(studio == nil ? Color.gray.opacity(DesignTokens.Opacity.placeholder) : Color.studioHeaderGray(for: appearance.currentTheme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { photoOverlay }
                .clipShape(thumbnailClip)

            Text("#\(place)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .padding([.trailing, .bottom], 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var photoOverlay: some View {
        Group {
            if let studio {
                StudioImageView(studio: studio)
                    .padding(8)
            } else if let url = thumbnailURL {
                CustomAsyncImage(url: url) { loader in
                    if loader.isLoading {
                        InlineSpinner(scale: .medium)
                    } else if let image = loader.image {
                        image.resizable().scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: thumbnailAlignment)
                    } else {
                        placeholderIcon
                    }
                }
            } else {
                placeholderIcon
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: thumbnailAlignment)
        .clipped()
    }

    private var placeholderIcon: some View {
        Image(systemName: placeholderSystemImage)
            .font(.title2)
            .foregroundStyle(Color.appAccent.opacity(0.45))
    }
}

private struct TopListsStatColumn: View {
    let title: String
    let value: String
    var emphasized: Bool = false

    var body: some View {
        VStack(alignment: .center, spacing: 1) {
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(emphasized ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private enum TopListsFormat {
    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
#endif
