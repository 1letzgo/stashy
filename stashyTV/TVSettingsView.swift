//
//  TVSettingsView.swift
//  stashyTV
//
//  Created for stashy tvOS.
//

import SwiftUI
import UIKit

struct TVSettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    var body: some View {
        List {
            // First row must be focusable so ↑ from Settings can reach the tab bar.
            Section {
                NavigationLink {
                    TVServersSettingsView().tvExitDismissable()
                } label: {
                    settingsRow(title: "Servers", icon: "server.rack", subtitle: "Active & saved servers")
                }

                NavigationLink {
                    TVAppearanceSettingsView().tvExitDismissable()
                } label: {
                    settingsRow(title: "Appearance", icon: "paintbrush.fill", subtitle: "Accent color")
                }

                NavigationLink {
                    TVSecuritySettingsView().tvExitDismissable()
                } label: {
                    settingsRow(title: "Security", icon: "lock.fill", subtitle: "PIN lock")
                }

                NavigationLink {
                    TVPlaybackSettingsView().tvExitDismissable()
                } label: {
                    settingsRow(title: "Playback", icon: "play.rectangle.fill", subtitle: "Streaming quality")
                }

                NavigationLink {
                    TVStashyPlusSettingsView().tvExitDismissable()
                } label: {
                    settingsRow(title: "stashy+", icon: "sparkles.tv.fill", subtitle: "Premium features & Channels")
                }
            } header: {
                Text("General")
            }

            Section {
                NavigationLink {
                    TVDefaultSortSettingsView().tvExitDismissable()
                } label: {
                    settingsRow(title: "Default Sorting", icon: "arrow.up.arrow.down", subtitle: "Per-tab sort order")
                }

                NavigationLink {
                    TVDefaultFilterSettingsView().tvExitDismissable()
                } label: {
                    settingsRow(title: "Default Filters", icon: "line.3.horizontal.decrease.circle", subtitle: "Saved filters per tab")
                }

                NavigationLink {
                    TVTabVisibilitySettingsView().tvExitDismissable()
                } label: {
                    settingsRow(title: "Visible Tabs", icon: "rectangle.3.group.fill", subtitle: "Top navigation")
                }
            } header: {
                Text("Content")
            }

            Section {
                NavigationLink {
                    TVAboutSettingsView().tvExitDismissable()
                } label: {
                    settingsRow(title: "About", icon: "info.circle", subtitle: "Version & build")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80).focusable(false)
        }
        .background(Color.appBackground)
    }

    private func settingsRow(title: String, icon: String, subtitle: String) -> some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(appearanceManager.tintColor)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Servers

private struct TVServersSettingsView: View {
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var showingAddServer = false
    @State private var editingServer: ServerConfig?

    var body: some View {
        List {
            Section {
                if let config = configManager.activeConfig {
                    NavigationLink {
                        TVServerDetailView().tvExitDismissable()
                    } label: {
                        HStack(spacing: 20) {
                            Image(systemName: "server.rack")
                                .font(.title2)
                                .foregroundColor(appearanceManager.tintColor)
                                .frame(width: 44)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(config.name)
                                    .font(.headline)
                                Text(config.baseURL)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.yellow)
                        Text("No server configured")
                            .foregroundStyle(.secondary)
                    }
                    .focusable()
                }
            } header: {
                Text("Active Server")
            }

            Section {
                ForEach(configManager.savedServers) { server in
                    Button {
                        configManager.saveConfig(server)
                    } label: {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name)
                                    .font(.headline)
                                Text(server.baseURL)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if server.id == configManager.activeConfig?.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(appearanceManager.tintColor)
                            }
                        }
                    }
                    .contextMenu {
                        Button("Edit") {
                            editingServer = server
                        }
                        Button("Delete", role: .destructive) {
                            configManager.deleteServer(id: server.id)
                        }
                    }
                }

                Button {
                    showingAddServer = true
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
            } header: {
                Text("Saved Servers")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80).focusable(false)
        }
        .sheet(isPresented: $showingAddServer) {
            TVServerFormView(server: nil) { newServer in
                configManager.addOrUpdateServer(newServer)
                configManager.saveConfig(newServer)
                showingAddServer = false
            }
        }
        .sheet(item: $editingServer) { server in
            TVServerFormView(server: server) { updatedServer in
                configManager.addOrUpdateServer(updatedServer)
                if updatedServer.id == configManager.activeConfig?.id {
                    configManager.saveConfig(updatedServer)
                }
                editingServer = nil
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Servers")
    }
}

// MARK: - Appearance

private struct TVAppearanceSettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Accent Color")
                        .font(.headline)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(appearanceManager.presets) { preset in
                                Button {
                                    appearanceManager.tintColor = preset.color
                                } label: {
                                    TVColorPresetButton(
                                        preset: preset,
                                        isSelected: colorsEqual(preset.color, appearanceManager.tintColor)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            } header: {
                Text("Appearance")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80).focusable(false)
        }
        .background(Color.appBackground)
        .navigationTitle("Appearance")
    }

    private func colorsEqual(_ a: Color, _ b: Color, tolerance: CGFloat = 0.01) -> Bool {
        let ua = UIColor(a)
        let ub = UIColor(b)

        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0

        guard ua.getRed(&ar, green: &ag, blue: &ab, alpha: &aa),
              ub.getRed(&br, green: &bg, blue: &bb, alpha: &ba) else {
            return String(describing: a) == String(describing: b)
        }

        return abs(ar - br) <= tolerance
            && abs(ag - bg) <= tolerance
            && abs(ab - bb) <= tolerance
            && abs(aa - ba) <= tolerance
    }
}

// MARK: - Security

private struct TVSecuritySettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var securityManager = TVSecurityManager.shared
    @State private var showingSetPasscode = false

    var body: some View {
        List {
            Section {
                Toggle(
                    "Enable PIN Lock",
                    isOn: Binding(
                        get: { securityManager.isPinLockEnabled && securityManager.isPinSet },
                        set: { enabled in
                            if enabled {
                                if !securityManager.isPinSet {
                                    showingSetPasscode = true
                                } else {
                                    securityManager.isPinLockEnabled = true
                                }
                            } else {
                                securityManager.isPinLockEnabled = false
                            }
                        }
                    )
                )
                .tint(appearanceManager.tintColor)

                if securityManager.isPinSet {
                    Button("Change PIN") {
                        showingSetPasscode = true
                    }

                    Button("Remove PIN", role: .destructive) {
                        securityManager.removePin()
                    }
                }
            } header: {
                Text("Security")
            } footer: {
                Text("The app will require your PIN each time it is opened and whenever it returns from the background.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80).focusable(false)
        }
        .fullScreenCover(isPresented: $showingSetPasscode) {
            TVPasscodeSetupView(isPresented: $showingSetPasscode)
                .presentationBackground(Color.black)
        }
        .background(Color.appBackground)
        .navigationTitle("Security")
    }
}

// MARK: - Playback

private struct TVPlaybackSettingsView: View {
    @ObservedObject private var configManager = ServerConfigManager.shared

    var body: some View {
        List {
            Section {
                if let config = configManager.activeConfig {
                    HStack {
                        Text("Streaming Quality")
                        Spacer()
                        Menu {
                            ForEach(StreamingQuality.allCases, id: \.self) { quality in
                                Button {
                                    var updated = config
                                    updated.defaultQuality = quality
                                    configManager.saveConfig(updated)
                                    configManager.addOrUpdateServer(updated)
                                } label: {
                                    HStack {
                                        Text(quality.displayName)
                                        if config.defaultQuality == quality {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(config.defaultQuality.displayName)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("Connect to a server to configure quality.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Playback")
            } footer: {
                Text("\"Original\" streams MP4 files directly for best seeking performance. Lower qualities use HLS transcoding.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80).focusable(false)
        }
        .background(Color.appBackground)
        .navigationTitle("Playback")
    }
}

// MARK: - Default Sorting

private struct TVDefaultSortSettingsView: View {
    @ObservedObject private var tabManager = TabManager.shared

    var body: some View {
        List {
            Section {
                sceneSortRow
                performerSortRow
                studioSortRow
                tagSortRow
                groupSortRow
            } header: {
                Text("Default Sorting")
            } footer: {
                Text("The sort order used when opening each tab.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80).focusable(false)
        }
        .background(Color.appBackground)
        .navigationTitle("Default Sorting")
    }

    private func sortRowShell<Content: View>(
        label: String, current: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            Menu {
                content()
            } label: {
                Text(current)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var sceneSortRow: some View {
        let binding = Binding<StashDBViewModel.SceneSortOption>(
            get: { StashDBViewModel.SceneSortOption(rawValue: tabManager.getPersistentSortOption(for: .scenes) ?? "") ?? .dateDesc },
            set: { tabManager.setPersistentSortOption(for: .scenes, option: $0.rawValue) }
        )
        return sortRowShell(label: "Scenes", current: binding.wrappedValue.displayName) {
            Button(action: { binding.wrappedValue = .random }) {
                HStack { Text("Random"); if binding.wrappedValue == .random { Spacer(); Image(systemName: "checkmark") } }
            }
            Divider()
            Menu("Date") {
                Button(action: { binding.wrappedValue = .dateDesc }) {
                    HStack { Text("Newest First"); if binding.wrappedValue == .dateDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .dateAsc }) {
                    HStack { Text("Oldest First"); if binding.wrappedValue == .dateAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Duration") {
                Button(action: { binding.wrappedValue = .durationDesc }) {
                    HStack { Text("Longest First"); if binding.wrappedValue == .durationDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .durationAsc }) {
                    HStack { Text("Shortest First"); if binding.wrappedValue == .durationAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Rating") {
                Button(action: { binding.wrappedValue = .ratingDesc }) {
                    HStack { Text("High → Low"); if binding.wrappedValue == .ratingDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .ratingAsc }) {
                    HStack { Text("Low → High"); if binding.wrappedValue == .ratingAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Counter") {
                Button(action: { binding.wrappedValue = .oCounterDesc }) {
                    HStack { Text("High → Low"); if binding.wrappedValue == .oCounterDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .oCounterAsc }) {
                    HStack { Text("Low → High"); if binding.wrappedValue == .oCounterAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Views") {
                Button(action: { binding.wrappedValue = .playCountDesc }) {
                    HStack { Text("Most Viewed"); if binding.wrappedValue == .playCountDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .playCountAsc }) {
                    HStack { Text("Least Viewed"); if binding.wrappedValue == .playCountAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Last Played") {
                Button(action: { binding.wrappedValue = .lastPlayedAtDesc }) {
                    HStack { Text("Recently Played"); if binding.wrappedValue == .lastPlayedAtDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .lastPlayedAtAsc }) {
                    HStack { Text("Least Recently"); if binding.wrappedValue == .lastPlayedAtAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Created") {
                Button(action: { binding.wrappedValue = .createdAtDesc }) {
                    HStack { Text("Newest First"); if binding.wrappedValue == .createdAtDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .createdAtAsc }) {
                    HStack { Text("Oldest First"); if binding.wrappedValue == .createdAtAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
        }
    }

    private var performerSortRow: some View {
        let binding = Binding<StashDBViewModel.PerformerSortOption>(
            get: { StashDBViewModel.PerformerSortOption(rawValue: tabManager.getPersistentSortOption(for: .performers) ?? "") ?? .nameAsc },
            set: { tabManager.setPersistentSortOption(for: .performers, option: $0.rawValue) }
        )
        return sortRowShell(label: "Performers", current: binding.wrappedValue.displayName) {
            Button(action: { binding.wrappedValue = .random }) {
                HStack { Text("Random"); if binding.wrappedValue == .random { Spacer(); Image(systemName: "checkmark") } }
            }
            Divider()
            Menu("Name") {
                Button(action: { binding.wrappedValue = .nameAsc }) {
                    HStack { Text("A → Z"); if binding.wrappedValue == .nameAsc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .nameDesc }) {
                    HStack { Text("Z → A"); if binding.wrappedValue == .nameDesc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Scene Count") {
                Button(action: { binding.wrappedValue = .sceneCountDesc }) {
                    HStack { Text("Most Scenes"); if binding.wrappedValue == .sceneCountDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .sceneCountAsc }) {
                    HStack { Text("Least Scenes"); if binding.wrappedValue == .sceneCountAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Counter") {
                Button(action: { binding.wrappedValue = .oCountDesc }) {
                    HStack { Text("High → Low"); if binding.wrappedValue == .oCountDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .oCountAsc }) {
                    HStack { Text("Low → High"); if binding.wrappedValue == .oCountAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Birthdate") {
                Button(action: { binding.wrappedValue = .birthdateDesc }) {
                    HStack { Text("Youngest First"); if binding.wrappedValue == .birthdateDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .birthdateAsc }) {
                    HStack { Text("Oldest First"); if binding.wrappedValue == .birthdateAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Created") {
                Button(action: { binding.wrappedValue = .createdAtDesc }) {
                    HStack { Text("Newest First"); if binding.wrappedValue == .createdAtDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .createdAtAsc }) {
                    HStack { Text("Oldest First"); if binding.wrappedValue == .createdAtAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Updated") {
                Button(action: { binding.wrappedValue = .updatedAtDesc }) {
                    HStack { Text("Recently Updated"); if binding.wrappedValue == .updatedAtDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .updatedAtAsc }) {
                    HStack { Text("Least Recently"); if binding.wrappedValue == .updatedAtAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
        }
    }

    private var studioSortRow: some View {
        let binding = Binding<StashDBViewModel.StudioSortOption>(
            get: { StashDBViewModel.StudioSortOption(rawValue: tabManager.getPersistentSortOption(for: .studios) ?? "") ?? .nameAsc },
            set: { tabManager.setPersistentSortOption(for: .studios, option: $0.rawValue) }
        )
        return sortRowShell(label: "Studios", current: binding.wrappedValue.displayName) {
            Button(action: { binding.wrappedValue = .random }) {
                HStack { Text("Random"); if binding.wrappedValue == .random { Spacer(); Image(systemName: "checkmark") } }
            }
            Divider()
            Menu("Name") {
                Button(action: { binding.wrappedValue = .nameAsc }) {
                    HStack { Text("A → Z"); if binding.wrappedValue == .nameAsc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .nameDesc }) {
                    HStack { Text("Z → A"); if binding.wrappedValue == .nameDesc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Scene Count") {
                Button(action: { binding.wrappedValue = .sceneCountDesc }) {
                    HStack { Text("Most Scenes"); if binding.wrappedValue == .sceneCountDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .sceneCountAsc }) {
                    HStack { Text("Least Scenes"); if binding.wrappedValue == .sceneCountAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Created") {
                Button(action: { binding.wrappedValue = .createdAtDesc }) {
                    HStack { Text("Newest First"); if binding.wrappedValue == .createdAtDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .createdAtAsc }) {
                    HStack { Text("Oldest First"); if binding.wrappedValue == .createdAtAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Updated") {
                Button(action: { binding.wrappedValue = .updatedAtDesc }) {
                    HStack { Text("Recently Updated"); if binding.wrappedValue == .updatedAtDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .updatedAtAsc }) {
                    HStack { Text("Least Recently"); if binding.wrappedValue == .updatedAtAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
        }
    }

    private var tagSortRow: some View {
        let binding = Binding<StashDBViewModel.TagSortOption>(
            get: { StashDBViewModel.TagSortOption(rawValue: tabManager.getPersistentSortOption(for: .tags) ?? "") ?? .nameAsc },
            set: { tabManager.setPersistentSortOption(for: .tags, option: $0.rawValue) }
        )
        return sortRowShell(label: "Tags", current: binding.wrappedValue.displayName) {
            Menu("Name") {
                Button(action: { binding.wrappedValue = .nameAsc }) {
                    HStack { Text("A → Z"); if binding.wrappedValue == .nameAsc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .nameDesc }) {
                    HStack { Text("Z → A"); if binding.wrappedValue == .nameDesc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Scene Count") {
                Button(action: { binding.wrappedValue = .sceneCountDesc }) {
                    HStack { Text("Most Scenes"); if binding.wrappedValue == .sceneCountDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .sceneCountAsc }) {
                    HStack { Text("Least Scenes"); if binding.wrappedValue == .sceneCountAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Created") {
                Button(action: { binding.wrappedValue = .createdAtDesc }) {
                    HStack { Text("Newest First"); if binding.wrappedValue == .createdAtDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .createdAtAsc }) {
                    HStack { Text("Oldest First"); if binding.wrappedValue == .createdAtAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Updated") {
                Button(action: { binding.wrappedValue = .updatedAtDesc }) {
                    HStack { Text("Recently Updated"); if binding.wrappedValue == .updatedAtDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .updatedAtAsc }) {
                    HStack { Text("Least Recently"); if binding.wrappedValue == .updatedAtAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
        }
    }

    private var groupSortRow: some View {
        let binding = Binding<StashDBViewModel.GroupSortOption>(
            get: { StashDBViewModel.GroupSortOption(rawValue: tabManager.getPersistentSortOption(for: .groups) ?? "") ?? .nameAsc },
            set: { tabManager.setPersistentSortOption(for: .groups, option: $0.rawValue) }
        )
        return sortRowShell(label: "Groups", current: binding.wrappedValue.displayName) {
            Button(action: { binding.wrappedValue = .random }) {
                HStack { Text("Random"); if binding.wrappedValue == .random { Spacer(); Image(systemName: "checkmark") } }
            }
            Divider()
            Menu("Name") {
                Button(action: { binding.wrappedValue = .nameAsc }) {
                    HStack { Text("A → Z"); if binding.wrappedValue == .nameAsc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .nameDesc }) {
                    HStack { Text("Z → A"); if binding.wrappedValue == .nameDesc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Scene Count") {
                Button(action: { binding.wrappedValue = .sceneCountDesc }) {
                    HStack { Text("Most Scenes"); if binding.wrappedValue == .sceneCountDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .sceneCountAsc }) {
                    HStack { Text("Least Scenes"); if binding.wrappedValue == .sceneCountAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
            Menu("Date") {
                Button(action: { binding.wrappedValue = .dateDesc }) {
                    HStack { Text("Newest First"); if binding.wrappedValue == .dateDesc { Spacer(); Image(systemName: "checkmark") } }
                }
                Button(action: { binding.wrappedValue = .dateAsc }) {
                    HStack { Text("Oldest First"); if binding.wrappedValue == .dateAsc { Spacer(); Image(systemName: "checkmark") } }
                }
            }
        }
    }
}

// MARK: - Default Filters

private struct TVDefaultFilterSettingsView: View {
    @ObservedObject private var tabManager = TabManager.shared
    @StateObject private var filterViewModel = StashDBViewModel()

    var body: some View {
        List {
            Section {
                tvFilterRow(label: "Scenes", icon: "film", tab: .scenes, mode: .scenes)
                tvFilterRow(label: "Performers", icon: "person.3", tab: .performers, mode: .performers)
                tvFilterRow(label: "Studios", icon: "building.2", tab: .studios, mode: .studios)
                tvFilterRow(label: "Tags", icon: "tag", tab: .tags, mode: .tags)
                tvFilterRow(label: "Groups", icon: "rectangle.stack", tab: .groups, mode: .groups)
            } header: {
                Text("Default Filters")
            } footer: {
                Text("Saved filters from your Stash server that will be applied automatically when opening each tab.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80).focusable(false)
        }
        .onAppear {
            filterViewModel.fetchSavedFilters()
        }
        .background(Color.appBackground)
        .navigationTitle("Default Filters")
    }

    @ViewBuilder
    private func tvFilterRow(label: String, icon: String, tab: AppTab, mode: StashDBViewModel.FilterMode) -> some View {
        let filters = filterViewModel.savedFilters.values
            .filter { $0.mode == mode }
            .sorted { $0.name < $1.name }

        let currentId = tabManager.getDefaultFilterId(for: tab)
        let currentName = tabManager.getDefaultFilterName(for: tab)

        HStack {
            Text(label)
            Spacer()
            Menu {
                Button {
                    tabManager.setDefaultFilter(for: tab, filterId: nil, filterName: nil)
                } label: {
                    HStack {
                        Text("None")
                        if currentId == nil { Spacer(); Image(systemName: "checkmark") }
                    }
                }
                if !filters.isEmpty {
                    Divider()
                    ForEach(filters) { filter in
                        Button {
                            tabManager.setDefaultFilter(for: tab, filterId: filter.id, filterName: filter.name)
                        } label: {
                            HStack {
                                Text(filter.name)
                                if currentId == filter.id { Spacer(); Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            } label: {
                Text(currentName ?? "None")
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Visible Tabs

private struct TVTabVisibilitySettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var tabManager = TabManager.shared

    var body: some View {
        List {
            Section {
                tabVisibilityRow(.reels, label: "Feeds", icon: "play.rectangle.on.rectangle")
                tabVisibilityRow(.scenes, label: "Scenes", icon: "film.fill")
                tabVisibilityRow(.performers, label: "Performers", icon: "person.3.fill")
                tabVisibilityRow(.studios, label: "Studios", icon: "building.2.fill")
                tabVisibilityRow(.tags, label: "Tags", icon: "tag.fill")
                tabVisibilityRow(.groups, label: "Groups", icon: "rectangle.stack.fill")
                tabVisibilityRow(.galleries, label: "Galleries", icon: "photo.stack.fill")
                tabVisibilityRow(.images, label: "Images", icon: "photo.fill")
            } header: {
                Text("Visible Tabs")
            } footer: {
                Text("Choose which tabs appear in the top navigation bar.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80).focusable(false)
        }
        .background(Color.appBackground)
        .navigationTitle("Visible Tabs")
    }

    @ViewBuilder
    private func tabVisibilityRow(_ tab: AppTab, label: String, icon: String) -> some View {
        let isVisible = tabManager.tabs.first(where: { $0.id == tab })?.isVisible ?? true
        Toggle(isOn: Binding(
            get: { isVisible },
            set: { _ in tabManager.toggle(tab) }
        )) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(appearanceManager.tintColor)
                    .frame(width: 28)
                Text(label)
            }
        }
        .tint(appearanceManager.tintColor)
    }
}

// MARK: - About

private struct TVAboutSettingsView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Text("App")
                    Spacer()
                    Text("stashy for Apple TV")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Build")
                    Spacer()
                    Text(buildNumber)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80).focusable(false)
        }
        .background(Color.appBackground)
        .navigationTitle("About")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Server Form View

struct TVServerFormView: View {
    let server: ServerConfig?
    let onSave: (ServerConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var port: String = ""
    @State private var selectedProtocol: ServerProtocol = .https
    @State private var apiKey: String = ""
    
    // Auth State
    @State private var authMethod: AuthMethod = .none
    @State private var username = ""
    @State private var password = ""
    @State private var isFetchingKey = false
    @State private var loginErrorMessage: String? = nil

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case name, address, port, apiKey
    }

    init(server: ServerConfig?, onSave: @escaping (ServerConfig) -> Void) {
        self.server = server
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 40) {
                    Text(server == nil ? "Add Server" : "Edit Server")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 40)

                    VStack(spacing: 24) {
                        TextField("Server Name", text: $name)
                            .focused($focusedField, equals: .name)

                        TextField("Server Address", text: $address)
                            .focused($focusedField, equals: .address)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: address) { _, newValue in
                                let detection = ServerConfig.detectProtocol(from: newValue)
                                if let detectedProtocol = detection.protocol {
                                    selectedProtocol = detectedProtocol
                                    address = detection.address
                                }
                            }

                        HStack(spacing: 24) {
                            TextField("Port (optional)", text: $port)
                                .focused($focusedField, equals: .port)
                                .frame(maxWidth: 300)

                            Picker("Protocol", selection: $selectedProtocol) {
                                ForEach(ServerProtocol.allCases, id: \.self) { proto in
                                    Text(proto.displayName).tag(proto)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 300)
                        }

                        // Authentication Section
                        VStack(alignment: .leading, spacing: 24) {
                            Text("Authentication")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Picker("Auth Method", selection: $authMethod) {
                                ForEach(AuthMethod.allCases, id: \.self) { method in
                                    Text(method.rawValue).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            if authMethod == .login {
                                VStack(spacing: 24) {
                                    TextField("Username", text: $username)
                                        .textContentType(.username)
                                        .textInputAutocapitalization(.never)
                                    
                                    SecureField("Password", text: $password)
                                        .textContentType(.password)
                                    
                                    Button {
                                        fetchKeyViaLogin()
                                    } label: {
                                        HStack(spacing: 12) {
                                            if isFetchingKey {
                                                ProgressView()
                                            }
                                            Text(isFetchingKey ? "Logging in..." : "Fetch API Key")
                                        }
                                        .frame(minWidth: 300)
                                    }
                                    .disabled(username.isEmpty || password.isEmpty || isFetchingKey)
                                    
                                    if let error = loginErrorMessage {
                                        Text(error)
                                            .foregroundColor(.red)
                                            .font(.callout)
                                    }
                                }
                            } else if authMethod == .apiKey {
                                TextField("API Key", text: $apiKey)
                                    .focused($focusedField, equals: .apiKey)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(20)
                    }
                    .frame(maxWidth: 800)

                    HStack(spacing: 40) {
                        Button("Cancel") {
                            dismiss()
                        }

                        Button("Save") {
                            save()
                        }
                        .disabled(address.isEmpty)
                    }
                    .padding(.bottom, 60)
                }
                .padding(.horizontal, 60)
            }
        }
            .onAppear {
                if let server = server {
                    name = server.name
                    address = server.serverAddress
                    port = server.port ?? ""
                    selectedProtocol = server.serverProtocol
                    apiKey = server.secureApiKey ?? ""
                    
                    // Determine initial auth method
                    if let key = server.secureApiKey, !key.isEmpty {
                        authMethod = .apiKey
                    } else {
                        authMethod = .none
                    }
                }
            }
        }

    private func save() {
        // Wenn Login-Auth gewählt aber noch kein Key geholt wurde: erst fetchen, dann speichern.
        if authMethod == .login && apiKey.isEmpty && !username.isEmpty && !password.isEmpty {
            fetchKeyViaLogin(saveAfterFetch: true)
            return
        }

        let parsed = ServerConfig.parseHostAndPort(address)
        let finalAddress = parsed.host
        let finalPort = !port.isEmpty ? port : parsed.port

        let config = ServerConfig(
            id: server?.id ?? UUID(),
            name: name.isEmpty ? "My Stash" : name,
            serverAddress: finalAddress,
            port: finalPort,
            serverProtocol: selectedProtocol,
            apiKey: authMethod == .none ? nil : (apiKey.isEmpty ? nil : apiKey)
        )

        onSave(config)
    }
    
    private func fetchKeyViaLogin(saveAfterFetch: Bool = false) {
        let parsed = ServerConfig.parseHostAndPort(address)
        let finalAddress = parsed.host
        let finalPort = !port.isEmpty ? port : parsed.port
        
        let config = ServerConfig(
            name: name,
            serverAddress: finalAddress,
            port: finalPort,
            serverProtocol: selectedProtocol
        )
        
        isFetchingKey = true
        loginErrorMessage = nil
        
        Task {
            do {
                let fetchedKey = try await LoginAuthHelper.shared.fetchAPIKey(
                    baseURL: config.baseURL,
                    username: username,
                    password: password
                )
                
                await MainActor.run {
                    self.apiKey = fetchedKey
                    self.isFetchingKey = false
                    // Auth-Method nicht wechseln – User bleibt im Login-Flow.
                    // Username/Password behalten für eventuelle Retry.
                    if saveAfterFetch {
                        self.save()
                    }
                }
            } catch {
                await MainActor.run {
                    self.loginErrorMessage = error.localizedDescription
                    self.isFetchingKey = false
                }
            }
        }
    }
}

// MARK: - Color Preset Button

struct TVColorPresetButton: View {
    let preset: ColorOption
    let isSelected: Bool
    @Environment(\.isFocused) var isFocused

    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(preset.color)
                .frame(width: 60, height: 60)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.white : (isFocused ? Color.white.opacity(0.5) : Color.clear), lineWidth: 4)
                )
                .scaleEffect(isFocused ? 1.2 : 1.0)
                .shadow(color: preset.color.opacity(isFocused ? 0.8 : 0.4), radius: isFocused ? 12 : (isSelected ? 8 : 0))

            Text(preset.localizedName)
                .font(.caption)
                .foregroundStyle(isFocused ? .primary : .secondary)
        }
        .padding(16) // Padding to avoid clipping the scale effect
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
