import SwiftUI

/// tvOS studio image (PNG/JPG/SVG) via the shared `StudioLogoStore`: rendered once
/// with SwiftDraw, then served from memory/disk cache. Same pipeline as iOS.
struct TVStudioImageView: View {
    let studioId: String
    let studioName: String
    var contentMode: ContentMode = .fit

    @State private var imageLoadState: ImageLoadState = .loading

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
        .task(id: studioId) {
            await loadImage()
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
        // No `updated_at` at the tvOS call sites; the cache is server-scoped with a
        // 30-day TTL and clears from Settings, which is enough for a studio logo.
        if let image = await StudioLogoStore.shared.image(
            studioId: studioId, updatedAt: nil,
            height: Self.rasterHeight, maxWidth: Self.rasterMaxWidth
        ) {
            imageLoadState = .success(Image(uiImage: image))
        } else {
            imageLoadState = .failure
        }
    }
}
