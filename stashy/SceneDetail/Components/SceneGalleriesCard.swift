
import SwiftUI

struct SceneGalleriesCard: View {
    let galleries: [Gallery]?
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Galleries")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if let galleries = galleries, !galleries.isEmpty {
                WrappedHStack(items: galleries) { gallery in
                    NavigationLink(destination: ImagesView(gallery: gallery)) {
                        HStack(spacing: 6) {
                            if let url = gallery.coverURL {
                                CustomAsyncImage(url: url) { loader in
                                    if let image = loader.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 32, height: 32)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "photo.on.rectangle")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 14, height: 14)
                                            .foregroundColor(appearanceManager.tintColor.opacity(0.5))
                                            .frame(width: 32, height: 32)
                                            .background(appearanceManager.tintColor.opacity(0.1))
                                            .clipShape(Circle())
                                    }
                                }
                            } else {
                                Image(systemName: "photo.on.rectangle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                    .foregroundColor(appearanceManager.tintColor.opacity(0.5))
                                    .frame(width: 32, height: 32)
                                    .background(appearanceManager.tintColor.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            
                            Text(gallery.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            
                            if let count = gallery.imageCount {
                                Text("\(count)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(appearanceManager.tintColor.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.trailing, 10)
                        .padding(.vertical, 4)
                        .padding(.leading, 4)
                        .background(appearanceManager.tintColor.opacity(0.1))
                        .foregroundColor(appearanceManager.tintColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else {
                Text("No linked galleries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}
