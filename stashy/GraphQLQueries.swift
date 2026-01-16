//
//  GraphQLQueries.swift
//  stashy
//
//  Created for architecture improvement - Phase 2
//

import Foundation

class GraphQLQueries {
    
    // MARK: - Cache
    
    /// In-memory cache to avoid repeated disk reads
    private static var queryCache: [String: String] = [:]
    private static var composedQueryCache: [String: String] = [:]
    
    // MARK: - Generic Loading (with caching)
    
    /// Loads a GraphQL query from cache or App Bundle
    private static func loadQuery(named fileName: String) -> String {
        // Check cache first
        if let cached = queryCache[fileName] {
            return cached
        }
        
        // Load from bundle
        var content = ""
        
        if let url = Bundle.main.url(forResource: fileName, withExtension: "graphql", subdirectory: "graphql") {
            do {
                content = try String(contentsOf: url, encoding: .utf8)
            } catch {
                print("❌ Critical: Failed to load GraphQL file: \(fileName).graphql - \(error)")
            }
        } else if let fallbackUrl = Bundle.main.url(forResource: fileName, withExtension: "graphql") {
            // Fallback without subdirectory
            do {
                content = try String(contentsOf: fallbackUrl, encoding: .utf8)
            } catch {
                print("❌ Critical: Failed to load GraphQL file: \(fileName).graphql - \(error)")
            }
        } else {
            print("❌ Critical: Could not find GraphQL file: \(fileName).graphql")
        }
        
        // Cache the result (even if empty, to avoid repeated lookups)
        queryCache[fileName] = content
        return content
    }
    
    // MARK: - Cached Fragment Composition
    
    private static var _sceneRelatedFragments: String?
    static var sceneRelatedFragments: String {
        if let cached = _sceneRelatedFragments { return cached }
        let result = "\(loadQuery(named: "fragment_SceneFields"))\n\(loadQuery(named: "fragment_PerformerFields"))\n\(loadQuery(named: "fragment_StudioFields"))\n\(loadQuery(named: "fragment_TagFields"))"
        _sceneRelatedFragments = result
        return result
    }
    
    // MARK: - Query Composition (with caching)
    
    /// Helper to combine a main query with ONLY the necessary fragments (cached)
    static func queryWithFragments(_ queryName: String) -> String {
        // Check composed query cache
        if let cached = composedQueryCache[queryName] {
            return cached
        }
        
        let query = loadQuery(named: queryName)
        var fragments = ""
        
        // Append only required fragments based on query name
        switch queryName {
        case "findScenes", "findScene":
            fragments = sceneRelatedFragments
            
        case "findPerformers":
            fragments = loadQuery(named: "fragment_PerformerFields")
            
        case "findStudios", "findStudio":
            fragments = loadQuery(named: "fragment_StudioFields")
            
        case "findGalleries":
            fragments = loadQuery(named: "fragment_GalleryFields")
            
        case "findTags", "findTag":
            fragments = loadQuery(named: "fragment_TagFields")
            
        case "findImages":
            fragments = loadQuery(named: "fragment_ImageFields")
            
        default:
            print("⚠️ Warning: No explicit fragment mapping for \(queryName)")
        }
        
        let composed = "\(query)\n\(fragments)"
        composedQueryCache[queryName] = composed
        return composed
    }
}
