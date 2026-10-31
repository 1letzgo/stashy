//
//  TVChannel.swift
//  stashyTV
//
//  Channels on the Dashboard and the detail pages. They open Feeds as a starting point, the
//  same model as iOS (`HomeChannel` → `navigateToReelsChannel`).
//

import SwiftUI

/// A channel: built-in sorts, the server's saved scene filters, or every scene of a single
/// performer, studio, tag or group. Like on iOS it is a starting point for Feeds (Scenes mode
/// with the channel's filter and sort), not a player of its own.
struct TVChannel: Identifiable, Hashable {
    /// Entity-scoped channels, keyed by the GraphQL scene-filter field they filter on.
    enum Scope: String, Hashable {
        case performer = "performers"
        case studio = "studios"
        case tag = "tags"
        case group = "groups"

        /// Stash-Seite: alles außer `performers` ist ein
        /// `HierarchicalMultiCriterionInput`.
        var isHierarchical: Bool {
            self != .performer
        }

        var label: String {
            switch self {
            case .performer: return "Performer"
            case .studio: return "Studio"
            case .tag: return "Tag"
            case .group: return "Group"
            }
        }

        var icon: String {
            switch self {
            case .performer: return "person.fill"
            case .studio: return "building.2.fill"
            case .tag: return "tag.fill"
            case .group: return "rectangle.stack.fill"
            }
        }
    }

    enum Kind: Hashable {
        case recentlyReleased
        case recentlyAdded
        case savedFilter
        case scoped(Scope, id: String)
    }

    let kind: Kind
    let title: String
    let savedFilter: StashDBViewModel.SavedFilter?

    var id: String {
        switch kind {
        case .recentlyReleased: return "channel.recentlyReleased"
        case .recentlyAdded: return "channel.recentlyAdded"
        case .savedFilter: return "channel.filter.\(savedFilter?.id ?? title)"
        case .scoped(let scope, let id): return "channel.\(scope.rawValue).\(id)"
        }
    }

    var sortBy: StashDBViewModel.SceneSortOption {
        switch kind {
        case .recentlyAdded: return .createdAtDesc
        case .savedFilter: return savedFilter?.resolvedSceneSort ?? .dateDesc
        default: return .dateDesc
        }
    }

    var icon: String {
        switch kind {
        case .recentlyReleased: return "sparkles.tv.fill"
        case .recentlyAdded: return "plus.rectangle.on.folder.fill"
        case .savedFilter: return "line.3.horizontal.decrease.circle.fill"
        case .scoped(let scope, _): return scope.icon
        }
    }

    var subtitle: String {
        switch kind {
        case .savedFilter: return "Saved filter"
        case .scoped(let scope, _): return scope.label
        default: return "Channel"
        }
    }

    /// Scene filter passed to `fetchScenePage`. Entity-scoped channels build an
    /// ad-hoc filter, since they have no counterpart on the server.
    var sceneFilter: StashDBViewModel.SavedFilter? {
        switch kind {
        case .scoped(let scope, let entityID):
            var criterion: [String: StashJSONValue] = [
                "modifier": .string("INCLUDES"),
                "value": .array([.string(entityID)])
            ]
            // `studios`, `tags` und `groups` sind in Stash
            // `HierarchicalMultiCriterionInput` und brauchen `depth`; nur
            // `performers` ist ein einfaches `MultiCriterionInput`.
            // Der Rest der App setzt das überall (siehe `FilterFieldCatalog`
            // und die Scope-Filter im StashDBViewModel) — hier fehlte es.
            if scope.isHierarchical {
                criterion["depth"] = .int(0)
            }
            return StashDBViewModel.SavedFilter(
                id: id,
                name: title,
                mode: .scenes,
                filter: nil,
                object_filter: .object([scope.rawValue: .object(criterion)]),
                ui_options: nil
            )
        default:
            return savedFilter
        }
    }

    static let recentlyReleased = TVChannel(
        kind: .recentlyReleased,
        title: "Recently Released",
        savedFilter: nil
    )

    static let recentlyAdded = TVChannel(
        kind: .recentlyAdded,
        title: "Recently Added",
        savedFilter: nil
    )

    static func performer(id: String, name: String) -> TVChannel {
        TVChannel(kind: .scoped(.performer, id: id), title: name, savedFilter: nil)
    }

    static func studio(id: String, name: String) -> TVChannel {
        TVChannel(kind: .scoped(.studio, id: id), title: name, savedFilter: nil)
    }

    static func tag(id: String, name: String) -> TVChannel {
        TVChannel(kind: .scoped(.tag, id: id), title: name, savedFilter: nil)
    }

    static func group(id: String, name: String) -> TVChannel {
        TVChannel(kind: .scoped(.group, id: id), title: name, savedFilter: nil)
    }

    /// What the channel hands to Feeds.
    var feedStart: TVFeedChannelStart {
        TVFeedChannelStart(id: id, title: title, filter: sceneFilter, sortRaw: sortBy.rawValue)
    }
}

// MARK: - Opening a channel

/// Presents Feeds full screen for the channel in `channel`. Overlay navigation (scene,
/// performer, studio) waits for the cover to close, then pushes onto the host's stack — the
/// same flow as the Feeds tab.
struct TVChannelFeedCover: ViewModifier {
    @Binding var channel: TVChannel?
    var onDismiss: () -> Void = {}

    @State private var pendingDestination: TVFeedDestination?
    @Environment(\.tvNavigationPath) private var navigationPath

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $channel, onDismiss: handleDismiss) { channel in
                TVChannelFeedHost(
                    channel: channel,
                    onNavigate: { destination in
                        pendingDestination = destination
                        self.channel = nil
                    },
                    onClose: { self.channel = nil }
                )
            }
            .dismissOnAppLock { channel = nil }
    }

    private func handleDismiss() {
        onDismiss()
        guard let destination = pendingDestination else { return }
        pendingDestination = nil
        switch destination {
        case .scene(let id):
            navigationPath?.wrappedValue.append(TVSceneLink(sceneId: id))
        case .performer(let id, let name):
            navigationPath?.wrappedValue.append(TVPerformerLink(id: id, name: name))
        case .studio(let id, let name):
            navigationPath?.wrappedValue.append(TVStudioLink(id: id, name: name))
        }
    }
}

/// Owns the feed session, so it (and its catalog) only exists while a channel plays — not on
/// every page that merely offers a channel.
private struct TVChannelFeedHost: View {
    let channel: TVChannel
    var onNavigate: (TVFeedDestination) -> Void
    var onClose: () -> Void

    @StateObject private var session = TVFeedSession()

    var body: some View {
        TVFeedPlayerView(session: session, onNavigate: onNavigate, onClose: onClose)
            .onAppear { session.activate(channel: channel.feedStart) }
            .onDisappear { session.deactivate() }
            .interactiveDismissDisabled()
    }
}

extension View {
    func tvChannelFeedCover(_ channel: Binding<TVChannel?>, onDismiss: @escaping () -> Void = {}) -> some View {
        modifier(TVChannelFeedCover(channel: channel, onDismiss: onDismiss))
    }
}
