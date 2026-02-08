
import SwiftUI

struct SceneTagsCard: View {
    let tags: [Tag]?
    @Binding var isTagsExpanded: Bool
    @Binding var tagsTotalHeight: CGFloat
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    private let collapsedHeight: CGFloat = 68 // Exakt 2 Zeilen
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            
            VStack(alignment: .trailing, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    if let tags = tags {
                        WrappedHStack(items: tags) { tag in
                            NavigationLink(destination: TagDetailView(selectedTag: tag)) {
                                 Text(tag.name)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(appearanceManager.tintColor.opacity(0.1))
                                    .foregroundColor(appearanceManager.tintColor)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(appearanceManager.tintColor, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear.onAppear {
                                    tagsTotalHeight = geo.size.height
                                }
                                .onChange(of: geo.size.height) { old, newValue in
                                    tagsTotalHeight = newValue
                                }
                            }
                        )
                    }
                }
                .frame(maxHeight: isTagsExpanded ? .none : collapsedHeight, alignment: .topLeading)
                .clipped()
                
                if tagsTotalHeight > collapsedHeight {
                    Button(action: {
                        withAnimation(.spring()) {
                            isTagsExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isTagsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(appearanceManager.tintColor)
                            .padding(6)
                            .background(appearanceManager.tintColor.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}
