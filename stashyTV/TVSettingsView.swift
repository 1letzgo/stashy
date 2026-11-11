//
//  TVSettingsView.swift
//  stashyTV
//
//  Created for stashy tvOS.
//

import SwiftUI
import UIKit

/// Ein Eintrag der Settings-Übersicht.
///
/// Der Beschreibungstext füttert die rechte Spalte — tvOS-Einstellungen sind
/// konventionell zweispaltig: schmale Liste links, Kontext zum fokussierten
/// Eintrag rechts. Deshalb braucht die Liste auch nie die volle Breite.
private enum TVSettingsEntry: Hashable {
    case servers, appearance, security, stashyPlus
    case defaultSort, defaultFilters, visibleTabs
    case homeRows
    case subtitles
    case dolbyVision
    case playCount
    case maintenance
    case about

    var title: String {
        switch self {
        case .servers: return tr("servers")
        case .appearance: return tr("appearance")
        case .security: return tr("security")
        case .stashyPlus: return "stashy+"
        case .defaultSort: return tr("default_sorting")
        case .defaultFilters: return tr("default_filters")
        case .visibleTabs: return tr("visible_tabs")
        case .homeRows: return tr("home_rows")
        case .subtitles: return tr("subtitles")
        case .dolbyVision: return tr("dolby_vision")
        case .playCount: return tr("count_as_played")
        case .maintenance: return tr("maintenance")
        case .about: return tr("about")
        }
    }

    var icon: String {
        switch self {
        case .servers: return "server.rack"
        case .appearance: return "paintbrush.fill"
        case .security: return "lock.fill"
        case .stashyPlus: return "sparkles.tv.fill"
        case .defaultSort: return "arrow.up.arrow.down"
        case .defaultFilters: return "line.3.horizontal.decrease.circle"
        case .visibleTabs: return "rectangle.3.group.fill"
        case .homeRows: return "rectangle.grid.1x2.fill"
        case .subtitles: return "captions.bubble.fill"
        case .dolbyVision: return "sparkles.tv"
        case .playCount: return "play.circle"
        case .maintenance: return "internaldrive"
        case .about: return "info.circle"
        }
    }

    var summary: String {
        switch self {
        case .servers:
            return tr("hint_add_stash_servers_switch_between")
        case .appearance:
            return tr("hint_pick_app_theme_and_accent")
        case .security:
            return tr("hint_require_pin_before_app_opens")
        case .stashyPlus:
            return tr("hint_premium_features_including_channels_continuous")
        case .defaultSort:
            return tr("hint_sort_order_each_section_opens")
        case .defaultFilters:
            return tr("hint_saved_server_filter_to_apply")
        case .visibleTabs:
            return tr("hint_hide_sections_you_do_not")
        case .homeRows:
            return tr("hint_choose_which_rows_home_shows")
        case .subtitles:
            return tr("hint_turn_subtitles_on_automatically_choose")
        case .playCount:
            return tr("hint_how_long_scene_has_to")
        case .dolbyVision:
            return tr("hint_turn_off_if_dolby_vision")
        case .maintenance:
            return tr("hint_clear_cached_artwork_for_active")
        case .about:
            return tr("version_and_build_number")
        }
    }
}

struct TVSettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @FocusState private var focusedEntry: TVSettingsEntry?
    /// Wird an die gepushten Unterseiten weitergereicht, damit `tvExitDismissable()`
    /// dort den Pfad kennt und die Menu-Taste eine Ebene zurückgeht.
    @Environment(\.tvNavigationPath) private var navigationPath
    /// Der Fokus verlässt die Liste, sobald er in die Sidebar wandert. Ohne
    /// gemerkten Eintrag stünde die rechte Spalte dann leer.
    @State private var detailEntry: TVSettingsEntry = .servers

    /// Liste links schmal halten — eine Einstellungszeile über die volle
    /// 1920pt-Breite ist der Hauptgrund, warum das vorher nach iOS aussah.
    private static let listWidth: CGFloat = 720

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            entryList
                .frame(width: Self.listWidth)
                .focusSection()

            detailPane
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 60)
        }
        .padding(.trailing, 80)
        .background(TVThemeFill())
        .onChange(of: focusedEntry) { _, entry in
            if let entry { detailEntry = entry }
        }
        .navigationDestination(for: TVSettingsEntry.self) { entry in
            destination(for: entry)
                .tvExitDismissable()
                .environment(\.tvNavigationPath, navigationPath)
        }
    }

    private var entryList: some View {
        List {
            Section {
                link(.servers)
                link(.appearance)
                link(.security)
                link(.stashyPlus)
            } header: {
                Text(tr("general"))
            }

            Section {
                link(.defaultSort)
                link(.defaultFilters)
                link(.visibleTabs)
                link(.homeRows)
            } header: {
                Text(tr("content"))
            }

            Section {
                link(.subtitles)
                // Kein eigener Wert-Text: tvOS zeichnet den Toggle-Zustand rechts selbst an.
                Toggle(isOn: $tabManager.playerDolbyVisionEnabled) {
                    row(.dolbyVision)
                }
                .focused($focusedEntry, equals: .dolbyVision)
                link(.playCount, value: TabManager.playCountThresholdLabel(tabManager.playCountPlayerSeconds))
            } header: {
                Text(tr("playback"))
            }

            Section {
                link(.maintenance)
                link(.about)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80).focusable(false)
        }
    }

    /// Wert-basiert statt ziel-basiert: nur so landet die Unterseite im
    /// `NavigationPath` des Settings-Tabs. Ein `NavigationLink(destination:)` schiebt
    /// zwar auch, taucht im gebundenen Pfad aber nie auf — dann ließ sich die
    /// Unterseite von außen nicht mehr schließen, und beim Wechsel in einen anderen
    /// Sidebar-Eintrag blieb sie stehen.
    private func link(_ entry: TVSettingsEntry, value: String? = nil) -> some View {
        NavigationLink(value: entry) {
            row(entry, value: value)
        }
        .focused($focusedEntry, equals: entry)
    }

    @ViewBuilder
    private func destination(for entry: TVSettingsEntry) -> some View {
        switch entry {
        case .servers: TVServersSettingsView()
        case .appearance: TVAppearanceSettingsView()
        case .security: TVSecuritySettingsView()
        case .stashyPlus: TVStashyPlusSettingsView()
        case .defaultSort: TVDefaultSortSettingsView()
        case .defaultFilters: TVDefaultFilterSettingsView()
        case .visibleTabs: TVTabVisibilitySettingsView()
        case .homeRows: TVHomeRowsSettingsView()
        case .subtitles: TVSubtitleSettingsView()
        case .maintenance: TVMaintenanceSettingsView()
        case .about: TVAboutSettingsView()
        // Kein Link, sondern ein Toggle in der Liste.
        case .playCount: playCountPage
        case .dolbyVision: EmptyView()
        }
    }

    private var playCountPage: some View {
        List {
            ForEach(TabManager.playCountThresholdOptions, id: \.self) { seconds in
                Button {
                    tabManager.playCountPlayerSeconds = seconds
                } label: {
                    HStack {
                        Text(TabManager.playCountThresholdLabel(seconds))
                        if tabManager.playCountPlayerSeconds == seconds {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        .tvSettingsPage(tr("count_as_played"),
                        description: tr("hint_how_long_scene_has_to"))
    }

    /// Nur Text, Wert rechtsbündig — die tvOS-Form. Icons und Untertitel in
    /// jeder Zeile waren aus der iOS-Settings-Welt übernommen.
    private func row(_ entry: TVSettingsEntry, value: String? = nil) -> some View {
        HStack {
            Text(entry.title)
            if let value {
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailPane: some View {
        let entry = detailEntry
        return VStack(alignment: .leading, spacing: 28) {
            Image(systemName: entry.icon)
                .font(.system(size: 72))
                .foregroundColor(appearanceManager.tintColor)

            Text(entry.title)
                .font(.title)
                .fontWeight(.semibold)

            Text(entry.summary)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 620, alignment: .leading)
    }
}

// MARK: - Settings page chrome

/// Gemeinsames Gerüst für alle Settings-Unterseiten.
///
/// tvOS zeichnet keine Navigation-Bar — `navigationTitle` ist dort unsichtbar.
/// Ohne eigenen Titel landet der Nutzer in einer Liste ohne Überschrift und
/// weiß nicht, wo er ist. Der Erklärtext steht rechts statt als Listen-Footer:
/// zweispaltig ist die tvOS-Form, ein Footer unter der Liste ist aus iOS
/// übernommen und auf 1920pt kaum lesbar.
struct TVSettingsPageChrome: ViewModifier {
    let title: String
    let description: String?
    /// Optional unter der Beschreibung in der rechten Spalte, z.B. eine Vorschau.
    var detail: AnyView? = nil

    /// Knapp halbe Bildbreite. Eine Einstellungszeile über die volle Breite ist
    /// der Hauptgrund, warum diese Seiten vorher nach iOS aussahen.
    private static let contentWidth: CGFloat = 900

    func body(content: Content) -> some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                content
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 80).focusable(false)
                    }
            }
            .frame(width: Self.contentWidth)
            .focusSection()

            if description != nil || detail != nil {
                VStack(alignment: .leading, spacing: 32) {
                    if let description {
                        Text(description)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let detail {
                        detail
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
                // Auf Höhe der ersten Listenzeile, nicht des Titels.
                .padding(.top, 96)
                .focusable(false)
            }

            Spacer(minLength: 0)
        }
        // Gepushte Seiten decken die Sidebar ab; der überscan-sichere Rand
        // muss deshalb hier selbst kommen.
        .padding(.leading, 60)
        .padding(.trailing, 80)
        .padding(.top, 60)
        .background(TVThemeFill())
        // tvOS zeichnet `navigationTitle` mittig und ausgegraut über den Inhalt.
        // Neben der linksbündigen Überschrift stünde der Titel doppelt da, also
        // leer setzen — dasselbe macht `TVSceneDetailView`.
        .navigationTitle("")
    }
}

extension View {
    /// Titel + zweispaltiges Layout für eine Settings-Unterseite.
    func tvSettingsPage(_ title: String, description: String? = nil) -> some View {
        modifier(TVSettingsPageChrome(title: title, description: description))
    }

    func tvSettingsPage<Detail: View>(_ title: String, description: String? = nil,
                                      @ViewBuilder detail: () -> Detail) -> some View {
        modifier(TVSettingsPageChrome(title: title, description: description,
                                      detail: AnyView(detail())))
    }
}

// MARK: - Servers

private struct TVServersSettingsView: View {
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    /// Genau **eine** Presentation auf Ebene der `List`. Vorher lagen hier ein
    /// `confirmationDialog` und zwei `.sheet` übereinander — SwiftUI erlaubt pro
    /// View nur eine, gestapelt hoben sie sich gegenseitig auf (Sheet ging auf
    /// und sofort wieder zu).
    @State private var serverForm: ServerFormTarget?

    /// Der aktive Server steht schon oben; hier nur die Umschalt-Kandidaten.
    private var otherServers: [ServerConfig] {
        configManager.savedServers.filter { $0.id != configManager.activeConfig?.id }
    }

    private enum ServerFormTarget: Identifiable {
        case new
        case edit(ServerConfig)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let server): return server.id.uuidString
            }
        }
    }

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
                    // Ohne das liess sich der aktive Server (bei nur einem Server: der
                    // einzige) nie bearbeiten, z. B. um den API-Key zu ändern.
                    .contextMenu {
                        Button(tr("action_edit")) { serverForm = .edit(config) }
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.yellow)
                        Text(tr("empty_server_configured"))
                            .foregroundStyle(.secondary)
                    }
                    .focusable()
                }
            } header: {
                Text(tr("active_server"))
            }

            if !otherServers.isEmpty {
                Section {
                    ForEach(otherServers) { server in
                        TVSavedServerRow(
                            server: server,
                            onActivate: { configManager.saveConfig(server) },
                            onEdit: { serverForm = .edit(server) },
                            onDelete: { configManager.deleteServer(id: server.id) }
                        )
                    }
                } header: {
                    Text(tr("switch_server"))
                }
            }

            Section {
                Button {
                    serverForm = .new
                } label: {
                    Label(tr("action_add_server"), systemImage: "plus")
                }
            }
        }
        .dismissOnAppLock { serverForm = nil }
        .sheet(item: $serverForm) { target in
            switch target {
            case .new:
                TVServerFormView(server: nil) { newServer in
                    configManager.addOrUpdateServer(newServer)
                    configManager.saveConfig(newServer)
                    serverForm = nil
                }
            case .edit(let server):
                TVServerFormView(server: server) { updatedServer in
                    configManager.addOrUpdateServer(updatedServer)
                    if updatedServer.id == configManager.activeConfig?.id {
                        configManager.saveConfig(updatedServer)
                    }
                    serverForm = nil
                }
            }
        }
        .tvSettingsPage(tr("servers"), description: tr("hint_add_stash_servers_and_switch"))
    }
}

/// Eigene View, damit der Aktions-Dialog **auf der Zeile** liegt und nicht auf
/// der `List` — dort würde er mit dem Form-Sheet um dieselbe Presentation
/// konkurrieren.
/// Eine Zeile, ein Button. Ein zweiter Button daneben (vorher „•••") teilt sich
/// in einer tvOS-List-Zeile den Select mit dem Aktivieren-Button — dann öffnete
/// beim Serverwechsel jedes Mal der Bearbeiten-Dialog. Bearbeiten und Löschen
/// liegen deshalb wieder auf dem Kontextmenü (langes Select).
private struct TVSavedServerRow: View {
    let server: ServerConfig
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        Button(action: onActivate) {
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.headline)
                Text(server.baseURL)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            Button(tr("action_edit"), action: onEdit)
            Button(tr("action_delete"), role: .destructive) { confirmingDelete = true }
        }
        .alert(tr("confirm_delete_arg", server.name), isPresented: $confirmingDelete) {
            Button(tr("action_delete"), role: .destructive, action: onDelete)
            Button(tr("action_cancel"), role: .cancel) {}
        }
    }
}

// MARK: - Appearance

private struct TVAppearanceSettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text(tr("theme"))
                        .font(.headline)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 24) {
                            ForEach(AppTheme.tvOSThemes) { theme in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        appearanceManager.preferredTheme = theme
                                    }
                                } label: {
                                    TVThemePreviewCard(
                                        theme: theme,
                                        isSelected: appearanceManager.currentTheme == theme,
                                        tint: appearanceManager.tintColor
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text(tr("accent_color"))
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
            }
        }
        .tvSettingsPage(tr("appearance"), description: tr("hint_pick_app_theme_and_accent"))
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
                    tr("action_enable_pin_lock"),
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
                    Button(tr("action_change_pin")) {
                        showingSetPasscode = true
                    }

                    Button(tr("action_remove_pin"), role: .destructive) {
                        securityManager.removePin()
                    }
                }
            }
        }
        .dismissOnAppLock { showingSetPasscode = false }
        .fullScreenCover(isPresented: $showingSetPasscode) {
            TVPasscodeSetupView(isPresented: $showingSetPasscode)
                .presentationBackground(Color.black)
        }
        .tvSettingsPage(tr("security"), description: tr("hint_app_asks_for_your_pin"))
    }
}

// MARK: - Default Sorting

private struct TVDefaultSortSettingsView: View {
    @ObservedObject private var tabManager = TabManager.shared

    @AppStorage(StudioCountsStore.includeSubStudiosKey) private var includeSubStudios = false

    var body: some View {
        List {
            Section {
                sortRow(label: tr("scenes"), tab: .scenes, type: StashDBViewModel.SceneSortOption.self, fallback: .dateDesc)
                sortRow(label: tr("performers"), tab: .performers, type: StashDBViewModel.PerformerSortOption.self, fallback: .nameAsc)
                sortRow(label: tr("studios"), tab: .studios, type: StashDBViewModel.StudioSortOption.self, fallback: .nameAsc)
                sortRow(label: tr("tags"), tab: .tags, type: StashDBViewModel.TagSortOption.self, fallback: .nameAsc)
                sortRow(label: tr("groups"), tab: .groups, type: StashDBViewModel.GroupSortOption.self, fallback: .nameAsc)
            }
            if StashServerCapabilities.supports032 {
                Section {
                    Toggle(tr("studio_counts_include_sub_studios"), isOn: $includeSubStudios)
                }
            }
        }
        .tvSettingsPage(tr("default_sorting"), description: tr("hint_sort_order_each_section_opens"))
    }

    /// Eine flache Auswahl pro Entität. Vorher lagen hier verschachtelte
    /// `Menu`-Submenüs — auf tvOS drei Ebenen tief mit der Fernbedienung.
    @ViewBuilder
    private func sortRow<Option>(
        label: String,
        tab: AppTab,
        type: Option.Type,
        fallback: Option
    ) -> some View where Option: RawRepresentable & CaseIterable & Hashable & DisplayNameProvider,
                         Option.RawValue == String,
                         Option.AllCases == [Option] {
        let binding = Binding<Option>(
            get: { Option(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? fallback },
            set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
        )
        TVSettingsPickerRow(
            title: label,
            options: Option.allCases
                .filter { ($0 as? any StashVersionedSortOption)?.isAvailableOnServer ?? true }
                .map { TVPickerOption($0, $0.displayName) },
            selection: binding
        )
    }
}

// MARK: - Default Filters

private struct TVDefaultFilterSettingsView: View {
    @ObservedObject private var tabManager = TabManager.shared
    @StateObject private var filterViewModel = StashDBViewModel()

    var body: some View {
        List {
            Section {
                tvFilterRow(label: tr("scenes"), icon: "film", tab: .scenes, mode: .scenes)
                tvFilterRow(label: tr("performers"), icon: "person.3", tab: .performers, mode: .performers)
                tvFilterRow(label: tr("studios"), icon: "building.2", tab: .studios, mode: .studios)
                tvFilterRow(label: tr("tags"), icon: "tag", tab: .tags, mode: .tags)
                tvFilterRow(label: tr("groups"), icon: "rectangle.stack", tab: .groups, mode: .groups)
            }
        }
        .onAppear {
            filterViewModel.fetchSavedFilters()
        }
        .tvSettingsPage(tr("default_filters"), description: tr("hint_saved_filter_from_your_stash"))
    }

    @ViewBuilder
    private func tvFilterRow(label: String, icon: String, tab: AppTab, mode: StashDBViewModel.FilterMode) -> some View {
        let filters = filterViewModel.savedFilters.values
            .filter { $0.mode == mode }
            .sorted { $0.name < $1.name }

        let currentId = tabManager.getDefaultFilterId(for: tab)

        TVSettingsPickerRow(
            title: label,
            options: [TVPickerOption("", tr("none"))] + filters.map { TVPickerOption($0.id, $0.name) },
            selection: Binding(
                get: { currentId ?? "" },
                set: { newId in
                    guard !newId.isEmpty else {
                        tabManager.setDefaultFilter(for: tab, filterId: nil, filterName: nil)
                        return
                    }
                    let name = filters.first(where: { $0.id == newId })?.name
                    tabManager.setDefaultFilter(for: tab, filterId: newId, filterName: name)
                }
            )
        )
    }
}

// MARK: - Visible Tabs

private struct TVTabVisibilitySettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var tabManager = TabManager.shared

    var body: some View {
        List {
            Section {
                tabVisibilityRow(.reels, label: tr("feeds"), icon: "play.rectangle.on.rectangle")
                tabVisibilityRow(.scenes, label: tr("scenes"), icon: "film.fill")
                tabVisibilityRow(.performers, label: tr("performers"), icon: "person.3.fill")
                tabVisibilityRow(.studios, label: tr("studios"), icon: "building.2.fill")
                tabVisibilityRow(.tags, label: tr("tags"), icon: "tag.fill")
                tabVisibilityRow(.groups, label: tr("groups"), icon: "rectangle.stack.fill")
                tabVisibilityRow(.galleries, label: tr("galleries"), icon: "photo.stack.fill")
                tabVisibilityRow(.images, label: tr("images"), icon: "photo.fill")
                tabVisibilityRow(.markers, label: tr("markers"), icon: "bookmark.fill")
            }
        }
        .tvSettingsPage(tr("visible_tabs"), description: tr("hint_sections_you_turn_off_disappear"))
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

// MARK: - Subtitles

/// Untertitel-Defaults und -Look für tvOS. Schreibt genau dieselben
/// UserDefaults-Keys wie die iOS-Seite (Settings → Playback → Subtitles), damit
/// `TabManager.subtitleStyle` und der Auto-Pick in `AetherSceneEngine` hier
/// identisch lesen. Zwei getrennte Stores (iPhone/Apple TV) — deshalb braucht
/// die TV-App ihre eigene Oberfläche, nicht nur der Renderer.
private struct TVSubtitleSettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    /// Die Sprachliste ist zu lang für einen `confirmationDialog` — eigene Seite.
    @State private var showingLanguagePicker = false

    var body: some View {
        List {
            Section {
                Toggle(tr("action_show_subtitles_automatically"), isOn: $tabManager.subtitlesAutoEnabled)
                    .tint(appearanceManager.tintColor)

                Button {
                    showingLanguagePicker = true
                } label: {
                    HStack {
                        Text(tr("preferred_language"))
                        Spacer()
                        Text(languageLabel)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(tr("defaults"))
            }

            Section {
                TVSettingsPickerRow(
                    title: tr("size"),
                    options: SubtitleFontSize.allCases.map { TVPickerOption($0, $0.label) },
                    selection: $tabManager.subtitleFontSize
                )

                TVSettingsPickerRow(
                    title: tr("font"),
                    options: SubtitleFontFamily.allCases.map { TVPickerOption($0, $0.label) },
                    selection: $tabManager.subtitleFontFamily
                )

                TVSettingsPickerRow(
                    title: tr("text_color"),
                    options: SubtitleTextColorChoice.allCases.map { TVPickerOption($0, $0.label) },
                    selection: $tabManager.subtitleTextColor
                )

                Toggle(tr("background_box"), isOn: $tabManager.subtitleBoxEnabled)
                    .tint(appearanceManager.tintColor)

                TVSettingsPickerRow(
                    title: tr("background_color"),
                    options: SubtitleBackgroundChoice.allCases.map { TVPickerOption($0, $0.label) },
                    selection: $tabManager.subtitleBackgroundColor
                )
                .disabled(!tabManager.subtitleBoxEnabled)
            } header: {
                Text(tr("appearance"))
            }
        }
        .dismissOnAppLock { showingLanguagePicker = false }
        .fullScreenCover(isPresented: $showingLanguagePicker) {
            TVSubtitleLanguagePickerView(selection: $tabManager.subtitlePreferredLanguage)
        }
        // Die Vorschau steht rechts neben der Liste: unter der Liste wäre sie nicht
        // fokussierbar und damit nie ganz im Bild.
        .tvSettingsPage(tr("subtitles"),
                        description: tr("hint_subtitles_start_on_preferred_language")) {
            preview
        }
    }

    private var languageLabel: String {
        let code = SubtitlePreferredLanguage.normalized(tabManager.subtitlePreferredLanguage)
        return SubtitlePreferredLanguage.pickerOptions().first { $0.id == code }?.label ?? tr("any")
    }

    /// Cue wie der Player ihn zeichnet — mit demselben TV-Scale, damit die
    /// Größenwahl hier so aussieht wie später im Vollbild.
    private var preview: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.22), Color(white: 0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            StashySubtitleText(text: tr("sample_subtitle"),
                               scale: TVSubtitleMetrics.previewScale,
                               lineLimit: 2,
                               style: tabManager.subtitleStyle)
                .padding(.horizontal, 24)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 24)
        }
        .frame(width: 620, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
        .focusable(false)
        .accessibilityLabel(tr("subtitle_preview"))
    }
}

/// Scale-Faktoren für die Untertitel auf tvOS an einer Stelle: Der Player
/// zeichnet auf die volle 1920pt-Bühne, die Vorschau in eine 900pt-Spalte.
enum TVSubtitleMetrics {
    /// Vollbild-Player. 18pt (Medium) landen damit bei ~38pt auf 1080p.
    static let playerScale: CGFloat = 2.1
    /// Vorschau in den Settings — 620pt-Kachel, also gut ein Drittel der Bühne.
    static let previewScale: CGFloat = 1.7
}

/// Eigene Seite für die Sprachwahl: "Any", dann die gängigen Sprachen, dann
/// der Rest. Ein `confirmationDialog` mit ~180 Zeilen wäre mit der
/// Fernbedienung nicht bedienbar.
private struct TVSubtitleLanguagePickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    private var options: [(id: String, label: String)] { SubtitlePreferredLanguage.pickerOptions() }

    private var common: [(id: String, label: String)] {
        let wanted = Set([SubtitlePreferredLanguage.anyValue] + SubtitlePreferredLanguage.commonCodes)
        return options.filter { wanted.contains($0.id) }
    }

    private var rest: [(id: String, label: String)] {
        let wanted = Set([SubtitlePreferredLanguage.anyValue] + SubtitlePreferredLanguage.commonCodes)
        return options.filter { !wanted.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(common, id: \.id) { option in
                        row(option)
                    }
                } header: {
                    Text(tr("common"))
                }

                Section {
                    ForEach(rest, id: \.id) { option in
                        row(option)
                    }
                } header: {
                    Text(tr("all_languages"))
                }
            }
            .tvSettingsPage(tr("preferred_language"),
                            description: tr("hint_language_scenes_subtitles_start_with"))
        }
        .background(TVThemeFill())
    }

    private func row(_ option: (id: String, label: String)) -> some View {
        let isSelected = SubtitlePreferredLanguage.normalized(selection) == option.id
        return Button {
            selection = option.id
            dismiss()
        } label: {
            HStack {
                Text(option.label)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(appearanceManager.tintColor)
                }
            }
        }
    }
}

// MARK: - Maintenance

private struct TVMaintenanceSettingsView: View {
    @ObservedObject private var configManager = ServerConfigManager.shared
    @State private var didClear = false

    var body: some View {
        List {
            Section {
                // Nicht `.disabled` ohne Server — das ist der einzige Button
                // der Seite, deaktiviert wäre sie eine Sackgasse.
                Button {
                    guard configManager.activeConfig != nil else { return }
                    // Gegenstück zu „Clear Image Cache" auf iOS
                    // (`MainTabView`, Wartungsaufgaben).
                    ImageCache.shared.clearCurrentServerCache()
                    didClear = true
                } label: {
                    HStack {
                        Text(tr("action_clear_image_cache"))
                        if didClear {
                            Spacer()
                            Text(tr("cleared"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .tvSettingsPage(tr("maintenance"), description: tr("hint_removes_cached_artwork_for_active"))
    }
}

// MARK: - About

private struct TVAboutSettingsView: View {
    var body: some View {
        List {
            Section {
                // Jede Zeile fokussierbar: eine tvOS-Liste ohne fokussierbare
                // Zeile lässt sich weder scrollen noch verlassen.
                aboutRow(tr("app"), tr("stashy_for_apple_tv"))
                aboutRow(tr("version"), appVersion)
                aboutRow(tr("build"), buildNumber)
            }
        }
        .tvSettingsPage(tr("about"), description: tr("hint_version_and_build_number_of"))
    }

    private func aboutRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .focusable()
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
    @State private var localAddress: String = ""
    @State private var selectedProtocol: ServerProtocol = .https
    @State private var apiKey: String = ""
    /// Custom HTTP headers (SSO / reverse proxy), stored with the config on tvOS.
    @State private var customHeaders: [ServerHTTPHeader] = []
    
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
                    Text(server == nil ? tr("action_add_server") : tr("action_edit_server"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 40)

                    VStack(spacing: 24) {
                        TextField(tr("server_name"), text: $name)
                            .focused($focusedField, equals: .name)

                        TextField(tr("server_address"), text: $address)
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
                            TextField(tr("port_optional"), text: $port)
                                .focused($focusedField, equals: .port)
                                .frame(maxWidth: 300)

                            Picker(tr("protocol"), selection: $selectedProtocol) {
                                ForEach(ServerProtocol.allCases, id: \.self) { proto in
                                    Text(proto.displayName).tag(proto)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 300)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            TextField(tr("local_address_optional_e_g"), text: $localAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Text(tr("hint_used_instead_of_address_above"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Authentication Section
                        VStack(alignment: .leading, spacing: 24) {
                            Text(tr("authentication"))
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Picker(tr("auth_method"), selection: $authMethod) {
                                ForEach(AuthMethod.allCases, id: \.self) { method in
                                    Text(method.displayName).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            if authMethod == .login {
                                VStack(spacing: 24) {
                                    TextField(tr("username"), text: $username)
                                        .textContentType(.username)
                                        .textInputAutocapitalization(.never)
                                    
                                    SecureField(tr("password"), text: $password)
                                        .textContentType(.password)
                                    
                                    Button {
                                        fetchKeyViaLogin()
                                    } label: {
                                        HStack(spacing: 12) {
                                            if isFetchingKey {
                                                ProgressView()
                                            }
                                            Text(isFetchingKey ? tr("logging_in_menu") : tr("action_fetch_api_key"))
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
                                TextField(tr("api_key"), text: $apiKey)
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

                    TVCustomHeadersCard(headers: $customHeaders)
                        .frame(maxWidth: 800)

                    HStack(spacing: 40) {
                        Button(tr("action_cancel")) {
                            dismiss()
                        }

                        Button(tr("action_save")) {
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
                    localAddress = server.localBaseURL ?? ""
                    selectedProtocol = server.serverProtocol
                    apiKey = server.secureApiKey ?? ""
                    customHeaders = server.secureCustomHeaders
                    
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
            name: name.isEmpty ? tr("my_stash") : name,
            serverAddress: finalAddress,
            port: finalPort,
            serverProtocol: selectedProtocol,
            apiKey: authMethod == .none ? nil : (apiKey.isEmpty ? nil : apiKey),
            customHeaders: {
                let usable = ServerHTTPHeader.sanitized(customHeaders)
                return usable.isEmpty ? nil : usable
            }(),
            localURL: ServerConfig.normalizedLocalURL(localAddress)
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
                    password: password,
                    extraHeaders: ServerHTTPHeader.sanitized(customHeaders)
                        .reduce(into: [:]) { $0[$1.name] = $1.value }
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

// MARK: - Custom Headers

/// Name/value pairs sent with every request to the server (SSO, reverse proxy). Used by the
/// server form in Settings and by first-run setup.
struct TVCustomHeadersCard: View {
    @Binding var headers: [ServerHTTPHeader]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(tr("custom_headers"))
                .font(.headline)
                .foregroundStyle(.secondary)

            // Stacked, not side by side: the form can be presented narrow, and a header
            // name like `CF-Access-Client-Secret` has to stay readable.
            ForEach($headers) { $header in
                VStack(alignment: .leading, spacing: 12) {
                    TextField(tr("header_name"), text: $header.name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack(spacing: 16) {
                        SecureField(tr("value"), text: $header.value)
                        Button {
                            headers.removeAll { $0.id == header.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .accessibilityLabel(tr("action_remove_header"))
                    }
                }
            }

            Button {
                headers.append(ServerHTTPHeader(name: "", value: ""))
            } label: {
                Label(tr("action_add_header"), systemImage: "plus.circle.fill")
            }

            Text(tr("hint_sent_with_every_request_to"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
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

