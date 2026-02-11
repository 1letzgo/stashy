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
            print("📁 --- BUNDLE INSPECTION START ---")
            print("📁 Main Bundle Path: \(Bundle.main.bundlePath)")
            
            // List everything in the root
            if let rootFiles = try? FileManager.default.contentsOfDirectory(atPath: Bundle.main.bundlePath) {
                print("📁 Root files: \(rootFiles.joined(separator: ", "))")
            }
            
            // Specifically list 'graphql' directory if it exists
            let graphqlPath = (Bundle.main.bundlePath as NSString).appendingPathComponent("graphql")
            if let gFiles = try? FileManager.default.contentsOfDirectory(atPath: graphqlPath) {
                print("📁 'graphql' directory exists and contains: \(gFiles.joined(separator: ", "))")
            } else {
                print("❌ 'graphql' directory NOT found at \(graphqlPath)")
            }
            
            // Try recursive scan for .graphql files
            let enumerator = FileManager.default.enumerator(atPath: Bundle.main.bundlePath)
            var foundGraphql: [String] = []
            while let file = enumerator?.nextObject() as? String {
                if file.hasSuffix(".graphql") {
                    foundGraphql.append(file)
                }
            }
            print("📁 Recursive scan found: \(foundGraphql.joined(separator: ", "))")
            print("📁 --- BUNDLE INSPECTION END ---")
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
                print("✅ Found and loaded: \(fileName).graphql from \(url.lastPathComponent)")
            } catch {
                print("❌ Critical: Failed to load GraphQL file: \(fileName).graphql - \(error)")
            }
        } else {
            print("❌ Critical: Could not find GraphQL file: \(fileName).graphql in ANY location")
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
            
        case "findSceneMarkers":
            fragments = loadQuery(named: "fragment_PerformerFields")
            
        default:
            print("⚠️ Warning: No explicit fragment mapping for \(queryName)")
        }
        
        let composed = "\(query)\n\(fragments)"
        setComposedQuery(queryName, value: composed)
        return composed
    }
}

