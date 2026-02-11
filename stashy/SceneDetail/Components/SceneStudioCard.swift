
#if !os(tvOS)
import SwiftUI

struct SceneStudioCard: View {
    let studio: SceneStudio
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Studio")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            VStack {
                NavigationLink(destination: StudioDetailView(studio: studio.toStudio())) {
                    studioCardContent
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
    
    private var studioCardContent: some View {
        ZStack(alignment: .bottom) {
            // Studio Logo (Rounded Rectangle)
            ZStack {
                StudioImageView(studio: studio.toStudio())
                    .padding(8)
            }
            .frame(width: 110, height: 88)
            .background(appearanceManager.tintColor)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card).stroke(appearanceManager.tintColor.opacity(0.1), lineWidth: 0.2))
            
            // Name Pill Overlaid at Bottom
            Text(studio.name)
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
                .offset(y: 8)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}
#endif

