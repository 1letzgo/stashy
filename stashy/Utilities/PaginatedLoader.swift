//
//  PaginatedLoader.swift
//  stashy
//
//  Created by Architecture Improvement on 17.01.26.
//

import Foundation
import Combine

/// Generic pagination loader that handles loading states and data management
@MainActor
class PaginatedLoader<T>: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var items: [T] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMore: Bool = true
    @Published var error: Error?
    
    // MARK: - Private Properties
    
    private var currentPage: Int = 1
    private let perPage: Int
    private var totalItems: Int = 0
    
    // MARK: - Loader Function Type
    
    typealias LoaderFunction = (Int, Int) async throws -> (items: [T], total: Int)
    private let loaderFunction: LoaderFunction
    
    // MARK: - Initialization
    
    init(perPage: Int = 20, loader: @escaping LoaderFunction) {
        self.perPage = perPage
        self.loaderFunction = loader
    }
    
    // MARK: - Public Methods
    
    /// Loads the initial page of data
    func loadInitial() async {
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        currentPage = 1
        
        do {
            let result = try await loaderFunction(currentPage, perPage)
            items = result.items
            totalItems = result.total
            hasMore = items.count < totalItems
            currentPage += 1
        } catch {
            self.error = error
            items = []
            hasMore = false
        }
        
        isLoading = false
    }
    
    /// Loads the next page of data and appends to existing items
    func loadMore() async {
        guard !isLoadingMore && hasMore && !isLoading else { return }
        
        isLoadingMore = true
        error = nil
        
        do {
            let result = try await loaderFunction(currentPage, perPage)
            items.append(contentsOf: result.items)
            totalItems = result.total
            hasMore = items.count < totalItems
            currentPage += 1
        } catch {
            self.error = error
        }
        
        isLoadingMore = false
    }
    
    /// Refreshes the data by reloading the initial page
    func refresh() async {
        await loadInitial()
    }
    
    /// Resets the loader to initial state
    func reset() {
        items = []
        currentPage = 1
        totalItems = 0
        hasMore = true
        isLoading = false
        isLoadingMore = false
        error = nil
    }
    
    // MARK: - Computed Properties
    
    var isEmpty: Bool {
        return items.isEmpty && !isLoading
    }
    
    var totalCount: Int {
        return totalItems
    }
    
    var currentCount: Int {
        return items.count
    }
}

// MARK: - Convenience Extensions

extension PaginatedLoader {
    
    /// Creates a loader for scenes using SceneRepository
    static func scenes(
        repository: SceneRepositoryProtocol,
        sortBy: StashDBViewModel.SceneSortOption = .dateDesc,
        searchQuery: String = "",
        filter: StashDBViewModel.SavedFilter? = nil,
        perPage: Int = 20
    ) -> PaginatedLoader<Scene> {
        return PaginatedLoader<Scene>(perPage: perPage) { page, perPage in
            return try await repository.fetchScenes(
                page: page,
                perPage: perPage,
                sortBy: sortBy,
                searchQuery: searchQuery,
                filter: filter
            )
        }
    }
    
    /// Creates a loader for performers using PerformerRepository
    static func performers(
        repository: PerformerRepositoryProtocol,
        sortBy: StashDBViewModel.PerformerSortOption = .nameAsc,
        searchQuery: String = "",
        filter: StashDBViewModel.SavedFilter? = nil,
        perPage: Int = 500
    ) -> PaginatedLoader<Performer> {
        return PaginatedLoader<Performer>(perPage: perPage) { page, perPage in
            return try await repository.fetchPerformers(
                page: page,
                perPage: perPage,
                sortBy: sortBy,
                searchQuery: searchQuery,
                filter: filter
            )
        }
    }
    
    /// Creates a loader for studios using StudioRepository
    static func studios(
        repository: StudioRepositoryProtocol,
        sortBy: StashDBViewModel.StudioSortOption = .nameAsc,
        searchQuery: String = "",
        filter: StashDBViewModel.SavedFilter? = nil,
        perPage: Int = 500
    ) -> PaginatedLoader<Studio> {
        return PaginatedLoader<Studio>(perPage: perPage) { page, perPage in
            return try await repository.fetchStudios(
                page: page,
                perPage: perPage,
                sortBy: sortBy,
                searchQuery: searchQuery,
                filter: filter
            )
        }
    }
    
    /// Creates a loader for galleries using GalleryRepository
    static func galleries(
        repository: GalleryRepositoryProtocol,
        sortBy: StashDBViewModel.GallerySortOption = .titleAsc,
        searchQuery: String = "",
        filter: StashDBViewModel.SavedFilter? = nil,
        perPage: Int = 20
    ) -> PaginatedLoader<Gallery> {
        return PaginatedLoader<Gallery>(perPage: perPage) { page, perPage in
            return try await repository.fetchGalleries(
                page: page,
                perPage: perPage,
                sortBy: sortBy,
                searchQuery: searchQuery,
                filter: filter
            )
        }
    }
    
    /// Creates a loader for tags using TagRepository
    static func tags(
        repository: TagRepositoryProtocol,
        searchQuery: String = "",
        filter: StashDBViewModel.SavedFilter? = nil,
        perPage: Int = 500
    ) -> PaginatedLoader<Tag> {
        return PaginatedLoader<Tag>(perPage: perPage) { page, perPage in
            return try await repository.fetchTags(
                page: page,
                perPage: perPage,
                searchQuery: searchQuery,
                filter: filter
            )
        }
    }
}