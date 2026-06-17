import SwiftUI
import PocketSVG
import UIKit

/// tvOS studio image view with hybrid support (PNG/JPG + SVG).
struct TVStudioImageView: View {
    let studioId: String
    let studioName: String
    var contentMode: ContentMode = .fit

    @State private var imageLoadState: ImageLoadState = .loading

    enum ImageLoadState {
        case loading
        case success(Image)
        case successSVG(String)
        case failure
    }

    private var imageURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return URL(string: "\(config.baseURL)/studio/\(studioId)/image")
    }

    var body: some View {
        Group {
            switch imageLoadState {
            case .loading:
                Rectangle()
                    .fill(Color.gray.opacity(0.08))
                    .overlay(ProgressView().scaleEffect(0.9))

            case .success(let image):
                if contentMode == .fill {
                    image.resizable().scaledToFill()
                } else {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

            case .successSVG(let svgString):
                TVPocketSVGView(svgString: svgString, contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failure:
                placeholderView
            }
        }
        .task {
            await loadImage()
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.08))
            .overlay(
                Image(systemName: "building.2.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.12))
            )
    }

    private func loadImage() async {
        guard let url = imageURL else {
            imageLoadState = .failure
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30.0

            if let config = ServerConfigManager.shared.loadConfig(),
               let apiKey = config.secureApiKey, !apiKey.isEmpty {
                request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                imageLoadState = .failure
                return
            }

            // 1) PNG/JPG/etc.
            if let uiImage = UIImage(data: data) {
                imageLoadState = .success(Image(uiImage: uiImage))
                return
            }

            // 2) SVG
            let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
            let dataString = String(data: data, encoding: .utf8) ?? ""
            let isSVGHeader = contentType?.lowercased().contains("svg") == true
            let isSVGContent = dataString.lowercased().contains("<svg")

            if (isSVGHeader || isSVGContent), !dataString.isEmpty {
                // PocketSVG (SVGEngine.mm) wirft `NSAssertionHandler`-NSExceptions bei
                // nicht-hex Farbwerten (rgb()/named/currentColor/leer) und kann
                // bei Gradients/Patterns/Use/Mask abstürzen. Swift kann ObjC-Exceptions
                // NICHT mit do/catch fangen → SIGABRT. Deshalb hier hart präventiv:
                //   1) Konstrukte ablehnen, die PocketSVG nicht zuverlässig kann
                //   2) Farbattribute auf #RRGGBB/none/transparent normalisieren
                if Self.svgContainsUnsupportedConstructs(dataString) {
                    imageLoadState = .failure
                    return
                }
                let sanitized = Self.sanitizeSVGColors(in: dataString)
                imageLoadState = .successSVG(sanitized)
                return
            }

            imageLoadState = .failure
        } catch {
            imageLoadState = .failure
        }
    }

    // MARK: - SVG Defensive Sanitization

    /// PocketSVG hat keine vollständige Unterstützung für diese Konstrukte; einige
    /// von ihnen lösen die NSException in `hexTriplet` oder andere Asserts aus.
    /// Lieber Placeholder anzeigen als crashen.
    private static func svgContainsUnsupportedConstructs(_ svg: String) -> Bool {
        let lowered = svg.lowercased()
        let banned = [
            "<lineargradient", "<radialgradient", "<pattern",
            "<filter", "<mask", "<clippath", "<use ", "<symbol",
            "url(#" // jegliche paint-server Referenzen
        ]
        for needle in banned where lowered.contains(needle) {
            return true
        }
        return false
    }

    /// Ersetzt unsichere Farbwerte in den relevanten Attributen durch `none`.
    /// Erlaubt bleiben: `#RGB`, `#RRGGBB`, `none`, `transparent`, `inherit`.
    private static func sanitizeSVGColors(in svg: String) -> String {
        var result = svg
        let attributes = ["fill", "stroke", "stop-color", "flood-color", "lighting-color", "color"]
        for attr in attributes {
            // attr="value"   und   attr='value'
            for quote in ["\"", "'"] {
                let pattern = "(?i)\\b\(attr)=\(quote)([^\(quote)]*)\(quote)"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
                let ns = result as NSString
                let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: ns.length))
                for match in matches.reversed() {
                    let valueRange = match.range(at: 1)
                    guard valueRange.location != NSNotFound else { continue }
                    let value = ns.substring(with: valueRange).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !isSafeColorValue(value) {
                        result = (result as NSString).replacingCharacters(in: match.range, with: "\(attr)=\(quote)none\(quote)")
                    }
                }
            }
        }
        // Auch CSS in style="…": fill:rgb(255,0,0) etc.
        if let styleRegex = try? NSRegularExpression(pattern: "(?i)style=\"([^\"]*)\"", options: []) {
            let ns = result as NSString
            let matches = styleRegex.matches(in: result, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
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
        let parts = style.split(separator: ";", omittingEmptySubsequences: true)
        var rebuilt: [String] = []
        for part in parts {
            let kv = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { rebuilt.append(String(part)); continue }
            let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if ["fill", "stroke", "stop-color", "flood-color", "lighting-color", "color"].contains(key) {
                if !isSafeColorValue(value) {
                    rebuilt.append("\(key):none")
                    continue
                }
            }
            rebuilt.append(String(part))
        }
        return rebuilt.joined(separator: ";")
    }

    private static func isSafeColorValue(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty { return false }
        if value == "none" || value == "transparent" || value == "inherit" { return true }
        if value.hasPrefix("#") {
            let hex = value.dropFirst()
            if hex.count == 3 || hex.count == 6 || hex.count == 8 {
                return hex.allSatisfy { $0.isHexDigit }
            }
            return false
        }
        return false
    }
}

private struct TVPocketSVGView: UIViewRepresentable {
    let svgString: String
    let contentMode: ContentMode

    func makeUIView(context: Context) -> SVGImageView {
        let view = SVGImageView()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.contentMode = (contentMode == .fill) ? .scaleAspectFill : .scaleAspectFit
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.layer.contentsGravity = (contentMode == .fill) ? .resizeAspectFill : .resizeAspect
        return view
    }

    func updateUIView(_ uiView: SVGImageView, context: Context) {
        uiView.contentMode = (contentMode == .fill) ? .scaleAspectFill : .scaleAspectFit
        uiView.layer.contentsGravity = (contentMode == .fill) ? .resizeAspectFill : .resizeAspect
        uiView.paths = SVGBezierPath.paths(fromSVGString: svgString)
        // Force a layout pass so the layer scales to the SwiftUI-provided bounds.
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        uiView.setNeedsDisplay()
    }
}
