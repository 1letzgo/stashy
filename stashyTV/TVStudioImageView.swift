import SwiftUI

/// tvOS studio image (PNG/JPG/SVG) via the shared `StudioLogoStore`: rendered once
/// with SwiftDraw, then served from memory/disk cache. Same pipeline as iOS.
struct TVStudioImageView: View {
    let studioId: String
    let studioName: String
    var contentMode: ContentMode = .fit
    /// The studio's `image_path` when known. Stash answers a studio without a logo
    /// with a generic white camera (`…&default=true`); like iOS, show our own glyph then.
    var imagePath: String? = nil
    /// Height of the logo in a title line (studio detail header). Set, the view shows the
    /// logo at this height and its own width, and nothing at all while loading or when the
    /// studio has none: no placeholder box next to the name.
    var titleLogoHeight: CGFloat? = nil

    @State private var imageLoadState: ImageLoadState = .loading
    /// Width ÷ height of the loaded logo, for the title-line size.
    @State private var logoAspect: CGFloat = 1

    enum ImageLoadState {
        case loading
        case success(Image)
        case failure
    }

    /// Hero in the studio detail is the largest consumer (16:9, full width).
    private static let rasterHeight: CGFloat = 360
    private static let rasterMaxWidth: CGFloat = 1080

    var body: some View {
        Group {
            if let titleLogoHeight {
                titleLogo(height: titleLogoHeight)
            } else {
                standardBody
            }
        }
        .task(id: "\(studioId)|\(imagePath ?? "")") {
            await loadImage()
        }
    }

    @ViewBuilder
    private func titleLogo(height: CGFloat) -> some View {
        if case .success(let image) = imageLoadState {
            image
                .resizable()
                .scaledToFit()
                .frame(width: min(height * 4, height * logoAspect), height: height)
                // The gap to the name belongs to the logo: without one there is no gap.
                .padding(.trailing, 24)
        } else {
            // Zero-sized but present, so `.task` above still runs.
            Color.clear.frame(width: 0, height: 0)
        }
    }

    @ViewBuilder
    private var standardBody: some View {
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

            case .failure:
                placeholderView
            }
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.08))
            .overlay(
                Image(systemName: "building.2.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
            )
    }

    private func loadImage() async {
        if imagePath?.contains("default=true") == true {
            imageLoadState = .failure
            return
        }
        // No `updated_at` at the tvOS call sites; the cache is server-scoped with a
        // 30-day TTL and clears from Settings, which is enough for a studio logo.
        if let image = await StudioLogoStore.shared.image(
            studioId: studioId, updatedAt: nil,
            height: Self.rasterHeight, maxWidth: Self.rasterMaxWidth
        ) {
            if image.size.height > 0 { logoAspect = image.size.width / image.size.height }
            imageLoadState = .success(Image(uiImage: image))
        } else {
            imageLoadState = .failure
        }
    }
}
