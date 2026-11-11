//
//  ServerConfig.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

import Foundation
import SwiftUI
import Combine
import Network

extension Notification.Name {
    /// Nach Abschluss von `StashDBViewModel.initializeServerConnection()` (Filter + Statistik). z.B. tvOS-Dashboard nach Serverwechsel neu laden; vermeidet Race mit `GraphQLClient.cancelAllRequests()`.
    static let stashServerInitializationFinished = Notification.Name("stashServerInitializationFinished")
}

enum ServerProtocol: String, Codable, CaseIterable {
    case http = "HTTP"
    case https = "HTTPS"
    
    var displayName: String {
        rawValue
    }
    
    var defaultPort: String {
        switch self {
        case .http: return "80"
        case .https: return "443"
        }
    }
}

enum AuthMethod: String, Codable, CaseIterable {
    case none = "None"
    case login = "Login"
    case apiKey = "API Key"

    /// Shown in the pickers; the raw value is stored in `ServerConfig` and must not change.
    var displayName: String {
        switch self {
        case .none: return tr("none")
        case .login: return "Login"
        case .apiKey: return tr("api_key")
        }
    }
}

// Legacy enum for backward compatibility
enum ConnectionType: String, Codable, CaseIterable {
    case ipAddress = "IP Address"
    case domain = "Domain"

    var displayName: String {
        rawValue
    }
}

/// A user-defined HTTP header sent with every request to the Stash server — for setups behind
/// SSO or a reverse proxy that expects its own token (e.g. `X-Auth-Token`, `CF-Access-Client-Id`).
nonisolated struct ServerHTTPHeader: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var value: String

    init(id: UUID = UUID(), name: String, value: String) {
        self.id = id
        self.name = name
        self.value = value
    }

    /// Headers URLSession / the player manage themselves; setting them breaks requests.
    nonisolated static let reservedNames: Set<String> = [
        "host", "content-length", "content-type", "connection", "transfer-encoding",
        "upgrade", "range", "accept-encoding", "te", "trailer", "keep-alive", "proxy-connection"
    ]

    nonisolated var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    nonisolated var trimmedValue: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// RFC 7230 token characters only, not reserved, value present.
    nonisolated var isUsable: Bool {
        let n = trimmedName
        guard !n.isEmpty, !trimmedValue.isEmpty else { return false }
        guard !Self.reservedNames.contains(n.lowercased()) else { return false }
        let token = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return n.unicodeScalars.allSatisfy { token.contains($0) }
            && !trimmedValue.contains("\n") && !trimmedValue.contains("\r")
    }

    /// Empty rows are dropped silently; invalid names are reported by the form.
    nonisolated static func sanitized(_ headers: [ServerHTTPHeader]) -> [ServerHTTPHeader] {
        headers
            .filter { $0.isUsable }
            .map { ServerHTTPHeader(id: $0.id, name: $0.trimmedName, value: $0.trimmedValue) }
    }
}

/// Decides whether a connection test actually reached Stash. A host that merely answers — an
/// SSO login page, a reverse proxy's error page, some other service on that port — is a
/// failure, not "Connected". Only a GraphQL response carrying Stash's version counts.
enum StashConnectionProbe {
    /// The query every test sends; `evaluate` looks for its answer.
    nonisolated static let versionQueryBody = #"{"query":"{ version { version } }"}"#

    enum Outcome: Equatable {
        case stash(version: String)
        case failure(String)
    }

    nonisolated static func evaluate(data: Data?, response: URLResponse?, error: Error?) -> Outcome {
        if let error {
            let code = (error as NSError).code
            switch code {
            case NSURLErrorCannotConnectToHost: return .failure(tr("error_connect_check_address_and_port"))
            case NSURLErrorTimedOut: return .failure(tr("connection_timed_out"))
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return .failure(tr("host_not_found"))
            case NSURLErrorServerCertificateUntrusted, NSURLErrorSecureConnectionFailed:
                return .failure(tr("hint_secure_connection_failed_check_http"))
            default: return .failure(error.localizedDescription)
            }
        }
        guard let http = response as? HTTPURLResponse else {
            return .failure(tr("empty_response_from_server"))
        }
        // Stash 0.32+ refuses these before authentication, so "check the API key" would mislead.
        let body = data.flatMap { String(data: $0, encoding: .utf8) }?.lowercased() ?? ""
        if http.statusCode == 403, body.contains("public ip") {
            return .failure(tr("hint_stash_refuses_public_ips_while"))
        }
        if http.statusCode == 400, body.contains("invalid ip") {
            return .failure(tr("hint_stash_rejected_reverse_proxy_in"))
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            return .failure(tr("hint_authentication_failed_check_api_key"))
        }

        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if let version = ((json?["data"] as? [String: Any])?["version"] as? [String: Any])?["version"] as? String,
           !version.isEmpty {
            return .stash(version: version)
        }
        // Stash answered, but refused (e.g. "not authorized" as a GraphQL error).
        if let errors = json?["errors"] as? [[String: Any]],
           let message = errors.first?["message"] as? String, !message.isEmpty {
            return .failure(tr("stash_rejected_request_arg", message))
        }
        guard (200...299).contains(http.statusCode) else {
            return .failure(tr("server_error_http_arg", http.statusCode))
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if contentType.contains("html") {
            return .failure(tr("hint_host_answered_with_web_page"))
        }
        return .failure(tr("hint_host_answered_but_not_as"))
    }
}

/// Thrown by the view model's test so its message reaches `errorMessage` unchanged.
struct StashConnectionProbeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ServerConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "My Stash"
    var serverAddress: String  // Unified field for IP or domain
    var port: String?          // Optional port
    var serverProtocol: ServerProtocol
    var apiKey: String?        // Optional API Key for authentication
    var subpath: String?       // Optional subpath (e.g. "/stash")
    /// Custom headers. iOS keeps them in the Keychain (`secureCustomHeaders`) and leaves this
    /// nil; tvOS has no Keychain here and stores them in the config like the API key.
    var customHeaders: [ServerHTTPHeader]?
    /// Optional second address of the same server, as a full base URL (`http://192.168.1.10:9999`,
    /// no trailing slash). While it answers as Stash the app uses it instead of the address
    /// above (`ServerEndpointSelector`); id, API key and headers stay the same.
    var localURL: String?

    /// The address in use right now: the local one while it is reachable, else the regular one.
    var baseURL: String {
        if let local = localBaseURL, ServerEndpointSelector.shared.usesLocal(id) {
            return local
        }
        return externalBaseURL
    }

    /// The regular (external) address, whatever is in use.
    nonisolated var externalBaseURL: String {
        let effectivePort = port ?? serverProtocol.defaultPort
        let scheme = serverProtocol == .https ? "https" : "http"

        // Only append port if it's not the default for the protocol
        let needsPort = (serverProtocol == .https && effectivePort != "443") ||
                       (serverProtocol == .http && effectivePort != "80")

        var url = needsPort ? "\(scheme)://\(serverAddress):\(effectivePort)" : "\(scheme)://\(serverAddress)"
        if let sub = subpath, !sub.isEmpty {
            url += sub.hasPrefix("/") ? sub : "/\(sub)"
        }
        return url
    }

    nonisolated var localBaseURL: String? {
        guard let local = localURL?.trimmingCharacters(in: .whitespacesAndNewlines), !local.isEmpty else { return nil }
        return local
    }

    /// "192.168.1.10:9999/stash" → "http://192.168.1.10:9999/stash"; nil when empty or unusable.
    /// A local address defaults to HTTP when no scheme is typed.
    nonisolated static func normalizedLocalURL(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "http://" + text
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard let comps = URLComponents(string: text), let host = comps.host, !host.isEmpty else { return nil }
        return text
    }

    /// Stash answers with absolute URLs for the host a request came through, so a URL kept in a
    /// list or a cache can name the address that is not in use. Moves such a URL to the other
    /// address of this server; anything else comes back unchanged.
    nonisolated func addressed(_ url: URL, toLocal: Bool) -> URL {
        guard let local = localBaseURL, !url.isFileURL else { return url }
        return toLocal
            ? Self.swappingBase(of: url, from: externalBaseURL, to: local)
            : Self.swappingBase(of: url, from: local, to: externalBaseURL)
    }

    /// `url` on the address in use right now.
    nonisolated func activeAddressed(_ url: URL) -> URL {
        addressed(url, toLocal: ServerEndpointSelector.shared.usesLocal(id))
    }

    nonisolated static func swappingBase(of url: URL, from: String, to: String) -> URL {
        guard let source = URLComponents(string: from), let target = URLComponents(string: to),
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host?.lowercased(), host == source.host?.lowercased() else { return url }
        func effectivePort(_ c: URLComponents) -> Int {
            c.port ?? (c.scheme?.lowercased() == "https" ? 443 : 80)
        }
        // A proxy that ends TLS can make Stash answer with the other scheme: without an
        // explicit port on either side the host alone decides.
        guard effectivePort(comps) == effectivePort(source) || (comps.port == nil && source.port == nil) else { return url }

        var path = comps.percentEncodedPath
        let sourceSub = source.percentEncodedPath
        if !sourceSub.isEmpty, path == sourceSub || path.hasPrefix(sourceSub + "/") {
            path.removeFirst(sourceSub.count)
        }
        comps.scheme = target.scheme
        comps.host = target.host
        comps.port = target.port
        comps.percentEncodedPath = target.percentEncodedPath + path
        return comps.url ?? url
    }

    var hasValidConfig: Bool {
        return !serverAddress.isEmpty
    }
    
    /// API key from Keychain (preferred) or stored value (migration fallback)
    nonisolated var secureApiKey: String? {
        #if !os(tvOS)
        // First try Keychain
        if let keychainKey = KeychainManager.shared.loadAPIKey(forServerID: id) {
            let trimmed = keychainKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        #endif
        // Fallback to stored value (for migration)
        return apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Custom headers from the Keychain (iOS) or the stored config (tvOS / not yet migrated).
    nonisolated var secureCustomHeaders: [ServerHTTPHeader] {
        #if !os(tvOS)
        let stored = KeychainManager.shared.loadCustomHeaders(forServerID: id)
        if !stored.isEmpty { return stored }
        #endif
        return ServerHTTPHeader.sanitized(customHeaders ?? [])
    }

    /// Everything a request to `url` needs to authenticate: the Stash `ApiKey` plus the custom
    /// headers. Custom headers only go to this server's host, never to a third party (stash-box
    /// artwork, funscript hosts); `nil` means "a request to the server itself".
    nonisolated func requestHeaders(for url: URL? = nil) -> [String: String] {
        if let url, url.isFileURL { return [:] }
        var headers: [String: String] = [:]
        if let key = secureApiKey, !key.isEmpty {
            headers["ApiKey"] = key
        }
        let host = url?.host?.lowercased()
        let localHost = localBaseURL.flatMap { URLComponents(string: $0)?.host?.lowercased() }
        if host == nil || host == serverAddress.lowercased() || host == localHost {
            for header in secureCustomHeaders {
                headers[header.name] = header.value
            }
        }
        return headers
    }

    // Modern initializer
    init(
        id: UUID = UUID(),
        name: String = "My Stash",
        serverAddress: String,
        port: String? = nil,
        serverProtocol: ServerProtocol = .https,
        apiKey: String? = nil,
        subpath: String? = nil,
        customHeaders: [ServerHTTPHeader]? = nil,
        localURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.serverAddress = serverAddress
        self.port = port
        self.serverProtocol = serverProtocol
        self.apiKey = apiKey
        self.subpath = subpath
        self.customHeaders = customHeaders
        self.localURL = localURL
    }
    
    // Backward compatibility decoder
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "My Stash"
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        customHeaders = try container.decodeIfPresent([ServerHTTPHeader].self, forKey: .customHeaders)
        localURL = try container.decodeIfPresent(String.self, forKey: .localURL)
        
        // Try to decode new format first
        if let serverAddress = try? container.decode(String.self, forKey: .serverAddress),
           let protocolValue = try? container.decode(ServerProtocol.self, forKey: .serverProtocol) {
            // New format
            self.serverAddress = serverAddress
            self.port = try container.decodeIfPresent(String.self, forKey: .port)
            self.serverProtocol = protocolValue
            self.subpath = try container.decodeIfPresent(String.self, forKey: .subpath)
        } else {
            // Legacy format - migrate
            let connectionType = try container.decode(ConnectionType.self, forKey: .connectionType)
            let useHTTPS = try container.decodeIfPresent(Bool.self, forKey: .useHTTPS) ?? true
            
            switch connectionType {
            case .ipAddress:
                self.serverAddress = try container.decode(String.self, forKey: .ipAddress)
                self.port = try container.decode(String.self, forKey: .port)
                self.serverProtocol = .http  // IP addresses were always HTTP in old format
            case .domain:
                self.serverAddress = try container.decode(String.self, forKey: .domain)
                self.port = nil  // Domains didn't have explicit port in old format
                self.serverProtocol = useHTTPS ? .https : .http
            }
            
            AppLog.debug("📦 Migrated legacy server config: \(name)")
        }
    }
    
    // Custom encoder to match the coding keys
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(serverAddress, forKey: .serverAddress)
        try container.encodeIfPresent(port, forKey: .port)
        try container.encode(serverProtocol, forKey: .serverProtocol)
        try container.encodeIfPresent(apiKey, forKey: .apiKey)
        try container.encodeIfPresent(subpath, forKey: .subpath)
        try container.encodeIfPresent(customHeaders, forKey: .customHeaders)
        try container.encodeIfPresent(localBaseURL, forKey: .localURL)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, apiKey, subpath, customHeaders, localURL
        // New format keys
        case serverAddress, port, serverProtocol
        // Legacy format keys (for backward compatibility)
        case connectionType, ipAddress, domain, useHTTPS
    }
    
    static func == (lhs: ServerConfig, rhs: ServerConfig) -> Bool {
        return lhs.id == rhs.id
    }
    
    /// Detects protocol from input string and returns it along with the cleaned address
    static func detectProtocol(from input: String) -> (protocol: ServerProtocol?, address: String) {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = cleaned.lowercased()
        
        if lowercased.hasPrefix("https://") {
            return (.https, String(cleaned.dropFirst(8)))
        } else if lowercased.hasPrefix("http://") {
            return (.http, String(cleaned.dropFirst(7)))
        }
        
        return (nil, cleaned)
    }

    /// Parses an input string (e.g. "1.2.3.4:9999/stash" or "example.com/api") into components
    static func parseAddress(_ input: String) -> (host: String, port: String?, subpath: String?) {
        // First, strip protocol if present
        let detection = detectProtocol(from: input)
        var safeInput = detection.address
        
        // Ensure we have a valid structure for URL components
        if !safeInput.contains("://") {
            safeInput = "http://\(safeInput)"
        }
        
        guard let url = URL(string: safeInput) else {
            return (detection.address, nil, nil)
        }
        
        let host = url.host ?? detection.address
        let port = url.port.map { String($0) }
        
        // Extract subpath (excluding any trailing slash)
        var path = url.path
        if path == "/" {
            path = ""
        } else if path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        
        return (host, port, path.isEmpty ? nil : path)
    }

    /// Backwards compatibility wrapper
    static func parseHostAndPort(_ input: String) -> (host: String, port: String?) {
        let result = parseAddress(input)
        return (result.host, result.port)
    }
}

class ServerConfigManager: ObservableObject {
    static let shared = ServerConfigManager()
    private let activeConfigKey = "stashy_server_config"
    private let savedServersKey = "stashy_saved_servers"

    // Publish saved servers list updates
    @Published var activeConfig: ServerConfig?
    @Published var savedServers: [ServerConfig] = []
    /// The active server is reached through its local address right now (`ServerEndpointSelector`).
    @Published var usesLocalAddress = false
    
    private init() {
        self.activeConfig = loadConfig()
        self.savedServers = getSavedServers() // Load initial list
        ServerEndpointSelector.shared.start()
    }

    // MARK: - Active Server Management
    func saveConfig(_ config: ServerConfig) {
        let oldConfig = self.activeConfig
        let encoder = JSONEncoder()
        
        if let encoded = try? encoder.encode(config) {
            UserDefaults.standard.set(encoded, forKey: activeConfigKey)
            self.activeConfig = config
            AppLog.debug("✅ Active server updated: \(config.name)")
            
            // Decide between the two addresses before anything refetches: requests wait for it.
            if oldConfig?.id != config.id || oldConfig?.localBaseURL != config.localBaseURL {
                ServerEndpointSelector.shared.refresh(blocking: true)
            }

            let coreSettingsChanged = oldConfig == nil ||
                oldConfig?.externalBaseURL != config.externalBaseURL ||
                oldConfig?.secureApiKey != config.secureApiKey ||
                oldConfig?.secureCustomHeaders != config.secureCustomHeaders ||
                oldConfig?.id != config.id

            if coreSettingsChanged {
                // Clear system URL cache to avoid using stale data/auth for the new server
                URLCache.shared.removeAllCachedResponses()
                
                // Notify all ViewModels to reset their data
                NotificationCenter.default.post(name: NSNotification.Name("ServerConfigChanged"), object: nil)
            } else {
                // Only secondary settings changed. Emit a minor notification if needed,
                // but do not nuke the URLSession.
                NotificationCenter.default.post(name: NSNotification.Name("ServerConfigPropertiesChanged"), object: nil)
            }
        }
    }

    func loadConfig() -> ServerConfig? {
        if let data = UserDefaults.standard.data(forKey: activeConfigKey) {
            let decoder = JSONDecoder()
            if let config = try? decoder.decode(ServerConfig.self, from: data) {
                #if !os(tvOS)
                // Auto-migrate API key to Keychain if needed
                KeychainManager.shared.migrateAPIKeyIfNeeded(from: config)
                #endif
                return config
            }
        }
        return nil
    }

    /// Move any leftover plaintext `apiKey` fields into Keychain and re-persist configs without secrets.
    func scrubPlaintextAPIKeysFromDisk() {
        #if !os(tvOS)
        var changed = false

        if var active = loadConfig(), let key = active.apiKey, !key.isEmpty {
            KeychainManager.shared.migrateAPIKeyIfNeeded(from: active)
            active.apiKey = nil
            if let encoded = try? JSONEncoder().encode(active) {
                UserDefaults.standard.set(encoded, forKey: activeConfigKey)
                self.activeConfig = active
                changed = true
            }
        }

        var servers = getSavedServers()
        for i in servers.indices {
            if let key = servers[i].apiKey, !key.isEmpty {
                KeychainManager.shared.migrateAPIKeyIfNeeded(from: servers[i])
                servers[i].apiKey = nil
                changed = true
            }
        }
        if changed {
            saveServersList(servers)
            AppLog.debug("🧹 Scrubbed plaintext API keys from UserDefaults")
        }
        #endif
    }
    
    // MARK: - Saved Servers Management
    // Helper to load from UserDefaults
    func getSavedServers() -> [ServerConfig] {
        if let data = UserDefaults.standard.data(forKey: savedServersKey) {
            let decoder = JSONDecoder()
            if let servers = try? decoder.decode([ServerConfig].self, from: data) {
                return servers
            }
        }
        
        // Migration: If we have an active config but no saved servers list, add the active one to the list
        if let current = loadConfig() {
            let initialList = [current]
            saveServersList(initialList) // This will update UserDefaults
            return initialList
        }
        
        return []
    }
    
    // Helper to save to UserDefaults and update published property
    func saveServersList(_ servers: [ServerConfig]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(servers) {
            UserDefaults.standard.set(encoded, forKey: savedServersKey)
            self.savedServers = servers // Update published property to trigger UI refresh
        }
    }
    
    func addOrUpdateServer(_ config: ServerConfig) {
        var servers = getSavedServers()
        
        if let index = servers.firstIndex(where: { $0.id == config.id }) {
            servers[index] = config
        } else {
            servers.append(config)
        }
        
        saveServersList(servers)
    }
    
    func deleteServer(at indexSet: IndexSet) {
        var servers = getSavedServers()
        
        // Check if active server is being deleted
        if let active = activeConfig {
            for index in indexSet {
                if index < servers.count && servers[index].id == active.id {
                    clearActiveConfig()
                }
            }
        }

        for index in indexSet where index < servers.count {
            let id = servers[index].id
            #if !os(tvOS)
            _ = KeychainManager.shared.deleteAPIKey(forServerID: id)
            KeychainManager.shared.deleteCustomHeaders(forServerID: id)
            #endif
            ImageCache.shared.clearCache(forServerID: id)
        }
        
        servers.remove(atOffsets: indexSet)
        saveServersList(servers)
    }
    
    func deleteServer(id: UUID) {
        // Check if active server is being deleted
        if let active = activeConfig, active.id == id {
            clearActiveConfig()
        }
        
        #if !os(tvOS)
        _ = KeychainManager.shared.deleteAPIKey(forServerID: id)
        KeychainManager.shared.deleteCustomHeaders(forServerID: id)
        #endif
        ImageCache.shared.clearCache(forServerID: id)
        
        var servers = getSavedServers()
        servers.removeAll { $0.id == id }
        saveServersList(servers)
    }
    
    private func clearActiveConfig() {
        UserDefaults.standard.removeObject(forKey: activeConfigKey)
        self.activeConfig = nil
        AppLog.error("⚠️ Active server deleted, config cleared.")
        
        // Notify app to reset UI state
        NotificationCenter.default.post(name: NSNotification.Name("ServerConfigChanged"), object: nil)
    }
}
// MARK: - Local / external address

/// Picks between a server's regular address and its optional local one (`ServerConfig.localURL`)
/// by asking the local one whether it is Stash: no Wi-Fi name, so no location permission, and
/// it works the same on iOS, macOS and tvOS. Probes on app start, a server change and a network
/// change (requests wait for those, `settle`), and quietly on becoming active and after a
/// connection error. A change of address is not a server change: nothing is reset, URLs that
/// name the other address are moved over where they are requested (`activeAddressed`).
nonisolated final class ServerEndpointSelector: @unchecked Sendable {
    static let shared = ServerEndpointSelector()

    private let lock = NSLock()
    private var localServerID: UUID?
    private var probe: Task<Void, Never>?
    private var blockingProbes = 0
    private var lastFailureProbe = Date.distantPast
    private var started = false
    private var lastPathSignature: String?
    private let monitor = NWPathMonitor()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: StashTrustDelegate(), delegateQueue: nil)
    }()

    func usesLocal(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return localServerID == id
    }

    func start() {
        lock.lock()
        let first = !started
        started = true
        lock.unlock()
        guard first else { return }

        refresh(blocking: true)
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let signature = "\(path.status)|" + path.availableInterfaces.map { "\($0.type):\($0.name)" }.joined(separator: ",")
            self.lock.lock()
            let previous = self.lastPathSignature
            self.lastPathSignature = signature
            self.lock.unlock()
            // The first report is the state at launch, which `start` already probes.
            guard let previous, previous != signature else { return }
            self.refresh(blocking: true)
        }
        monitor.start(queue: DispatchQueue(label: "stashy.endpoint.path"))
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.refresh(blocking: false)
        }
    }

    /// Asks the local address again. `blocking`: requests started meanwhile wait for the answer
    /// (at most 2 s), because the address in use is unknown; otherwise they keep the current one.
    func refresh(blocking: Bool) {
        lock.lock()
        let previous = probe
        if blocking { blockingProbes += 1 }
        let task = Task { [weak self] in
            await previous?.value
            await self?.runProbe()
            guard let self, blocking else { return }
            self.lock.lock()
            self.blockingProbes -= 1
            self.lock.unlock()
        }
        probe = task
        lock.unlock()
    }

    /// Returns once the address in use is known. Immediately unless a blocking probe runs.
    func settle() async {
        lock.lock()
        let pending = blockingProbes > 0 ? probe : nil
        lock.unlock()
        await pending?.value
    }

    /// A request could not connect: the network may have changed without a path update.
    func noteConnectionFailure() {
        lock.lock()
        let due = Date().timeIntervalSince(lastFailureProbe) > 10
        if due { lastFailureProbe = Date() }
        lock.unlock()
        if due { refresh(blocking: false) }
    }

    private func runProbe() async {
        let config = await MainActor.run { ServerConfigManager.shared.loadConfig() }
        var reachable = false
        if let config, let local = config.localBaseURL, let url = URL(string: "\(local)/graphql") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 1.5
            for (name, value) in config.requestHeaders(for: url) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            request.httpBody = StashConnectionProbe.versionQueryBody.data(using: .utf8)
            if let (data, response) = try? await Self.session.data(for: request),
               case .stash = StashConnectionProbe.evaluate(data: data, response: response, error: nil) {
                reachable = true
            }
        }
        let newID = reachable ? config?.id : nil
        lock.lock()
        let changed = localServerID != newID
        localServerID = newID
        lock.unlock()
        if changed {
            AppLog.debug("🌐 SERVER CONFIG: using \(reachable ? "local" : "regular") address")
        }
        await MainActor.run {
            if ServerConfigManager.shared.usesLocalAddress != reachable {
                ServerConfigManager.shared.usesLocalAddress = reachable
            }
        }
    }
}

// MARK: - Server capabilities

/// What the active server can answer. Stash rejects a whole query over one unknown field or sort,
/// so anything newer than the oldest supported server is gated here. Unknown version = off.
enum StashServerCapabilities {
    private static let versionKeyPrefix = "stash_server_version_"

    static func record(version: String, serverID: UUID) {
        UserDefaults.standard.set(version, forKey: versionKeyPrefix + serverID.uuidString)
    }

    /// Asks the active server for its version without touching any view state.
    static func refresh() async {
        guard let id = ServerConfigManager.shared.activeConfig?.id else { return }
        struct Response: Decodable {
            struct DataContainer: Decodable {
                struct Version: Decodable { let version: String? }
                let version: Version
            }
            let data: DataContainer?
        }
        // `variables: [:]`: without variables GraphQLClient sends the string as the raw body
        // (meant for pre-encoded mutations) and Stash rejects it.
        let response: Response? = try? await GraphQLClient.shared.execute(
            query: "{ version { version } }", variables: [:]
        )
        if let version = response?.data?.version.version, !version.isEmpty {
            record(version: version, serverID: id)
        }
    }

    /// `v0.32.0`, `0.32.0` and dev builds like `v0.32.0-1-g944dd694` → `[0, 32, 0]`.
    static func parse(_ version: String) -> [Int]? {
        let core = version.trimmingCharacters(in: .whitespacesAndNewlines)
            .drop { $0 == "v" || $0 == "V" }
            .prefix { $0.isNumber || $0 == "." }
        let parts = core.split(separator: ".").compactMap { Int($0) }
        return parts.count >= 2 ? parts : nil
    }

    static func isAtLeast032(_ version: String?) -> Bool {
        guard let version, let parts = parse(version) else { return false }
        return parts.lexicographicallyPrecedes([0, 32]) == false
    }

    /// Stash 0.31: image phashes in Generate.
    static var supports031: Bool {
        guard let id = ServerConfigManager.shared.activeConfig?.id,
              let version = UserDefaults.standard.string(forKey: versionKeyPrefix + id.uuidString),
              let parts = parse(version) else { return false }
        return parts.lexicographicallyPrecedes([0, 31]) == false
    }

    /// Stash 0.32: `production_date`, recursive studio counts, tag count `depth`, new sorts.
    static var supports032: Bool {
        guard let id = ServerConfigManager.shared.activeConfig?.id else { return false }
        return isAtLeast032(UserDefaults.standard.string(forKey: versionKeyPrefix + id.uuidString))
    }
}

/// A sort option that some servers reject as an invalid sort.
protocol StashVersionedSortOption {
    var requiresStash032: Bool { get }
}

extension StashVersionedSortOption {
    var isAvailableOnServer: Bool { !requiresStash032 || StashServerCapabilities.supports032 }
}

extension StashVersionedSortOption where Self: CaseIterable {
    static var availableCases: [Self] { allCases.filter(\.isAvailableOnServer) }
}
