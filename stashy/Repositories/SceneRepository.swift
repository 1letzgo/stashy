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
    
    /// Fetches a single scene by ID
    func fetchSceneDetails(sceneId: String) async throws -> Scene?
    
    /// Updates the resume time for a scene
    func updateResumeTime(sceneId: String, resumeTime: Double) async throws -> Bool
    
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
    
    // MARK: - Fetch Scene Details
    
    func fetchSceneDetails(sceneId: String) async throws -> Scene? {
        let query = GraphQLQueries.queryWithFragments("findScene")
        let variables: [String: Any] = ["id": sceneId]
        
        let response: SingleSceneResponse = try await graphQLClient.execute(query: query, variables: variables)
        return response.data?.findScene
    }
    
    // MARK: - Update Resume Time
    
    func updateResumeTime(sceneId: String, resumeTime: Double) async throws -> Bool {
        let formattedTime = String(format: "%.2f", resumeTime)
        let mutation = """
        mutation SceneSaveActivity($id: ID!, $resume_time: Float) {
            sceneSaveActivity(id: $id, resume_time: $resume_time, playDuration: 0)
        }
        """
        
        let variables: [String: Any] = [
            "id": sceneId,
            "resume_time": Double(formattedTime) ?? resumeTime
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
