
#if !os(tvOS)
import SwiftUI

struct SceneDirectorCard: View {
    let director: String
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Director")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            NavigationLink(destination: DirectorDetailView(director: director)) {
                directorCardContent
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }

    private var directorCardContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "megaphone.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(appearanceManager.tintColor)
                .frame(width: 36, height: 36)
                .background(appearanceManager.tintColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))

            Text(director)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                Color.secondaryAppBackground
                appearanceManager.tintColor.opacity(0.08)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(appearanceManager.tintColor.opacity(0.3), lineWidth: 0.5)
        )
    }
}
#endif
