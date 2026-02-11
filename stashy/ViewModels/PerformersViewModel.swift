//
//  PerformersViewModel.swift
//  stashy
//
//  Created by Architecture Improvement on 17.01.26.
//

import Foundation
import Combine

@MainActor
class PerformersViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let performerRepository: PerformerRepositoryProtocol
    
    // MARK: - Published Properties
    
    @Published var performersLoader: PaginatedLoader<Performer>
    @Published var currentSortOption: StashDBViewModel.PerformerSortOption = .nameAsc
    @Published var searchQuery: String = ""
    @Published var currentFilter: StashDBViewModel.SavedFilter?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(performerRepository: PerformerRepositoryProtocol = PerformerRepository()) {
        self.performerRepository = performerRepository
        
        // Initialize with default loader (use literal defaults to avoid accessing self before init)
        self.performersLoader = PaginatedLoader<Performer>.performers(
            repository: performerRepository,
            sortBy: .nameAsc,
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
        performersLoader = PaginatedLoader<Performer>.performers(
            repository: performerRepository,
            sortBy: currentSortOption,
            searchQuery: searchQuery,
            filter: currentFilter
        )
        
        Task {
            await performersLoader.loadInitial()
        }
    }
    
    // MARK: - Public Methods
    
    func loadInitialPerformers() async {
        await performersLoader.loadInitial()
    }
    
    func loadMorePerformers() async {
        await performersLoader.loadMore()
    }
    
    func refreshPerformers() async {
        await performersLoader.refresh()
    }
    
    func updateSortOption(_ sortOption: StashDBViewModel.PerformerSortOption) {
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
    
    var performers: [Performer] {
        return performersLoader.items
    }
    
    var isLoading: Bool {
        return performersLoader.isLoading
    }
    
    var isLoadingMore: Bool {
        return performersLoader.isLoadingMore
    }
    
    var hasMorePerformers: Bool {
        return performersLoader.hasMore
    }
    
    var isEmpty: Bool {
        return performersLoader.isEmpty
    }
    
    var totalCount: Int {
        return performersLoader.totalCount
    }
    
    var currentCount: Int {
        return performersLoader.currentCount
    }
    
    var error: Error? {
        return performersLoader.error
    }
}