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
        searchQuery: String,
        filter: StashDBViewModel.SavedFilter?
    ) async throws -> (tags: [Tag], total: Int)
    
    /// Fetches a single tag by ID
    func fetchTagDetails(tagId: String) async throws -> Tag?
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
        if let savedFilter = filter, let filterJson = savedFilter.filter {
            tagFilter = filterJson
        }
        
        var variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": "name",
                "direction": "ASC"
            ]
        ]
        
        if !tagFilter.isEmpty {
            variables["tag_filter"] = tagFilter
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            graphQLClient.execute(query: query, variables: variables) { (result: Result<TagResponse, GraphQLNetworkError>) in
                switch result {
                case .success(let response):
                    let tags = response.data?.findTags?.tags ?? []
                    let total = response.data?.findTags?.count ?? 0
                    continuation.resume(returning: (tags, total))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Fetch Tag Details
    
    func fetchTagDetails(tagId: String) async throws -> Tag? {
        let query = GraphQLQueries.queryWithFragments("findTag")
        let variables: [String: Any] = ["id": tagId]
        
        return try await withCheckedThrowingContinuation { continuation in
            graphQLClient.execute(query: query, variables: variables) { (result: Result<SingleTagResponse, GraphQLNetworkError>) in
                switch result {
                case .success(let response):
                    continuation.resume(returning: response.data?.findTag)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
