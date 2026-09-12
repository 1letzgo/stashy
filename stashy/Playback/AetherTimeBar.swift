//
//  AetherTimeBar.swift
//  stashy
//
//  Die geteilte Scrub-Leiste: Glass-Capsule mit verstrichener Zeit links, Track in der
//  Mitte, Restzeit rechts. Rein wertgetrieben — kein Engine-Bezug —, damit Scene Detail,
//  Feeds/StashTok und der Bild-Vollbildmodus exakt dieselbe Leiste rendern.
//
//  Der Aufrufer besitzt Zustand und Nebenwirkungen (Seek, Vorschau-Decode, Chrome-Timer);
//  diese View zeichnet nur und meldet Scrub-Positionen zurück.
//

#if !os(tvOS)

import SwiftUI
import UIKit

struct AetherTimeBar: View {
    /// Anzuzeigende Zeit. Während des Scrubbens reicht der Aufrufer die Scrub-Zeit herein.
    var currentTime: Double
    var duration: Double
    var isScrubbing: Bool
    /// Scrub-Still. `nil` zeigt den dunklen Platzhalter, damit die Vorschau nicht springt.
    var previewImage: UIImage?
    /// Marker-Positionen (Sekunden) als Punkte auf dem Track. Leer blendet sie aus.
    var markerSeconds: [Double] = []
    var isCompact: Bool = false
    var onScrubChanged: (Double) -> Void
    var onScrubEnded: (Double) -> Void

    private var barHeight: CGFloat { isCompact ? 36 : 44 }

    var body: some View {
        let duration = max(self.duration, 0)
        let displayedTime = max(0, currentTime)
        let remaining = max(0, duration - displayedTime)
        // Labels reserve the width of the longest value the scene can show, so the track does
        // not jump when the elapsed time gains a digit (9:59 → 10:00).
        let template = AetherTimeBar.widestLabel(for: duration)
        HStack(spacing: 12) {
            timeLabel(AetherTimeBar.formatTime(displayedTime), template: template)

            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let progress = duration > 0 ? min(1, max(0, displayedTime / duration)) : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: width * CGFloat(progress))
                    if duration > 0 {
                        markerDots(barWidth: width, duration: duration)
                    }
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            let seconds = Double(min(max(0, value.location.x), width) / width) * duration
                            onScrubChanged(seconds)
                        }
                        .onEnded { value in
                            guard duration > 0 else { return }
                            let seconds = Double(min(max(0, value.location.x), width) / width) * duration
                            onScrubEnded(seconds)
                        }
                )
                .overlay(alignment: .topLeading) {
                    if isScrubbing, duration > 0 {
                        scrubPreviewOverlay(barWidth: width,
                                            progress: CGFloat(progress),
                                            time: displayedTime)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            timeLabel("-\(AetherTimeBar.formatTime(remaining))", template: "-" + template)
        }
        .padding(.horizontal, 16)
        .frame(height: barHeight)
        .stashyGlass(shape: Capsule())
    }

    /// Ein kleiner Punkt pro Marker; Marker außerhalb der Laufzeit werden übersprungen.
    @ViewBuilder
    private func markerDots(barWidth: CGFloat, duration: Double) -> some View {
        let dot: CGFloat = isCompact ? 5 : 6
        ForEach(Array(markerSeconds.enumerated()), id: \.offset) { _, seconds in
            if seconds >= 0, seconds <= duration {
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                    .frame(width: dot, height: dot)
                    .offset(x: min(max(0, barWidth * CGFloat(seconds / duration) - dot / 2), barWidth - dot))
            }
        }
        .allowsHitTesting(false)
    }

    /// Schwebendes Still über dem Scrub-Daumen, an die Leiste geklemmt, damit es nie
    /// aus der Oberfläche läuft.
    @ViewBuilder
    private func scrubPreviewOverlay(barWidth: CGFloat, progress: CGFloat, time: Double) -> some View {
        let previewWidth: CGFloat = 120
        let previewHeight: CGFloat = previewWidth * 9 / 16
        let half = previewWidth / 2
        let rawCenter = barWidth * progress
        let center = barWidth > previewWidth
            ? min(max(half, rawCenter), barWidth - half)
            : barWidth / 2

        VStack(spacing: 3) {
            ZStack {
                Color.black.opacity(0.7)
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: previewWidth, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.75), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.55), radius: 6, x: 0, y: 2)

            Text(AetherTimeBar.formatTime(time))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: previewWidth)
        .offset(x: center - half, y: -(previewHeight + 24))
        .allowsHitTesting(false)
    }

    /// `h:mm:ss` ab einer Stunde, sonst `m:ss`.
    /// Fixed-width label: the template sits invisibly underneath and defines the frame.
    private func timeLabel(_ text: String, template: String) -> some View {
        Text(template)
            .font(.system(size: isCompact ? 10 : 12, weight: .semibold).monospacedDigit())
            .hidden()
            .overlay(
                Text(text)
                    .font(.system(size: isCompact ? 10 : 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .fixedSize()
            )
    }

    /// `0:00` / `00:00` / `0:00:00` … — the widest string `formatTime` can produce for this duration.
    static func widestLabel(for duration: Double) -> String {
        if duration >= 36000 { return "00:00:00" }
        if duration >= 3600 { return "0:00:00" }
        if duration >= 600 { return "00:00" }
        return "0:00"
    }

    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

#endif
