//
//  GraphQLQueries.swift
//  stashy
//
//  Created for architecture improvement - Phase 2
//

import Foundation

class GraphQLQueries {
    
    // MARK: - Thread Safety
    
    /// Serial queue for thread-safe cache access
    private static let cacheQueue = DispatchQueue(label: "com.stashy.graphql.cache", attributes: .concurrent)
    
    // MARK: - Cache & Diagnostics
    private static var cachedQueries: [String: String] = [:]
    private static let cacheLock = NSLock()
    private static var hasLoggedAllResources = false
    private static var _composedQueryCache: [String: String] = [:]
    private static var __sceneRelatedFragments: String?
    
    // Thread-safe accessors
    private static func getCachedQuery(_ key: String) -> String? {
        cacheQueue.sync { cachedQueries[key] }
    }
    
    private static func setCachedQuery(_ key: String, value: String) {
        cacheQueue.async(flags: .barrier) { cachedQueries[key] = value }
    }
    
    private static func getComposedQuery(_ key: String) -> String? {
        cacheQueue.sync { _composedQueryCache[key] }
    }
    
    private static func setComposedQuery(_ key: String, value: String) {
        cacheQueue.async(flags: .barrier) { _composedQueryCache[key] = value }
    }
    
    private static func getSceneRelatedFragments() -> String? {
        cacheQueue.sync { __sceneRelatedFragments }
    }
    
    private static func setSceneRelatedFragments(_ value: String) {
        cacheQueue.async(flags: .barrier) { __sceneRelatedFragments = value }
    }
    
    // MARK: - Generic Loading (with caching)
    
    /// Loads a GraphQL query from cache or App Bundle
    static func loadQuery(named fileName: String) -> String {
        // Check cache first (thread-safe)
        if let cached = getCachedQuery(fileName) {
            return cached
        }
        
        // DEBUG: Deep bundle inspection
        if !hasLoggedAllResources {
            hasLoggedAllResources = true
            AppLog.debug("📁 --- BUNDLE INSPECTION START ---")
            AppLog.debug("📁 Main Bundle Path: \(Bundle.main.bundlePath)")
            
            // List everything in the root
            if let rootFiles = try? FileManager.default.contentsOfDirectory(atPath: Bundle.main.bundlePath) {
                AppLog.debug("📁 Root files: \(rootFiles.joined(separator: ", "))")
            }
            
            // Specifically list 'graphql' directory if it exists
            let graphqlPath = (Bundle.main.bundlePath as NSString).appendingPathComponent("graphql")
            if let gFiles = try? FileManager.default.contentsOfDirectory(atPath: graphqlPath) {
                AppLog.debug("📁 'graphql' directory exists and contains: \(gFiles.joined(separator: ", "))")
            } else {
                AppLog.error("❌ 'graphql' directory NOT found at \(graphqlPath)")
            }
            
            // Try recursive scan for .graphql files
            let enumerator = FileManager.default.enumerator(atPath: Bundle.main.bundlePath)
            var foundGraphql: [String] = []
            while let file = enumerator?.nextObject() as? String {
                if file.hasSuffix(".graphql") {
                    foundGraphql.append(file)
                }
            }
            AppLog.debug("📁 Recursive scan found: \(foundGraphql.joined(separator: ", "))")
            AppLog.debug("📁 --- BUNDLE INSPECTION END ---")
        }

        // Load from bundle
        var content = ""
        
        // Try multiple strategies
        let strategies: [() -> URL?] = [
            { Bundle.main.url(forResource: fileName, withExtension: "graphql", subdirectory: "graphql") },
            { Bundle.main.url(forResource: fileName, withExtension: "graphql") },
            { 
                let path = (Bundle.main.bundlePath as NSString).appendingPathComponent("graphql/\(fileName).graphql")
                return URL(fileURLWithPath: path)
            },
            {
                let path = (Bundle.main.bundlePath as NSString).appendingPathComponent("\(fileName).graphql")
                return URL(fileURLWithPath: path)
            }
        ]
        
        var foundUrl: URL? = nil
        for strategy in strategies {
            if let url = strategy(), FileManager.default.fileExists(atPath: url.path) {
                foundUrl = url
                break
            }
        }
        
        if let url = foundUrl {
            do {
                content = try String(contentsOf: url, encoding: .utf8)
                AppLog.debug("✅ Found and loaded: \(fileName).graphql from \(url.lastPathComponent)")
            } catch {
                AppLog.error("❌ Critical: Failed to load GraphQL file: \(fileName).graphql - \(error)")
            }
        } else {
            AppLog.error("❌ Critical: Could not find GraphQL file: \(fileName).graphql in ANY location")
        }
        
        // Cache the result (even if empty, to avoid repeated lookups)
        setCachedQuery(fileName, value: content)
        return content
    }
    
    // MARK: - Cached Fragment Composition
    
    static var sceneRelatedFragments: String {
        if let cached = getSceneRelatedFragments() { return cached }
        let result = "\(loadQuery(named: "fragment_SceneFields"))\n\(loadQuery(named: "fragment_PerformerFields"))\n\(loadQuery(named: "fragment_StudioFields"))\n\(loadQuery(named: "fragment_TagFields"))"
        setSceneRelatedFragments(result)
        return result
    }
    
    // MARK: - Query Composition (with caching)
    
    /// Helper to combine a main query with ONLY the necessary fragments (cached)
    static func queryWithFragments(_ queryName: String) -> String {
        // Check composed query cache (thread-safe)
        if let cached = getComposedQuery(queryName) {
            return cached
        }
        
        let query = loadQuery(named: queryName)
        var fragments = ""
        
        // Append only required fragments based on query name
        switch queryName {
        case "findScenes":
            // List: schlankes Fragment (ohne Marker/Tags/Galleries/Groups und ohne riesige PerformerFields-Streuung).
            fragments = loadQuery(named: "fragment_SceneListFields")
        case "findScene":
            fragments = sceneRelatedFragments
            
        case "findPerformers":
            fragments = loadQuery(named: "fragment_PerformerFields")
            
        case "hotOrNotFindPerformers":
            fragments = loadQuery(named: "fragment_HotOrNotPerformerFields")
            
        case "findStudios", "findStudio":
            fragments = loadQuery(named: "fragment_StudioFields")
            
        case "findGalleries":
            fragments = loadQuery(named: "fragment_GalleryFields")
            
        case "findTags", "findTag":
            fragments = loadQuery(named: "fragment_TagFields")
            
        case "findImages":
            fragments = loadQuery(named: "fragment_ImageFields")
            
        case "findSceneMarkers":
            fragments = loadQuery(named: "fragment_PerformerFields")
            
        case "findGroups", "findGroup":
            // Groups don't have a dedicated fragment yet, they use inline fields in findGroups.graphql
            fragments = ""
            
        default:
            AppLog.error("⚠️ Warning: No explicit fragment mapping for \(queryName)")
        }
        
        let composed = "\(query)\n\(fragments)"
        setComposedQuery(queryName, value: composed)
        return composed
    }
    
    // MARK: - Inline Queries/Mutations (extracted from StashDBViewModel)

    static let findSavedFiltersQuery = """
        {
          "query": "query GetAllFilterDefinitions { findSavedFilters { id name mode filter object_filter ui_options find_filter { sort direction } } }"
        }
        """

    static let serverVersionQuery = """
        {
          "query": "{ version { version } }"
        }
        """

    static let serverStatsQuery = """
        {
          "query": "{ stats { scene_count scenes_size scenes_duration image_count images_size gallery_count performer_count studio_count group_count tag_count total_o_count total_play_duration total_play_count scenes_played movie_count } }"
        }
        """

    static let findSceneMarkersCountQuery = """
        {
          "query": "{ findSceneMarkers(filter: { per_page: 1 }) { count } }"
        }
        """

    static let findGroupsForSceneQuery = """
        query FindGroups($filter: FindFilterType) {
            findGroups(filter: $filter) {
                groups { id name updated_at front_image_path }
            }
        }
        """

    static let findGalleriesForSceneQuery = """
        query FindGalleries($filter: FindFilterType, $gallery_filter: GalleryFilterType) {
            findGalleries(filter: $filter, gallery_filter: $gallery_filter) {
                galleries {
                    id
                    title
                    date
                    image_count
                    updated_at
                    cover { id paths { thumbnail } }
                }
            }
        }
        """
    static let saveSceneFilterMutation = """
        mutation SaveSceneFilter($input: SaveFilterInput!) {
          saveFilter(input: $input) {
            id
            name
            mode
            filter
            object_filter
            ui_options
            find_filter { sort direction }
          }
        }
        """

    static let saveCatalogFilterMutation = """
        mutation SaveCatalogFilter($input: SaveFilterInput!) {
          saveFilter(input: $input) {
            id
            name
            mode
            filter
            object_filter
            ui_options
            find_filter { sort direction }
          }
        }
        """

    static let destroySavedFilterMutation = """
        mutation DestroySavedSceneFilter($input: DestroyFilterInput!) {
          destroySavedFilter(input: $input)
        }
        """

    static let metadataScanMutation = """
        {
          "query": "mutation { metadataScan(input: {}) }"
        }
        """

    static let sceneAddPlayMutation = """
        mutation SceneAddPlay($id: ID!, $times: [Timestamp!]) {
          sceneAddPlay(id: $id, times: $times) {
            count
            history
          }
        }
        """

    static let sceneMarkerIncrementPlayMutation = """
        mutation SceneMarkerIncrementPlay($id: ID!) {
          sceneMarkerUpdate(input: { id: $id }) {
            id
            play_count
          }
        }
        """

    static let sceneMarkerCreateMutation = """
        mutation SceneMarkerCreate($input: SceneMarkerCreateInput!) {
            sceneMarkerCreate(input: $input) {
                id
                title
                seconds
                screenshot
            }
        }
        """

    static let sceneUpdateOrganizedMutation = """
        mutation SceneUpdate($input: SceneUpdateInput!) {
            sceneUpdate(input: $input) { id organized }
        }
        """

    static let sceneUpdateRatingMutation = """
        mutation SceneUpdate($input: SceneUpdateInput!) {
            sceneUpdate(input: $input) { id rating100 }
        }
        """

    static let sceneUpdatePerformersMutation = """
        mutation SceneUpdate($input: SceneUpdateInput!) {
            sceneUpdate(input: $input) { id performers { id name scene_count gallery_count o_counter updated_at } }
        }
        """

    static let sceneUpdateStudioMutation = """
        mutation SceneUpdate($input: SceneUpdateInput!) {
            sceneUpdate(input: $input) { id studio { id name updated_at } }
        }
        """

    static let sceneUpdateTagsMutation = """
        mutation SceneUpdate($input: SceneUpdateInput!) {
            sceneUpdate(input: $input) { id tags { id name } }
        }
        """

    /// Compact census queries for the AI Tags statistics model — ids only, so a
    /// 250-item page stays small even across a whole library.
    static let statsScenesQuery = """
        query StatsScenes($filter: FindFilterType, $scene_filter: SceneFilterType) {
            findScenes(filter: $filter, scene_filter: $scene_filter) {
                count
                scenes { id tags { id name } performers { id } studio { id } galleries { id } }
            }
        }
        """

    static let statsImagesQuery = """
        query StatsImages($filter: FindFilterType, $image_filter: ImageFilterType) {
            findImages(filter: $filter, image_filter: $image_filter) {
                count
                images { id tags { id name } performers { id } studio { id } galleries { id } }
            }
        }
        """

    static let sceneMarkerUpdateTagsMutation = """
        mutation SceneMarkerUpdate($input: SceneMarkerUpdateInput!) {
            sceneMarkerUpdate(input: $input) { id tags { id name } primary_tag { id name } }
        }
        """

    static let imageUpdateTagsMutation = """
        mutation ImageUpdate($input: ImageUpdateInput!) {
            imageUpdate(input: $input) { id tags { id name } }
        }
        """

    static let sceneUpdateGroupsMutation = """
        mutation SceneUpdate($input: SceneUpdateInput!) {
            sceneUpdate(input: $input) { id groups { group { id name updated_at front_image_path } scene_index } }
        }
        """

    static let sceneUpdateGalleriesMutation = """
        mutation SceneUpdate($input: SceneUpdateInput!) {
            sceneUpdate(input: $input) { id galleries { id title date image_count updated_at cover { id paths { thumbnail } } } }
        }
        """

    static let sceneUpdateTitleDetailsMutation = """
        mutation SceneUpdate($input: SceneUpdateInput!) {
            sceneUpdate(input: $input) { id title details }
        }
        """

    static let sceneUpdateLanguageMutation = """
        mutation SceneUpdate($input: SceneUpdateInput!) {
            sceneUpdate(input: $input) { id }
        }
        """

    static let sceneUpdateCoverImageMutation = """
        mutation SceneUpdate($input: SceneUpdateInput!) {
            sceneUpdate(input: $input) { id }
        }
        """

    static let tagUpdateFavoriteMutation = """
        mutation TagUpdate($input: TagUpdateInput!) {
            tagUpdate(input: $input) { id favorite }
        }
        """

    static let tagUpdateDetailsMutation = """
        mutation TagUpdate($input: TagUpdateInput!) {
            tagUpdate(input: $input) { id name description }
        }
        """

    static let tagUpdateImageMutation = """
        mutation TagUpdate($input: TagUpdateInput!) {
            tagUpdate(input: $input) { id }
        }
        """

    static let tagCreateMutation = """
        mutation TagCreate($input: TagCreateInput!) {
            tagCreate(input: $input) { id name scene_count }
        }
        """

    static let imageUpdateRatingMutation = """
        mutation ImageUpdate($input: ImageUpdateInput!) {
            imageUpdate(input: $input) { id rating100 }
        }
        """

    static let imageUpdateOCounterMutation = """
        mutation ImageUpdate($input: ImageUpdateInput!) {
            imageUpdate(input: $input) { id o_counter }
        }
        """

    static let performerCreateMutation = """
        mutation PerformerCreate($input: PerformerCreateInput!) {
            performerCreate(input: $input) { id name scene_count gallery_count updated_at }
        }
        """

    static let performerUpdateFavoriteMutation = """
        mutation PerformerUpdate($input: PerformerUpdateInput!) {
            performerUpdate(input: $input) { id favorite }
        }
        """

    static let performerUpdateImageMutation = """
        mutation PerformerUpdate($input: PerformerUpdateInput!) {
            performerUpdate(input: $input) { id image_path }
        }
        """

    static let performerUpdateDetailsMutation = """
        mutation PerformerUpdate($input: PerformerUpdateInput!) {
            performerUpdate(input: $input) {
                id name disambiguation birthdate country gender ethnicity
                height_cm weight measurements fake_tits penis_length
                career_length tattoos piercings alias_list rating100
            }
        }
        """

    static let studioCreateMutation = """
        mutation StudioCreate($input: StudioCreateInput!) {
            studioCreate(input: $input) { id name scene_count updated_at }
        }
        """

    static let studioUpdateFavoriteMutation = """
        mutation StudioUpdate($input: StudioUpdateInput!) {
            studioUpdate(input: $input) { id favorite }
        }
        """

    static let studioUpdateDetailsMutation = """
        mutation StudioUpdate($input: StudioUpdateInput!) {
            studioUpdate(input: $input) { id name url details rating100 }
        }
        """

    static let groupCreateMutation = """
        mutation GroupCreate($input: GroupCreateInput!) {
            groupCreate(input: $input) { id name updated_at front_image_path scene_count }
        }
        """

    static let groupUpdateDetailsMutation = """
        mutation GroupUpdate($input: GroupUpdateInput!) {
            groupUpdate(input: $input) { id name date synopsis rating100 }
        }
        """

    static let galleryUpdateDetailsMutation = """
        mutation GalleryUpdate($input: GalleryUpdateInput!) {
            galleryUpdate(input: $input) { id title date details }
        }
        """

    static let deleteFilesMutation = """
        mutation DeleteFiles($ids: [ID!]!) {
            deleteFiles(ids: $ids)
        }
        """
}

