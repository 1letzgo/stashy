//
//  SceneDetailLayoutSettingsView.swift
//  stashy
//
//  Order and visibility of the cards below the player on the scene detail screen.
//

#if !os(tvOS)
import SwiftUI
import Combine

/// A card on the scene detail screen. The video player is fixed at the top and not part of this list.
/// Raw values are persisted — never rename them.
enum SceneDetailCard: String, CaseIterable, Identifiable {
    case details
    case heatmap
    case aiMotion
    case similarScenes
    case performersStudio
    case groups
    case tags
    case galleries

    var id: String { rawValue }

    var title: String {
        switch self {
        case .details: return "Details"
        case .heatmap: return "Funscript Heatmap"
        case .aiMotion: return "AI Motion Status"
        case .similarScenes: return "Similar Scenes"
        case .performersStudio: return "Performers & Studio"
        case .groups: return "Groups"
        case .tags: return "Tags"
        case .galleries: return "Galleries"
        }
    }

    var subtitle: String? {
        switch self {
        case .heatmap: return "Interactive scenes with a funscript"
        case .aiMotion: return "While AI Motion is syncing"
        case .similarScenes: return "stashy+"
        default: return nil
        }
    }

    var systemImage: String {
        switch self {
        case .details: return "text.alignleft"
        case .heatmap: return "waveform.path.ecg"
        case .aiMotion: return "waveform"
        case .similarScenes: return "sparkles.rectangle.stack"
        case .performersStudio: return "person.2"
        case .groups: return "film.stack"
        case .tags: return "tag"
        case .galleries: return "photo.on.rectangle"
        }
    }

    /// Half-width cards pair up side by side in landscape when they are adjacent.
    var isHalfWidthInLandscape: Bool {
        self == .groups || self == .tags
    }

    static let defaultOrder: [SceneDetailCard] = allCases
}

/// Global (not per-server) layout of the scene detail cards.
final class SceneDetailLayoutManager: ObservableObject {
    static let shared = SceneDetailLayoutManager()

    static let orderKey = "sceneDetailCardOrder"
    static let hiddenKey = "sceneDetailHiddenCards"

    @Published private(set) var order: [SceneDetailCard]
    @Published private(set) var hidden: Set<SceneDetailCard>

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.order = Self.normalizedOrder(defaults.stringArray(forKey: Self.orderKey) ?? [])
        self.hidden = Set((defaults.stringArray(forKey: Self.hiddenKey) ?? []).compactMap(SceneDetailCard.init(rawValue:)))
    }

    /// Stored ids first (unknown ones dropped, duplicates removed), then every card missing
    /// from storage in default order, so cards added in a later version show up automatically.
    static func normalizedOrder(_ stored: [String]) -> [SceneDetailCard] {
        var result: [SceneDetailCard] = []
        for id in stored {
            if let card = SceneDetailCard(rawValue: id), !result.contains(card) {
                result.append(card)
            }
        }
        for card in SceneDetailCard.defaultOrder where !result.contains(card) {
            result.append(card)
        }
        return result
    }

    /// Cards to render, in order, without the hidden ones.
    var visibleCards: [SceneDetailCard] {
        order.filter { !hidden.contains($0) }
    }

    var isDefault: Bool {
        order == SceneDetailCard.defaultOrder && hidden.isEmpty
    }

    func isVisible(_ card: SceneDetailCard) -> Bool {
        !hidden.contains(card)
    }

    func setVisible(_ card: SceneDetailCard, _ visible: Bool) {
        if visible { hidden.remove(card) } else { hidden.insert(card) }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func resetToDefault() {
        order = SceneDetailCard.defaultOrder
        hidden = []
        defaults.removeObject(forKey: Self.orderKey)
        defaults.removeObject(forKey: Self.hiddenKey)
    }

    private func save() {
        defaults.set(order.map(\.rawValue), forKey: Self.orderKey)
        // Keep the stored hidden list in display order so it reads predictably.
        defaults.set(order.filter { hidden.contains($0) }.map(\.rawValue), forKey: Self.hiddenKey)
    }
}

struct SceneDetailLayoutSettingsView: View {
    @ObservedObject private var layout = SceneDetailLayoutManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    var body: some View {
        List {
            Section {
                stashyScrollingSectionHeader("Cards")
                ForEach(Array(layout.order.enumerated()), id: \.element.id) { index, card in
                    Toggle(isOn: Binding(
                        get: { layout.isVisible(card) },
                        set: { layout.setVisible(card, $0) }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.title)
                                if let subtitle = card.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: card.systemImage)
                        }
                    }
                    .tint(appearanceManager.tintColor)
                    .stashyGroupedBlockRow(index: index, count: layout.order.count)
                }
                .onMove { indices, newOffset in
                    layout.move(from: indices, to: newOffset)
                }
                stashyScrollingSectionFooter("Drag to reorder the cards below the video player; switch a card off to hide it. In landscape, Groups and Tags sit side by side when they are next to each other. Cards that have nothing to show stay hidden either way.")
                    .moveDisabled(true)
            }

            Section {
                Button("Reset to Default") {
                    layout.resetToDefault()
                }
                .disabled(layout.isDefault)
                .stashyGroupedSettingsRow()
                .moveDisabled(true)
            }
        }
        .stashyMovableCardsList()
        .environment(\.editMode, .constant(.active))
        .deleteDisabled(true)
        .applyAppBackground()
        .stashySettingsDetailChrome("Scene View")
    }
}
#endif
