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

    /// Shared-scene count per co-performer of `performerId` (the performer itself excluded).
    /// Pages through every scene of the performer requesting only `performers { id }`.
    func fetchCoPerformerSceneCounts(performerId: String) async throws -> [String: Int] {
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
        return counts
    }

    /// Co-performers (from `counts`) matching `performerFilter`, in `sort` order.
    ///
    /// `findPerformers(ids:)` ignores `performer_filter` and `filter` on the server, so the scope
    /// goes through the filter instead: Stash's `performers` criterion ("appears with", which also
    /// counts shared images / galleries) narrows the query, and the result is intersected with the
    /// scene-based `counts`. A user criterion on `performers` wins; the intersection still scopes.
    /// `sort == nil` → "Shared scenes": count desc, then name.
    func fetchCoPerformers(
        performerId: String,
        counts: [String: Int],
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
            .compactMap { p in counts[p.id].map { CoPerformer(performer: p, sharedSceneCount: $0) } }
        guard sort == nil else { return matched }
        return matched.sorted { a, b in
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

/// Session-only memory cache for "Appears with", keyed by server + performer (+ filter + sort
/// for the resolved lists). Shared-scene counts are cached apart so filter / sort changes only
/// re-run the cheap `findPerformers` query.
@MainActor
final class CoPerformerCache {
    static let shared = CoPerformerCache()
    private var counts: [String: [String: Int]] = [:]
    private var lists: [String: [CoPerformer]] = [:]

    private func key(_ performerId: String) -> String {
        let server = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "none"
        return "\(server)_\(performerId)"
    }

    private func key(_ performerId: String, queryKey: String) -> String {
        "\(key(performerId))_\(queryKey)"
    }

    func counts(_ performerId: String) -> [String: Int]? { counts[key(performerId)] }
    func setCounts(_ performerId: String, _ value: [String: Int]) { counts[key(performerId)] = value }

    func get(_ performerId: String, queryKey: String) -> [CoPerformer]? { lists[key(performerId, queryKey: queryKey)] }
    func set(_ performerId: String, queryKey: String, _ value: [CoPerformer]) { lists[key(performerId, queryKey: queryKey)] = value }

    /// Pull-to-refresh: drops the counts and every filter / sort variant of this performer.
    func invalidate(_ performerId: String) {
        let k = key(performerId)
        counts[k] = nil
        lists = lists.filter { !$0.key.hasPrefix(k + "_") }
    }
}
