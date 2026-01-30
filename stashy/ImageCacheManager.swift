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
        let absString = url.absoluteString ?? ""
        if !absString.contains("?") {
            return url
        }
        
        guard let urlComponents = URLComponents(url: url as URL, resolvingAgainstBaseURL: false) else {
            return url
        }
        var stable = urlComponents
        stable.query = nil
        stable.fragment = nil
        return (stable.url ?? url as URL) as NSURL
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

// MARK: - Image Loader

class ImageLoader: ObservableObject {
    @Published var image: Image?
    @Published var imageData: Data?
    @Published var isLoading = true
    @Published var error: Error?

    private let url: URL?

    init(url: URL?) {
        self.url = url
        loadImage()
    }

    private func loadImage() {
        guard let url = url else {
            self.error = CustomAsyncImageError.noURL
            self.isLoading = false
            return
        }

        Task {
            // 1. Check Memory/Disk Cache for UIImage (Fastest)
            // object(forKey already checks both memory and disk)
            if let cachedUIImage = ImageCache.shared.object(forKey: url as NSURL) {
                await MainActor.run {
                    self.image = Image(uiImage: cachedUIImage)
                    self.isLoading = false
                }
                return
            }

            do {
                let data = try await loadImage(from: url)
                await MainActor.run {
                    self.imageData = data
                    if let uiImage = UIImage(data: data) {
                        // Save to cache
                        ImageCache.shared.setData(data, forKey: url as NSURL)
                        self.image = Image(uiImage: uiImage)
                    } else {
                        self.error = CustomAsyncImageError.invalidImageData
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
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
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                // Check for specific server errors
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                     // Auth error?
                }
                throw CustomAsyncImageError.serverError(statusCode: httpResponse.statusCode)
            }
            
            return data
        } catch {
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

    init(url: URL?, @ViewBuilder content: @escaping (ImageLoader) -> Content) {
        self.url = url
        self.content = content
        self._loader = StateObject(wrappedValue: ImageLoader(url: url))
    }

    var body: some View {
        content(loader)
    }
}
