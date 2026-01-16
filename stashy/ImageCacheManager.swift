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
    private let diskCacheDirectory: URL
    
    private init() {
        // Memory Cache Config
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 1024 * 1024 * 200 // 200 MB
        
        // Disk Cache Config
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        diskCacheDirectory = paths[0].appendingPathComponent("StashyImageCache")
        
        createDiskCacheDirectory()
    }
    
    private func createDiskCacheDirectory() {
        if !fileManager.fileExists(atPath: diskCacheDirectory.path) {
            try? fileManager.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    /// Creates a stable cache key by stripping query parameters (like ?t=timestamp)
    private func stableCacheKey(for url: NSURL) -> String {
        guard let urlComponents = URLComponents(url: url as URL, resolvingAgainstBaseURL: false) else {
            return url.absoluteString ?? ""
        }
        // Remove query and fragment to get stable key
        var stable = urlComponents
        stable.query = nil
        stable.fragment = nil
        return stable.url?.absoluteString ?? url.absoluteString ?? ""
    }
    
    private func cacheFileURL(for key: NSURL) -> URL {
        let keyString = stableCacheKey(for: key)
        // Simple hashing for filename
        let filename = SHA256.hash(data: Data(keyString.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDirectory.appendingPathComponent(filename)
    }
    
    /// Stable NSURL key for memory cache (without query params)
    private func stableMemoryCacheKey(for url: NSURL) -> NSURL {
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
        
        // 1. Check Memory (Fastest)
        if let image = memoryCache.object(forKey: stableKey) {
            return image
        }
        
        // 2. Check Disk
        let fileURL = cacheFileURL(for: key)
        if fileManager.fileExists(atPath: fileURL.path) {
            // Check expiration (e.g., 7 days)
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let modificationDate = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modificationDate) < 60 * 60 * 24 * 7 {
                
                if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
                    // Re-cache in memory with stable key
                    memoryCache.setObject(image, forKey: stableKey)
                    return image
                }
            } else {
                // Remove expired file
                try? fileManager.removeItem(at: fileURL)
            }
        }
        
        return nil
    }
    
    func setObject(_ image: UIImage, forKey key: NSURL) {
        let stableKey = stableMemoryCacheKey(for: key)
        
        // 1. Save to Memory with stable key
        memoryCache.setObject(image, forKey: stableKey)
        
        // 2. Save to Disk (Async to avoid blocking UI)
        Task.detached(priority: .background) {
            if let data = image.jpegData(compressionQuality: 0.8) {
                let fileURL = self.cacheFileURL(for: key)
                try? data.write(to: fileURL)
            }
        }
    }
    
    func clearCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: diskCacheDirectory)
        createDiskCacheDirectory()
    }
}

// MARK: - Image Loader

class ImageLoader: ObservableObject {
    @Published var image: Image?
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

        // Check cache first
        if let cachedImage = ImageCache.shared.object(forKey: url as NSURL) {
            print("🖼️ CACHE HIT: \(url.path)")
            self.image = Image(uiImage: cachedImage)
            self.isLoading = false
            return
        }
        
        print("🖼️ CACHE MISS: \(url.path)")

        Task {
            do {
                let data = try await loadImage(from: url)
                if let uiImage = UIImage(data: data) {
                    // Save to cache
                    ImageCache.shared.setObject(uiImage, forKey: url as NSURL)
                    
                    await MainActor.run {
                        self.image = Image(uiImage: uiImage)
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.error = CustomAsyncImageError.invalidImageData
                        self.isLoading = false
                    }
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
