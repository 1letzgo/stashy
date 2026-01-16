---
description: Stashy App Architecture Improvement - 6-Phase Plan
---

# Stashy Architecture Improvement Workflow

This workflow describes how to improve the Stashy iOS app architecture step by step.

## Prerequisites
- Xcode project is open
- App compiles successfully before starting

## Phase 1: Network Layer Extraction (2-3h)
> Extract networking logic from StashDBViewModel into dedicated GraphQLClient

1. Create new file `stashy/Networking/GraphQLClient.swift`
2. Move `performGraphQLQuery` method from StashDBViewModel to GraphQLClient
3. Add async/await support alongside completion handlers
4. Add proper error types (NetworkError enum)
5. Update all 24+ callers in StashDBViewModel to use new client
6. Test: Run app and verify all data loads correctly

## Phase 2: Query Externalization (1-2h)
> Use existing .graphql files instead of inline strings

1. Create `stashy/Networking/GraphQLQueries.swift`
2. Add static method to load query from bundle: `loadQuery(_ name: String) -> String`
3. Replace inline query strings with `GraphQLQueries.findScenes`, etc.
4. Verify all 40 .graphql files in `/graphql/` are used
5. Test: Confirm all queries execute successfully

## Phase 3: Repository Pattern (4-6h)
> Organize data access by domain

1. Create folder `stashy/Repositories/`
2. Create `SceneRepository.swift` - extract all scene-related methods
3. Create `PerformerRepository.swift` - extract performer methods
4. Create `StudioRepository.swift` - extract studio methods  
5. Create `GalleryRepository.swift` - extract gallery methods
6. Create `TagRepository.swift` - extract tag methods
7. Add protocols for each repository (enables testing)
8. Test: Each repository in isolation

## Phase 4: Pagination Abstraction (2-3h)
> Create reusable pagination component

1. Create `stashy/Utilities/PaginatedLoader.swift`
2. Implement generic `PaginatedLoader<T>` with:
   - `@Published var items: [T]`
   - `@Published var isLoading: Bool`
   - `@Published var hasMore: Bool`
   - `func loadInitial() async`
   - `func loadMore() async`
3. Migrate one view (e.g., ScenesView) to use PaginatedLoader
4. Migrate remaining views
5. Test: Pagination works in all list views

## Phase 5: ViewModel Decomposition (8-12h)
> Split monolithic ViewModel into domain-specific ViewModels

1. Create `ScenesViewModel.swift` using SceneRepository + PaginatedLoader
2. Create `PerformersViewModel.swift`
3. Create `StudiosViewModel.swift`
4. Create `GalleriesViewModel.swift`
5. Create `TagsViewModel.swift`
6. Create `StatisticsViewModel.swift`
7. Migrate views one by one to new ViewModels
8. Deprecate StashDBViewModel (keep for compatibility during migration)
9. Test: Each tab works with new ViewModel

## Phase 6: API Caching (3-4h, Optional)
> Add response caching for better UX

1. Create `stashy/Networking/APICacheManager.swift`
2. Implement memory + disk cache (similar to ImageCacheManager)
3. Add TTL support (e.g., 5 min for details, 1 min for lists)
4. Integrate into GraphQLClient
5. Add cache invalidation on mutations
6. Test: Verify cached responses are used

## Verification Checklist
After each phase:
- [ ] App compiles without errors
- [ ] Navigate to all tabs successfully
- [ ] Scenes/Performers/Studios lists load and paginate
- [ ] Search works correctly
- [ ] Server switching works
- [ ] Offline error messages display correctly
