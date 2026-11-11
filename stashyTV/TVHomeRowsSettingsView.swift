//
//  TVHomeRowsSettingsView.swift
//  stashyTV
//
//  Settings › Home Rows: which rows the tvOS Home shows and in what order. Same
//  `TabManager.homeRows` store as the iOS dashboard settings (per server, per device).
//  Reordering without drag: Select on a row opens a short action sheet (show/hide,
//  move up/down/to top) — the remote-friendly form of the iOS edit list.
//

import SwiftUI

extension HomeRowType {
    /// Row heading on the TV Home. The iOS titles ("Scenes - New") read like settings
    /// labels; the TV keeps the streaming-app wording its fixed rows had.
    var tvTitle: String {
        switch self {
        case .lastPlayed: return tr("continue_watching")
        case .channels: return tr("channels")
        case .newest3Min: return tr("new_releases")
        case .lastAdded3Min: return tr("recently_added")
        case .mostViewed3Min: return tr("most_viewed")
        case .topCounter3Min: return tr("top_o_count")
        case .topRating3Min: return tr("top_rated")
        case .random: return tr("random_picks")
        case .statistics: return tr("statistics")
        case .newPerformers: return tr("new_performers")
        case .performersHighestSceneCount: return tr("top_performers")
        case .performersHighestOCount: return tr("performers_by_o_count")
        case .performersHighestRating: return tr("top_rated_performers")
        case .newStudios: return tr("new_studios")
        case .studiosHighestSceneCount: return tr("top_studios")
        case .newGalleries: return tr("new_galleries")
        case .recentlyUpdatedGalleries: return tr("recently_updated_galleries")
        case .galleriesHighestImageCount: return tr("largest_galleries")
        case .recommendations: return tr("for_you")
        case .forgottenFavorites: return tr("forgotten_favorites")
        case .customFilter: return tr("custom_filter")
        }
    }

    /// The tvOS Home has no statistics block; the row stays in the shared store but is
    /// neither rendered nor offered here.
    /// For You is built on iOS and macOS only, and so are custom filter rows for now.
    var isAvailableOnTV: Bool {
        self != .statistics && self != .recommendations && self != .forgottenFavorites && self != .customFilter
    }
}

struct TVHomeRowsSettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    @State private var editingRow: HomeRowConfig?
    @FocusState private var focusedRow: UUID?

    private var rows: [HomeRowConfig] {
        tabManager.homeRows.filter { $0.type.isAvailableOnTV }
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button {
                        editingRow = row
                    } label: {
                        HStack(spacing: 16) {
                            Text("\(index + 1)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                            Text(title(for: row))
                                .opacity(row.isEnabled ? 1 : 0.5)
                            Spacer()
                            Text(row.isEnabled ? tr("on") : tr("off"))
                                .foregroundStyle(row.isEnabled ? appearanceManager.tintColor : .secondary)
                        }
                    }
                    .focused($focusedRow, equals: row.id)
                }
            }
        }
        .confirmationDialog(
            editingRow.map { title(for: $0) } ?? "",
            isPresented: Binding(
                get: { editingRow != nil },
                set: { if !$0 { editingRow = nil } }
            ),
            titleVisibility: .visible,
            presenting: editingRow
        ) { row in
            let current = rows.first(where: { $0.id == row.id }) ?? row
            Button(current.isEnabled ? tr("action_hide_from_home") : tr("action_show_on_home")) {
                tabManager.toggleHomeRow(current.id)
            }
            if canMove(current.id, by: -1) {
                Button(tr("action_move_up")) { move(current.id, by: -1) }
                Button(tr("action_move_to_top")) { moveToTop(current.id) }
            }
            if canMove(current.id, by: 1) {
                Button(tr("action_move_down")) { move(current.id, by: 1) }
            }
            Button(tr("action_cancel"), role: .cancel) {}
        }
        .tvSettingsPage(
            tr("home_rows"),
            description: tr("hint_choose_rows_on_home_and")
        )
    }

    private func title(for row: HomeRowConfig) -> String {
        if row.type == .channels && !stashyPlus.isUnlocked {
            return "\(row.type.tvTitle) (stashy+)"
        }
        return row.type.tvTitle
    }

    // MARK: - Reordering

    /// Moves are made among the rows listed here; hidden-on-TV entries (statistics) keep
    /// their slot in the shared store and are stepped over.
    private func canMove(_ id: UUID, by step: Int) -> Bool {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return false }
        return rows.indices.contains(index + step)
    }

    private func move(_ id: UUID, by step: Int) {
        let visible = rows
        guard let index = visible.firstIndex(where: { $0.id == id }),
              visible.indices.contains(index + step) else { return }
        let neighbourId = visible[index + step].id
        reorder(id, relativeTo: neighbourId, before: step < 0)
    }

    private func moveToTop(_ id: UUID) {
        guard let firstId = rows.first?.id, firstId != id else { return }
        reorder(id, relativeTo: firstId, before: true)
    }

    private func reorder(_ id: UUID, relativeTo targetId: UUID, before: Bool) {
        let all = tabManager.homeRows
        guard let from = all.firstIndex(where: { $0.id == id }),
              let target = all.firstIndex(where: { $0.id == targetId }) else { return }
        // `move(fromOffsets:toOffset:)` counts the destination in the array before removal.
        let destination = before ? target : target + 1
        tabManager.moveHomeRow(from: IndexSet(integer: from), to: destination)
        // The list rebuilds under the focused button; keep focus on the row that moved.
        DispatchQueue.main.async { focusedRow = id }
    }
}
