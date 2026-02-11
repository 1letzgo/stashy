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
