
//
//  ServerConfigView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

import SwiftUI

struct ServerConfigView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    
    // UI State
    @State private var showSuccessMessage: Bool = false
    @State private var isScanningLibrary: Bool = false
    @State private var showScanAlert: Bool = false
    @State private var scanAlertMessage: String = ""
    @State private var showingAddServerSheet = false
    @State private var editingServer: ServerConfig?

    var body: some View {
        Form {
            serversSection
            
            if let _ = configManager.activeConfig {
                Section("Downloads") {
                    NavigationLink(destination: DownloadsView()) {
                        Label("Downloads", systemImage: "square.and.arrow.down")
                    }
                }
            }
            
            if let _ = configManager.activeConfig {
                // Active server controls moved to list row
            } else {
                noServerSection
            }
            
            interfaceSettingsSection
            
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddServerSheet) {
            NavigationView {
                ServerFormViewNew(configToEdit: nil) { newConfig in
                    configManager.addOrUpdateServer(newConfig)
                    // Auto connect if it's the first one
                    if configManager.activeConfig == nil {
                        configManager.saveConfig(newConfig)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingServer) { server in
            NavigationView {
                ServerFormViewNew(configToEdit: server, onSave: { updatedConfig in
                    configManager.addOrUpdateServer(updatedConfig)
                    // If we edited the active config, update it
                    if configManager.activeConfig?.id == updatedConfig.id {
                        configManager.saveConfig(updatedConfig)
                    }
                    editingServer = nil
                }, onDelete: {
                    configManager.deleteServer(id: server.id)
                    editingServer = nil
                })
            }
            .presentationDetents([.medium, .large])
        }
        // fetchStatistics removed from onAppear here as it is now in the subview
        .onAppear {
             if let _ = configManager.activeConfig {
                 viewModel.testConnection()
             }
        }
        .alert("Library Scan", isPresented: $showScanAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(scanAlertMessage)
        }
    }
    
    
    // MARK: - Subviews
    
    private var serversSection: some View {
        Section("Servers") {
            List {
                ForEach(configManager.savedServers) { server in
                    ServerListRow(
                        server: server,
                        viewModel: viewModel,
                        isActive: configManager.activeConfig?.id == server.id,
                        isConnected: configManager.activeConfig?.id == server.id && viewModel.isServerConnected,
                        isScanning: isScanningLibrary,
                        onConnect: {
                            configManager.saveConfig(server)
                            viewModel.resetData()
                            viewModel.testConnection()
                            viewModel.fetchStatistics()
                            coordinator.resetAllStacks()
                        },
                        onEdit: {
                            editingServer = server
                        },
                        onScan: {
                            startLibraryScan()
                        }
                    )
                }
                .onDelete { indexSet in
                    configManager.deleteServer(at: indexSet)
                }
            }
            
            Button(action: {
                showingAddServerSheet = true
            }) {
                Label("Add New Server", systemImage: "plus")
            }
        }
    }
    
    private var interfaceSettingsSection: some View {
        Section("Interface") {
            NavigationLink(destination: AppearanceSettingsView()) {
                Label("Appearance", systemImage: "paintbrush")
            }
            
            NavigationLink(destination: TabOrderView().environmentObject(viewModel)) {
                Label("Manage Tabs", systemImage: "list.bullet")
            }
            
            NavigationLink(destination: TabDefaultSortView()) {
                 Label("Default Sort Options", systemImage: "arrow.up.arrow.down")
            }
            
            NavigationLink(destination: TabDefaultFilterView()) {
                 Label("Default Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }
    
    // activeServerSection removed as its functionality was moved to the row
    
    private var noServerSection: some View {
        Section {
            Text("No server connected. Please add and connect a server.")
                .foregroundColor(.secondary)
        }
    }
    
    private var aboutSection: some View {
        Text("🚧 crafted by letzgo")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
    }
    
    private func startLibraryScan() {
        isScanningLibrary = true
        viewModel.triggerLibraryScan { success, message in
            DispatchQueue.main.async {
                isScanningLibrary = false
                scanAlertMessage = message
                showScanAlert = true
            }
        }
    }
}

// MARK: - Server List Row
// MARK: - Server List Row
struct ServerListRow: View {
    let server: ServerConfig
    @ObservedObject var viewModel: StashDBViewModel // Add ViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    let isActive: Bool
    let isConnected: Bool
    let isScanning: Bool
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onScan: () -> Void
    
    var body: some View {
        HStack {
            // Main clickable area (Name, Indicator, URL)
            Button(action: {
                if !isActive {
                    onConnect()
                }
            }) {
                HStack {
                    // Traffic Light Indicator
                    Image(systemName: "circle.fill")
                        .foregroundColor(indicatorColor)
                        .font(.caption)
                        .padding(.trailing, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(server.baseURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .buttonStyle(PlainButtonStyle())
            //.disabled(isActive) // Removed to prevent graying out active item

            
            NavigationLink(destination: ServerDetailView(server: server, viewModel: viewModel)) {
                 EmptyView()
            }
            .padding(.leading, 8)
        }
    }
    
    private var indicatorColor: Color {
        if isActive {
            return isConnected ? .green : .yellow
        } else {
            return .gray.opacity(0.3)
        }
    }
}

// MARK: - Server Form View
struct ServerFormView: View {
    @Environment(\.presentationMode) var presentationMode
    
    // Form State
    // Form State
    @State private var name: String = "My Stash"
    @State private var serverAddress: String = ""
    @State private var serverProtocol: ServerProtocol = .https
    @State private var apiKey: String = ""
    
    let configToEdit: ServerConfig?
    let onSave: (ServerConfig) -> Void
    let onDelete: (() -> Void)? // Optional delete callback
    
    @State private var showingDeleteAlert = false
    
    init(configToEdit: ServerConfig?, onSave: @escaping (ServerConfig) -> Void, onDelete: (() -> Void)? = nil) {
        self.configToEdit = configToEdit
        self.onSave = onSave
        self.onDelete = onDelete
        
        // Initial values are set in onAppear because State requires init
    }
    
    var isConfigValid: Bool {
        return !name.isEmpty && !serverAddress.isEmpty
    }
    
    var body: some View {
        Form {
            Section("Server Details") {
                TextField("Server Name", text: $name)
                
                Picker("Protocol", selection: $serverProtocol) {
                    ForEach(ServerProtocol.allCases, id: \.self) { proto in
                        Text(proto.displayName).tag(proto)
                    }
                }
                .pickerStyle(.segmented)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server Address")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("192.168.1.100:9999 or stash.example.com", text: $serverAddress)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .onChange(of: serverAddress) { oldValue, newValue in
                            if newValue.lowercased().hasPrefix("https://") {
                                serverProtocol = .https
                                serverAddress = String(newValue.dropFirst(8))
                            } else if newValue.lowercased().hasPrefix("http://") {
                                serverProtocol = .http
                                serverAddress = String(newValue.dropFirst(7))
                            }
                        }
                }
                .padding(.vertical, 4)
                
                // API Key
                HStack {
                    Text("API Key")
                    Spacer()
                    SecureField("Optional", text: $apiKey)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
            }
            
            // Delete Button (only if editing)
            if configToEdit != nil {
                Section {
                    Button(role: .destructive, action: {
                        showingDeleteAlert = true
                    }) {
                        HStack {
                            Spacer()
                            Text("Delete Server")
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(configToEdit == nil ? "Add Server" : "Edit Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveServer()
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(!isConfigValid)
            }
        }
        .onAppear {
            if let config = configToEdit {
                name = config.name
                serverAddress = config.serverAddress + (config.port != nil ? ":\(config.port!)" : "")
                serverProtocol = config.serverProtocol
                apiKey = config.apiKey ?? ""
            }
        }
        .alert("Delete Server", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this server configuration? This action cannot be undone.")
        }
    }
    
    private func saveServer() {
        let parsed = ServerConfig.parseHostAndPort(serverAddress)
        let newConfig = ServerConfig(
            id: configToEdit?.id ?? UUID(), // Preserve ID if editing, new UUID if adding
            name: name,
            serverAddress: parsed.host,
            port: parsed.port,
            serverProtocol: serverProtocol,
            apiKey: apiKey.isEmpty ? nil : apiKey
        )
        onSave(newConfig)
    }
}

// Subview for Tab Customization (Reordering & Visibility)
struct TabOrderView: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    // Top-level tabs that can be reordered
    private var mainReorderableTabs: [TabConfig] {
        tabManager.tabs
            .filter { $0.id != .settings && $0.id != .studios && $0.id != .tags && $0.id != .scenes && $0.id != .galleries && $0.id != .performers && $0.id != .dashboard }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    
    // Unified list of sub-tabs that the user can reorder within the Catalogs tab
    private var catalogueSubTabs: [TabConfig] {
        tabManager.tabs
            .filter { $0.id == .performers || $0.id == .studios || $0.id == .tags || $0.id == .scenes || $0.id == .galleries }
            .sorted { $0.sortOrder < $1.sortOrder }
    }


    // List of home rows
    private var homeRows: [HomeRowConfig] {
        tabManager.homeRows
    }
    
    @State private var showingAddCustomRow = false
    @State private var newRowTitle = ""
    @State private var selectedFilterId = ""
    @State private var navigateToDashboard = false
    @EnvironmentObject var viewModel: StashDBViewModel
    
    var body: some View {
        List {
            Section("Dashboard") {
                HStack {
                    Label("Configure Dashboard", systemImage: "uiwindow.split.2x1")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    navigateToDashboard = true
                }
            }
            .navigationDestination(isPresented: $navigateToDashboard) {
                DashboardSettingsView()
            }
            
            Section("Optional Tabs") {
                tabToggle(for: .reels)
                tabToggle(for: .downloads)
            }
            
            Section {
                // Fixed Dashboard Row
                HStack {
                    Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.icon)
                    Spacer()
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                        .disabled(true)
                }
                .tint(appearanceManager.tintColor)

                ForEach(catalogueSubTabs) { tab in
                    Toggle(isOn: Binding(
                        get: { tab.isVisible },
                        set: { _ in tabManager.toggle(tab.id) }
                    )) {
                        Label(tab.id.title, systemImage: tab.id.icon)
                    }
                    .tint(appearanceManager.tintColor)
                }
                .onMove { indices, newOffset in
                    tabManager.moveSubTab(from: indices, to: newOffset, within: .catalogue)
                }
            } header: {
                Text("Home Content")
            } footer: {
                Text("The first visible item in this list is the default view. Enabling multiple items shows a switcher.")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Manage Tabs")
    }
    
    @ViewBuilder
    private func tabToggle(for tabId: AppTab) -> some View {
        if let config = tabManager.tabs.first(where: { $0.id == tabId }) {
            Toggle(isOn: Binding(
                get: { config.isVisible },
                set: { _ in tabManager.toggle(tabId) }
            )) {
                Label(tabId.title, systemImage: tabId.icon)
            }
            .tint(appearanceManager.tintColor)
        }
    }
}

// Dedicated View for Dashboard Settings
struct DashboardSettingsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        List {
            Section {
                ForEach(tabManager.homeRows) { row in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { row.isEnabled },
                            set: { _ in tabManager.toggleHomeRow(row.id) }
                        )) {
                            VStack(alignment: .leading) {
                                Text(row.title)
                            }
                        }
                        .tint(appearanceManager.tintColor)
                    }
                }
                .onMove { indices, newOffset in
                    tabManager.moveHomeRow(from: indices, to: newOffset)
                }
            } header: {
                Text("Dashboard Rows")
            } footer: {
                Text("Enable and reorder the rows shown on the Dashboard.")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Dashboard Settings")
    }
}

// Subview for Default Sort Options
struct TabDefaultSortView: View {
    @ObservedObject var tabManager = TabManager.shared
    
    var visibleTabs: [TabConfig] {
        tabManager.tabs
            .filter { $0.id != .settings && $0.id != .catalogue && $0.id != .media && $0.id != .downloads && $0.id != .dashboard && $0.isVisible }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    
    var body: some View {
        List {
            Section(header: Text("Default Sort Order")) {
                ForEach(visibleTabs) { tab in
                    sortPicker(for: tab.id)
                }
            }
            
            Section(header: Text("Detail Views Sort Order")) {
                ForEach(tabManager.detailViews) { config in
                    detailSortPicker(for: config)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Default Sorting")
    }
    
    @ViewBuilder
    private func sortPicker(for tab: AppTab) -> some View {
        HStack {
            Label(tab.title, systemImage: tab.icon)
            Spacer()
            switch tab {
            case .studios:
                Picker("", selection: Binding(
                    get: { StashDBViewModel.StudioSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .sceneCountDesc },
                    set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.StudioSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                
            case .performers:
                Picker("", selection: Binding(
                    get: { StashDBViewModel.PerformerSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .sceneCountDesc },
                    set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.PerformerSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            case .scenes:
                Picker("", selection: Binding(
                    get: { StashDBViewModel.SceneSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .dateDesc },
                    set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            case .galleries:
                Picker("", selection: Binding(
                    get: { StashDBViewModel.GallerySortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .dateDesc },
                    set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.GallerySortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            case .tags:
                Picker("", selection: Binding(
                    get: { StashDBViewModel.TagSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .sceneCountDesc },
                    set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.TagSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                
            case .reels:
                Picker("", selection: Binding(
                    get: { StashDBViewModel.SceneSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .random },
                    set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            case .images:
                Picker("", selection: Binding(
                    get: { StashDBViewModel.ImageSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .dateDesc },
                    set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.ImageSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            default:
                EmptyView()
            }
        }
    }


    @ViewBuilder
    private func detailSortPicker(for config: DetailViewConfig) -> some View {
        HStack {
            Label(config.id.title, systemImage: config.id.icon)
            Spacer()
            if config.id == .gallery {
                Picker("", selection: Binding(
                    get: { StashDBViewModel.ImageSortOption(rawValue: tabManager.getPersistentDetailSortOption(for: config.id.rawValue) ?? "") ?? .dateDesc },
                    set: { tabManager.setPersistentDetailSortOption(for: config.id.rawValue, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.ImageSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            } else {
                Picker("", selection: Binding(
                    get: { StashDBViewModel.SceneSortOption(rawValue: tabManager.getPersistentDetailSortOption(for: config.id.rawValue) ?? "") ?? .dateDesc },
                    set: { tabManager.setPersistentDetailSortOption(for: config.id.rawValue, option: $0.rawValue) }
                )) {
                    ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}

// Subview for Default Filters
struct TabDefaultFilterView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var tabManager = TabManager.shared
    
    var body: some View {
        List {
            Section {
                filterPicker(for: .dashboard, title: "Dashboard", icon: "chart.bar.fill")
                filterPicker(for: .scenes, title: "Scenes", icon: "film")
                filterPicker(for: .galleries, title: "Galleries", icon: "photo.stack")
                filterPicker(for: .performers, title: "Performers", icon: "person.3")
                filterPicker(for: .studios, title: "Studios", icon: "building.2")
                filterPicker(for: .tags, title: "Tags", icon: "tag")
            } header: {
                Text("Default Filters")
            } footer: {
                Text("Pick a saved filter that will be applied automatically when you open the respective tab.")
            }
            
            Section {
                filterPicker(for: .reels, title: "Scenes", icon: "film", modeOverride: .scenes)
                markerFilterPicker(for: .reels, title: "Markers", icon: "mappin.and.ellipse")
            } header: {
                Text("StashTok Default Filters")
            } footer: {
                Text("Set separate default filters for scenes and markers in StashTok.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Default Filters")
        .toolbar {
            if viewModel.isLoadingSavedFilters {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .shimmer()
                }
            }
        }
        .onAppear {
            viewModel.fetchSavedFilters()
        }
    }
    
    @ViewBuilder
    private func filterPicker(for tab: AppTab, title: String, icon: String, modeOverride: StashDBViewModel.FilterMode? = nil) -> some View {
        let mode: StashDBViewModel.FilterMode? = modeOverride ?? {
            switch tab {
            case .scenes, .reels, .dashboard: return .scenes
            case .performers: return .performers
            case .studios: return .studios
            case .galleries: return .galleries
            case .tags: return .tags
            default: return nil
            }
        }()
        
        if let mode = mode {
            let filters = viewModel.savedFilters.values
                .filter { $0.mode == mode }
                .sorted { $0.name < $1.name }
            
            let currentId = tabManager.getDefaultFilterId(for: tab)
            
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                
                if filters.isEmpty && !viewModel.isLoadingSavedFilters {
                    Text("No filters found")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    Picker("", selection: Binding(
                        get: { currentId ?? "" },
                        set: { newId in
                            if newId.isEmpty {
                                tabManager.setDefaultFilter(for: tab, filterId: nil, filterName: nil)
                            } else if let filter = filters.first(where: { $0.id == newId }) {
                                tabManager.setDefaultFilter(for: tab, filterId: filter.id, filterName: filter.name)
                            }
                        }
                    )) {
                        Text("None").tag("")
                        
                        ForEach(filters) { filter in
                            Text(filter.name).tag(filter.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        }
    }
    
    @ViewBuilder
    private func markerFilterPicker(for tab: AppTab, title: String, icon: String) -> some View {
        let mode: StashDBViewModel.FilterMode = .sceneMarkers
        
        let filters = viewModel.savedFilters.values
            .filter { $0.mode == mode }
            .sorted { $0.name < $1.name }
        
        let currentId = tabManager.getDefaultMarkerFilterId(for: tab)
        
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            
            if filters.isEmpty && !viewModel.isLoadingSavedFilters {
                Text("No filters found")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                Picker("", selection: Binding(
                    get: { currentId ?? "" },
                    set: { newId in
                        if newId.isEmpty {
                            tabManager.setDefaultMarkerFilter(for: tab, filterId: nil, filterName: nil)
                        } else if let filter = filters.first(where: { $0.id == newId }) {
                            tabManager.setDefaultMarkerFilter(for: tab, filterId: filter.id, filterName: filter.name)
                        }
                    }
                )) {
                    Text("None").tag("")
                    
                    ForEach(filters) { filter in
                        Text(filter.name).tag(filter.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}


struct ServerStatisticsView: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject private var configManager = ServerConfigManager.shared
    
    var body: some View {
        List {
            if let stats = viewModel.statistics {
                Section("Database Statistics") {
                    HStack {
                        Label("Scenes", systemImage: "film")
                        Spacer()
                        Text("\(stats.sceneCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Performers", systemImage: "person.2")
                        Spacer()
                        Text("\(stats.performerCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Studios", systemImage: "building.2")
                        Spacer()
                        Text("\(stats.studioCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Total Size", systemImage: "internaldrive")
                        Spacer()
                        Text(formatBytes(stats.scenesSize))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Total Duration", systemImage: "clock")
                        Spacer()
                        Text(formatDuration(stats.scenesDuration))
                            .foregroundColor(.secondary)
                    }
                }
            } else if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 40, height: 40)
                                .skeleton()
                            Text("Loading statistics...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .shimmer()
                        }
                        Spacer()
                    }
                }
            } else {
                 Section {
                     Text("Unable to load statistics. Check server connection.")
                 }
            }
        }
        .navigationTitle("Statistics")
        .onAppear {
             viewModel.fetchStatistics()
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDuration(_ seconds: Float) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

#Preview {
    ServerConfigView()
}

// MARK: - Server Detail View
struct ServerDetailView: View {
    let server: ServerConfig
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    
    @State private var showingEditSheet = false
    @State private var isScanning = false
    @State private var showScanAlert = false
    @State private var scanAlertMessage = ""
    @Environment(\.presentationMode) var presentationMode
    
    var isActive: Bool {
        configManager.activeConfig?.id == server.id
    }
    
    var body: some View {
        Form {
            Section("Server Information") {
                LabeledContent("Name", value: server.name)
                LabeledContent("URL", value: server.baseURL)
                
                LabeledContent("Protocol", value: server.serverProtocol.displayName)
                
                if isActive {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(viewModel.serverStatus)
                            .foregroundColor(viewModel.isServerConnected ? .green : .red)
                    }
                }
            }
            
            Section("Actions") {
                if !isActive {
                    Button(action: connectServer) {
                        Label("Connect to Server", systemImage: "power")
                            .foregroundColor(.primary)
                    }
                }
                
                Button(action: {
                     if !isActive {
                         connectServer()
                     }
                     // Give it a moment to connect or just trigger scan (viewModel will handle connection check usually)
                     isScanning = true
                     DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                         viewModel.triggerLibraryScan { success, message in
                             DispatchQueue.main.async {
                                 isScanning = false
                                 scanAlertMessage = message
                                 showScanAlert = true
                             }
                         }
                     }
                }) {
                    HStack {
                        Label("Scan Library", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundColor(.primary)
                        Spacer()
                        if isScanning {
                            ProgressView()
                        }
                    }
                }
                .disabled(isScanning)
                
                Button(action: { showingEditSheet = true }) {
                    Label("Edit Configuration", systemImage: "pencil")
                        .foregroundColor(.primary)
                }
            }
            // Removed sheet modifier
            
            Section {
                Button(role: .destructive, action: {
                    configManager.deleteServer(id: server.id)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Label("Delete Server", systemImage: "trash")
                        .foregroundColor(appearanceManager.tintColor)
                }
            }
        }
        .navigationTitle(server.name)
        .alert("Library Scan", isPresented: $showScanAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(scanAlertMessage)
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationView {
                ServerFormViewNew(configToEdit: server) { updatedConfig in
                    configManager.addOrUpdateServer(updatedConfig)
                    if configManager.activeConfig?.id == updatedConfig.id {
                        configManager.saveConfig(updatedConfig)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .toolbar {
            if isActive && viewModel.isServerConnected {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
    }
    
    private func connectServer() {
        configManager.saveConfig(server)
        viewModel.resetData()
        viewModel.testConnection()
        viewModel.fetchStatistics()
        coordinator.resetAllStacks()
    }

}
