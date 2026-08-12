#if !os(tvOS)
import AVFoundation
import SwiftUI

enum SceneTeleprompterMetrics {
    static let renderedLinesBeforeCenter = 6
    static var renderedLineCount: Int { renderedLinesBeforeCenter * 2 + 1 }
    static let defaultLineSpacing: CGFloat = 2
    static let lineHeightFactor: CGFloat = 1.25
    static let defaultFontSize: CGFloat = 20
    static let inactiveLineTextOpacity: CGFloat = 0.32
    static let activeLineTextOpacity: CGFloat = 0.7

    static func layout(height: CGFloat) -> (slotHeight: CGFloat, fontSize: CGFloat, rowStride: CGFloat) {
        let gaps = CGFloat(renderedLineCount - 1)
        let fit = max(14, (height - gaps * defaultLineSpacing) / (CGFloat(renderedLineCount) * lineHeightFactor))
        let fontSize = min(28, fit)
        let slotHeight = ceil(fontSize * lineHeightFactor)
        return (slotHeight, fontSize, slotHeight + defaultLineSpacing)
    }

    static func characterLimit(width: CGFloat, fontSize: CGFloat) -> Int {
        guard width > 1 else { return 42 }
        return max(12, Int(floor(width / (fontSize * 0.56))))
    }
}

struct SceneTeleprompterPanel: View {
    @ObservedObject var transcription: SceneLiveTranscriptionController
    let player: AVPlayer?
    var accent: Color = .accentColor

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .fill(Color.black.opacity(0.88))

            if let message = transcription.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(16)
            } else if transcription.isPreparing && !transcription.isTeleprompterReady {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    if let progress = transcription.modelDownloadProgress {
                        let name = transcription.downloadingModelLanguage
                        let label = progress > 0
                            ? "Downloading \(name ?? "speech model")… \(Int(progress * 100))%"
                            : "Downloading \(name ?? "speech model")…"
                        Text(label)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    } else {
                        Text("Preparing teleprompter…")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    if let notice = transcription.localeFallbackNotice {
                        Text(notice)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(16)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { _ in
                    let time = player?.currentTime().seconds ?? 0
                    GeometryReader { geo in
                        let metrics = SceneTeleprompterMetrics.layout(height: geo.size.height)
                        let centerY = CGFloat(SceneTeleprompterMetrics.renderedLinesBeforeCenter)
                            * metrics.rowStride + metrics.slotHeight / 2
                        teleprompterStack(at: time, width: geo.size.width, metrics: metrics)
                            .frame(width: geo.size.width, alignment: .leading)
                            .offset(y: geo.size.height * 0.5 - centerY)
                            .onAppear {
                                transcription.updateCharacterLimit(
                                    SceneTeleprompterMetrics.characterLimit(
                                        width: geo.size.width - 24,
                                        fontSize: metrics.fontSize
                                    )
                                )
                            }
                            .onChange(of: geo.size.width) { _, w in
                                transcription.updateCharacterLimit(
                                    SceneTeleprompterMetrics.characterLimit(
                                        width: w - 24,
                                        fontSize: metrics.fontSize
                                    )
                                )
                            }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }

    @ViewBuilder
    private func teleprompterStack(
        at time: Double,
        width: CGFloat,
        metrics: (slotHeight: CGFloat, fontSize: CGFloat, rowStride: CGFloat)
    ) -> some View {
        let fractional = transcription.fractionalActiveLinePosition(at: time)
        let centerIdx = Int(floor(fractional))
        let progress = fractional - Double(centerIdx)
        let before = SceneTeleprompterMetrics.renderedLinesBeforeCenter
        let lines = transcription.transcriptLines

        VStack(spacing: SceneTeleprompterMetrics.defaultLineSpacing) {
            ForEach(-before...before, id: \.self) { offset in
                let idx = centerIdx + offset
                let line = (idx >= 0 && idx < lines.count) ? lines[idx] : nil
                lineView(line, roleOffset: offset, time: time, fontSize: metrics.fontSize)
                    .frame(height: metrics.slotHeight, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .offset(y: -progress * metrics.rowStride)
    }

    @ViewBuilder
    private func lineView(
        _ line: SceneTranscriptLine?,
        roleOffset: Int,
        time: Double,
        fontSize: CGFloat
    ) -> some View {
        if let line {
            let isCurrent = roleOffset == 0
            HStack(spacing: 0) {
                ForEach(line.words) { word in
                    Text(word.text)
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundColor(wordColor(word, isCurrent: isCurrent, time: time))
                }
            }
            .opacity(isCurrent ? 1 : SceneTeleprompterMetrics.inactiveLineTextOpacity)
        } else {
            Text(" ")
                .font(.system(size: fontSize, weight: .bold))
                .opacity(0)
        }
    }

    private func wordColor(_ word: SceneTranscriptWord, isCurrent: Bool, time: Double) -> Color {
        if word.isVolatile {
            return .white.opacity(0.45)
        }
        if isCurrent, time >= word.globalStart, time < word.globalEnd {
            return accent
        }
        if isCurrent {
            return .white.opacity(SceneTeleprompterMetrics.activeLineTextOpacity)
        }
        return .white
    }
}
#endif
