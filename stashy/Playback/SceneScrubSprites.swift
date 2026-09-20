//
//  SceneScrubSprites.swift
//  stashy
//
//  Stash generates a scrubber sprite sheet per scene (Settings › Tasks › Generate › Scene
//  scrubber sprites): one JPEG holding a grid of thumbnails plus a WebVTT that says which
//  rectangle belongs to which moment. Reading a tile out of that sheet costs nothing, while
//  decoding a frame out of the video costs a demuxer, a seek and a decode — and delivers black
//  while the session is still coming up. The sheet is therefore the scrub preview's first
//  source; frame extraction stays as the fallback for scenes with no sprites.
//

#if !os(tvOS)
import Foundation
import UIKit

@MainActor
final class SceneScrubSprites {
    /// One VTT cue: the moment it covers and its rectangle on the sheet.
    private struct Tile {
        let start: Double
        let end: Double
        let rect: CGRect
    }

    private let vttURL: URL
    private let spriteURL: URL
    private var tiles: [Tile] = []
    private var sheet: UIImage?
    private var loadTask: Task<Void, Never>?
    private(set) var isUnavailable = false
    /// Cropped tiles, keyed by their rect — scrubbing walks over the same few tiles repeatedly.
    private var cropped: [String: UIImage] = [:]

    init?(vttPath: String?, spritePath: String?) {
        guard let vttPath, let spritePath,
              !vttPath.isEmpty, vttPath != "null",
              !spritePath.isEmpty, spritePath != "null",
              let vtt = Self.signed(vttPath), let sprite = Self.signed(spritePath) else { return nil }
        self.vttURL = vtt
        self.spriteURL = sprite
    }

    /// Fetches sheet + index once. Safe to call on every scrub start.
    func prepare() {
        guard loadTask == nil, !isUnavailable else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            let vttURL = self.vttURL
            let spriteURL = self.spriteURL
            async let indexData = Self.load(vttURL)
            async let sheetData = Self.load(spriteURL)
            let (vtt, sprite) = await (indexData, sheetData)
            guard let vtt, let sprite, let image = UIImage(data: sprite) else {
                self.isUnavailable = true
                return
            }
            let parsed = Self.parse(vtt: vtt)
            guard !parsed.isEmpty else {
                self.isUnavailable = true
                return
            }
            self.tiles = parsed
            self.sheet = image
        }
    }

    /// The tile covering `seconds`, or nil while the sheet is still loading / missing.
    func thumbnail(at seconds: Double) -> UIImage? {
        guard let sheet, !tiles.isEmpty else { return nil }
        let target = max(0, seconds)
        let tile = tiles.last(where: { $0.start <= target }) ?? tiles.first
        guard let tile else { return nil }
        let key = "\(Int(tile.rect.origin.x)),\(Int(tile.rect.origin.y)),\(Int(tile.rect.width)),\(Int(tile.rect.height))"
        if let cached = cropped[key] { return cached }
        // The sheet is a plain JPEG, so its pixel grid and the VTT's coordinates line up 1:1.
        guard let cg = sheet.cgImage?.cropping(to: tile.rect) else { return nil }
        let image = UIImage(cgImage: cg)
        cropped[key] = image
        return image
    }

    // MARK: - Loading

    private static func load(_ url: URL) async -> Data? {
        var request = authenticatedStashRequest(for: url)
        request.timeoutInterval = 20
        do {
            let (data, response) = try await StashNetworking.session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static func signed(_ path: String) -> URL? {
        guard let url = URL(string: path) else { return nil }
        guard let config = ServerConfigManager.shared.activeConfig,
              let key = config.secureApiKey, !key.isEmpty else { return url }
        if url.query?.lowercased().contains("apikey=") == true { return url }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = comps?.queryItems ?? []
        items.append(URLQueryItem(name: "apikey", value: key.trimmingCharacters(in: .whitespacesAndNewlines)))
        comps?.queryItems = items
        return comps?.url ?? url
    }

    // MARK: - WebVTT

    /// Stash writes one cue per tile:
    ///
    ///     00:00:00.000 --> 00:00:10.000
    ///     …_sprite.jpg#xywh=0,0,160,90
    private static func parse(vtt: Data) -> [Tile] {
        guard let text = String(data: vtt, encoding: .utf8) else { return [] }
        var tiles: [Tile] = []
        var pendingRange: (start: Double, end: Double)?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.contains("-->") {
                let parts = line.components(separatedBy: "-->")
                guard parts.count == 2,
                      let start = seconds(fromTimestamp: parts[0]),
                      let end = seconds(fromTimestamp: parts[1]) else {
                    pendingRange = nil
                    continue
                }
                pendingRange = (start, end)
                continue
            }
            guard let range = pendingRange,
                  let hash = line.range(of: "#xywh=") else { continue }
            let numbers = line[hash.upperBound...]
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            pendingRange = nil
            guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { continue }
            tiles.append(Tile(
                start: range.start,
                end: range.end,
                rect: CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
            ))
        }
        return tiles.sorted { $0.start < $1.start }
    }

    /// `00:01:23.456` / `01:23.456` → seconds.
    private static func seconds(fromTimestamp raw: String) -> Double? {
        let stamp = raw.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces).first ?? ""
        let parts = stamp.components(separatedBy: ":")
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total: Double = 0
        for part in parts {
            guard let value = Double(part.replacingOccurrences(of: ",", with: ".")) else { return nil }
            total = total * 60 + value
        }
        return total
    }
}
#endif
