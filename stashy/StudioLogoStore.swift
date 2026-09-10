//
//  StudioLogoStore.swift
//  stashy
//
//  Ein Renderer für Studio-Bilder auf iOS und tvOS: PNG/JPG werden skaliert,
//  SVG über SwiftDraw gerastert. Ergebnis liegt als PNG im Speicher- und
//  Platten-Cache, pro Studio und Zielhöhe genau einmal.
//

import SwiftUI
import UIKit
import SwiftDraw

// MARK: - Store

/// Liefert das Studio-Bild als fertig gerastertes `UIImage`.
///
/// Konsumenten: `SceneStudioBadge` (Scene-Cards, klein), `StudioImageView` (iOS
/// Kacheln/Header) und `TVStudioImageView` (tvOS). Niemals ein SVG live in einer
/// WebView rendern — das war die alte, nicht scrollbare Lösung.
actor StudioLogoStore {
    static let shared = StudioLogoStore()

    /// Rasterhöhe des Karten-Abzeichens in Punkten. Karten zeigen es 12–16 pt
    /// hoch; das Doppelte reicht auch auf 3x-Displays ohne sichtbare Unschärfe.
    static let badgeHeight: CGFloat = 32
    static let badgeMaxWidth: CGFloat = 640

    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    /// Schlüssel, für die es kein Bild gibt (Platzhalter, Fehler). Verhindert,
    /// dass jede Karte den Server erneut fragt.
    private var missing: Set<String> = []

    private init() {
        memory.countLimit = 400
    }

    /// Cache-Schlüssel; `updatedAt` sorgt dafür, dass ein neues Studio-Bild den
    /// alten Eintrag nicht überlebt. Version hochzählen, wenn sich die Rasterung ändert.
    static func cacheKey(studioId: String, updatedAt: String?, height: CGFloat) -> String {
        "v10|\(studioId)|\(updatedAt ?? "")|\(Int(height))"
    }

    func image(
        studioId: String, updatedAt: String?, height: CGFloat, maxWidth: CGFloat
    ) async -> UIImage? {
        let key = Self.cacheKey(studioId: studioId, updatedAt: updatedAt, height: height)

        if let cached = memory.object(forKey: key as NSString) { return cached }
        if missing.contains(key) { return nil }
        if let running = inFlight[key] { return await running.value }

        let task = Task<UIImage?, Never> {
            await Self.load(studioId: studioId, key: key, height: height, maxWidth: maxWidth)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image {
            memory.setObject(image, forKey: key as NSString)
        } else {
            missing.insert(key)
        }
        return image
    }

    /// Vergisst gemerkte Fehlschläge — z. B. nach Serverwechsel oder wenn ein
    /// Studio-Bild neu gesetzt wurde.
    func forgetMissing() {
        missing.removeAll()
    }

    // MARK: Loading

    private static func diskKey(_ key: String) -> NSURL? {
        NSURL(string: "stashy-studio-logo://\(key)")
    }

    private static func load(studioId: String, key: String, height: CGFloat, maxWidth: CGFloat) async -> UIImage? {
        // 1. Platte: schon einmal gerastert?
        if let diskKey = diskKey(key),
           let data = await ImageCache.shared.loadData(forKey: diskKey),
           let image = UIImage(data: data) {
            return image
        }

        // 2. Server
        guard let config = ServerConfigManager.shared.loadConfig(),
              let url = URL(string: "\(config.baseURL)/studio/\(studioId)/image") else {
            return nil
        }
        let request = stashRequest(to: url, config: config, timeout: 20)
        guard let (data, response) = try? await StashNetworking.session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        let scale = await MainActor.run { UIScreen.main.scale }
        let contentType = (http.allHeaderFields["Content-Type"] as? String)?.lowercased() ?? ""

        // 3. Rastern abseits des Main Threads — beim ersten Scrollen laden alle
        //    sichtbaren Karten gleichzeitig ihr Logo.
        let rendered = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let image: UIImage?
            if let raster = UIImage(data: data) {
                image = StudioLogoRasterizer.scaled(raster, height: height, maxWidth: maxWidth, scale: scale)
            } else {
                let looksLikeSVG = contentType.contains("svg")
                    || String(data: data.prefix(512), encoding: .utf8)?.lowercased().contains("<svg") == true
                    || String(data: data.prefix(512), encoding: .utf8)?.lowercased().contains("<?xml") == true
                guard looksLikeSVG else { return nil }
                image = StudioLogoRasterizer.rasterize(svgData: data, height: height, maxWidth: maxWidth, scale: scale)
                if image == nil {
                    AppLog.debug("StudioLogo: SwiftDraw could not render studio \(studioId)")
                }
            }
            guard let image else { return nil }
            return image
        }.value

        if let rendered, let diskKey = diskKey(key), let png = rendered.pngData() {
            ImageCache.shared.setData(png, forKey: diskKey)
        }
        return rendered
    }
}

// MARK: - Rasterizer

nonisolated enum StudioLogoRasterizer {
    /// Skaliert ein Rasterbild auf die Zielhöhe und schneidet vorher transparenten
    /// Rand weg — viele Logos kommen mit viel Luft drumherum.
    static func scaled(_ image: UIImage, height: CGFloat, maxWidth: CGFloat, scale: CGFloat) -> UIImage? {
        guard image.size.height > 0, image.size.width > 0 else { return nil }
        guard let trimmed = trimmedToVisiblePixels(image) else { return nil }
        let size = fit(trimmed.size, height: height, maxWidth: maxWidth)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            trimmed.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// SVG → Pixel über SwiftDraw. Rendert auf die Zielhöhe, schneidet Luft weg und
    /// rastert bei viel Rand ein zweites Mal größer, damit der sichtbare Ausschnitt in
    /// voller Auflösung ankommt statt hochskaliert zu werden.
    static func rasterize(svgData: Data, height: CGFloat, maxWidth: CGFloat, scale: CGFloat) -> UIImage? {
        guard let svg = SVG(data: svgData, options: .hideUnsupportedFilters),
              svg.size.width > 0, svg.size.height > 0 else { return nil }

        let firstSize = fit(svg.size, height: height, maxWidth: maxWidth)
        let first = svg.rasterize(size: firstSize, scale: scale)
        guard let visible = visiblePixelRect(first) else { return nil }

        // Wenig Rand → erster Render reicht (nur zuschneiden).
        if visible.height >= firstSize.height * 0.8, visible.width >= firstSize.width * 0.8 {
            return crop(first, to: visible)
        }

        // Viel Rand: Faktor so wählen, dass der sichtbare Teil die Zielhöhe füllt
        // (bzw. an `maxWidth` anschlägt), dann das Ganze größer rendern und zuschneiden.
        let factor = min(height / visible.height, maxWidth / visible.width)
        let secondSize = CGSize(width: (firstSize.width * factor).rounded(), height: (firstSize.height * factor).rounded())
        let second = svg.rasterize(size: secondSize, scale: scale)
        let scaledVisible = CGRect(
            x: visible.minX * factor, y: visible.minY * factor,
            width: visible.width * factor, height: visible.height * factor
        )
        return crop(second, to: scaledVisible.intersection(CGRect(origin: .zero, size: secondSize)))
    }

    static func fit(_ source: CGSize, height: CGFloat, maxWidth: CGFloat) -> CGSize {
        var size = CGSize(width: source.width / source.height * height, height: height)
        if size.width > maxWidth {
            size = CGSize(width: maxWidth, height: maxWidth * source.height / source.width)
        }
        return CGSize(width: max(size.width.rounded(), 1), height: max(size.height.rounded(), 1))
    }

    // MARK: Alpha trim

    /// Schneidet (fast) transparenten Rand weg — Schatten und Glows zählen nicht,
    /// sonst sitzt der Schriftzug klein in einer großen Box. `nil`, wenn das Bild
    /// keinen sichtbaren Pixel hat.
    static func trimmedToVisiblePixels(_ image: UIImage) -> UIImage? {
        guard let rect = visiblePixelRect(image) else { return nil }
        return crop(image, to: rect)
    }

    /// Bounding Box der sichtbaren Pixel in Punkten (Bildkoordinaten).
    static func visiblePixelRect(_ image: UIImage) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        // Auf einer kleinen Kopie suchen (max 256 px Kante) — reicht für den
        // Zuschnitt und bleibt billig.
        let sampleMax = 256
        let sw = min(cg.width, sampleMax)
        let sh = max(1, Int(CGFloat(cg.height) * CGFloat(sw) / CGFloat(cg.width)))
        let bytesPerRow = sw * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * sh)
        guard let ctx = CGContext(
            data: &pixels, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: sw, height: sh))

        var minX = sw, minY = sh, maxX = -1, maxY = -1
        for y in 0..<sh {
            let row = y * bytesPerRow
            for x in 0..<sw where pixels[row + x * 4 + 3] > 48 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        let fx = CGFloat(cg.width) / CGFloat(sw) / image.scale
        let fy = CGFloat(cg.height) / CGFloat(sh) / image.scale
        return CGRect(
            x: floor(CGFloat(minX) * fx), y: floor(CGFloat(minY) * fy),
            width: ceil(CGFloat(maxX - minX + 1) * fx), height: ceil(CGFloat(maxY - minY + 1) * fy)
        ).intersection(CGRect(origin: .zero, size: image.size))
    }

    private static func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let pixelRect = CGRect(
            x: rect.minX * image.scale, y: rect.minY * image.scale,
            width: rect.width * image.scale, height: rect.height * image.scale
        ).integral
        if pixelRect.minX <= 0, pixelRect.minY <= 0,
           pixelRect.width >= CGFloat(cg.width), pixelRect.height >= CGFloat(cg.height) {
            return image
        }
        guard let cropped = cg.cropping(to: pixelRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - Generic SVG image

/// Zeigt beliebige SVG-Daten (z. B. Tag-Bilder) als gerastertes Bild. Für
/// Studio-Logos den `StudioLogoStore` nehmen — der cacht.
struct RasterizedSVGImage: View {
    let data: Data
    var height: CGFloat = 240

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: data) {
            let height = height
            let data = data
            let scale = UIScreen.main.scale
            image = await Task.detached(priority: .userInitiated) {
                StudioLogoRasterizer.rasterize(svgData: data, height: height, maxWidth: height * 4, scale: scale)
            }.value
        }
    }
}
