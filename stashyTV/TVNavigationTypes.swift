//
//  TVNavigationTypes.swift
//  stashyTV
//
//  Strongly-typed navigation destinations for type-safe, lazy NavigationLink.
//

import SwiftUI

// MARK: - Protocols for Unification

protocol TVGridItem: Identifiable {
    var id: String { get }
    var name: String { get }
    var thumbnailURL: URL? { get }
    var sceneCountDisplay: Int { get }
}

protocol TVDetailItem: TVGridItem {
    var details: String? { get }
    var favorite: Bool? { get }
    var rating100: Int? { get }
}

// MARK: - Destination Types

struct TVSceneLink: Hashable {
    let sceneId: String
}

struct TVPerformerLink: Hashable {
    let id: String
    let name: String
}

struct TVStudioLink: Hashable {
    let id: String
    let name: String
}

struct TVTagLink: Hashable {
    let id: String
    let name: String
}

struct TVGroupLink: Hashable {
    let id: String
    let name: String
}

struct TVSceneListLink: Hashable {
    let sortBy: StashDBViewModel.SceneSortOption
}

// MARK: - Centralised Navigation Destinations

/// Apply to the root view of each NavigationStack so every child view can
/// push any destination without knowing about the surrounding stack.
struct TVNavigationDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: TVSceneLink.self) { link in
                TVSceneDetailView(sceneId: link.sceneId)
            }
            .navigationDestination(for: TVPerformerLink.self) { link in
                TVPerformerDetailView(performerId: link.id, performerName: link.name)
            }
            .navigationDestination(for: TVStudioLink.self) { link in
                TVStudioDetailView(studioId: link.id, studioName: link.name)
            }
            .navigationDestination(for: TVTagLink.self) { link in
                TVTagDetailView(tagId: link.id, tagName: link.name)
            }
            .navigationDestination(for: TVGroupLink.self) { link in
                TVGroupDetailView(groupId: link.id, groupName: link.name)
            }
            .navigationDestination(for: TVSceneListLink.self) { link in
                TVScenesView(sortBy: link.sortBy)
            }
    }
}

extension View {
    func withTVDestinations() -> some View {
        modifier(TVNavigationDestinations())
    }
}
