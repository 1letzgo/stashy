//
//  TagRepository.swift
//  stashy
//
//  Created by Gemini on 16.01.26.
//

import Foundation

// MARK: - Tag Repository Protocol

protocol TagRepositoryProtocol {
    /// Fetches a paginated list of tags
    func fetchTags(
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.TagSortOption,
        searchQuery: String,
        filter: StashDBViewModel.SavedFilter?
    ) async throws -> (tags: [Tag], total: Int)
    
    /// Fetches a single tag by ID
    func fetchTagDetails(tagId: String) async throws -> Tag?

    /// Re-points every usage of `sourceIds` at `destinationId` and deletes the sources.
    @discardableResult
    func mergeTags(sourceIds: [String], destinationId: String) async throws -> Tag?

    /// Every tag on the server, paged until exhausted.
    func fetchEveryTag() async throws -> [Tag]

    /// Deletes the given tags.
    @discardableResult
    func deleteTags(ids: [String]) async throws -> Bool
}

// MARK: - Tag Repository Implementation

class TagRepository: TagRepositoryProtocol {
    
    private let graphQLClient: GraphQLClient
    
    init(graphQLClient: GraphQLClient = .shared) {
        self.graphQLClient = graphQLClient
    }
    
    // MARK: - Fetch Tags List
    
    func fetchTags(
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.TagSortOption = .nameAsc,
        searchQuery: String,
        filter: StashDBViewModel.SavedFilter?
    ) async throws -> (tags: [Tag], total: Int) {
        let query = GraphQLQueries.queryWithFragments("findTags")
        
        var tagFilter: [String: Any] = [:]
        
        // Add search filter
        if !searchQuery.isEmpty {
            tagFilter["name"] = ["value": searchQuery, "modifier": "INCLUDES"]
        }
        
        // Apply saved filter if present
        if let savedFilter = filter, let filterDict = savedFilter.filterDict {
            tagFilter = filterDict
        }
        
        var variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ]
        ]
        
        if !tagFilter.isEmpty {
            variables["tag_filter"] = tagFilter
        }
        
        let response: TagsResponse = try await graphQLClient.execute(query: query, variables: variables)
        let tags = response.data?.findTags.tags ?? []
        let total = response.data?.findTags.count ?? 0
        return (tags, total)
    }
    
    // MARK: - Fetch Tag Details
    
    func fetchTagDetails(tagId: String) async throws -> Tag? {
        let query = GraphQLQueries.queryWithFragments("findTag")
        let variables: [String: Any] = ["id": tagId]
        
        let response: SingleTagResponse = try await graphQLClient.execute(query: query, variables: variables)
        return response.data?.findTag
    }

    // MARK: - Merge Tags

    /// Stash macht die eigentliche Arbeit: `tagsMerge` schreibt Szenen, Bilder,
    /// Galerien, Performer und Marker (Primär- wie Zusatz-Tag) der Quellen auf das
    /// Ziel um und löscht die Quell-Tags anschließend. Deshalb hier kein
    /// Umschreiben pro Entität — ein Aufruf statt hunderter Mutationen.
    @discardableResult
    func mergeTags(sourceIds: [String], destinationId: String) async throws -> Tag? {
        let mutation = GraphQLQueries.loadQuery(named: "tagsMerge")
        let variables: [String: Any] = [
            "input": [
                "source": sourceIds,
                "destination": destinationId
            ]
        ]

        let response: TagsMergeResponse = try await graphQLClient.execute(query: mutation, variables: variables)
        return response.data?.tagsMerge
    }

    // MARK: - All Tags

    /// `findTags` liefert maximal eine Seite; für Aufräumaufgaben muss aber wirklich
    /// jeder Tag gesehen werden, sonst bleiben unbenutzte hinter der Seitengrenze übrig.
    func fetchEveryTag() async throws -> [Tag] {
        var collected: [Tag] = []
        var page = 1
        let perPage = 500

        while true {
            let result = try await fetchTags(
                page: page,
                perPage: perPage,
                sortBy: .nameAsc,
                searchQuery: "",
                filter: nil
            )
            collected.append(contentsOf: result.tags)

            if result.tags.count < perPage { break }
            if result.total > 0 && collected.count >= result.total { break }

            page += 1
            // Sicherheitsventil gegen ein Backend, das immer volle Seiten liefert.
            if page > 60 { break }
        }

        return collected
    }

    // MARK: - Delete Tags

    @discardableResult
    func deleteTags(ids: [String]) async throws -> Bool {
        guard !ids.isEmpty else { return true }
        let mutation = GraphQLQueries.loadQuery(named: "tagsDestroy")
        let response: TagsDestroyResponse = try await graphQLClient.execute(
            query: mutation,
            variables: ["ids": ids]
        )
        return response.data?.tagsDestroy ?? false
    }
}

// MARK: - Delete Response

private struct TagsDestroyResponse: Codable {
    struct DataPart: Codable {
        let tagsDestroy: Bool?
    }

    let data: DataPart?
}

// MARK: - Merge Response

private struct TagsMergeResponse: Codable {
    struct DataPart: Codable {
        let tagsMerge: Tag?
    }

    let data: DataPart?
}
