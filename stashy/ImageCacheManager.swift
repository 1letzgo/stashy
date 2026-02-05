//
//  ImageCacheManager.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI
import Combine
import CryptoKit

// MARK: - Image Cache (Memory + Disk)

class ImageCache {
    static let shared = ImageCache()
    
    private let memoryCache = NSCache<NSURL, UIImage>()
    private let fileManager = FileManager.default
    private let baseDiskCacheDirectory: URL
    private var _cachedServerCacheDirectory: URL?
    private var lastCleanupDate: Date?
    
    private init() {
        // Memory Cache Config
        memoryCache.countLimit = 300 // Increased
        memoryCache.totalCostLimit = 1024 * 1024 * 300 // 300 MB
        
        // Disk Cache Config
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        baseDiskCacheDirectory = paths[0].appendingPathComponent("StashyImageCache")
        
        createBaseDiskCacheDirectory()
        
        // Listen for server changes
        NotificationCenter.default.addObserver(self, selector: #selector(handleServerChange), name: NSNotification.Name("ServerConfigChanged"), object: nil)
    }
    
    @objc private func handleServerChange() {
        memoryCache.removeAllObjects()
        resetServerCachePath()
    }
    
    private func createBaseDiskCacheDirectory() {
        if !fileManager.fileExists(atPath: baseDiskCacheDirectory.path) {
            try? fileManager.createDirectory(at: baseDiskCacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    private var currentServerCacheDirectory: URL {
        if let cached = _cachedServerCacheDirectory {
            return cached
        }
        let serverId = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
        let dir = baseDiskCacheDirectory.appendingPathComponent(serverId)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        _cachedServerCacheDirectory = dir
        return dir
    }
    
    func resetServerCachePath() {
        _cachedServerCacheDirectory = nil
    }
    
    /// Creates a stable cache key by stripping variable query parameters (like ?t=timestamp)
    /// But KEEPS size parameters (width, height) to allow caching different sizes
    private func stableCacheKey(for url: NSURL) -> String {
        let absString = url.absoluteString ?? ""
        // Fast path: if no query params, return as is
        if !absString.contains("?") {
            return absString
        }
        
        guard let urlComponents = URLComponents(url: url as URL, resolvingAgainstBaseURL: false) else {
            return absString
        }
        
        var stable = urlComponents
        // Filter query items to keep only size-related ones
        if let queryItems = stable.queryItems {
            let allowedParams = Set(["width", "height", "size"])
            let filteredItems = queryItems.filter { allowedParams.contains($0.name) }
            
            if filteredItems.isEmpty {
                stable.query = nil
            } else {
                stable.queryItems = filteredItems
            }
        } else {
            stable.query = nil
        }
        
        stable.fragment = nil
        return stable.url?.absoluteString ?? absString
    }
    
    private func cacheFileURL(for key: NSURL) -> URL {
        let keyString = stableCacheKey(for: key)
        let filename = SHA256.hash(data: Data(keyString.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        return currentServerCacheDirectory.appendingPathComponent(filename)
    }
    
    private func stableMemoryCacheKey(for url: NSURL) -> NSURL {
        let keyString = stableCacheKey(for: url)
        return (URL(string: keyString) ?? url as URL) as NSURL
    }
    
    func object(forKey key: NSURL) -> UIImage? {
        let stableKey = stableMemoryCacheKey(for: key)
        
        // 1. Memory Cache
        if let image = memoryCache.object(forKey: stableKey) {
            return image
        }
        
        // 2. Disk Cache
        let fileURL = cacheFileURL(for: key)
        if fileManager.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
                memoryCache.setObject(image, forKey: stableKey)
                return image
            }
        }
        return nil
    }
    
    func setData(_ data: Data, forKey key: NSURL) {
        let stableKey = stableMemoryCacheKey(for: key)
        
        // Store in Memory
        if let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: stableKey)
        }
        
        // Store on Disk
        Task.detached(priority: .background) {
            let fileURL = self.cacheFileURL(for: key)
            try? data.write(to: fileURL)
            
            // Only cleanup once every 4 hours to avoid heavy disk IO
            if self.lastCleanupDate == nil || Date().timeIntervalSince(self.lastCleanupDate!) > 60 * 60 * 4 {
                self.cleanupOldFiles()
                self.lastCleanupDate = Date()
            }
        }
    }
    
    func data(forKey key: NSURL) -> Data? {
        let fileURL = cacheFileURL(for: key)
        if fileManager.fileExists(atPath: fileURL.path) {
            return try? Data(contentsOf: fileURL)
        }
        return nil
    }
    
    private func cleanupOldFiles() {
        // Simple periodic cleanup: remove files older than 30 days
        let thirtyDays: TimeInterval = 60 * 60 * 24 * 30
        let serverDir = currentServerCacheDirectory
        
        guard let files = try? fileManager.contentsOfDirectory(at: serverDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        
        for file in files {
            if let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = attrs.contentModificationDate,
               Date().timeIntervalSince(date) > thirtyDays {
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    func clearCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: baseDiskCacheDirectory)
        createBaseDiskCacheDirectory()
    }
    
    func clearCurrentServerCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: currentServerCacheDirectory)
    }
}

// MARK: - Image Loader Session Delegate (SSL Handling)

class ImageLoaderSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            let host = challenge.protectionSpace.host
            print("📱 ImageLoader SSL Challenge for host: \(host)")
            
            // Accept self-signed certificates for local/private IP ranges
            if isLocalOrPrivateIP(host) {
                print("✅ ImageLoader: Accepting SSL Trust for private/test host: \(host)")
                if let serverTrust = challenge.protectionSpace.serverTrust {
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                }
            } else {
                print("⚠️ ImageLoader: Host \(host) not in private ranges, using default SSL handling")
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
    
    private func isLocalOrPrivateIP(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" { return true }
        let privateRanges = ["10.", "172.16.", "172.17.", "172.18.", "172.19.", "172.20.", "172.21.", "172.22.", "172.23.", "172.24.", "172.25.", "172.26.", "172.27.", "172.28.", "172.29.", "172.30.", "172.31.", "192.168."]
        for range in privateRanges { if host.hasPrefix(range) { return true } }
        
        // Also allow stashytest.gole.tz specifically as it's the test domain showing SSL issues in logs
        if host.contains("gole.tz") { return true }
        
        return false
    }
}

// MARK: - Image Loader

@MainActor
class ImageLoader: ObservableObject {
    @Published var image: Image?
    @Published var imageData: Data?
    @Published var isLoading = true
    @Published var error: Error?

    private var url: URL?
    private var fetchTask: Task<Void, Never>?
    private let session: URLSession

    deinit {
        fetchTask?.cancel()
    }

    init(url: URL?) {
        self.url = url
        
        // Create custom session for SSL support
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config, delegate: ImageLoaderSessionDelegate(), delegateQueue: nil)
        
        loadImage()
    }

    func updateURL(_ newURL: URL?, force: Bool = false) {
        if !force {
            guard newURL != self.url else { return }
        }
        
        fetchTask?.cancel()
        self.url = newURL
        self.image = nil
        self.error = nil
        self.isLoading = true
        loadImage()
    }

    private func loadImage() {
        guard let url = url else {
            self.error = CustomAsyncImageError.noURL
            self.isLoading = false
            return
        }

        fetchTask?.cancel()
        fetchTask = Task {
            // Check cancellation
            if Task.isCancelled { return }
            
            // 1. Check Memory/Disk Cache for UIImage (Fastest)
            // object(forKey already checks both memory and disk)
            if let cachedUIImage = ImageCache.shared.object(forKey: url as NSURL) {
                if Task.isCancelled { return }
                self.image = Image(uiImage: cachedUIImage)
                self.isLoading = false
                return
            }

            do {
                let data = try await loadImage(from: url)
                if Task.isCancelled { return }
                
                self.imageData = data
                if let uiImage = UIImage(data: data) {
                    // Save to cache
                    ImageCache.shared.setData(data, forKey: url as NSURL)
                    self.image = Image(uiImage: uiImage)
                } else {
                    self.error = CustomAsyncImageError.invalidImageData
                }
                self.isLoading = false
            } catch {
                if Task.isCancelled { return }
                self.error = error
                self.isLoading = false
            }
        }
    }

    private func loadImage(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0 // Reduced timeout for faster failure
        request.cachePolicy = .reloadIgnoringLocalCacheData // Force check with server if not in own cache

        // Add API Key if available
        if let config = ServerConfigManager.shared.activeConfig,
           let apiKey = config.secureApiKey, !apiKey.isEmpty {
            request.addValue(apiKey, forHTTPHeaderField: "ApiKey")
        }

        do {
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                print("❌ ImageLoader Error: HTTP \(httpResponse.statusCode) for \(url)")
                // Check for specific server errors
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                     // Auth error?
                }
                throw CustomAsyncImageError.serverError(statusCode: httpResponse.statusCode)
            }
            
            return data
        } catch {
            print("❌ ImageLoader Network Error: \(error.localizedDescription) for \(url)")
            // Re-throw NSURLErrorDomain errors (like cannotConnectToHost)
            // so they can be identified as connection issues
            throw error
        }
    }
}

// MARK: - Custom Async Image View

enum CustomAsyncImageError: LocalizedError {
    case noURL
    case invalidImageData
    case serverError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .noURL: return "No URL provided"
        case .invalidImageData: return "Invalid image data"
        case .serverError(let statusCode): return "Server returned error: \(statusCode)"
        }
    }
}

struct CustomAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (ImageLoader) -> Content

    @StateObject private var loader: ImageLoader
    @ObservedObject private var configManager = ServerConfigManager.shared

    init(url: URL?, @ViewBuilder content: @escaping (ImageLoader) -> Content) {
        self.url = url
        self.content = content
        self._loader = StateObject(wrappedValue: ImageLoader(url: url))
    }

    var body: some View {
        content(loader)
            .onChange(of: url) { oldValue, newValue in
                loader.updateURL(newValue)
            }
            .onChange(of: configManager.activeConfig?.id) { _, _ in
                // Force reload even if URL is same string, as headers (API Key) changed
                loader.updateURL(url, force: true)
            }
    }
}
