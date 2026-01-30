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
    
    /// Fetches a single performer by ID
    func fetchPerformerDetails(performerId: String) async throws -> Performer?
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
    
    // MARK: - Fetch Performer Details
    
    func fetchPerformerDetails(performerId: String) async throws -> Performer? {
        let query = GraphQLQueries.queryWithFragments("findPerformer")
        let variables: [String: Any] = ["id": performerId]
        
        let response: SinglePerformerResponse = try await graphQLClient.execute(query: query, variables: variables)
        return response.data?.findPerformer
    }
}
