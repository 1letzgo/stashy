//
//  StudioRepository.swift
//  stashy
//
//  Created by Gemini on 16.01.26.
//

import Foundation
import Combine

// MARK: - Studio Repository Protocol

protocol StudioRepositoryProtocol {
    /// Fetches a paginated list of studios
    func fetchStudios(
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.StudioSortOption,
        searchQuery: String,
        filter: StashDBViewModel.SavedFilter?
    ) async throws -> (studios: [Studio], total: Int)
    
    /// Fetches a single studio by ID
    func fetchStudioDetails(studioId: String) async throws -> Studio?

    /// Every studio on the server, paged until exhausted.
    func fetchEveryStudio() async throws -> [Studio]

    /// Wie `fetchEveryStudio`, zusätzlich mit `aliases` und `stash_ids` — die
    /// Merge-Vorlagen finden ein neu angelegtes Studio nur über diese Merkmale wieder.
    func fetchEveryStudioForMerge() async throws -> [Studio]

    /// Re-points everything attached to `sourceIds` (scenes, galleries, images,
    /// groups, child studios) at `destinationId`, then deletes the sources.
    func mergeStudios(sourceIds: [String], destinationId: String) async throws
}

// MARK: - Studio Repository Implementation

class StudioRepository: StudioRepositoryProtocol {
    
    private let graphQLClient: GraphQLClient
    
    init(graphQLClient: GraphQLClient = .shared) {
        self.graphQLClient = graphQLClient
    }
    
    // MARK: - Fetch Studios List
    
    func fetchStudios(
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.StudioSortOption,
        searchQuery: String,
        filter: StashDBViewModel.SavedFilter?
    ) async throws -> (studios: [Studio], total: Int) {
        let query = GraphQLQueries.queryWithFragments("findStudios")
        
        var studioFilter: [String: Any] = [:]
        
        // Add search filter
        if !searchQuery.isEmpty {
            studioFilter["name"] = ["value": searchQuery, "modifier": "INCLUDES"]
        }
        
        // Apply saved filter if present
        if let savedFilter = filter, let filterDict = savedFilter.filterDict {
            studioFilter = filterDict
        }
        
        var variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ]
        ]
        
        if !studioFilter.isEmpty {
            variables["studio_filter"] = studioFilter
        }
        
        let response: StudiosResponse = try await graphQLClient.execute(query: query, variables: variables)
        let studios = response.data?.findStudios.studios ?? []
        let total = response.data?.findStudios.count ?? 0
        return (studios, total)
    }
    
    // MARK: - Fetch Studio Details
    
    func fetchStudioDetails(studioId: String) async throws -> Studio? {
        let query = GraphQLQueries.queryWithFragments("findStudio")
        let variables: [String: Any] = ["id": studioId]
        
        let response: SingleStudioResponse = try await graphQLClient.execute(query: query, variables: variables)
        return response.data?.findStudio
    }
}

// MARK: - Every studio / merge

extension StudioRepository {
    func fetchEveryStudio() async throws -> [Studio] {
        var collected: [Studio] = []
        var page = 1
        let perPage = 500

        while true {
            let result = try await fetchStudios(page: page, perPage: perPage, sortBy: .nameAsc, searchQuery: "", filter: nil)
            collected.append(contentsOf: result.studios)
            if result.studios.count < perPage { break }
            if result.total > 0 && collected.count >= result.total { break }
            page += 1
            // Sicherheitsventil gegen ein Backend, das immer volle Seiten liefert.
            if page > 60 { break }
        }
        return collected
    }

    /// Eine Seite mit Merge-Feldern. Ältere Server kennen `aliases`/`stash_ids` auf
    /// Studio unter Umständen nicht — der Aufrufer fällt dann auf die schmale Abfrage zurück.
    private func fetchStudiosForMerge(page: Int, perPage: Int) async throws -> (studios: [Studio], total: Int) {
        let query = GraphQLQueries.loadQuery(named: "findStudiosForMerge")
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": "name",
                "direction": "ASC"
            ]
        ]
        let response: StudiosResponse = try await graphQLClient.execute(query: query, variables: variables)
        return (response.data?.findStudios.studios ?? [], response.data?.findStudios.count ?? 0)
    }

    func fetchEveryStudioForMerge() async throws -> [Studio] {
        var collected: [Studio] = []
        var page = 1
        let perPage = 500

        while true {
            let result: (studios: [Studio], total: Int)
            do {
                result = try await fetchStudiosForMerge(page: page, perPage: perPage)
            } catch {
                // Server ohne diese Felder: lieber die Liste ohne Identitätsmerkmale
                // als gar keine.
                AppLog.error("⚠️ findStudiosForMerge failed, falling back: \(error.localizedDescription)")
                return try await fetchEveryStudio()
            }
            collected.append(contentsOf: result.studios)
            if result.studios.count < perPage { break }
            if result.total > 0 && collected.count >= result.total { break }
            page += 1
            if page > 60 { break }
        }
        return collected
    }

    /// Stash hat kein `studiosMerge` (Stand v0.31). Die App macht es in drei Schritten:
    /// Verknüpfungen einsammeln, per Bulk-Update umhängen, Quellen löschen. Vor dem
    /// Löschen wird nachgezählt — hängt noch etwas an einer Quelle, bricht der Merge ab.
    /// `studiosDestroy` würde diese Szenen sonst ohne Studio zurücklassen.
    func mergeStudios(sourceIds: [String], destinationId: String) async throws {
        guard !sourceIds.isEmpty else { return }

        let links = try await collectLinks(of: sourceIds)
        AppLog.debug("StudioMerge: \(links.scenes.count) scenes, \(links.galleries.count) galleries, \(links.images.count) images, \(links.groups.count) groups, \(links.children.count) child studios → \(destinationId)")

        try await reassign("bulkSceneUpdateStudio", ids: links.scenes, key: "studioId", target: destinationId)
        try await reassign("bulkGalleryUpdateStudio", ids: links.galleries, key: "studioId", target: destinationId)
        try await reassign("bulkImageUpdateStudio", ids: links.images, key: "studioId", target: destinationId)
        try await reassign("bulkGroupUpdateStudio", ids: links.groups, key: "studioId", target: destinationId)
        // Kinder der Quellen hängen danach unter dem Ziel — außer dem Ziel selbst.
        try await reassign("bulkStudioUpdateParent", ids: links.children.filter { $0 != destinationId }, key: "parentId", target: destinationId)

        let remaining = try await collectLinks(of: sourceIds)
        let leftovers = remaining.scenes.count + remaining.galleries.count + remaining.images.count + remaining.groups.count
            + remaining.children.filter { $0 != destinationId }.count
        guard leftovers == 0 else {
            AppLog.error("StudioMerge: \(leftovers) links still point at the sources, not deleting")
            throw StudioMergeError.incomplete(leftovers)
        }

        let destroyed: StudiosDestroyResponse = try await graphQLClient.execute(
            query: GraphQLQueries.loadQuery(named: "studiosDestroy"),
            variables: ["ids": sourceIds]
        )
        guard destroyed.data?.studiosDestroy == true else {
            throw StudioMergeError.destroyFailed
        }
    }

    private struct StudioLinks {
        var scenes: [String] = []
        var galleries: [String] = []
        var images: [String] = []
        var groups: [String] = []
        var children: [String] = []
    }

    /// Seitenweise statt `per_page: -1` — das verhält sich nicht auf jeder Server-Version gleich.
    private func collectLinks(of studioIds: [String]) async throws -> StudioLinks {
        var links = StudioLinks()
        var page = 1
        let perPage = 500
        while true {
            let response: StudioMergeSourcesResponse = try await graphQLClient.execute(
                query: GraphQLQueries.loadQuery(named: "findStudioMergeSources"),
                variables: ["studios": studioIds, "page": page, "perPage": perPage]
            )
            guard let data = response.data else { throw StudioMergeError.noData }
            links.scenes += data.findScenes.scenes.map(\.id)
            links.galleries += data.findGalleries.galleries.map(\.id)
            links.images += data.findImages.images.map(\.id)
            links.groups += data.findGroups.groups.map(\.id)
            links.children += data.findStudios.studios.map(\.id)

            let maxCount = max(data.findScenes.count, data.findGalleries.count, data.findImages.count, data.findGroups.count, data.findStudios.count)
            if page * perPage >= maxCount || page >= 200 { break }
            page += 1
        }
        return links
    }

    private func reassign(_ mutationName: String, ids: [String], key: String, target: String) async throws {
        guard !ids.isEmpty else { return }
        // Bulk-Updates in Häppchen: sehr große Studios würden sonst einen einzigen
        // Riesen-Request und ein langes DB-Lock erzeugen.
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let _: StudioMergeMutationResponse = try await graphQLClient.execute(
                query: GraphQLQueries.loadQuery(named: mutationName),
                variables: ["ids": chunk, key: target]
            )
        }
    }
}

enum StudioMergeError: LocalizedError {
    case noData
    case incomplete(Int)
    case destroyFailed

    var errorDescription: String? {
        switch self {
        case .noData: return "Server returned no data"
        case .incomplete(let n): return "\(n) items could not be moved — nothing was deleted"
        case .destroyFailed: return "Sources could not be deleted"
        }
    }
}

private struct StudioMergeSourcesResponse: Codable {
    struct IDOnly: Codable { let id: String }
    struct Scenes: Codable { let count: Int; let scenes: [IDOnly] }
    struct Galleries: Codable { let count: Int; let galleries: [IDOnly] }
    struct Images: Codable { let count: Int; let images: [IDOnly] }
    struct Groups: Codable { let count: Int; let groups: [IDOnly] }
    struct Studios: Codable { let count: Int; let studios: [IDOnly] }
    struct DataPart: Codable {
        let findScenes: Scenes
        let findGalleries: Galleries
        let findImages: Images
        let findGroups: Groups
        let findStudios: Studios
    }
    let data: DataPart?
}

/// Das Ergebnis der Bulk-Mutationen interessiert nicht — nur, dass sie durchliefen
/// (Fehler wirft der Client über die Envelope-Prüfung).
private struct StudioMergeMutationResponse: Codable {
    let data: [String: [IDOnlyRecord]?]?
    struct IDOnlyRecord: Codable { let id: String }
}

private struct StudiosDestroyResponse: Codable {
    struct DataPart: Codable { let studiosDestroy: Bool? }
    let data: DataPart?
}

