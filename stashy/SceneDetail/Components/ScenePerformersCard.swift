
import SwiftUI

struct ScenePerformersCard: View {
    let performers: [ScenePerformer]
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performers")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            VStack(spacing: 12) {
                ForEach(performers.sorted { $0.name < $1.name }) { scenePerformer in
                    NavigationLink(destination: PerformerDetailView(performer: scenePerformer.toPerformer())) {
                        ZStack(alignment: .bottom) {
                            // Thumbnail Circle
                            ZStack {
                                if let url = scenePerformer.thumbnailURL {
                                     CustomAsyncImage(url: url) { loader in
                                         if let image = loader.image {
                                             image
                                                 .resizable()
                                                 .scaledToFill()
                                                 .frame(width: 80, height: 80, alignment: .top)
                                                 .clipShape(Circle())
                                         } else {
                                             Circle()
                                                 .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                                 .frame(width: 80, height: 80)
                                                 .skeleton()
                                         }
                                     }
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .frame(width: 80, height: 80)
                                        .foregroundColor(appearanceManager.tintColor.opacity(0.4))
                                }
                            }
                            .padding(4)
                            .background(appearanceManager.tintColor)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(appearanceManager.tintColor.opacity(0.1), lineWidth: 0.2))
                            
                            // Name Pill Overlaid at Bottom
                            Text(scenePerformer.name)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    ZStack {
                                        Color(UIColor.systemBackground)
                                        appearanceManager.tintColor.opacity(0.1)
                                    }
                                )
                                .foregroundColor(appearanceManager.tintColor)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(appearanceManager.tintColor, lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                .offset(y: 8) // Push it slightly over the bottom edge
                        }
                        .padding(.bottom, 8) // Make room for the offset name
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}
