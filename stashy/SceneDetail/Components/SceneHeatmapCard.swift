
#if !os(tvOS)
import SwiftUI

struct SceneHeatmapCard: View {
    let heatmapURL: URL
    let durationSeconds: Double
    let currentTimeSeconds: Double
    let onSeek: (Double) -> Void
    @ObservedObject var appearanceManager = AppearanceManager.shared

    private let heatmapHeight: CGFloat = 120
    private let contentPadding: CGFloat = 12
    private let widthPerMinute: CGFloat = 40

    @State private var didInitialScroll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Interactive Heatmap")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, contentPadding)
                .padding(.top, 8)

            GeometryReader { proxy in
                let baseWidth = max(timelineWidth, 1)
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: proxy.size.width / 2)

                            ZStack(alignment: .topLeading) {
                                heatmapLine(width: baseWidth, height: heatmapHeight)

                                Rectangle()
                                    .fill(appearanceManager.tintColor)
                                    .frame(width: 2, height: heatmapHeight)
                                    .position(x: markerX(baseWidth: baseWidth), y: heatmapHeight / 2)

                                Circle()
                                    .fill(appearanceManager.tintColor)
                                    .frame(width: 8, height: 8)
                                    .position(x: markerX(baseWidth: baseWidth), y: 8)

                                Color.clear
                                    .frame(width: 1, height: 1)
                                    .position(x: markerX(baseWidth: baseWidth), y: heatmapHeight / 2)
                                    .id("heatmap-marker")
                            }
                            .frame(width: baseWidth, height: heatmapHeight)
                            .contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        guard durationSeconds > 0 else { return }
                                        let x = min(max(0, value.location.x), baseWidth)
                                        let fraction = baseWidth > 0 ? x / baseWidth : 0
                                        onSeek(durationSeconds * fraction)
                                    }
                            )

                            Color.clear
                                .frame(width: proxy.size.width / 2)
                        }
                        .padding(.horizontal, contentPadding)
                    }
                    .onAppear {
                        if !didInitialScroll {
                            scrollProxy.scrollTo("heatmap-marker", anchor: .center)
                            didInitialScroll = true
                        }
                    }
                    .onChange(of: currentTimeSeconds) { _, _ in
                        scrollProxy.scrollTo("heatmap-marker", anchor: .center)
                    }
                }
            }
            .frame(height: heatmapHeight)
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }

    private var timelineWidth: CGFloat {
        let minutes = max(durationSeconds / 60.0, 1)
        return CGFloat(minutes) * widthPerMinute
    }

    private func markerX(baseWidth: CGFloat) -> CGFloat {
        guard durationSeconds > 0 else { return 0 }
        let clampedTime = min(max(currentTimeSeconds, 0), durationSeconds)
        return baseWidth * CGFloat(clampedTime / durationSeconds)
    }

    private func heatmapLine(width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: height / 2))
            path.addLine(to: CGPoint(x: width, y: height / 2))
        }
        .stroke(appearanceManager.tintColor.opacity(0.6), lineWidth: 3)
    }
}
#endif
