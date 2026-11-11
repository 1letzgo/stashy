#if !os(tvOS)
import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
#if canImport(AetherEngine)
import AetherEngine
#endif

// MARK: - Cue model

struct SubtitleCue: Equatable, Identifiable {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    /// Filled in asynchronously by on-device translation for live captions.
    var translated: String?

    init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, text: String, translated: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.translated = translated
    }

    /// Identity is the timed content — a re-parsed cue is the same cue.
    static func == (lhs: SubtitleCue, rhs: SubtitleCue) -> Bool {
        lhs.start == rhs.start
            && lhs.end == rhs.end
            && lhs.text == rhs.text
            && lhs.translated == rhs.translated
    }

    var displayText: String { translated ?? text }
}

// MARK: - Controller

@MainActor
final class SubtitleController: ObservableObject {
    @Published private(set) var currentText: String = ""
    /// Device live ASR is feeding the caption channel (`currentText`).
    @Published private(set) var isLiveCaptionsActive = false

    #if canImport(AetherEngine)
    private var engineClockCancellable: AnyCancellable?
    #endif
    private var liveHoldUntil = Date.distantPast
    private static let liveHoldSeconds: TimeInterval = 2.2
    /// When true, live text is driven by playhead timing (empty string clears).
    private var liveCaptionsTimelineSynced = false

    /// Server captions are registered as external subtitle tracks on the engine and drawn from
    /// its own cue pipeline; this controller only carries live captions. "Off" is the one
    /// selection that matters here: it ends live captions and clears the text.
    func select(_ caption: VideoCaption?, userInitiated: Bool = false) {
        endLiveCaptions()
        currentText = ""
    }

    /// Caption URL for a scene — the engine path registers Stash's server captions as external
    /// subtitle tracks. Shared with tvOS.
    static func captionURL(for caption: VideoCaption, scene: Scene) -> URL? {
        StashCaptionURL.url(for: caption, scene: scene)
    }

    /// Take over the normal caption channel for on-device live speech (same overlay as server VTT).
    func beginLiveCaptions(timelineSynced: Bool = false) {
        currentText = ""
        liveHoldUntil = Date.distantPast
        liveCaptionsTimelineSynced = timelineSynced
        isLiveCaptionsActive = true
    }

    func setLiveCaptionsTimelineSynced(_ synced: Bool) {
        liveCaptionsTimelineSynced = synced
        if synced {
            liveHoldUntil = Date.distantFuture
        }
    }

    func pushLiveCaption(_ text: String) {
        guard isLiveCaptionsActive else { return }
        let trimmed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if !currentText.isEmpty { currentText = "" }
            liveHoldUntil = Date.distantPast
            return
        }
        if currentText != trimmed {
            currentText = trimmed
        }
        if liveCaptionsTimelineSynced {
            liveHoldUntil = Date.distantFuture
        } else {
            liveHoldUntil = Date().addingTimeInterval(Self.liveHoldSeconds)
        }
    }

    func endLiveCaptions() {
        guard isLiveCaptionsActive else { return }
        isLiveCaptionsActive = false
        liveCaptionsTimelineSynced = false
        liveHoldUntil = Date.distantPast
        if !currentText.isEmpty { currentText = "" }
    }

    #if canImport(AetherEngine)
    /// Binds the caption clock to the playback engine. Only the live-caption channel needs it: server VTT
    /// is registered as an external subtitle track on the engine and drawn from its own cue
    /// pipeline. The tick still matters — a non-timeline-synced live
    /// caption expires by wall clock and needs someone to clear it.
    func attach(aether: AetherSceneEngine) {
        detachClock()
        engineClockCancellable = aether.engine.clock.$sourceTime
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] seconds in
                guard let self, seconds.isFinite else { return }
                self.updateText(at: max(0, seconds))
            }
    }
    #endif

    func detach() {
        endLiveCaptions()
        detachClock()
        currentText = ""
    }

    private func detachClock() {
        #if canImport(AetherEngine)
        engineClockCancellable?.cancel()
        engineClockCancellable = nil
        #endif
    }

    private func updateText(at seconds: TimeInterval) {
        if isLiveCaptionsActive {
            if !liveCaptionsTimelineSynced, Date() >= liveHoldUntil, !currentText.isEmpty {
                currentText = ""
            }
            return
        }

        if !currentText.isEmpty { currentText = "" }
    }
}

extension VideoCaption {
    var displayName: String {
        if languageCode == "00" { return tr("unknown") }
        if let name = Locale.current.localizedString(forLanguageCode: languageCode) {
            return "\(name) (\(captionType))"
        }
        return "\(languageCode) (\(captionType))"
    }

    var shortLabel: String {
        if languageCode == "00" { return "CC" }
        return languageCode.uppercased()
    }
}
#endif
