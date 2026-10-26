//
//  SettingsTransfer.swift
//  stashy
//
//  Export / import of servers and app settings as one JSON file, shared with Android
//  (format: docs/settings-transfer-format.md).
//

#if !os(tvOS)
import SwiftUI
import UniformTypeIdentifiers

/// A JSON value of any shape, for the free-form parts of the file.
enum SettingsJSONValue: Codable, Equatable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SettingsJSONValue])
    case object([String: SettingsJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([SettingsJSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: SettingsJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }

    /// From a Foundation object (plist / JSONSerialization output).
    init?(foundation value: Any) {
        switch value {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.compactMap(SettingsJSONValue.init(foundation:)))
        case let d as [String: Any]: self = .object(d.compactMapValues(SettingsJSONValue.init(foundation:)))
        case is NSNull: self = .null
        default: return nil
        }
    }

    /// To a Foundation object for `UserDefaults` / `JSONSerialization`.
    var foundation: Any {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? Int(n) as Any : n
        case .string(let s): return s
        case .array(let a): return a.map(\.foundation)
        case .object(let o): return o.mapValues(\.foundation)
        case .null: return NSNull()
        }
    }
}

struct SettingsTransferFile: Codable {
    struct AppInfo: Codable {
        var platform: String
        var version: String?
        var build: String?
    }

    struct Server: Codable {
        var id: String
        var name: String
        var serverAddress: String
        var port: String?
        var serverProtocol: String
        var subpath: String?
        var apiKey: String?
        var customHeaders: [Header]?
    }

    struct Header: Codable {
        var id: String?
        var name: String
        var value: String
    }

    struct Setting: Codable {
        var key: String
        var type: String
        var value: SettingsJSONValue
    }

    var format: String = "stashy-settings"
    var version: Int = 1
    var exportedAt: String
    var app: AppInfo
    var includesSecrets: Bool
    var activeServerId: String?
    var servers: [Server]
    var settings: [Setting]
}

enum SettingsTransferError: LocalizedError {
    case notASettingsFile
    case newerVersion(Int)

    var errorDescription: String? {
        switch self {
        case .notASettingsFile: return "This is not a stashy settings file."
        case .newerVersion(let v): return "This file was made by a newer stashy (format \(v)). Update the app first."
        }
    }
}

enum SettingsTransfer {
    static let formatName = "stashy-settings"
    static let formatVersion = 1

    struct ImportSummary {
        var servers = 0
        var settings = 0
        var skipped = 0
    }

    // MARK: Which keys travel

    private static let excludedKeys: Set<String> = [
        "stashy_server_config", "stashy_saved_servers", "stashy_saved_servers_backup",
        "totalTipsCount", "kBiometricsEnabled", "kAutoLockOnBackground",
    ]
    private static let excludedPrefixes = [
        "stashy_plus_", "mini_player_last_", "cached", "SK", "revenuecat", "license",
        "passcode", "kPasscode", "NS", "Apple", "com.apple", "WebKit", "AK", "PK", "MSV",
    ]

    static func isTransferable(_ key: String) -> Bool {
        if excludedKeys.contains(key) { return false }
        let lower = key.lowercased()
        if lower.contains("license") || lower.contains("passcode") { return false }
        return !excludedPrefixes.contains { key.hasPrefix($0) }
    }

    // MARK: Export

    static func export(includeSecrets: Bool) throws -> Data {
        let manager = ServerConfigManager.shared
        let servers = manager.getSavedServers().map { config -> SettingsTransferFile.Server in
            var server = SettingsTransferFile.Server(
                id: config.id.uuidString,
                name: config.name,
                serverAddress: config.serverAddress,
                port: config.port,
                serverProtocol: config.serverProtocol.rawValue,
                subpath: config.subpath
            )
            if includeSecrets {
                server.apiKey = config.secureApiKey
                let headers = config.secureCustomHeaders
                server.customHeaders = headers.isEmpty ? nil : headers.map {
                    .init(id: $0.id.uuidString, name: $0.name, value: $0.value)
                }
            }
            return server
        }

        let bundleId = Bundle.main.bundleIdentifier ?? "de.letzgo.stashy"
        let domain = UserDefaults.standard.persistentDomain(forName: bundleId) ?? [:]
        var settings: [SettingsTransferFile.Setting] = []
        for key in domain.keys.sorted() where isTransferable(key) {
            guard let entry = entry(for: key, value: domain[key]!) else { continue }
            settings.append(entry)
        }

        let info = Bundle.main.infoDictionary
        #if os(macOS)
        let platform = "macos"
        #else
        let platform = "ios"
        #endif
        let file = SettingsTransferFile(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            app: .init(
                platform: platform,
                version: info?["CFBundleShortVersionString"] as? String,
                build: info?["CFBundleVersion"] as? String
            ),
            includesSecrets: includeSecrets,
            activeServerId: manager.activeConfig?.id.uuidString,
            servers: servers,
            settings: settings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    private static func entry(for key: String, value: Any) -> SettingsTransferFile.Setting? {
        switch value {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .init(key: key, type: "bool", value: .bool(n.boolValue))
            }
            let isInteger = CFNumberIsFloatType(n) == false
            return .init(key: key, type: isInteger ? "int" : "double", value: .number(n.doubleValue))
        case let s as String:
            return .init(key: key, type: "string", value: .string(s))
        case let d as Data:
            // Codable blobs: JSON inside Data travels as "json"; anything else stays here.
            guard let object = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]),
                  let json = SettingsJSONValue(foundation: object) else { return nil }
            return .init(key: key, type: "json", value: json)
        case let a as [Any]:
            guard let json = SettingsJSONValue(foundation: a) else { return nil }
            return .init(key: key, type: "array", value: json)
        case let o as [String: Any]:
            guard let json = SettingsJSONValue(foundation: o) else { return nil }
            return .init(key: key, type: "dictionary", value: json)
        default:
            return nil   // Dates and other plist types have no portable form.
        }
    }

    // MARK: Import

    static func importFile(_ data: Data) throws -> ImportSummary {
        let file = try JSONDecoder().decode(SettingsTransferFile.self, from: data)
        guard file.format == formatName else { throw SettingsTransferError.notASettingsFile }
        guard file.version <= formatVersion else { throw SettingsTransferError.newerVersion(file.version) }

        var summary = ImportSummary()
        let defaults = UserDefaults.standard

        for entry in file.settings where isTransferable(entry.key) {
            if apply(entry, to: defaults) { summary.settings += 1 } else { summary.skipped += 1 }
        }

        let manager = ServerConfigManager.shared
        var imported: [ServerConfig] = []
        for server in file.servers {
            guard let id = UUID(uuidString: server.id),
                  let proto = ServerProtocol(rawValue: server.serverProtocol.uppercased()) else {
                summary.skipped += 1
                continue
            }
            var config = ServerConfig(
                serverAddress: server.serverAddress,
                port: server.port,
                serverProtocol: proto
            )
            config.id = id
            config.name = server.name
            config.subpath = server.subpath
            if let key = server.apiKey, !key.isEmpty {
                _ = KeychainManager.shared.saveAPIKey(key, forServerID: id)
            }
            if let headers = server.customHeaders {
                let parsed = headers.map {
                    ServerHTTPHeader(id: $0.id.flatMap(UUID.init(uuidString:)) ?? UUID(), name: $0.name, value: $0.value)
                }
                _ = KeychainManager.shared.saveCustomHeaders(parsed, forServerID: id)
            }
            manager.addOrUpdateServer(config)
            imported.append(config)
            summary.servers += 1
        }

        let active = file.activeServerId.flatMap { id in imported.first { $0.id.uuidString == id } }
            ?? (manager.activeConfig == nil ? imported.first : nil)
        if let active {
            manager.saveConfig(active)
        }
        reloadAfterImport()
        return summary
    }

    /// Stores one entry the way this platform keeps that key; an existing key keeps its type.
    private static func apply(_ entry: SettingsTransferFile.Setting, to defaults: UserDefaults) -> Bool {
        let existing = defaults.object(forKey: entry.key)
        switch entry.type {
        case "bool":
            guard case .bool(let b) = entry.value else { return false }
            defaults.set(b, forKey: entry.key)
        case "int", "double":
            guard case .number(let n) = entry.value else { return false }
            if entry.type == "int", !(existing is NSNumber && CFNumberIsFloatType(existing as! NSNumber)) {
                defaults.set(Int(n), forKey: entry.key)
            } else {
                defaults.set(n, forKey: entry.key)
            }
        case "string":
            guard case .string(let s) = entry.value else { return false }
            // Android keeps some collections as JSON strings that iOS keeps as Data.
            if existing is Data, let data = s.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
                defaults.set(data, forKey: entry.key)
            } else {
                defaults.set(s, forKey: entry.key)
            }
        case "json":
            let object = entry.value.foundation
            if existing is [Any] || existing is [String: Any] {
                defaults.set(object, forKey: entry.key)
            } else if existing is String {
                guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]),
                      let s = String(data: data, encoding: .utf8) else { return false }
                defaults.set(s, forKey: entry.key)
            } else {
                guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]) else { return false }
                defaults.set(data, forKey: entry.key)
            }
        case "array", "dictionary":
            if existing is Data,
               let data = try? JSONSerialization.data(withJSONObject: entry.value.foundation, options: [.fragmentsAllowed]) {
                defaults.set(data, forKey: entry.key)
            } else {
                defaults.set(entry.value.foundation, forKey: entry.key)
            }
        default:
            return false
        }
        return true
    }

    /// Lets the singletons that cache settings pick up the new values.
    private static func reloadAfterImport() {
        ServerConfigManager.shared.savedServers = ServerConfigManager.shared.getSavedServers()
        NotificationCenter.default.post(name: NSNotification.Name("ServerConfigChanged"), object: nil)
        NotificationCenter.default.post(name: .stashySettingsImported, object: nil)
    }
}

extension Notification.Name {
    /// Posted after a settings file was imported.
    static let stashySettingsImported = Notification.Name("stashySettingsImported")
}

/// The exported file for `fileExporter` / sharing.
struct SettingsTransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static var defaultFilename: String {
        let date = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        return "stashy-settings-\(date).json"
    }
}

private struct TransferRowStyle: ViewModifier {
    var grouped: Bool
    var index: Int
    var count: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        if grouped {
            content.stashyGroupedBlockRow(index: index, count: count)
        } else {
            content
        }
    }
}

/// Export / import controls, shared by Settings and the setup wizard.
struct SettingsTransferControls: View {
    /// Setup shows only the import button.
    var importOnly = false
    /// Settings list: the rows take the grouped block style of the other sections.
    var groupedRows = false
    var onImported: (() -> Void)? = nil

    @ObservedObject private var appearance = AppearanceManager.shared
    @State private var includeSecrets = false
    @State private var showsSecretsChoice = false
    @State private var exportDocument: SettingsTransferDocument?
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var resultMessage: String?
    @State private var showsResult = false

    // Each button carries its own presentations: modifiers on a `Group` are copied onto every
    // child, and two file exporters on one screen cancel each other out.
    var body: some View {
        if !importOnly {
            exportButton
        }
        importButton
    }

    private var exportButton: some View {
        Button {
            showsSecretsChoice = true
        } label: {
            Label("Export Settings", systemImage: "square.and.arrow.up")
        }
        .modifier(TransferRowStyle(grouped: groupedRows, index: 0, count: 2))
        .alert("Include API keys?", isPresented: $showsSecretsChoice) {
            Button("Without API keys") { startExport(includeSecrets: false) }
            Button("With API keys and headers", role: .destructive) { startExport(includeSecrets: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("With API keys the file gives full access to your servers. Keep it private.")
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: SettingsTransferDocument.defaultFilename
        ) { result in
            if case .failure(let error) = result {
                resultMessage = error.localizedDescription
                showsResult = true
            }
        }
    }

    private var importButton: some View {
        Button {
            showsImporter = true
        } label: {
            Label("Import Settings", systemImage: "square.and.arrow.down")
        }
        .modifier(TransferRowStyle(grouped: groupedRows, index: importOnly ? 0 : 1, count: importOnly ? 1 : 2))
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json, .data]) { result in
            handleImport(result)
        }
        .alert("Settings", isPresented: $showsResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func startExport(includeSecrets: Bool) {
        do {
            exportDocument = SettingsTransferDocument(data: try SettingsTransfer.export(includeSecrets: includeSecrets))
            showsExporter = true
        } catch {
            resultMessage = error.localizedDescription
            showsResult = true
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            resultMessage = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let summary = try SettingsTransfer.importFile(try Data(contentsOf: url))
                // The import resets the navigation (ServerConfigChanged), which would tear an
                // alert down with this view — the toast outlives it.
                ToastManager.shared.show(
                    "Imported \(summary.servers) server(s) and \(summary.settings) setting(s). Restart stashy to apply every setting.",
                    icon: "square.and.arrow.down.fill",
                    duration: 4
                )
                onImported?()
                return
            } catch {
                resultMessage = error.localizedDescription
            }
        }
        showsResult = true
    }
}
#endif
