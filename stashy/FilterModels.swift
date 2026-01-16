//
//  FilterModels.swift
//  stashy
//
//  Filter models for Scenes, Performers, and Studios
//

import Foundation



// MARK: - Studio Filters
struct StudioFilters: Codable, Equatable {
    var parentStudio: String?  // Parent Studio ID
    var minSceneCount: Int?
    var maxSceneCount: Int?
    var hasScenes: Bool = true  // Default: only show studios with scenes
    
    var isActive: Bool {
        parentStudio != nil || minSceneCount != nil || maxSceneCount != nil || !hasScenes
    }
    
    func toGraphQLFilter() -> String {
        var filters: [String] = []
        
        // Scene count filter - only use min if set, otherwise use hasScenes logic
        if let minCount = minSceneCount, minCount > 0 {
            filters.append("scene_count: { modifier: GREATER_THAN, value: \(minCount) }")
        } else if hasScenes {
            filters.append("scene_count: { modifier: GREATER_THAN, value: 0 }")
        }
        
        if let maxCount = maxSceneCount, maxCount > 0 {
            filters.append("scene_count: { modifier: LESS_THAN, value: \(maxCount) }")
        }
        
        if let parentStudio = parentStudio, !parentStudio.isEmpty {
            filters.append("parent: { modifier: EQUALS, value: \"\(parentStudio)\" }")
        }
        
        return filters.isEmpty ? "" : "studio_filter: { \(filters.joined(separator: ", ")) }, "
    }
}

