//
//  FilterRepository.swift
//  stashy
//
//  Created by Architecture Improvement on 20.01.26.
//

import Foundation

// MARK: - Filter Repository Protocol

protocol FilterRepositoryProtocol {
    /// Fetches all saved filters from the server
    func fetchSavedFilters() async throws -> [StashDBViewModel.SavedFilter]
}

// MARK: - Filter Repository Implementation

class FilterRepository: FilterRepositoryProtocol {
    
    private let graphQLClient: GraphQLClient
    
    init(graphQLClient: GraphQLClient = .shared) {
        self.graphQLClient = graphQLClient
    }
    
    // MARK: - Fetch Saved Filters
    
    func fetchSavedFilters() async throws -> [StashDBViewModel.SavedFilter] {
        let query = """
        query GetAllFilterDefinitions {
          findSavedFilters {
            id
            name
            mode
            filter
            object_filter
          }
        }
        """
        
        let response: StashDBViewModel.SavedFiltersResponse = try await graphQLClient.execute(query: query)
        return response.data?.findSavedFilters ?? []
    }
}
