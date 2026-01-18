//
//  ScenesViewModel.swift
//  stashy
//
//  Created by Architecture Improvement on 17.01.26.
//

import Foundation
import Combine

@MainActor
class ScenesViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let sceneRepository: SceneRepositoryProtocol
    
    // MARK: - Published Properties
    
    @Published var scenesLoader: PaginatedLoader<Scene>
    @Published var currentSortOption: StashDBViewModel.SceneSortOption = .dateDesc
    @Published var searchQuery: String = ""
    @Published var currentFilter: StashDBViewModel.SavedFilter?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(sceneRepository: SceneRepositoryProtocol = SceneRepository()) {
        self.sceneRepository = sceneRepository
        
        // Initialize with default loader
        self.scenesLoader = PaginatedLoader.scenes(
            repository: sceneRepository,
            sortBy: currentSortOption,
            searchQuery: searchQuery,
            filter: currentFilter
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
        scenesLoader = PaginatedLoader.scenes(
            repository: sceneRepository,
            sortBy: currentSortOption,
            searchQuery: searchQuery,
            filter: currentFilter
        )
        
        Task {
            await scenesLoader.loadInitial()
        }
    }
    
    // MARK: - Public Methods
    
    func loadInitialScenes() async {
        await scenesLoader.loadInitial()
    }
    
    func loadMoreScenes() async {
        await scenesLoader.loadMore()
    }
    
    func refreshScenes() async {
        await scenesLoader.refresh()
    }
    
    func updateSortOption(_ sortOption: StashDBViewModel.SceneSortOption) {
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
    
    var scenes: [Scene] {
        return scenesLoader.items
    }
    
    var isLoading: Bool {
        return scenesLoader.isLoading
    }
    
    var isLoadingMore: Bool {
        return scenesLoader.isLoadingMore
    }
    
    var hasMoreScenes: Bool {
        return scenesLoader.hasMore
    }
    
    var isEmpty: Bool {
        return scenesLoader.isEmpty
    }
    
    var totalCount: Int {
        return scenesLoader.totalCount
    }
    
    var currentCount: Int {
        return scenesLoader.currentCount
    }
    
    var error: Error? {
        return scenesLoader.error
    }
}