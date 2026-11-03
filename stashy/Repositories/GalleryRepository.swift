//
//  GalleryRepository.swift
//  stashy
//
//  Created by Gemini on 16.01.26.
//

import Foundation

// MARK: - Gallery Reader Info

struct GalleryReaderInfo: Decodable, Equatable {
    struct Chapter: Decodable, Identifiable, Equatable {
        let id: String
        let title: String
        /// 1-based page the chapter starts on.
        let image_index: Int
    }
    struct Tag: Decodable, Identifiable, Equatable {
        let id: String
        let name: String
    }
    let chapters: [Chapter]
    let tags: [Tag]
}

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
    
    /// Fetches `custom_fields` by gallery id. Separate from `GalleryFields`: that fragment has to
    /// keep working on servers whose galleries have no custom fields.
    func fetchCustomFields(galleryIds: [String]) async throws -> [String: [String: StashJSONValue]]
    
    /// Sets the given custom fields, leaving all others untouched
    func updateCustomFields(galleryId: String, partial: [String: Any]) async throws
    
    /// Fetches what the Magazin reader shows beyond the list's `GalleryFields`
    func fetchReaderInfo(galleryId: String) async throws -> GalleryReaderInfo
    
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
        if let savedFilter = filter, let filterDict = savedFilter.filterDict {
            galleryFilter = filterDict
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
        
        let response: GalleriesResponse = try await graphQLClient.execute(query: query, variables: variables)
        let galleries = response.data?.findGalleries.galleries ?? []
        let total = response.data?.findGalleries.count ?? 0
        return (galleries, total)
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
        
        let response: GalleriesResponse = try await graphQLClient.execute(query: query, variables: variables)
        let galleries = response.data?.findGalleries.galleries ?? []
        let total = response.data?.findGalleries.count ?? 0
        return (galleries, total)
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
        
        let response: GalleriesResponse = try await graphQLClient.execute(query: query, variables: variables)
        let galleries = response.data?.findGalleries.galleries ?? []
        let total = response.data?.findGalleries.count ?? 0
        return (galleries, total)
    }
    
    // MARK: - Gallery Custom Fields
    
    private struct CustomFieldsResponse: Decodable {
        struct DataContainer: Decodable {
            struct Result: Decodable {
                let galleries: [Entry]
            }
            let findGalleries: Result
        }
        struct Entry: Decodable {
            let id: String
            let custom_fields: [String: StashJSONValue]?
        }
        let data: DataContainer?
    }
    
    func fetchCustomFields(galleryIds: [String]) async throws -> [String: [String: StashJSONValue]] {
        let variables: [String: Any] = [
            "filter": ["per_page": galleryIds.count],
            "ids": galleryIds
        ]
        let response: CustomFieldsResponse = try await graphQLClient.execute(
            query: GraphQLQueries.loadQuery(named: "findGalleriesCustomFields"),
            variables: variables
        )
        var fields: [String: [String: StashJSONValue]] = [:]
        for gallery in response.data?.findGalleries.galleries ?? [] {
            fields[gallery.id] = gallery.custom_fields ?? [:]
        }
        return fields
    }
    
    func updateCustomFields(galleryId: String, partial: [String: Any]) async throws {
        let variables: [String: Any] = [
            "input": [
                "id": galleryId,
                "custom_fields": ["partial": partial]
            ]
        ]
        _ = try await graphQLClient.executeRaw(
            query: GraphQLQueries.loadQuery(named: "galleryUpdateCustomFields"),
            variables: variables
        )
    }
    
    // MARK: - Gallery Reader Info
    
    private struct ReaderInfoResponse: Decodable {
        struct DataContainer: Decodable {
            let findGallery: GalleryReaderInfo?
        }
        let data: DataContainer?
    }
    
    func fetchReaderInfo(galleryId: String) async throws -> GalleryReaderInfo {
        let response: ReaderInfoResponse = try await graphQLClient.execute(
            query: GraphQLQueries.loadQuery(named: "findGalleryReaderInfo"),
            variables: ["id": galleryId]
        )
        return response.data?.findGallery ?? GalleryReaderInfo(chapters: [], tags: [])
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
        
        let response: GalleryImagesResponse = try await graphQLClient.execute(query: query, variables: variables)
        let images = response.data?.findImages.images ?? []
        let total = response.data?.findImages.count ?? 0
        return (images, total)
    }
}
