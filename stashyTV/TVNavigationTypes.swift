//
//  TVNavigationTypes.swift
//  stashyTV
//
//  Strongly-typed navigation destinations for type-safe, lazy NavigationLink.
//

import SwiftUI
import Combine

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

// MARK: - Per-tab navigation paths

/// Sidebar-Einträge. Liegt hier statt in `TVMainTabView`, weil `TVNavigationStore`
/// und `TVTabStack` den Typ als Schlüssel brauchen.
enum TVRootTab: String, Hashable, CaseIterable {
    case home, scenes, performers, studios, tags, groups, galleries, images, search, settings
}

/// Hält die `NavigationPath`s **außerhalb** des View-Baums.
///
/// Vorher lag der Pfad als `@State` in `TVTabStack`, also an dessen View-Identität.
/// Ob die unter `TabSection` und `.sidebarAdaptable` erhalten bleibt, ist
/// undokumentiert — und ein Verlust wäre unsichtbar: `TVNavButton` hängt am
/// Environment-Binding, ist das weg, passiert beim Select stillschweigend nichts.
@MainActor
final class TVNavigationStore: ObservableObject {
    @Published private var paths: [TVRootTab: NavigationPath] = [:]

    func binding(for tab: TVRootTab) -> Binding<NavigationPath> {
        Binding(
            get: { [weak self] in self?.paths[tab] ?? NavigationPath() },
            set: { [weak self] newValue in self?.paths[tab] = newValue }
        )
    }

    /// Zurück zur Wurzel — z. B. wenn der bereits aktive Sidebar-Eintrag erneut
    /// gewählt wird.
    func popToRoot(_ tab: TVRootTab) {
        guard let path = paths[tab], !path.isEmpty else { return }
        paths[tab] = NavigationPath()
    }
}

/// Per-tab stack: `NavigationPath` aus dem Store + Destinations im Stack registriert.
struct TVTabStack<Content: View>: View {
    let tab: TVRootTab
    @EnvironmentObject private var store: TVNavigationStore
    @ViewBuilder var content: () -> Content

    var body: some View {
        let path = store.binding(for: tab)
        NavigationStack(path: path) {
            content()
                .withTVDestinations()
        }
        .environment(\.tvNavigationPath, path)
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

/// On tvOS the Menu button triggers an "exit" command. Dismiss first when the
/// view is presented (sheet/cover), otherwise pop the tab `NavigationPath`.
private struct TVExitCommandDismiss: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(\.tvNavigationPath) private var path

    func body(content: Content) -> some View {
        content.onExitCommand {
            // Presented (Sheet/Cover) hat Vorrang: sonst poppt die Menu-Taste den
            // darunterliegenden Stack, statt das Cover zu schließen.
            if isPresented {
                dismiss()
                return
            }
            if let path, !path.wrappedValue.isEmpty {
                path.wrappedValue.removeLast()
            }
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
