//
//  PerformerRepository.swift
//  stashy
//
//  Created by Gemini on 16.01.26.
//

import Foundation

// MARK: - Performer Repository Protocol

protocol PerformerRepositoryProtocol {
    /// Fetches a paginated list of performers
    func fetchPerformers(
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.PerformerSortOption,
        searchQuery: String,
        filter: StashDBViewModel.SavedFilter?
    ) async throws -> (performers: [Performer], total: Int)
}

// MARK: - Performer Repository Implementation

class PerformerRepository: PerformerRepositoryProtocol {
    
    private let graphQLClient: GraphQLClient
    
    init(graphQLClient: GraphQLClient = .shared) {
        self.graphQLClient = graphQLClient
    }
    
    // MARK: - Fetch Performers List
    
    func fetchPerformers(
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.PerformerSortOption,
        searchQuery: String,
        filter: StashDBViewModel.SavedFilter?
    ) async throws -> (performers: [Performer], total: Int) {
        let query = GraphQLQueries.queryWithFragments("findPerformers")
        
        var performerFilter: [String: Any] = [:]
        
        // Add search filter
        if !searchQuery.isEmpty {
            performerFilter["name"] = ["value": searchQuery, "modifier": "INCLUDES"]
        }
        
        // Apply saved filter if present
        if let savedFilter = filter, let filterDict = savedFilter.filterDict {
            performerFilter = filterDict
        }
        
        var variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ]
        ]
        
        if !performerFilter.isEmpty {
            variables["performer_filter"] = performerFilter
        }
        
        let response: PerformersResponse = try await graphQLClient.execute(query: query, variables: variables)
        let performers = response.data?.findPerformers.performers ?? []
        let total = response.data?.findPerformers.count ?? 0
        return (performers, total)
    }

    // MARK: - Appears With (co-performers)

    private static let coAppearancePageSize = 1000

    /// Shared scenes, galleries and images per co-performer of `performerId` (the performer
    /// itself excluded). Pages through every scene, gallery and image of the performer, asking
    /// only for the ids it needs. An image inside a gallery both performers already share is not
    /// counted again, so a 20-picture set reads as one gallery, not 21 items.
    func fetchCoAppearanceCounts(performerId: String) async throws -> [String: CoAppearanceCounts] {
        async let scenesTask = fetchCoAppearanceRows(
            queryName: "findPerformerCoAppearances", filterKey: "scene_filter", performerId: performerId
        ) { (r: CoAppearanceScenesResponse) in
            r.data.map { ($0.findScenes.count, $0.findScenes.scenes.map { CoAppearanceRow(performers: $0.performers.map(\.id), galleries: []) }) }
        }
        async let galleriesTask = fetchCoAppearanceRows(
            queryName: "findPerformerGalleryCoAppearances", filterKey: "gallery_filter", performerId: performerId
        ) { (r: CoAppearanceGalleriesResponse) in
            r.data.map { ($0.findGalleries.count, $0.findGalleries.galleries.map { CoAppearanceRow(id: $0.id, performers: $0.performers.map(\.id), galleries: []) }) }
        }
        async let imagesTask = fetchCoAppearanceRows(
            queryName: "findPerformerImageCoAppearances", filterKey: "image_filter", performerId: performerId
        ) { (r: CoAppearanceImagesResponse) in
            r.data.map { ($0.findImages.count, $0.findImages.images.map { CoAppearanceRow(performers: $0.performers.map(\.id), galleries: $0.galleries.map(\.id)) }) }
        }
        let (scenes, galleries, images) = try await (scenesTask, galleriesTask, imagesTask)
        return Self.coAppearanceCounts(performerId: performerId, scenes: scenes, galleries: galleries, images: images)
    }

    /// Pure counting behind `fetchCoAppearanceCounts`.
    static func coAppearanceCounts(
        performerId: String,
        scenes: [CoAppearanceRow],
        galleries: [CoAppearanceRow],
        images: [CoAppearanceRow]
    ) -> [String: CoAppearanceCounts] {
        var counts: [String: CoAppearanceCounts] = [:]
        // A performer listed twice on one item still counts once.
        for scene in scenes {
            for coId in Set(scene.performers) where coId != performerId { counts[coId, default: .init()].scenes += 1 }
        }
        var galleryPerformers: [String: Set<String>] = [:]
        for gallery in galleries {
            let ids = Set(gallery.performers)
            if let gid = gallery.id { galleryPerformers[gid] = ids }
            for coId in ids where coId != performerId { counts[coId, default: .init()].galleries += 1 }
        }
        for image in images {
            for coId in Set(image.performers) where coId != performerId {
                let inSharedGallery = image.galleries.contains { galleryPerformers[$0]?.contains(coId) == true }
                if !inSharedGallery { counts[coId, default: .init()].images += 1 }
            }
        }
        return counts
    }

    private func fetchCoAppearanceRows<R: Decodable>(
        queryName: String,
        filterKey: String,
        performerId: String,
        extract: (R) -> (count: Int, rows: [CoAppearanceRow])?
    ) async throws -> [CoAppearanceRow] {
        let query = GraphQLQueries.loadQuery(named: queryName)
        var rows: [CoAppearanceRow] = []
        var page = 1
        while true {
            try Task.checkCancellation()
            let variables: [String: Any] = [
                filterKey: ["performers": ["value": [performerId], "modifier": "INCLUDES"]],
                "filter": [
                    "page": page,
                    "per_page": Self.coAppearancePageSize,
                    "sort": "id",
                    "direction": "ASC"
                ]
            ]
            let response: R = try await graphQLClient.execute(query: query, variables: variables)
            guard let result = extract(response) else { break }
            rows += result.rows
            if result.rows.isEmpty || rows.count >= result.count { break }
            page += 1
        }
        return rows
    }

    /// Co-performers (from `counts`) matching `performerFilter`, in `sort` order.
    ///
    /// `findPerformers(ids:)` ignores `performer_filter` and `filter` on the server, so the scope
    /// goes through the filter instead: Stash's `performers` criterion ("appears with", which also
    /// counts shared images / galleries) narrows the query, and the result is intersected with the
    /// locally counted `counts`. A user criterion on `performers` wins; the intersection still scopes.
    /// `sort == nil` → "Shared": total desc, then name.
    func fetchCoPerformers(
        performerId: String,
        counts: [String: CoAppearanceCounts],
        performerFilter: [String: Any],
        sort: (field: String, direction: String)?
    ) async throws -> [CoPerformer] {
        guard !counts.isEmpty else { return [] }
        try Task.checkCancellation()
        var filter = performerFilter
        if filter["performers"] == nil {
            filter["performers"] = ["value": [performerId], "modifier": "INCLUDES"]
        }
        let variables: [String: Any] = [
            "performer_filter": filter,
            "filter": [
                "per_page": -1,
                "sort": sort?.field ?? "name",
                "direction": sort?.direction ?? "ASC"
            ]
        ]
        let query = GraphQLQueries.queryWithFragments("findPerformers")
        let response: PerformersResponse = try await graphQLClient.execute(query: query, variables: variables)
        let matched = (response.data?.findPerformers.performers ?? [])
            .filter { $0.id != performerId }
            .compactMap { p in counts[p.id].flatMap { $0.total > 0 ? CoPerformer(performer: p, shared: $0) : nil } }
        guard sort == nil else { return matched }
        return matched.sorted { a, b in
            if a.shared.total != b.shared.total { return a.shared.total > b.shared.total }
            return a.performer.name.localizedCaseInsensitiveCompare(b.performer.name) == .orderedAscending
        }
    }
}

// MARK: - Appears With models

/// How often two performers appear together.
struct CoAppearanceCounts: Equatable {
    var scenes = 0
    var galleries = 0
    /// Images outside the galleries already counted.
    var images = 0
    var total: Int { scenes + galleries + images }

    /// "3 scenes, 1 gallery" — VoiceOver value of an "Appears with" card.
    var accessibilityText: String {
        func part(_ n: Int, _ one: String, _ many: String) -> String? { n > 0 ? tr(n == 1 ? one : many, n) : nil }
        return [part(scenes, "arg_shared_scene", "arg_shared_scenes"), part(galleries, "arg_shared_gallery", "arg_shared_galleries"),
                part(images, "arg_shared_image", "arg_shared_images")]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// A performer who shares at least one scene, gallery or image with another performer.
struct CoPerformer: Identifiable {
    let performer: Performer
    let shared: CoAppearanceCounts
    var id: String { performer.id }
}

/// One scene / gallery / image reduced to what the co-appearance count needs.
struct CoAppearanceRow {
    var id: String? = nil
    let performers: [String]
    let galleries: [String]
}

private struct CoAppearanceScenesResponse: Decodable {
    struct Payload: Decodable { let findScenes: Result }
    struct Result: Decodable {
        let count: Int
        let scenes: [SceneRef]
    }
    struct SceneRef: Decodable {
        let id: String
        let performers: [PerformerRef]
    }
    struct PerformerRef: Decodable { let id: String }
    let data: Payload?
}

private struct CoAppearanceGalleriesResponse: Decodable {
    struct Payload: Decodable { let findGalleries: Result }
    struct Result: Decodable {
        let count: Int
        let galleries: [GalleryRef]
    }
    struct GalleryRef: Decodable {
        let id: String
        let performers: [IdRef]
    }
    let data: Payload?
}

private struct CoAppearanceImagesResponse: Decodable {
    struct Payload: Decodable { let findImages: Result }
    struct Result: Decodable {
        let count: Int
        let images: [ImageRef]
    }
    struct ImageRef: Decodable {
        let id: String
        let performers: [IdRef]
        let galleries: [IdRef]
    }
    let data: Payload?
}

private struct IdRef: Decodable { let id: String }

/// Session-only memory cache for "Appears with", keyed by server + performer (+ filter + sort
/// for the resolved lists). Shared-scene counts are cached apart so filter / sort changes only
/// re-run the cheap `findPerformers` query.
@MainActor
final class CoPerformerCache {
    static let shared = CoPerformerCache()
    private var counts: [String: [String: CoAppearanceCounts]] = [:]
    private var lists: [String: [CoPerformer]] = [:]

    private func key(_ performerId: String) -> String {
        let server = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "none"
        return "\(server)_\(performerId)"
    }

    private func key(_ performerId: String, queryKey: String) -> String {
        "\(key(performerId))_\(queryKey)"
    }

    func counts(_ performerId: String) -> [String: CoAppearanceCounts]? { counts[key(performerId)] }
    func setCounts(_ performerId: String, _ value: [String: CoAppearanceCounts]) { counts[key(performerId)] = value }

    func get(_ performerId: String, queryKey: String) -> [CoPerformer]? { lists[key(performerId, queryKey: queryKey)] }
    func set(_ performerId: String, queryKey: String, _ value: [CoPerformer]) { lists[key(performerId, queryKey: queryKey)] = value }

    /// Pull-to-refresh: drops the counts and every filter / sort variant of this performer.
    func invalidate(_ performerId: String) {
        let k = key(performerId)
        counts[k] = nil
        lists = lists.filter { !$0.key.hasPrefix(k + "_") }
    }
}
