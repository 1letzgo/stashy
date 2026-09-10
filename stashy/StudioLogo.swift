//
//  StudioLogo.swift
//  stashy
//
//  Studio-Logo als kleines Abzeichen auf Szenenkarten, SVG inklusive.
//

#if !os(tvOS)
import SwiftUI
import UIKit
import PocketSVG

// MARK: - Badge

/// Studio-Logo statt Name auf Szenenkarten.
///
/// Zeigt den Namen, solange kein Logo da ist: während des Ladens, bei Studios ohne
/// eigenes Bild (Stash liefert dann einen Platzhalter, den wir nicht wollen) und
/// bei SVGs, die PocketSVG nicht sicher rendern kann.
struct SceneStudioBadge: View {
    let studio: SceneStudio
    var logoHeight: CGFloat = 16
    var maxLogoWidth: CGFloat = 180
    var font: Font = .caption
    var fontWeight: Font.Weight = .medium
    var uppercased: Bool = false

    @State private var logo: UIImage?

    var body: some View {
        Group {
            if let logo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: displaySize(for: logo).width, height: displaySize(for: logo).height)
                    .clipped()
            } else {
                Text(uppercased ? studio.name.uppercased() : studio.name)
                    .font(font)
                    .fontWeight(fontWeight)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: logoHeight + 8)
        .background(logo != nil ? Color.studioHeaderGray.opacity(0.92) : Color.black.opacity(DesignTokens.Opacity.badge))
        .clipShape(Capsule())
        .task(id: studio.logoCacheKey) {
            guard studio.hasCustomImage else {
                logo = nil
                return
            }
            logo = await StudioLogoStore.shared.logo(for: studio)
        }
    }
}

extension SceneStudioBadge {
    /// `logoHeight` ist die Mindesthöhe — kein Logo wird kleiner. Breite
    /// Schriftzüge werden bei `maxLogoWidth` gedeckelt und dann seitlich
    /// beschnitten statt geschrumpft.
    fileprivate func displaySize(for logo: UIImage) -> CGSize {
        let aspect = logo.size.width / max(logo.size.height, 1)
        return CGSize(width: min(logoHeight * aspect, maxLogoWidth), height: logoHeight)
    }
}

// MARK: - Store

/// Liefert das Studio-Logo als fertig gerastertes `UIImage`, egal ob der Server
/// PNG/JPG oder SVG ausliefert.
///
/// SVG wird über PocketSVG **einmal** in Pixel übersetzt und gecacht (Speicher und
/// Platte). Eine WebView pro Karte, wie `StudioImageView` sie für die große
/// Studio-Kachel nutzt, wäre in einem Grid nicht scrollbar.
actor StudioLogoStore {
    static let shared = StudioLogoStore()

    /// Rasterhöhe in Punkten. Karten zeigen das Logo 11 bis 14pt hoch; das
    /// Doppelte reicht auch auf 3x-Displays ohne sichtbare Unschärfe.
    static let rasterHeight: CGFloat = 28
    static let rasterMaxWidth: CGFloat = 600

    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    /// Schlüssel, für die es kein Logo gibt. Verhindert, dass jede Karte den
    /// Server erneut fragt.
    private var missing: Set<String> = []

    private init() {
        memory.countLimit = 400
    }

    func logo(for studio: SceneStudio) async -> UIImage? {
        guard studio.hasCustomImage else { return nil }
        return await image(studioId: studio.id, updatedAt: studio.updatedAt, height: Self.rasterHeight, maxWidth: Self.rasterMaxWidth)
    }

    /// Studio-Bild in beliebiger Rastergröße (Punkte); Studios View / Detail
    /// nutzen dieselbe Pipeline wie das Karten-Abzeichen, nur größer.
    func image(studioId: String, updatedAt: String?, height: CGFloat, maxWidth: CGFloat) async -> UIImage? {
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

    // MARK: Loading

    private static func diskKey(_ key: String) -> NSURL? {
        NSURL(string: "stashy-studio-logo://\(key)")
    }

    static func cacheKey(studioId: String, updatedAt: String?, height: CGFloat) -> String {
        "v6|\(studioId)|\(updatedAt ?? "")|\(Int(height))"
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
        // Rastern abseits des Main Threads — beim ersten Scrollen laden alle
        // sichtbaren Karten gleichzeitig ihr Logo.
        let rendered = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            // PNG/JPG direkt, sonst SVG.
            if let raster = UIImage(data: data) {
                return StudioLogoRasterizer.scaled(raster, height: height, maxWidth: maxWidth, scale: scale)
            }
            guard let text = String(data: data, encoding: .utf8),
                  contentType.contains("svg") || text.lowercased().contains("<svg") else {
                return nil
            }
            return StudioLogoRasterizer.rasterize(svg: text, height: height, maxWidth: maxWidth, scale: scale)
        }.value

        if let rendered, let diskKey = diskKey(key), let png = rendered.pngData() {
            ImageCache.shared.setData(png, forKey: diskKey)
        }
        return rendered
    }
}

extension SceneStudio {
    /// Ändert sich mit dem Studio-Bild (`updated_at`), damit ein neues Logo den
    /// Cache nicht überleben muss.
    var logoCacheKey: String {
        StudioLogoStore.cacheKey(studioId: id, updatedAt: updatedAt, height: StudioLogoStore.rasterHeight)
    }
}

// MARK: - Rasterizer

enum StudioLogoRasterizer {
    /// Skaliert ein Rasterbild auf die Badge-Höhe und schneidet vorher
    /// transparenten Rand weg — viele Logos kommen mit viel Luft drumherum und
    /// wirken sonst winzig im Abzeichen.
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

    /// SVG -> Pixel über PocketSVG. Zeichnet die Pfade direkt in den Kontext,
    /// skaliert auf ihre eigene Bounding Box (nicht die viewBox — die hat oft
    /// Rand). Gibt `nil` zurück, wenn das SVG Konstrukte nutzt, die PocketSVG
    /// nicht zuverlässig kann, oder wenn nichts Sichtbares herauskommt.
    static func rasterize(svg: String, height: CGFloat, maxWidth: CGFloat, scale: CGFloat) -> UIImage? {
        guard !StudioSVGSanitizer.containsUnsupportedConstructs(svg) else {
            AppLog.debug("StudioLogo: SVG skipped, unsupported construct (gradient/filter/mask/use)")
            return nil
        }
        let sanitized = StudioSVGSanitizer.sanitizeColors(in: svg)

        let paths = SVGBezierPath.paths(fromSVGString: sanitized)
        guard !paths.isEmpty else {
            AppLog.debug("StudioLogo: SVG produced no paths")
            return nil
        }

        let bounds = SVGBoundingRectForPaths(paths)
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0, bounds.width.isFinite, bounds.height.isFinite else { return nil }
        var box = bounds

        // Etwas großzügiger rastern (Strichbreiten ragen über die Pfad-Box hinaus),
        // der Rand wird danach wieder weggeschnitten.
        let inset = -max(box.width, box.height) * 0.02
        box = box.insetBy(dx: inset, dy: inset)

        let size = fit(box.size, height: height * 2, maxWidth: maxWidth * 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let raw = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.scaleBy(x: size.width / box.width, y: size.height / box.height)
            cg.translateBy(x: -box.minX, y: -box.minY)
            // `SVGDrawPaths` verschiebt um `rect.origin` und skaliert `rect.size`
            // gegen die Pfad-Bounds — zieht aber deren Ursprung nicht ab. Mit
            // Ursprung 0 und der Bounds-Größe ist sein Transform die Identität,
            // und nur die eigene CTM oben gilt.
            SVGDrawPathsWithBlock(paths, cg, CGRect(origin: .zero, size: bounds.size)) { path in
                // Wie `SVGLayer`: ohne `fill`-Attribut gilt Schwarz (SVG-Default).
                // `SVGDrawPaths` ließe solche Pfade einfach weg.
                let fill = (path.svgAttributes["fill"] as! CGColor?) ?? UIColor.black.cgColor
                if fill.alpha > 0 {
                    path.usesEvenOddFillRule = (path.svgAttributes["fill-rule"] as? String) == "evenodd"
                    UIColor(cgColor: fill).setFill()
                    path.fill()
                }
                if let stroke = path.svgAttributes["stroke"] as! CGColor?, stroke.alpha > 0 {
                    UIColor(cgColor: stroke).setStroke()
                    path.stroke()
                }
            }
        }
        guard let trimmed = trimmedToVisiblePixels(raw) else { return nil }
        return scaled(trimmed, height: height, maxWidth: maxWidth, scale: scale)
    }

    private static func fit(_ source: CGSize, height: CGFloat, maxWidth: CGFloat) -> CGSize {
        var size = CGSize(width: source.width / source.height * height, height: height)
        if size.width > maxWidth {
            size = CGSize(width: maxWidth, height: maxWidth * source.height / source.width)
        }
        return size
    }

    // MARK: Alpha trim

    /// Schneidet (fast) transparenten Rand weg — Schatten und Glows zählen
    /// nicht, sonst sitzt der Schriftzug klein in einer großen Box. `nil`, wenn
    /// das Bild keinen sichtbaren Pixel hat — dann zeigt das Abzeichen den Namen.
    static func trimmedToVisiblePixels(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return image }
        // Bounding Box auf einer kleinen Kopie suchen (max 256px Kante), reicht
        // für den Zuschnitt und bleibt billig.
        let sampleMax = 256
        let sw = min(cg.width, sampleMax)
        let sh = max(1, Int(CGFloat(cg.height) * CGFloat(sw) / CGFloat(cg.width)))
        let bytesPerRow = sw * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * sh)
        guard let ctx = CGContext(
            data: &pixels, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
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
        if minX == 0, minY == 0, maxX == sw - 1, maxY == sh - 1 { return image }

        let fx = CGFloat(cg.width) / CGFloat(sw)
        let fy = CGFloat(cg.height) / CGFloat(sh)
        let crop = CGRect(
            x: floor(CGFloat(minX) * fx), y: floor(CGFloat(minY) * fy),
            width: ceil(CGFloat(maxX - minX + 1) * fx), height: ceil(CGFloat(maxY - minY + 1) * fy)
        ).intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let cropped = cg.cropping(to: crop) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - SVG sanitizing

/// Zwilling von `TVStudioImageView` (tvOS): PocketSVG wirft bei nicht-hex Farben
/// und einigen Konstrukten ObjC-Exceptions, die Swift nicht fangen kann.
/// Lieber den Namen zeigen als crashen.
enum StudioSVGSanitizer {
    static func containsUnsupportedConstructs(_ svg: String) -> Bool {
        let lowered = svg.lowercased()
        let banned = [
            "<lineargradient", "<radialgradient", "<pattern",
            "<filter", "<mask", "<clippath", "<use ", "<symbol",
            "url(#"
        ]
        return banned.contains { lowered.contains($0) }
    }

    private static let colorAttributes = ["fill", "stroke", "stop-color", "flood-color", "lighting-color", "color"]

    static func sanitizeColors(in svg: String) -> String {
        var result = StudioSVGStyleInliner.inline(svg)
        currentColorHex = documentCurrentColor(in: svg)
        defer { currentColorHex = nil }
        for attr in colorAttributes {
            for quote in ["\"", "'"] {
                let pattern = "(?i)\\b\(attr)=\(quote)([^\(quote)]*)\(quote)"
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let ns = result as NSString
                for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
                    let valueRange = match.range(at: 1)
                    guard valueRange.location != NSNotFound else { continue }
                    let value = ns.substring(with: valueRange)
                    if !isSafeColorValue(value) {
                        let replacement = safeReplacement(for: value, attribute: attr)
                        result = (result as NSString).replacingCharacters(in: match.range, with: "\(attr)=\(quote)\(replacement)\(quote)")
                    }
                }
            }
        }
        if let styleRegex = try? NSRegularExpression(pattern: "(?i)style=\"([^\"]*)\"") {
            let ns = result as NSString
            for match in styleRegex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
                let valueRange = match.range(at: 1)
                guard valueRange.location != NSNotFound else { continue }
                let style = ns.substring(with: valueRange)
                let sanitized = sanitizeStyleDeclarations(style)
                if sanitized != style {
                    result = (result as NSString).replacingCharacters(in: match.range, with: "style=\"\(sanitized)\"")
                }
            }
        }
        return result
    }

    private static func sanitizeStyleDeclarations(_ style: String) -> String {
        style.split(separator: ";", omittingEmptySubsequences: true).map { part -> String in
            let kv = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { return String(part) }
            let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if colorAttributes.contains(key), !isSafeColorValue(value) {
                return "\(key):\(safeReplacement(for: value, attribute: key))"
            }
            return String(part)
        }.joined(separator: ";")
    }

    /// Was PocketSVG nicht kann, wird in Hex übersetzt statt gelöscht — ein
    /// Logo mit `fill="currentColor"` oder `rgb(...)` wäre sonst unsichtbar.
    /// Unbekannte Füllungen werden weiß (Abzeichen ist dunkel), Konturen fallen weg.
    private static func safeReplacement(for raw: String, attribute: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value == "currentcolor", let hex = currentColorHex { return hex }
        if let hex = hexFromCSSValue(value) { return hex }
        return attribute == "stroke" ? "none" : "#ffffff"
    }

    /// Wert des `color`-Attributs/-Styles auf dem Dokument, für `currentColor`.
    nonisolated(unsafe) private static var currentColorHex: String?

    private static func documentCurrentColor(in svg: String) -> String? {
        let patterns = ["(?i)\\bcolor=[\"']([^\"']+)[\"']", "(?i)[;\"']\\s*color\\s*:\\s*([^;\"']+)"]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: svg, range: NSRange(location: 0, length: (svg as NSString).length)) else { continue }
            let value = (svg as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if value == "currentcolor" { continue }
            if isSafeColorValue(value), value.hasPrefix("#") { return value }
            if let hex = hexFromCSSValue(value) { return hex }
        }
        return nil
    }

    /// `rgb()`, `rgba()`, `hsl()`, `hsla()`, 4/8-stellige Hex-Kurzformen und
    /// CSS-Farbnamen → 6-stelliges Hex. `nil`, wenn nicht lesbar.
    private static func hexFromCSSValue(_ value: String) -> String? {
        if let named = namedColors[value] { return named }
        if value.hasPrefix("#") {
            let hex = String(value.dropFirst())
            guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }
            switch hex.count {
            case 3, 4: return "#" + hex.prefix(3).map { "\($0)\($0)" }.joined()
            case 6: return "#" + hex
            case 8: return "#" + hex.prefix(6)
            default: return nil
            }
        }
        if value.hasPrefix("rgb") { return hexFromRGBFunction(value) }
        if value.hasPrefix("hsl") { return hexFromHSLFunction(value) }
        return nil
    }

    private static func functionArguments(_ value: String) -> [String]? {
        guard let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")") else { return nil }
        return value[value.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func hexFromHSLFunction(_ value: String) -> String? {
        guard let parts = functionArguments(value), parts.count >= 3,
              let h = Double(parts[0].replacingOccurrences(of: "deg", with: "")),
              let sPct = Double(parts[1].replacingOccurrences(of: "%", with: "")),
              let lPct = Double(parts[2].replacingOccurrences(of: "%", with: "")) else { return nil }
        let sat = sPct / 100, light = lPct / 100
        let c = (1 - abs(2 * light - 1)) * sat
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch hh {
        case ..<1: (r1, g1, b1) = (c, x, 0)
        case ..<2: (r1, g1, b1) = (x, c, 0)
        case ..<3: (r1, g1, b1) = (0, c, x)
        case ..<4: (r1, g1, b1) = (0, x, c)
        case ..<5: (r1, g1, b1) = (x, 0, c)
        default:   (r1, g1, b1) = (c, 0, x)
        }
        let m = light - c / 2
        let to255 = { (v: Double) in min(max(Int(((v + m) * 255).rounded()), 0), 255) }
        return String(format: "#%02x%02x%02x", to255(r1), to255(g1), to255(b1))
    }

    /// CSS-Farbnamen (Level 4).
    private static let namedColors: [String: String] = [
        "aliceblue": "#f0f8ff", "antiquewhite": "#faebd7", "aqua": "#00ffff", "aquamarine": "#7fffd4", "azure": "#f0ffff", "beige": "#f5f5dc",
        "bisque": "#ffe4c4", "black": "#000000", "blanchedalmond": "#ffebcd", "blue": "#0000ff", "blueviolet": "#8a2be2", "brown": "#a52a2a",
        "burlywood": "#deb887", "cadetblue": "#5f9ea0", "chartreuse": "#7fff00", "chocolate": "#d2691e", "coral": "#ff7f50", "cornflowerblue": "#6495ed",
        "cornsilk": "#fff8dc", "crimson": "#dc143c", "cyan": "#00ffff", "darkblue": "#00008b", "darkcyan": "#008b8b", "darkgoldenrod": "#b8860b",
        "darkgray": "#a9a9a9", "darkgreen": "#006400", "darkgrey": "#a9a9a9", "darkkhaki": "#bdb76b", "darkmagenta": "#8b008b", "darkolivegreen": "#556b2f",
        "darkorange": "#ff8c00", "darkorchid": "#9932cc", "darkred": "#8b0000", "darksalmon": "#e9967a", "darkseagreen": "#8fbc8f", "darkslateblue": "#483d8b",
        "darkslategray": "#2f4f4f", "darkslategrey": "#2f4f4f", "darkturquoise": "#00ced1", "darkviolet": "#9400d3", "deeppink": "#ff1493", "deepskyblue": "#00bfff",
        "dimgray": "#696969", "dimgrey": "#696969", "dodgerblue": "#1e90ff", "firebrick": "#b22222", "floralwhite": "#fffaf0", "forestgreen": "#228b22",
        "fuchsia": "#ff00ff", "gainsboro": "#dcdcdc", "ghostwhite": "#f8f8ff", "gold": "#ffd700", "goldenrod": "#daa520", "gray": "#808080",
        "green": "#008000", "greenyellow": "#adff2f", "grey": "#808080", "honeydew": "#f0fff0", "hotpink": "#ff69b4", "indianred": "#cd5c5c",
        "indigo": "#4b0082", "ivory": "#fffff0", "khaki": "#f0e68c", "lavender": "#e6e6fa", "lavenderblush": "#fff0f5", "lawngreen": "#7cfc00",
        "lemonchiffon": "#fffacd", "lightblue": "#add8e6", "lightcoral": "#f08080", "lightcyan": "#e0ffff", "lightgoldenrodyellow": "#fafad2", "lightgray": "#d3d3d3",
        "lightgreen": "#90ee90", "lightgrey": "#d3d3d3", "lightpink": "#ffb6c1", "lightsalmon": "#ffa07a", "lightseagreen": "#20b2aa", "lightskyblue": "#87cefa",
        "lightslategray": "#778899", "lightslategrey": "#778899", "lightsteelblue": "#b0c4de", "lightyellow": "#ffffe0", "lime": "#00ff00", "limegreen": "#32cd32",
        "linen": "#faf0e6", "magenta": "#ff00ff", "maroon": "#800000", "mediumaquamarine": "#66cdaa", "mediumblue": "#0000cd", "mediumorchid": "#ba55d3",
        "mediumpurple": "#9370db", "mediumseagreen": "#3cb371", "mediumslateblue": "#7b68ee", "mediumspringgreen": "#00fa9a", "mediumturquoise": "#48d1cc", "mediumvioletred": "#c71585",
        "midnightblue": "#191970", "mintcream": "#f5fffa", "mistyrose": "#ffe4e1", "moccasin": "#ffe4b5", "navajowhite": "#ffdead", "navy": "#000080",
        "oldlace": "#fdf5e6", "olive": "#808000", "olivedrab": "#6b8e23", "orange": "#ffa500", "orangered": "#ff4500", "orchid": "#da70d6",
        "palegoldenrod": "#eee8aa", "palegreen": "#98fb98", "paleturquoise": "#afeeee", "palevioletred": "#db7093", "papayawhip": "#ffefd5", "peachpuff": "#ffdab9",
        "peru": "#cd853f", "pink": "#ffc0cb", "plum": "#dda0dd", "powderblue": "#b0e0e6", "purple": "#800080", "rebeccapurple": "#663399",
        "red": "#ff0000", "rosybrown": "#bc8f8f", "royalblue": "#4169e1", "saddlebrown": "#8b4513", "salmon": "#fa8072", "sandybrown": "#f4a460",
        "seagreen": "#2e8b57", "seashell": "#fff5ee", "sienna": "#a0522d", "silver": "#c0c0c0", "skyblue": "#87ceeb", "slateblue": "#6a5acd",
        "slategray": "#708090", "slategrey": "#708090", "snow": "#fffafa", "springgreen": "#00ff7f", "steelblue": "#4682b4", "tan": "#d2b48c",
        "teal": "#008080", "thistle": "#d8bfd8", "tomato": "#ff6347", "turquoise": "#40e0d0", "violet": "#ee82ee", "wheat": "#f5deb3",
        "white": "#ffffff", "whitesmoke": "#f5f5f5", "yellow": "#ffff00", "yellowgreen": "#9acd32",
    ]

    private static func hexFromRGBFunction(_ value: String) -> String? {
        guard let parts = functionArguments(value), parts.count >= 3 else { return nil }
        let channels: [Int] = parts.prefix(3).compactMap { part in
            if part.hasSuffix("%"), let pct = Double(part.dropLast()) { return Int((pct / 100 * 255).rounded()) }
            if let v = Double(part) { return Int(v.rounded()) }
            return nil
        }
        guard channels.count == 3 else { return nil }
        return String(format: "#%02x%02x%02x", min(max(channels[0], 0), 255), min(max(channels[1], 0), 255), min(max(channels[2], 0), 255))
    }

    private static func isSafeColorValue(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty { return false }
        if value == "none" || value == "transparent" || value == "inherit" { return true }
        guard value.hasPrefix("#") else { return false }
        let hex = value.dropFirst()
        return [3, 6, 8].contains(hex.count) && hex.allSatisfy { $0.isHexDigit }
    }
}

// MARK: - CSS inlining

/// PocketSVG kennt keine `<style>`-Blöcke. Illustrator/Inkscape exportieren
/// Farben aber fast immer so (`.cls-1{fill:#fff}` + `class="cls-1"`), und ohne
/// Auflösung wird jede Fläche schwarz. Hier werden Klassen-, Element- und
/// ID-Regeln als Attribute an die Elemente geschrieben (nur wenn das Element
/// das Attribut nicht schon selbst setzt; `style=""` gewinnt weiterhin).
enum StudioSVGStyleInliner {
    private static let handled = ["fill", "stroke", "stroke-width", "fill-opacity", "stroke-opacity", "opacity", "fill-rule", "color"]

    private struct Rule {
        enum Target { case cls(String), id(String), tag(String), any }
        let target: Target
        let declarations: [(String, String)]
    }

    static func inline(_ svg: String) -> String {
        let styleRegex = try? NSRegularExpression(pattern: "(?is)<style[^>]*>(.*?)</style>")
        let ns = svg as NSString
        let matches = styleRegex?.matches(in: svg, range: NSRange(location: 0, length: ns.length)) ?? []
        guard !matches.isEmpty else { return svg }

        var rules: [Rule] = []
        for match in matches {
            rules.append(contentsOf: parseRules(ns.substring(with: match.range(at: 1))))
        }
        guard !rules.isEmpty else { return svg }

        // Style-Blöcke entfernen (PocketSVG stolpert sonst über CDATA-Inhalt).
        var result = svg
        for match in matches.reversed() {
            result = (result as NSString).replacingCharacters(in: match.range, with: "")
        }

        guard let tagRegex = try? NSRegularExpression(pattern: "<([a-zA-Z][a-zA-Z0-9]*)\\b([^>]*?)(/?)>") else { return result }
        let rns = result as NSString
        var out = result
        for match in tagRegex.matches(in: result, range: NSRange(location: 0, length: rns.length)).reversed() {
            let tag = rns.substring(with: match.range(at: 1)).lowercased()
            if ["svg", "style", "defs", "title", "desc", "metadata"].contains(tag) { continue }
            let attrs = rns.substring(with: match.range(at: 2))
            let classes = attributeValue("class", in: attrs)?.split(separator: " ").map(String.init) ?? []
            let id = attributeValue("id", in: attrs)

            var declarations: [String: String] = [:]
            for rule in rules {
                let applies: Bool
                switch rule.target {
                case .any: applies = true
                case .tag(let t): applies = t == tag
                case .cls(let c): applies = classes.contains(c)
                case .id(let i): applies = i == id
                }
                guard applies else { continue }
                for (key, value) in rule.declarations { declarations[key] = value }
            }
            guard !declarations.isEmpty else { continue }

            var additions = ""
            for (key, value) in declarations where attributeValue(key, in: attrs) == nil {
                additions += " \(key)=\"\(value)\""
            }
            guard !additions.isEmpty else { continue }
            let selfClosing = rns.substring(with: match.range(at: 3))
            let rebuilt = "<\(rns.substring(with: match.range(at: 1)))\(attrs)\(additions)\(selfClosing)>"
            out = (out as NSString).replacingCharacters(in: match.range, with: rebuilt)
        }
        return out
    }

    private static func parseRules(_ css: String) -> [Rule] {
        var cleaned = css.replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
        if let comments = try? NSRegularExpression(pattern: "(?s)/\\*.*?\\*/") {
            cleaned = comments.stringByReplacingMatches(in: cleaned, range: NSRange(location: 0, length: (cleaned as NSString).length), withTemplate: "")
        }
        guard let ruleRegex = try? NSRegularExpression(pattern: "([^{}]+)\\{([^}]*)\\}") else { return [] }
        let ns = cleaned as NSString
        var rules: [Rule] = []
        for match in ruleRegex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length)) {
            let selectors = ns.substring(with: match.range(at: 1)).split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let body = ns.substring(with: match.range(at: 2))
            let declarations: [(String, String)] = body.split(separator: ";").compactMap { part in
                let kv = part.split(separator: ":", maxSplits: 1)
                guard kv.count == 2 else { return nil }
                let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                var value = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
                value = value.replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces)
                guard handled.contains(key), !value.isEmpty else { return nil }
                return (key, value)
            }
            guard !declarations.isEmpty else { continue }
            for selector in selectors {
                // Nur einfache Selektoren: `.cls-1`, `#id`, `path`, `path.cls-1`, `*`.
                // Kombinatoren (`g > path`) werden auf ihr letztes Glied reduziert.
                let last = selector.split(whereSeparator: { $0 == " " || $0 == ">" }).last.map(String.init) ?? selector
                if last == "*" {
                    rules.append(Rule(target: .any, declarations: declarations))
                } else if let dot = last.firstIndex(of: ".") {
                    rules.append(Rule(target: .cls(String(last[last.index(after: dot)...])), declarations: declarations))
                } else if last.hasPrefix("#") {
                    rules.append(Rule(target: .id(String(last.dropFirst())), declarations: declarations))
                } else if last.allSatisfy({ $0.isLetter || $0.isNumber }) {
                    rules.append(Rule(target: .tag(last.lowercased()), declarations: declarations))
                }
            }
        }
        return rules
    }

    private static func attributeValue(_ name: String, in attrs: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(?i)(?:^|\\s)\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*[\"']([^\"']*)[\"']") else { return nil }
        let ns = attrs as NSString
        guard let match = regex.firstMatch(in: attrs, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
#endif
