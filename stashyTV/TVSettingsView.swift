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
    case servers, appearance, security, playback, stashyPlus
    case defaultSort, defaultFilters, visibleTabs
    case sidebar
    case about

    var title: String {
        switch self {
        case .servers: return "Servers"
        case .appearance: return "Appearance"
        case .security: return "Security"
        case .playback: return "Playback"
        case .stashyPlus: return "stashy+"
        case .defaultSort: return "Default Sorting"
        case .defaultFilters: return "Default Filters"
        case .visibleTabs: return "Visible Tabs"
        case .sidebar: return "Sidebar Navigation"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .servers: return "server.rack"
        case .appearance: return "paintbrush.fill"
        case .security: return "lock.fill"
        case .playback: return "play.rectangle.fill"
        case .stashyPlus: return "sparkles.tv.fill"
        case .defaultSort: return "arrow.up.arrow.down"
        case .defaultFilters: return "line.3.horizontal.decrease.circle"
        case .visibleTabs: return "rectangle.3.group.fill"
        case .sidebar: return "sidebar.leading"
        case .about: return "info.circle"
        }
    }

    var summary: String {
        switch self {
        case .servers:
            return "Add Stash servers, switch between them, and edit or remove saved ones."
        case .appearance:
            return "Pick the accent color used for focus highlights and icons throughout the app."
        case .security:
            return "Require a PIN before the app opens."
        case .playback:
            return "Choose the streaming quality. \"Original\" plays the file directly for the best seeking; lower qualities transcode."
        case .stashyPlus:
            return "Premium features, including Channels — continuous playback of a performer, studio, tag or saved filter."
        case .defaultSort:
            return "The sort order each section opens with."
        case .defaultFilters:
            return "A saved server filter to apply automatically when a section opens."
        case .visibleTabs:
            return "Hide sections you do not use. They disappear from the sidebar."
        case .sidebar:
            return "The left sidebar is the standard for Apple TV. Turn it off to go back to the classic tab bar along the top."
        case .about:
            return "Version and build number."
        }
    }
}

struct TVSettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @AppStorage("tvUseSidebar") private var useSidebar = true
    @FocusState private var focusedEntry: TVSettingsEntry?

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
        .background(Color.appBackground)
    }

    private var entryList: some View {
        List {
            Section {
                link(.servers) { TVServersSettingsView() }
                link(.appearance) { TVAppearanceSettingsView() }
                link(.security) { TVSecuritySettingsView() }
                link(.playback) { TVPlaybackSettingsView() }
                link(.stashyPlus) { TVStashyPlusSettingsView() }
            } header: {
                Text("General")
            }

            Section {
                link(.defaultSort) { TVDefaultSortSettingsView() }
                link(.defaultFilters) { TVDefaultFilterSettingsView() }
                link(.visibleTabs) { TVTabVisibilitySettingsView() }
            } header: {
                Text("Content")
            }

            Section {
                // Kein eigener Wert-Text: tvOS zeichnet den Toggle-Zustand
                // rechts selbst an, sonst steht dort zweimal „On".
                Toggle(isOn: $useSidebar) {
                    row(.sidebar)
                }
                .focused($focusedEntry, equals: .sidebar)
            } header: {
                Text("Navigation")
            }

            Section {
                link(.about) { TVAboutSettingsView() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80).focusable(false)
        }
    }

    @ViewBuilder
    private func link<Destination: View>(
        _ entry: TVSettingsEntry,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination().tvExitDismissable()
        } label: {
            row(entry)
        }
        .focused($focusedEntry, equals: entry)
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

    @ViewBuilder
    private var detailPane: some View {
        if let entry = focusedEntry {
            VStack(alignment: .leading, spacing: 28) {
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
            .transition(.opacity)
        } else {
            Color.clear
        }
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
                    TVSavedServerRow(
                        server: server,
                        isActive: server.id == configManager.activeConfig?.id,
                        onActivate: { configManager.saveConfig(server) },
                        onEdit: { serverForm = .edit(server) },
                        onDelete: { configManager.deleteServer(id: server.id) }
                    )
                }

                Button {
                    serverForm = .new
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
        .background(Color.appBackground)
        .navigationTitle("Servers")
    }
}

/// Eigene View, damit der Aktions-Dialog **auf der Zeile** liegt und nicht auf
/// der `List` — dort würde er mit dem Form-Sheet um dieselbe Presentation
/// konkurrieren.
private struct TVSavedServerRow: View {
    let server: ServerConfig
    let isActive: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @State private var showingActions = false

    var body: some View {
        HStack(spacing: 24) {
            Button(action: onActivate) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.name)
                            .font(.headline)
                        Text(server.baseURL)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isActive {
                        Image(systemName: "checkmark")
                            .foregroundColor(appearanceManager.tintColor)
                    }
                }
            }

            // Sichtbare Affordance für Bearbeiten/Löschen — vorher nur über ein
            // unsichtbares contextMenu (Long-Press auf Select) erreichbar.
            Button {
                showingActions = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Manage \(server.name)")
            }
        }
        .confirmationDialog(server.name, isPresented: $showingActions, titleVisibility: .visible) {
            Button("Edit", action: onEdit)
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
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
                    TVSettingsPickerRow(
                        title: "Streaming Quality",
                        options: StreamingQuality.allCases.map { TVPickerOption($0, $0.displayName) },
                        selection: Binding(
                            get: { config.defaultQuality },
                            set: { quality in
                                var updated = config
                                updated.defaultQuality = quality
                                configManager.saveConfig(updated)
                                configManager.addOrUpdateServer(updated)
                            }
                        )
                    )
                } else {
                    Text("Connect to a server to configure quality.")
                        .foregroundStyle(.secondary)
                        .focusable()
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
                sortRow(label: "Scenes", tab: .scenes, type: StashDBViewModel.SceneSortOption.self, fallback: .dateDesc)
                sortRow(label: "Performers", tab: .performers, type: StashDBViewModel.PerformerSortOption.self, fallback: .nameAsc)
                sortRow(label: "Studios", tab: .studios, type: StashDBViewModel.StudioSortOption.self, fallback: .nameAsc)
                sortRow(label: "Tags", tab: .tags, type: StashDBViewModel.TagSortOption.self, fallback: .nameAsc)
                sortRow(label: "Groups", tab: .groups, type: StashDBViewModel.GroupSortOption.self, fallback: .nameAsc)
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
            options: Option.allCases.map { TVPickerOption($0, $0.displayName) },
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

        TVSettingsPickerRow(
            title: label,
            options: [TVPickerOption("", "None")] + filters.map { TVPickerOption($0.id, $0.name) },
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
                .focusable()
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

