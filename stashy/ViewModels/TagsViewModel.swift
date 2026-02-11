//
//  TagsViewModel.swift
//  stashy
//
//  Created by Architecture Improvement on 17.01.26.
//

import Foundation
import Combine

@MainActor
class TagsViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let tagRepository: TagRepositoryProtocol
    
    // MARK: - Published Properties
    
    @Published var tagsLoader: PaginatedLoader<Tag>
    @Published var searchQuery: String = ""
    @Published var currentFilter: StashDBViewModel.SavedFilter?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(tagRepository: TagRepositoryProtocol = TagRepository()) {
        self.tagRepository = tagRepository
        
        // Initialize with default loader (use literal defaults to avoid accessing self before init)
        self.tagsLoader = PaginatedLoader<Tag>.tags(
            repository: tagRepository,
            searchQuery: "",
            filter: nil
        )
        
        setupBindings()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
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
        tagsLoader = PaginatedLoader<Tag>.tags(
            repository: tagRepository,
            searchQuery: searchQuery,
            filter: currentFilter
        )
        
        Task {
            await tagsLoader.loadInitial()
        }
    }
    
    // MARK: - Public Methods
    
    func loadInitialTags() async {
        await tagsLoader.loadInitial()
    }
    
    func loadMoreTags() async {
        await tagsLoader.loadMore()
    }
    
    func refreshTags() async {
        await tagsLoader.refresh()
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
    
    var tags: [Tag] {
        return tagsLoader.items
    }
    
    var isLoading: Bool {
        return tagsLoader.isLoading
    }
    
    var isLoadingMore: Bool {
        return tagsLoader.isLoadingMore
    }
    
    var hasMoreTags: Bool {
        return tagsLoader.hasMore
    }
    
    var isEmpty: Bool {
        return tagsLoader.isEmpty
    }
    
    var totalCount: Int {
        return tagsLoader.totalCount
    }
    
    var currentCount: Int {
        return tagsLoader.currentCount
    }
    
    var error: Error? {
        return tagsLoader.error
    }
}