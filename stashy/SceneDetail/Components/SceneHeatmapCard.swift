
#if !os(tvOS)
import SwiftUI

struct SceneHeatmapCard: View {
    let heatmapURL: URL?
    let funscriptURL: URL?
    let durationSeconds: Double
    let currentTimeSeconds: Double
    let onSeek: (Double) -> Void
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var handyManager = HandyManager.shared
    @ObservedObject var buttplugManager = ButtplugManager.shared
    @ObservedObject var loveSpouseManager = LoveSpouseManager.shared

    private let cardHeight: CGFloat = 140
    private let heatmapHeight: CGFloat = 80
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Interactive")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                if let funscriptURL = funscriptURL {
                    HStack(spacing: 8) {
                        // The Handy Button
                        if handyManager.isEnabled {
                            Button {
                                handyManager.setupScene(funscriptURL: funscriptURL)
                                HapticManager.medium()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: handyManager.isSyncing ? "hand.tap.fill" : "hand.tap")
                                    Text(handyManager.isSyncing ? "Ready" : "TheHandy")
                                }
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(handyManager.isSyncing ? .white : appearanceManager.tintColor)
                                .padding(.horizontal, 8)
                                .frame(minWidth: 92, minHeight: 28)
                                .background(handyManager.isSyncing ? Color.green : appearanceManager.tintColor.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                        
                        // Intiface Button
                        if buttplugManager.isEnabled {
                            Button {
                                buttplugManager.connect()
                                HapticManager.medium()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: buttplugManager.isConnected ? "cable.connector.fill" : "cable.connector")
                                    Text(buttplugManager.isConnected ? "Ready" : "Intiface")
                                }
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(buttplugManager.isConnected ? .white : appearanceManager.tintColor)
                                .padding(.horizontal, 8)
                                .frame(minWidth: 92, minHeight: 28)
                                .background(buttplugManager.isConnected ? Color.green : appearanceManager.tintColor.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                        
                        // Love Spouse Button
                        if loveSpouseManager.isEnabled {
                            Button {
                                if loveSpouseManager.isSyncing {
                                    loveSpouseManager.stop()
                                } else {
                                    loveSpouseManager.setupScene(funscriptURL: funscriptURL)
                                }
                                HapticManager.medium()
                            } label: {
                                let isSyncing = loveSpouseManager.isSyncing
                                HStack(spacing: 4) {
                                    Image(systemName: isSyncing ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right")
                                    Text(isSyncing ? "SYNC ON" : "Love Spouse")
                                }
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(isSyncing ? .white : appearanceManager.tintColor)
                                .padding(.horizontal, 8)
                                .frame(minWidth: 92, minHeight: 28)
                                .background(isSyncing ? Color.green : appearanceManager.tintColor.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                    }
                } else {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(appearanceManager.tintColor)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 0)

            GeometryReader { proxy in
                let width = proxy.size.width
                
                ZStack(alignment: .leading) {
                    // Background Track
                    Rectangle()
                        .fill(Color(UIColor.systemGray6))
                        .frame(height: heatmapHeight)
                    
                    // 1. Time Markers (Grid lines) - Background layer
                    timeMarkers(width: width)
                    
                    // 2. Base Heatmap (Inactive part)
                    heatmapLayer(width: width)
                        .opacity(0.15)
                    
                    // 3. Highlighted Heatmap (Active part)
                    heatmapLayer(width: width)
                        .mask(
                            HStack(spacing: 0) {
                                Rectangle()
                                    .frame(width: width * progress)
                                Spacer(minLength: 0)
                            }
                        )
                    
                    // 4. Playhead
                    playhead
                        .offset(x: width * progress)
                }
                .frame(width: width, height: heatmapHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = value.location.x / width
                            onSeek(durationSeconds * Double(min(max(fraction, 0), 1)))
                        }
                )
            }
            .frame(height: heatmapHeight + 30) // Extra space for labels at bottom
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }

    private var progress: CGFloat {
        guard durationSeconds > 0 else { return 0 }
        return CGFloat(min(max(currentTimeSeconds, 0), durationSeconds) / durationSeconds)
    }

    @ViewBuilder
    private func heatmapLayer(width: CGFloat) -> some View {
        if let url = heatmapURL {
            CustomAsyncImage(url: url) { loader in
                if let image = loader.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: heatmapHeight)
                        .clipped()
                } else {
                    Color.clear
                }
            }
        } else {
            // Placeholder when no heatmap is available
            ZStack {
                Rectangle().fill(Color.gray.opacity(0.1))
                Text("No Heatmap")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: width, height: heatmapHeight)
        }
    }

    @ViewBuilder
    private func timeMarkers(width: CGFloat) -> some View {
        // Show start, end and 3 intermediate points
        let positions: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        
        ZStack(alignment: .leading) {
            ForEach(positions, id: \.self) { pos in
                let x = width * CGFloat(pos)
                let time = durationSeconds * pos
                
                VStack(alignment: .leading, spacing: 12) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1, height: heatmapHeight)
                    
                    Text(formatTime(time))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        // Align text so it doesn't go off screen
                        .fixedSize()
                        .offset(x: pos == 1.0 ? -25 : (pos == 0 ? 0 : -10))
                }
                .offset(x: x)
            }
        }
    }

    private var playhead: some View {
        ZStack {
            // Main line
            Rectangle()
                .fill(appearanceManager.tintColor)
                .frame(width: 2, height: heatmapHeight + 4)
            
            // Indicator knob
            Circle()
                .fill(appearanceManager.tintColor)
                .frame(width: 10, height: 10)
                .offset(y: -(heatmapHeight/2 + 2))
                .shadow(color: appearanceManager.tintColor.opacity(0.4), radius: 3)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let seconds = max(seconds, 0)
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
#endif
