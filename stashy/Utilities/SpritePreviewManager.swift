import UIKit

struct VTTEntry {
    let startTime: Double
    let endTime: Double
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

@MainActor
class SpritePreviewManager: ObservableObject {
    @Published var spriteImage: UIImage?
    @Published var isLoaded = false

    private var vttEntries: [VTTEntry] = []
    private var loadTask: Task<Void, Never>?

    func load(vttURLString: String?, spriteURLString: String?) {
        loadTask?.cancel()
        vttEntries = []
        spriteImage = nil
        isLoaded = false

        guard let vttStr = vttURLString, let spriteStr = spriteURLString,
              let vttURL = URL(string: vttStr), let spriteURL = URL(string: spriteStr) else { return }

        let signedVTT = signedURL(vttURL) ?? vttURL
        let signedSprite = signedURL(spriteURL) ?? spriteURL

        loadTask = Task {
            do {
                let entries = try await fetchAndParseVTT(url: signedVTT)
                if Task.isCancelled { return }
                self.vttEntries = entries

                let image = try await fetchSpriteImage(url: signedSprite)
                if Task.isCancelled { return }
                self.spriteImage = image
                self.isLoaded = true
            } catch {
                // Non-blocking: sprite preview is optional
            }
        }
    }

    func frameImage(at time: Double) -> UIImage? {
        guard let sprite = spriteImage, let cgImage = sprite.cgImage else { return nil }
        guard let entry = findEntry(for: time) else { return nil }

        let scale = sprite.scale
        let cropRect = CGRect(
            x: CGFloat(entry.x) * scale,
            y: CGFloat(entry.y) * scale,
            width: CGFloat(entry.width) * scale,
            height: CGFloat(entry.height) * scale
        )
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }

    private func findEntry(for time: Double) -> VTTEntry? {
        guard !vttEntries.isEmpty else { return nil }
        var lo = 0
        var hi = vttEntries.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let entry = vttEntries[mid]
            if time < entry.startTime {
                hi = mid - 1
            } else if time >= entry.endTime {
                lo = mid + 1
            } else {
                return entry
            }
        }
        if let last = vttEntries.last, time >= last.startTime {
            return last
        }
        return vttEntries.first
    }

    // MARK: - Network

    private func fetchAndParseVTT(url: URL) async throws -> [VTTEntry] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        if let config = ServerConfigManager.shared.activeConfig,
           let apiKey = config.secureApiKey, !apiKey.isEmpty {
            request.addValue(apiKey, forHTTPHeaderField: "ApiKey")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parseVTT(text)
    }

    private func fetchSpriteImage(url: URL) async throws -> UIImage? {
        if let cached = ImageCache.shared.object(forKey: url as NSURL) {
            return cached
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if let config = ServerConfigManager.shared.activeConfig,
           let apiKey = config.secureApiKey, !apiKey.isEmpty {
            request.addValue(apiKey, forHTTPHeaderField: "ApiKey")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let image = UIImage(data: data) else { return nil }
        ImageCache.shared.setData(data, forKey: url as NSURL)
        return image
    }

    // MARK: - VTT Parsing

    private func parseVTT(_ text: String) -> [VTTEntry] {
        var entries: [VTTEntry] = []
        let lines = text.components(separatedBy: .newlines)
        var i = 0

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            guard line.contains("-->") else { i += 1; continue }

            let parts = line.components(separatedBy: "-->")
            guard parts.count == 2 else { i += 1; continue }

            let startTime = parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces))
            let endTime = parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces))
            guard let start = startTime, let end = endTime else { i += 1; continue }

            i += 1
            if i < lines.count {
                let dataLine = lines[i].trimmingCharacters(in: .whitespaces)
                if let entry = parseXYWH(dataLine, startTime: start, endTime: end) {
                    entries.append(entry)
                }
            }
            i += 1
        }
        return entries
    }

    private func parseTimestamp(_ str: String) -> Double? {
        let components = str.components(separatedBy: ":")
        guard components.count >= 2 else { return nil }

        if components.count == 3 {
            guard let h = Double(components[0]),
                  let m = Double(components[1]),
                  let s = Double(components[2]) else { return nil }
            return h * 3600 + m * 60 + s
        } else {
            guard let m = Double(components[0]),
                  let s = Double(components[1]) else { return nil }
            return m * 60 + s
        }
    }

    private func parseXYWH(_ line: String, startTime: Double, endTime: Double) -> VTTEntry? {
        guard let hashIndex = line.firstIndex(of: "#") else { return nil }
        let fragment = String(line[line.index(after: hashIndex)...])
        guard fragment.hasPrefix("xywh=") else { return nil }

        let values = fragment.dropFirst(5).components(separatedBy: ",")
        guard values.count == 4,
              let x = Int(values[0]),
              let y = Int(values[1]),
              let w = Int(values[2]),
              let h = Int(values[3]) else { return nil }

        return VTTEntry(startTime: startTime, endTime: endTime, x: x, y: y, width: w, height: h)
    }
}
