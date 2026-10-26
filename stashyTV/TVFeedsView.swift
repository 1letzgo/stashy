//
//  TVFeedsView.swift
//  stashyTV
//
//  Root of the Feeds sidebar entry: one card per feed mode that starts the full-screen
//  pager (`TVFeedPlayerView`), plus the Feeds settings iOS keeps under Settings › Feeds —
//  modes on/off, default sort and default saved filter per mode, continuous play and the
//  scenes' start position. Same `TabManager` keys as iOS.
//
//  The pager is a `fullScreenCover`, not the tab content itself: inside the sidebar layout
//  ◀ would hand focus to the sidebar instead of seeking.
//

#if canImport(AetherEngine)

import SwiftUI

struct TVFeedsView: View {
    @ObservedObject private var tabManager = TabManager.shared
    @ObservedObject private var appearance = AppearanceManager.shared
    /// Lives as long as the tab, so closing and reopening the feed lands on the same item.
    @StateObject private var session = TVFeedSession()
    @Environment(\.tvNavigationPath) private var navigationPath

    @State private var isFeedPresented = false
    @State private var launchMode: ReelsModeType = .scenes
    @State private var pendingDestination: TVFeedDestination?
    @FocusState private var focusedMode: ReelsModeType?

    private var modes: [ReelsModeType] { ReelsModeType.tvEnabledFeedModes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 50) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Feeds")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Full-screen, one after another. ▲ ▼ browse, ◀ ▶ seek, click for info and modes.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 40) {
                        ForEach(modes, id: \.self) { mode in
                            modeCard(mode)
                        }
                    }
                    .padding(.vertical, 30)
                    .padding(.horizontal, 4)
                }
                .scrollClipDisabled()
                .focusSection()

                settingsSection
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
        .background(Color.appBackground)
        .defaultFocus($focusedMode, modes.first)
        .onAppear {
            if session.catalog.savedFilters.isEmpty {
                session.catalog.fetchSavedFilters()
            }
        }
        .fullScreenCover(isPresented: $isFeedPresented, onDismiss: handleFeedDismissed) {
            TVFeedPlayerView(
                session: session,
                onNavigate: { destination in
                    pendingDestination = destination
                    isFeedPresented = false
                },
                onClose: { isFeedPresented = false }
            )
            .onAppear { session.activate(mode: launchMode) }
            .interactiveDismissDisabled()
        }
        .dismissOnAppLock { isFeedPresented = false }
    }

    private func start(_ mode: ReelsModeType) {
        launchMode = mode
        isFeedPresented = true
    }

    /// Navigation from the overlay waits for the cover to be gone, then pushes onto this tab.
    private func handleFeedDismissed() {
        session.deactivate()
        guard let destination = pendingDestination else {
            // Back on the mode card that opened the feed. Without this the focus engine picks
            // its own landing spot after the cover, and a click meant for the cards could flip a
            // Feed Settings toggle (Continuous Play sits right below them).
            focusedMode = launchMode
            return
        }
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

    // MARK: - Mode cards

    private func modeCard(_ mode: ReelsModeType) -> some View {
        Button {
            start(mode)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: mode.icon)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(appearance.tintColor)
                Spacer(minLength: 0)
                Text(mode.defaultTitle)
                    .font(.system(size: 36, weight: .bold))
                Text(modeSummary(mode))
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(30)
            .frame(width: 400, height: 260, alignment: .leading)
            .background(Color.white.opacity(0.06))
        }
        .buttonStyle(.card)
        .focused($focusedMode, equals: mode)
    }

    private func modeSummary(_ mode: ReelsModeType) -> String {
        let sort = mode.sortChoices.first(where: { $0.raw == mode.defaultSortRaw })?.label ?? "Random"
        if let filterId = mode.defaultFilterId {
            let name = session.catalog.savedFilters[filterId]?.name ?? filterName(for: mode) ?? "Saved filter"
            return "\(sort) · \(name)"
        }
        return sort
    }

    private func filterName(for mode: ReelsModeType) -> String? {
        switch mode {
        case .scenes: return tabManager.getDefaultFilterName(for: .reels)
        case .markers: return tabManager.getDefaultMarkerFilterName(for: .reels)
        case .clips: return tabManager.getDefaultClipFilterName(for: .reels)
        case .previews: return tabManager.getDefaultPreviewFilterName(for: .reels)
        case .pics, .verticals: return nil
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Feed Settings")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                Toggle(isOn: $tabManager.reelsContinuousPlay) {
                    Text("Continuous Play")
                }
                TVSettingsPickerRow(
                    title: "Scenes Start At",
                    options: TabManager.FeedsSceneStartPosition.allCases.map { TVPickerOption($0, $0.label) },
                    selection: $tabManager.feedsSceneStartPosition
                )
                TVSettingsPickerRow(
                    title: "Marker Length",
                    options: TabManager.feedsMarkerLengthOptions.map { TVPickerOption($0, "\(Int($0)) s") },
                    selection: $tabManager.feedsMarkerDefaultSeconds
                )
            }
            .frame(maxWidth: 1100)

            ForEach(ReelsModeType.tvFeedModes, id: \.self) { mode in
                modeSettings(mode)
            }
        }
        .focusSection()
    }

    @ViewBuilder
    private func modeSettings(_ mode: ReelsModeType) -> some View {
        let isEnabled = tabManager.reelsModes.first(where: { $0.type == mode })?.isEnabled ?? false
        VStack(alignment: .leading, spacing: 12) {
            Label(mode.defaultTitle, systemImage: mode.icon)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(appearance.tintColor)
                .padding(.top, 20)

            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { _ in tabManager.toggleReelsMode(mode) }
            )) {
                Text("Show in Feeds")
            }

            if isEnabled {
                TVSettingsPickerRow(
                    title: "Default Sort",
                    options: mode.sortChoices.map { TVPickerOption($0.raw, $0.label) },
                    selection: Binding(
                        get: { mode.defaultSortRaw },
                        set: { tabManager.setReelsDefaultSort(for: mode, option: $0) }
                    )
                )
                filterRow(mode)
            }
        }
        .frame(maxWidth: 1100)
    }

    private func filterRow(_ mode: ReelsModeType) -> some View {
        let filters = session.catalog.savedFilters.values
            .filter { $0.mode == mode.savedFilterMode }
            .sorted { $0.name < $1.name }
        return TVSettingsPickerRow(
            title: "Default Filter",
            options: [TVPickerOption("", "None")] + filters.map { TVPickerOption($0.id, $0.name) },
            selection: Binding(
                get: { mode.defaultFilterId ?? "" },
                set: { newId in
                    if newId.isEmpty {
                        mode.setDefaultFilter(id: nil, name: nil)
                    } else {
                        mode.setDefaultFilter(id: newId, name: filters.first(where: { $0.id == newId })?.name)
                    }
                }
            )
        )
    }
}

#endif
