//
//  StudiosViewModel.swift
//  stashy
//
//  Created by Architecture Improvement on 17.01.26.
//

import Foundation
import Combine

@MainActor
class StudiosViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let studioRepository: StudioRepositoryProtocol
    
    // MARK: - Published Properties
    
    @Published var studiosLoader: PaginatedLoader<Studio>
    @Published var currentSortOption: StashDBViewModel.StudioSortOption = .nameAsc
    @Published var searchQuery: String = ""
    @Published var currentFilter: StashDBViewModel.SavedFilter?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(studioRepository: StudioRepositoryProtocol = StudioRepository()) {
        self.studioRepository = studioRepository
        
        // Initialize with default loader (use literal defaults to avoid accessing self before init)
        self.studiosLoader = PaginatedLoader<Studio>.studios(
            repository: studioRepository,
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
        studiosLoader = PaginatedLoader<Studio>.studios(
            repository: studioRepository,
            sortBy: currentSortOption,
            searchQuery: searchQuery,
            filter: currentFilter
        )
        
        Task {
            await studiosLoader.loadInitial()
        }
    }
    
    // MARK: - Public Methods
    
    func loadInitialStudios() async {
        await studiosLoader.loadInitial()
    }
    
    func loadMoreStudios() async {
        await studiosLoader.loadMore()
    }
    
    func refreshStudios() async {
        await studiosLoader.refresh()
    }
    
    func updateSortOption(_ sortOption: StashDBViewModel.StudioSortOption) {
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
    
    var studios: [Studio] {
        return studiosLoader.items
    }
    
    var isLoading: Bool {
        return studiosLoader.isLoading
    }
    
    var isLoadingMore: Bool {
        return studiosLoader.isLoadingMore
    }
    
    var hasMoreStudios: Bool {
        return studiosLoader.hasMore
    }
    
    var isEmpty: Bool {
        return studiosLoader.isEmpty
    }
    
    var totalCount: Int {
        return studiosLoader.totalCount
    }
    
    var currentCount: Int {
        return studiosLoader.currentCount
    }
    
    var error: Error? {
        return studiosLoader.error
    }
}