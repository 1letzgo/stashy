//
//  SceneRepository.swift
//  stashy
//
//  Created by Gemini on 16.01.26.
//

import Foundation
import Combine

// MARK: - Scene Repository Protocol

protocol SceneRepositoryProtocol {
    /// Fetches a paginated list of scenes
    func fetchScenes(
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.SceneSortOption,
        searchQuery: String,
        filter: StashDBViewModel.SavedFilter?
    ) async throws -> (scenes: [Scene], total: Int)
    
    /// Fetches scenes for a specific performer
    func fetchPerformerScenes(
        performerId: String,
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.SceneSortOption
    ) async throws -> (scenes: [Scene], total: Int)
    
    /// Fetches scenes for a specific studio
    func fetchStudioScenes(
        studioId: String,
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.SceneSortOption
    ) async throws -> (scenes: [Scene], total: Int)
    
    /// Fetches scenes for a specific tag
    func fetchTagScenes(
        tagId: String,
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.SceneSortOption
    ) async throws -> (scenes: [Scene], total: Int)
    
    /// Fetches the scenes linked to a gallery
    func fetchGalleryScenes(galleryId: String) async throws -> [Scene]

    /// Fetches a single scene by ID
    func fetchSceneDetails(sceneId: String) async throws -> Scene?
    
    /// Updates resume time and/or adds watched seconds via `sceneSaveActivity`
    func updateResumeTime(sceneId: String, resumeTime: Double, playDuration: Double) async throws -> Bool
    
    /// Increments the play count for a scene
    func addPlay(sceneId: String) async throws -> Bool
    
    /// Deletes a scene
    func deleteScene(sceneId: String) async throws -> Bool
}

// MARK: - Scene Repository Implementation

class SceneRepository: SceneRepositoryProtocol {
    
    private let graphQLClient: GraphQLClient
    
    init(graphQLClient: GraphQLClient = .shared) {
        self.graphQLClient = graphQLClient
    }
    
    // MARK: - Fetch Scenes List
    
    func fetchScenes(
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.SceneSortOption,
        searchQuery: String,
        filter: StashDBViewModel.SavedFilter?
    ) async throws -> (scenes: [Scene], total: Int) {
        let query = GraphQLQueries.queryWithFragments("findScenes")
        
        var sceneFilter: [String: Any] = [:]
        
        // Add search filter
        if !searchQuery.isEmpty {
            sceneFilter["title"] = ["value": searchQuery, "modifier": "INCLUDES"]
        }
        
        // Apply saved filter if present
        if let savedFilter = filter, let filterDict = savedFilter.filterDict {
            sceneFilter = filterDict
        }
        
        var variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ]
        ]
        
        if !sceneFilter.isEmpty {
            variables["scene_filter"] = sceneFilter
        }
        
        let response: AltScenesResponse = try await graphQLClient.execute(query: query, variables: variables)
        let scenes = response.data?.findScenes?.scenes ?? []
        let total = response.data?.findScenes?.count ?? 0
        return (scenes, total)
    }
    
    // MARK: - Fetch Performer Scenes
    
    func fetchPerformerScenes(
        performerId: String,
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.SceneSortOption
    ) async throws -> (scenes: [Scene], total: Int) {
        let query = GraphQLQueries.queryWithFragments("findScenes")
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ],
            "scene_filter": [
                "performers": [
                    "value": [performerId],
                    "modifier": "INCLUDES"
                ]
            ]
        ]
        
        let response: AltScenesResponse = try await graphQLClient.execute(query: query, variables: variables)
        let scenes = response.data?.findScenes?.scenes ?? []
        let total = response.data?.findScenes?.count ?? 0
        return (scenes, total)
    }
    
    // MARK: - Fetch Studio Scenes
    
    func fetchStudioScenes(
        studioId: String,
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.SceneSortOption
    ) async throws -> (scenes: [Scene], total: Int) {
        let query = GraphQLQueries.queryWithFragments("findScenes")
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ],
            "scene_filter": [
                "studios": [
                    "value": [studioId],
                    "modifier": "INCLUDES",
                    "depth": 0
                ]
            ]
        ]
        
        let response: AltScenesResponse = try await graphQLClient.execute(query: query, variables: variables)
        let scenes = response.data?.findScenes?.scenes ?? []
        let total = response.data?.findScenes?.count ?? 0
        return (scenes, total)
    }
    
    // MARK: - Fetch Tag Scenes
    
    func fetchTagScenes(
        tagId: String,
        page: Int,
        perPage: Int,
        sortBy: StashDBViewModel.SceneSortOption
    ) async throws -> (scenes: [Scene], total: Int) {
        let query = GraphQLQueries.queryWithFragments("findScenes")
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ],
            "scene_filter": [
                "tags": [
                    "value": [tagId],
                    "modifier": "INCLUDES",
                    "depth": 0
                ]
            ]
        ]
        
        let response: AltScenesResponse = try await graphQLClient.execute(query: query, variables: variables)
        let scenes = response.data?.findScenes?.scenes ?? []
        let total = response.data?.findScenes?.count ?? 0
        return (scenes, total)
    }
    
    // MARK: - Fetch Gallery Scenes

    func fetchGalleryScenes(galleryId: String) async throws -> [Scene] {
        let query = GraphQLQueries.queryWithFragments("findScenes")

        let variables: [String: Any] = [
            "filter": ["page": 1, "per_page": 40, "sort": "date", "direction": "DESC"],
            "scene_filter": [
                "galleries": ["value": [galleryId], "modifier": "INCLUDES"]
            ]
        ]

        let response: AltScenesResponse = try await graphQLClient.execute(query: query, variables: variables)
        return response.data?.findScenes?.scenes ?? []
    }

    // MARK: - Fetch Scene Details
    
    func fetchSceneDetails(sceneId: String) async throws -> Scene? {
        let query = GraphQLQueries.queryWithFragments("findScene")
        let variables: [String: Any] = ["id": sceneId]
        
        let response: SingleSceneResponse = try await graphQLClient.execute(query: query, variables: variables)
        return response.data?.findScene
    }
    
    // MARK: - Update Resume Time
    
    func updateResumeTime(sceneId: String, resumeTime: Double, playDuration: Double = 0) async throws -> Bool {
        let formattedTime = String(format: "%.2f", resumeTime)
        let formattedDuration = String(format: "%.2f", max(0, playDuration))
        let mutation = """
        mutation SceneSaveActivity($id: ID!, $resume_time: Float, $playDuration: Float) {
            sceneSaveActivity(id: $id, resume_time: $resume_time, playDuration: $playDuration)
        }
        """
        
        let variables: [String: Any] = [
            "id": sceneId,
            "resume_time": Double(formattedTime) ?? resumeTime,
            "playDuration": Double(formattedDuration) ?? max(0, playDuration)
        ]
        
        do {
            let response = try await graphQLClient.performMutation(mutation: mutation, variables: variables)
            if let data = response["data"]?.value as? [String: Any],
               data["sceneSaveActivity"] != nil {
                return true
            }
            return false
        } catch {
            return false
        }
    }
    
    // MARK: - Add Play Count
    
    func addPlay(sceneId: String) async throws -> Bool {
        let mutation = """
        mutation SceneAddPlay($id: ID!) {
            sceneAddPlay(id: $id)
        }
        """
        
        let variables: [String: Any] = ["id": sceneId]
        
        do {
            let response = try await graphQLClient.performMutation(mutation: mutation, variables: variables)
            if let data = response["data"]?.value as? [String: Any],
               data["sceneAddPlay"] != nil {
                return true
            }
            return false
        } catch {
            return false
        }
    }
    
    // MARK: - Delete Scene
    
    func deleteScene(sceneId: String) async throws -> Bool {
        let mutation = """
        mutation SceneDestroy($id: ID!) {
            sceneDestroy(input: { id: $id })
        }
        """
        
        let variables: [String: Any] = ["id": sceneId]
        
        do {
            let response = try await graphQLClient.performMutation(mutation: mutation, variables: variables)
            if let data = response["data"]?.value as? [String: Any],
               data["sceneDestroy"] != nil {
                return true
            }
            return false
        } catch {
            return false
        }
    }
}

// MARK: - Production date (Stash 0.32+)

/// Kept out of the scene fragments: older servers reject a whole query over the unknown field.
enum SceneProductionDate {
    /// Stash stores a partial date with its precision: `2024`, `2024-05` or `2024-05-17`.
    static func isValid(_ text: String) -> Bool {
        text.isEmpty || text.range(of: #"^\d{4}(-\d{2}(-\d{2})?)?$"#, options: .regularExpression) != nil
    }

    private struct FetchResponse: Decodable {
        struct DataContainer: Decodable {
            struct SceneDate: Decodable { let production_date: String? }
            let findScene: SceneDate?
        }
        let data: DataContainer?
    }

    private struct UpdateResponse: Decodable {
        struct DataContainer: Decodable {
            struct Updated: Decodable { let id: String }
            let sceneUpdate: Updated?
        }
        let data: DataContainer?
    }

    static func fetch(sceneId: String) async -> String? {
        guard StashServerCapabilities.supports032 else { return nil }
        let response: FetchResponse? = try? await GraphQLClient.shared.execute(
            query: GraphQLQueries.loadQuery(named: "findSceneProductionDate"),
            variables: ["id": sceneId]
        )
        return response?.data?.findScene?.production_date
    }

    /// An empty `date` clears the field.
    static func update(sceneId: String, date: String) async -> Bool {
        let input: [String: Any] = ["id": sceneId, "production_date": date.isEmpty ? NSNull() : date]
        let response: UpdateResponse? = try? await GraphQLClient.shared.execute(
            query: GraphQLQueries.loadQuery(named: "sceneUpdateProductionDate"),
            variables: ["input": input]
        )
        return response?.data?.sceneUpdate != nil
    }
}
