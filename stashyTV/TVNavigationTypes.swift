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

struct TVGalleryLink: Hashable {
    let id: String
    let title: String
}

struct TVImageLink: Hashable, Identifiable {
    let id: String
    let title: String
    /// When non-nil, viewer browses this gallery instead of the global library.
    var galleryId: String? = nil
}

struct TVSceneListLink: Hashable {
    let sortBy: StashDBViewModel.SceneSortOption
}

// MARK: - Navigation path environment

private struct TVNavigationPathKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationPath>? = nil
}

extension EnvironmentValues {
    var tvNavigationPath: Binding<NavigationPath>? {
        get { self[TVNavigationPathKey.self] }
        set { self[TVNavigationPathKey.self] = newValue }
    }
}

/// Per-tab stack: stable `NavigationPath` + destinations registered inside the stack.
struct TVTabStack<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content()
                .withTVDestinations()
        }
        .environment(\.tvNavigationPath, $path)
    }
}

/// Push a typed destination onto the tab's `NavigationPath` (reliable on tvOS grids).
struct TVNavButton<Value: Hashable, Label: View>: View {
    let value: Value
    var buttonStyleCard: Bool = true
    @Environment(\.tvNavigationPath) private var path
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            path?.wrappedValue.append(value)
        } label: {
            label()
        }
        .modifier(TVOptionalCardButtonStyle(enabled: buttonStyleCard))
    }
}

private struct TVOptionalCardButtonStyle: ViewModifier {
    let enabled: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.buttonStyle(.card)
        } else {
            content.buttonStyle(.plain)
        }
    }
}

// MARK: - tvOS Exit/Menu handling

/// On tvOS the Menu button triggers an "exit" command. Prefer popping the tab
/// `NavigationPath`; fall back to `dismiss` only when the view is presented.
private struct TVExitCommandDismiss: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(\.tvNavigationPath) private var path

    func body(content: Content) -> some View {
        content.onExitCommand {
            if let path, !path.wrappedValue.isEmpty {
                path.wrappedValue.removeLast()
                return
            }
            guard isPresented else { return }
            dismiss()
        }
    }
}

extension View {
    /// Menu-/Back: eine Ebene zurück statt App verlassen.
    func tvExitDismissable() -> some View {
        modifier(TVExitCommandDismiss())
    }
}

// MARK: - Centralised Navigation Destinations

/// Optional typed destinations (kept for path-based pushes). Browse grids use
/// `NavigationLink(destination:)` — value-based links are unreliable in tvOS LazyVGrid.
struct TVNavigationDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: TVSceneLink.self) { link in
                TVSceneDetailView(sceneId: link.sceneId)
                    .tvExitDismissable()
            }
            .navigationDestination(for: TVPerformerLink.self) { link in
                TVPerformerDetailView(performerId: link.id, performerName: link.name)
                    .tvExitDismissable()
            }
            .navigationDestination(for: TVStudioLink.self) { link in
                TVStudioDetailView(studioId: link.id, studioName: link.name)
                    .tvExitDismissable()
            }
            .navigationDestination(for: TVTagLink.self) { link in
                TVTagDetailView(tagId: link.id, tagName: link.name)
                    .tvExitDismissable()
            }
            .navigationDestination(for: TVGroupLink.self) { link in
                TVGroupDetailView(groupId: link.id, groupName: link.name)
                    .tvExitDismissable()
            }
            .navigationDestination(for: TVGalleryLink.self) { link in
                TVGalleryDetailView(galleryId: link.id, galleryTitle: link.title)
                    .tvExitDismissable()
            }
            .navigationDestination(for: TVImageLink.self) { link in
                TVImageDetailView(
                    imageId: link.id,
                    imageTitle: link.title,
                    galleryId: link.galleryId
                )
                .tvExitDismissable()
            }
            .navigationDestination(for: TVSceneListLink.self) { link in
                TVScenesView(sortBy: link.sortBy)
                    .tvExitDismissable()
            }
    }
}

extension View {
    func withTVDestinations() -> some View {
        modifier(TVNavigationDestinations())
    }
}
