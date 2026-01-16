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
        if let savedFilter = filter, let filterJson = savedFilter.filter {
            performerFilter = filterJson
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
        
        return try await withCheckedThrowingContinuation { continuation in
            graphQLClient.execute(query: query, variables: variables) { (result: Result<PerformerResponse, GraphQLNetworkError>) in
                switch result {
                case .success(let response):
                    let performers = response.data?.findPerformers?.performers ?? []
                    let total = response.data?.findPerformers?.count ?? 0
                    continuation.resume(returning: (performers, total))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Fetch Performer Details
    
    func fetchPerformerDetails(performerId: String) async throws -> Performer? {
        let query = GraphQLQueries.queryWithFragments("findPerformer")
        let variables: [String: Any] = ["id": performerId]
        
        return try await withCheckedThrowingContinuation { continuation in
            graphQLClient.execute(query: query, variables: variables) { (result: Result<SinglePerformerResponse, GraphQLNetworkError>) in
                switch result {
                case .success(let response):
                    continuation.resume(returning: response.data?.findPerformer)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
