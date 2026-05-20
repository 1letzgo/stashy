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
                imageLoadState = .successSVG(dataString)
                return
            }

            imageLoadState = .failure
        } catch {
            imageLoadState = .failure
        }
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
        uiView.paths = SVGBezierPath.paths(fromSVGString: Self.sanitizeSVGColors(svgString))
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        uiView.setNeedsDisplay()
    }

    // PocketSVG's hexTriplet parser only handles named SVG colors, #hex, and rgb().
    // It crashes on rgba(), currentColor, transparent, inherit, url(), hsl(), etc.
    static func sanitizeSVGColors(_ svg: String) -> String {
        var result = svg
        result = result.replacingOccurrences(
            of: #"rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*[\d.]+\s*\)"#,
            with: "rgb($1,$2,$3)",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"hsla?\([^)]*\)"#,
            with: "#000000",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"url\([^)]*\)"#,
            with: "none",
            options: .regularExpression
        )
        let keywords = ["transparent", "currentColor", "currentcolor", "inherit"]
        for keyword in keywords {
            result = result.replacingOccurrences(of: keyword, with: keyword == "transparent" ? "none" : "#000000")
        }
        return result
    }
}
