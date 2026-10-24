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
        case .lastPlayed: return "Continue Watching"
        case .channels: return "Channels"
        case .newest3Min: return "New Releases"
        case .lastAdded3Min: return "Recently Added"
        case .mostViewed3Min: return "Most Viewed"
        case .topCounter3Min: return "Top O-Count"
        case .topRating3Min: return "Top Rated"
        case .random: return "Random Picks"
        case .statistics: return "Statistics"
        case .newPerformers: return "New Performers"
        case .performersHighestSceneCount: return "Top Performers"
        case .performersHighestOCount: return "Performers by O-Count"
        case .performersHighestRating: return "Top Rated Performers"
        case .newStudios: return "New Studios"
        case .studiosHighestSceneCount: return "Top Studios"
        case .newGalleries: return "New Galleries"
        case .recentlyUpdatedGalleries: return "Recently Updated Galleries"
        case .galleriesHighestImageCount: return "Largest Galleries"
        }
    }

    /// The tvOS Home has no statistics block; the row stays in the shared store but is
    /// neither rendered nor offered here.
    var isAvailableOnTV: Bool { self != .statistics }
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
                            Text(row.isEnabled ? "On" : "Off")
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
            Button(current.isEnabled ? "Hide from Home" : "Show on Home") {
                tabManager.toggleHomeRow(current.id)
            }
            if canMove(current.id, by: -1) {
                Button("Move Up") { move(current.id, by: -1) }
                Button("Move to Top") { moveToTop(current.id) }
            }
            if canMove(current.id, by: 1) {
                Button("Move Down") { move(current.id, by: 1) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .tvSettingsPage(
            "Home Rows",
            description: "Choose the rows on Home and their order. Select a row to show or hide it, or to move it up or down. Each server keeps its own setup."
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
