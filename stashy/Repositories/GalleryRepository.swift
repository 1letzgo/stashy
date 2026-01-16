//
//  GalleryRepository.swift
//  stashy
//
//  Created by Gemini on 16.01.26.
//

import Foundation

// MARK: - Gallery Repository Protocol

protocol GalleryRepositoryProtocol {
    /// Fetches a paginated list of galleries
    func fetchGalleries(
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.GallerySortOption,
        searchQuery: String,
        filter: StashDBViewModel.SavedFilter?
    ) async throws -> (galleries: [Gallery], total: Int)
    
    /// Fetches galleries for a specific performer
    func fetchPerformerGalleries(
        performerId: String,
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.GallerySortOption
    ) async throws -> (galleries: [Gallery], total: Int)
    
    /// Fetches galleries for a specific studio
    func fetchStudioGalleries(
        studioId: String,
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.GallerySortOption
    ) async throws -> (galleries: [Gallery], total: Int)
    
    /// Fetches images for a gallery
    func fetchGalleryImages(
        galleryId: String,
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.ImageSortOption
    ) async throws -> (images: [StashImage], total: Int)
}

// MARK: - Gallery Repository Implementation

class GalleryRepository: GalleryRepositoryProtocol {
    
    private let graphQLClient: GraphQLClient
    
    init(graphQLClient: GraphQLClient = .shared) {
        self.graphQLClient = graphQLClient
    }
    
    // MARK: - Fetch Galleries List
    
    func fetchGalleries(
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.GallerySortOption,
        searchQuery: String,
        filter: StashDBViewModel.SavedFilter?
    ) async throws -> (galleries: [Gallery], total: Int) {
        let query = GraphQLQueries.queryWithFragments("findGalleries")
        
        var galleryFilter: [String: Any] = [:]
        
        // Add search filter
        if !searchQuery.isEmpty {
            galleryFilter["title"] = ["value": searchQuery, "modifier": "INCLUDES"]
        }
        
        // Apply saved filter if present
        if let savedFilter = filter, let filterJson = savedFilter.filter {
            galleryFilter = filterJson
        }
        
        var variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ]
        ]
        
        if !galleryFilter.isEmpty {
            variables["gallery_filter"] = galleryFilter
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            graphQLClient.execute(query: query, variables: variables) { (result: Result<GalleryResponse, GraphQLNetworkError>) in
                switch result {
                case .success(let response):
                    let galleries = response.data?.findGalleries?.galleries ?? []
                    let total = response.data?.findGalleries?.count ?? 0
                    continuation.resume(returning: (galleries, total))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Fetch Performer Galleries
    
    func fetchPerformerGalleries(
        performerId: String,
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.GallerySortOption
    ) async throws -> (galleries: [Gallery], total: Int) {
        let query = GraphQLQueries.queryWithFragments("findGalleries")
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ],
            "gallery_filter": [
                "performers": [
                    "value": [performerId],
                    "modifier": "INCLUDES"
                ]
            ]
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            graphQLClient.execute(query: query, variables: variables) { (result: Result<GalleryResponse, GraphQLNetworkError>) in
                switch result {
                case .success(let response):
                    let galleries = response.data?.findGalleries?.galleries ?? []
                    let total = response.data?.findGalleries?.count ?? 0
                    continuation.resume(returning: (galleries, total))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Fetch Studio Galleries
    
    func fetchStudioGalleries(
        studioId: String,
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.GallerySortOption
    ) async throws -> (galleries: [Gallery], total: Int) {
        let query = GraphQLQueries.queryWithFragments("findGalleries")
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ],
            "gallery_filter": [
                "studios": [
                    "value": [studioId],
                    "modifier": "INCLUDES",
                    "depth": 0
                ]
            ]
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            graphQLClient.execute(query: query, variables: variables) { (result: Result<GalleryResponse, GraphQLNetworkError>) in
                switch result {
                case .success(let response):
                    let galleries = response.data?.findGalleries?.galleries ?? []
                    let total = response.data?.findGalleries?.count ?? 0
                    continuation.resume(returning: (galleries, total))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Fetch Gallery Images
    
    func fetchGalleryImages(
        galleryId: String,
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.ImageSortOption
    ) async throws -> (images: [StashImage], total: Int) {
        let query = GraphQLQueries.queryWithFragments("findImages")
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ],
            "image_filter": [
                "galleries": [
                    "value": [galleryId],
                    "modifier": "INCLUDES"
                ]
            ]
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            graphQLClient.execute(query: query, variables: variables) { (result: Result<ImagesResponse, GraphQLNetworkError>) in
                switch result {
                case .success(let response):
                    let images = response.data?.findImages?.images ?? []
                    let total = response.data?.findImages?.count ?? 0
                    continuation.resume(returning: (images, total))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
