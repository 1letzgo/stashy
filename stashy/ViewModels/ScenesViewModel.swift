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
    private let filterRepository: FilterRepositoryProtocol
    
    // MARK: - Published Properties
    
    @Published var scenesLoader: PaginatedLoader<Scene>
    @Published var currentSortOption: StashDBViewModel.SceneSortOption = .dateDesc
    @Published var searchQuery: String = ""
    @Published var currentFilter: StashDBViewModel.SavedFilter?
    @Published var savedFilters: [String: StashDBViewModel.SavedFilter] = [:]
    @Published var isLoadingFilters: Bool = false
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(
        sceneRepository: SceneRepositoryProtocol = SceneRepository(),
        filterRepository: FilterRepositoryProtocol = FilterRepository()
    ) {
        self.sceneRepository = sceneRepository
        self.filterRepository = filterRepository
        
        // Initialize with default loader (use literal defaults to avoid accessing self before init)
        self.scenesLoader = PaginatedLoader<Scene>.scenes(
            repository: sceneRepository,
            sortBy: .dateDesc,
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
        scenesLoader = PaginatedLoader<Scene>.scenes(
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
    
    func fetchSavedFilters() async {
        isLoadingFilters = true
        do {
            let filters = try await filterRepository.fetchSavedFilters()
            self.savedFilters = Dictionary(uniqueKeysWithValues: filters.map { ($0.id, $0) })
        } catch {
            print("❌ Error fetching saved filters: \(error.localizedDescription)")
        }
        isLoadingFilters = false
    }
    
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
    
    func updateSceneResumeTime(id: String, newResumeTime: Double) {
        if let index = scenesLoader.items.firstIndex(where: { $0.id == id }) {
            scenesLoader.items[index] = scenesLoader.items[index].withResumeTime(newResumeTime)
        }
    }
    
    func removeScene(id: String) {
        scenesLoader.items.removeAll(where: { $0.id == id })
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