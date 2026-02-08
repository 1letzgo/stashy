
import SwiftUI

struct TestFlightNoticeCard: View {
    @Environment(\.openURL) var openURL
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "apple.logo")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
            
            // Text
            VStack(alignment: .leading, spacing: 0) {
                Text("Support Stashy")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text("Official App Store Release")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .layoutPriority(1)
            
            Spacer(minLength: 4)
            
            // Button
            Button {
                if let url = URL(string: "https://apps.apple.com/us/app/stashy/id6754876029") {
                    openURL(url)
                }
            } label: {
                Text("VIEW")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.button)
                .fill(LinearGradient(
                    colors: [Color.blue, Color.purple.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}
