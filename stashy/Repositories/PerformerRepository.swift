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

    private static let coAppearanceScenePageSize = 1000
    private static let coPerformerIdChunkSize = 200

    /// All performers that appear in at least one scene together with `performerId`,
    /// sorted by shared-scene count (desc), then name.
    /// 1. Pages through every scene of the performer requesting only `performers { id }`.
    /// 2. Loads the co-performers via `findPerformers(ids:)` with the usual card fields.
    func fetchCoPerformers(performerId: String) async throws -> [CoPerformer] {
        let scenesQuery = GraphQLQueries.loadQuery(named: "findPerformerCoAppearances")
        var counts: [String: Int] = [:]
        var page = 1
        var fetched = 0
        while true {
            try Task.checkCancellation()
            let variables: [String: Any] = [
                "scene_filter": [
                    "performers": ["value": [performerId], "modifier": "INCLUDES"]
                ],
                "filter": [
                    "page": page,
                    "per_page": Self.coAppearanceScenePageSize,
                    "sort": "id",
                    "direction": "ASC"
                ]
            ]
            let response: CoAppearanceScenesResponse = try await graphQLClient.execute(query: scenesQuery, variables: variables)
            guard let result = response.data?.findScenes else { break }
            for scene in result.scenes {
                // A performer listed twice on one scene still counts once.
                for coId in Set(scene.performers.map(\.id)) where coId != performerId {
                    counts[coId, default: 0] += 1
                }
            }
            fetched += result.scenes.count
            if result.scenes.isEmpty || fetched >= result.count { break }
            page += 1
        }

        guard !counts.isEmpty else { return [] }

        let performersQuery = GraphQLQueries.queryWithFragments("findPerformers")
        let ids = Array(counts.keys)
        var performers: [Performer] = []
        var start = 0
        while start < ids.count {
            try Task.checkCancellation()
            let chunk = Array(ids[start..<min(start + Self.coPerformerIdChunkSize, ids.count)])
            let variables: [String: Any] = [
                "ids": chunk,
                "filter": ["per_page": -1]
            ]
            let response: PerformersResponse = try await graphQLClient.execute(query: performersQuery, variables: variables)
            performers.append(contentsOf: response.data?.findPerformers.performers ?? [])
            start += Self.coPerformerIdChunkSize
        }

        return performers
            .map { CoPerformer(performer: $0, sharedSceneCount: counts[$0.id] ?? 0) }
            .sorted { a, b in
                if a.sharedSceneCount != b.sharedSceneCount { return a.sharedSceneCount > b.sharedSceneCount }
                return a.performer.name.localizedCaseInsensitiveCompare(b.performer.name) == .orderedAscending
            }
    }
}

// MARK: - Appears With models

/// A performer who shares at least one scene with another performer.
struct CoPerformer: Identifiable {
    let performer: Performer
    /// Number of scenes both performers appear in.
    let sharedSceneCount: Int
    var id: String { performer.id }
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

/// Session-only memory cache for "Appears with", keyed by server + performer.
@MainActor
final class CoPerformerCache {
    static let shared = CoPerformerCache()
    private var storage: [String: [CoPerformer]] = [:]

    private func key(_ performerId: String) -> String {
        let server = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "none"
        return "\(server)_\(performerId)"
    }

    func get(_ performerId: String) -> [CoPerformer]? { storage[key(performerId)] }
    func set(_ performerId: String, _ value: [CoPerformer]) { storage[key(performerId)] = value }
}
