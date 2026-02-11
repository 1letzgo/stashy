//
//  GalleriesViewModel.swift
//  stashy
//
//  Created by Architecture Improvement on 17.01.26.
//

import Foundation
import Combine

@MainActor
class GalleriesViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let galleryRepository: GalleryRepositoryProtocol
    
    // MARK: - Published Properties
    
    @Published var galleriesLoader: PaginatedLoader<Gallery>
    @Published var currentSortOption: StashDBViewModel.GallerySortOption = .titleAsc
    @Published var searchQuery: String = ""
    @Published var currentFilter: StashDBViewModel.SavedFilter?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(galleryRepository: GalleryRepositoryProtocol = GalleryRepository()) {
        self.galleryRepository = galleryRepository
        
        // Initialize with default loader (use literal defaults to avoid accessing self before init)
        self.galleriesLoader = PaginatedLoader<Gallery>.galleries(
            repository: galleryRepository,
            sortBy: .titleAsc,
            searchQuery: "",
            filter: nil
        )
        
        setupBindings()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Recreate loader when sort option changes
        $currentSortOption
            .dropFirst()
            .sink { [weak self] sortOption in
                self?.updateLoader()
            }
            .store(in: &cancellables)
        
        // Recreate loader when search query changes (with debounce)
        $searchQuery
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] searchQuery in
                self?.updateLoader()
            }
            .store(in: &cancellables)
        
        // Recreate loader when filter changes
        $currentFilter
            .dropFirst()
            .sink { [weak self] filter in
                self?.updateLoader()
            }
            .store(in: &cancellables)
    }
    
    private func updateLoader() {
        galleriesLoader = PaginatedLoader<Gallery>.galleries(
            repository: galleryRepository,
            sortBy: currentSortOption,
            searchQuery: searchQuery,
            filter: currentFilter
        )
        
        Task {
            await galleriesLoader.loadInitial()
        }
    }
    
    // MARK: - Public Methods
    
    func loadInitialGalleries() async {
        await galleriesLoader.loadInitial()
    }
    
    func loadMoreGalleries() async {
        await galleriesLoader.loadMore()
    }
    
    func refreshGalleries() async {
        await galleriesLoader.refresh()
    }
    
    func updateSortOption(_ sortOption: StashDBViewModel.GallerySortOption) {
        currentSortOption = sortOption
    }
    
    func updateSearchQuery(_ query: String) {
        searchQuery = query
    }
    
    func updateFilter(_ filter: StashDBViewModel.SavedFilter?) {
        currentFilter = filter
    }
    
    func clearSearch() {
        searchQuery = ""
    }
    
    func clearFilter() {
        currentFilter = nil
    }
    
    // MARK: - Computed Properties
    
    var galleries: [Gallery] {
        return galleriesLoader.items
    }
    
    var isLoading: Bool {
        return galleriesLoader.isLoading
    }
    
    var isLoadingMore: Bool {
        return galleriesLoader.isLoadingMore
    }
    
    var hasMoreGalleries: Bool {
        return galleriesLoader.hasMore
    }
    
    var isEmpty: Bool {
        return galleriesLoader.isEmpty
    }
    
    var totalCount: Int {
        return galleriesLoader.totalCount
    }
    
    var currentCount: Int {
        return galleriesLoader.currentCount
    }
    
    var error: Error? {
        return galleriesLoader.error
    }
}