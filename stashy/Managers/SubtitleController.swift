#if !os(tvOS)
import Foundation
import AVFoundation
import Combine
import UIKit

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

// MARK: - WebVTT parser

enum WebVTTParser {
    static func parse(_ raw: String) -> [SubtitleCue] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var cues: [SubtitleCue] = []
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Drop UTF-8 BOM if present
        if let first = lines.first, first.hasPrefix("\u{FEFF}") {
            lines[0] = String(first.dropFirst())
        }

        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            if line.isEmpty { continue }
            if line.hasPrefix("WEBVTT") || line.hasPrefix("NOTE") || line.hasPrefix("STYLE") || line.hasPrefix("REGION") {
                // Skip header / metadata blocks until blank line
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    index += 1
                }
                continue
            }

            var timingLine = line
            // Optional cue identifier on its own line
            if !timingLine.contains("-->"), index < lines.count {
                let maybeTiming = lines[index].trimmingCharacters(in: .whitespaces)
                if maybeTiming.contains("-->") {
                    timingLine = maybeTiming
                    index += 1
                } else {
                    continue
                }
            }

            guard let (start, end) = parseTiming(timingLine) else { continue }

            var textLines: [String] = []
            while index < lines.count {
                let textLine = lines[index]
                index += 1
                if textLine.trimmingCharacters(in: .whitespaces).isEmpty { break }
                textLines.append(stripTags(textLine))
            }

            let text = textLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: text))
        }

        return cues.sorted { $0.start < $1.start }
    }

    private static func parseTiming(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count >= 2 else { return nil }
        let startRaw = parts[0].trimmingCharacters(in: .whitespaces)
        // End may have cue settings after the timestamp
        let endRaw = parts[1]
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        guard let start = parseTimestamp(startRaw), let end = parseTimestamp(endRaw) else { return nil }
        return (start, end)
    }

    private static func parseTimestamp(_ value: String) -> TimeInterval? {
        let cleaned = value.replacingOccurrences(of: ",", with: ".")
        let pieces = cleaned.split(separator: ":").map(String.init)
        guard pieces.count == 2 || pieces.count == 3 else { return nil }

        let hours: Double
        let minutes: Double
        let seconds: Double
        if pieces.count == 3 {
            guard let h = Double(pieces[0]), let m = Double(pieces[1]), let s = Double(pieces[2]) else { return nil }
            hours = h; minutes = m; seconds = s
        } else {
            guard let m = Double(pieces[0]), let s = Double(pieces[1]) else { return nil }
            hours = 0; minutes = m; seconds = s
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func stripTags(_ input: String) -> String {
        var result = ""
        var insideTag = false
        for ch in input {
            if ch == "<" {
                insideTag = true
                continue
            }
            if ch == ">" {
                insideTag = false
                continue
            }
            if !insideTag {
                result.append(ch)
            }
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

// MARK: - Controller

@MainActor
final class SubtitleController: ObservableObject {
    static let preferredLanguageKey = "stashy_preferred_caption_lang"

    @Published private(set) var currentText: String = ""
    @Published private(set) var availableCaptions: [VideoCaption] = []
    @Published private(set) var selectedCaption: VideoCaption?
    /// Device live ASR is feeding the same display channel as server VTT.
    @Published private(set) var isLiveCaptionsActive = false

    private var cues: [SubtitleCue] = []
    private var cueIndex: Int = 0
    private weak var player: AVPlayer?
    private var timeObserver: Any?
    private var loadTask: Task<Void, Never>?
    private var captionBaseURL: URL?
    private var liveHoldUntil = Date.distantPast
    private static let liveHoldSeconds: TimeInterval = 2.2
    /// When true, live text is driven by playhead timing (empty string clears).
    private var liveCaptionsTimelineSynced = false
    /// User chose "Off" in the CC menu — don't auto-enable again for this scene.
    private var captionsExplicitlyOff = false
    private var configuredSceneID: String?

    var hasCaptions: Bool { !availableCaptions.isEmpty }

    func configure(scene: Scene, player: AVPlayer?) {
        let sceneChanged = configuredSceneID != scene.id
        if sceneChanged {
            configuredSceneID = scene.id
            captionsExplicitlyOff = false
        }

        let previousCaptions = availableCaptions
        let previousBase = captionBaseURL
        availableCaptions = scene.captions ?? []
        captionBaseURL = Self.resolveCaptionBaseURL(scene.paths?.caption)
            ?? Self.fallbackCaptionBaseURL(sceneID: scene.id)
        attach(player: player)

        guard hasCaptions else {
            if !isLiveCaptionsActive {
                selectedCaption = nil
                currentText = ""
                cues = []
                cueIndex = 0
                loadTask?.cancel()
            }
            return
        }

        if isLiveCaptionsActive { return }
        if captionsExplicitlyOff { return }

        // Keep a working selection across detail refreshes / player attach.
        if !sceneChanged,
           previousCaptions == availableCaptions,
           previousBase == captionBaseURL,
           let selected = selectedCaption,
           availableCaptions.contains(where: { $0 == selected }),
           !cues.isEmpty || loadTask != nil {
            return
        }

        if let selected = selectedCaption,
           let stillThere = availableCaptions.first(where: { $0 == selected }) {
            select(stillThere)
            return
        }

        if let match = preferredCaption(from: availableCaptions) {
            select(match)
        } else if let first = availableCaptions.first {
            // Always show something when the scene has captions (Stash web also defaults on).
            select(first)
        }
    }

    func select(_ caption: VideoCaption?, userInitiated: Bool = false) {
        if userInitiated {
            captionsExplicitlyOff = caption == nil
        }
        endLiveCaptions()
        selectedCaption = caption
        currentText = ""
        cues = []
        cueIndex = 0
        loadTask?.cancel()

        if let caption {
            UserDefaults.standard.set(caption.languageCode, forKey: Self.preferredLanguageKey)
        }

        guard let caption, let url = url(for: caption) else {
            if caption != nil {
                AppLog.debug("💬 Caption URL missing for \(caption?.id ?? "?") (base=\(captionBaseURL?.absoluteString ?? "nil"))")
            }
            return
        }

        loadTask = Task { [weak self] in
            let text = await Self.fetchCaptionText(from: url)
            guard !Task.isCancelled, let self else { return }
            guard self.selectedCaption == caption else { return }
            let parsed = Self.parseCaptionFile(text ?? "")
            if parsed.isEmpty {
                AppLog.debug("💬 Caption parse produced 0 cues from \(redactedURLString(url))")
            }
            self.cues = parsed
            self.cueIndex = 0
            self.loadTask = nil
            if let seconds = self.player?.currentTime().seconds, seconds.isFinite {
                self.updateText(at: seconds)
            }
        }
    }

    private func preferredCaption(from captions: [VideoCaption]) -> VideoCaption? {
        let candidates: [String?] = [
            UserDefaults.standard.string(forKey: Self.preferredLanguageKey),
            SubtitleTargetLanguage.load(),
            Locale.current.language.languageCode?.identifier,
            "00",
        ]
        for raw in candidates {
            guard let code = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !code.isEmpty else { continue }
            if let match = captions.first(where: { $0.languageCode.lowercased() == code }) {
                return match
            }
        }
        return nil
    }

    private static func resolveCaptionBaseURL(_ path: String?) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        if path.hasPrefix("http://") || path.hasPrefix("https://"), let url = URL(string: path) {
            return url
        }
        guard let config = ServerConfigManager.shared.activeConfig ?? ServerConfigManager.shared.loadConfig() else {
            return URL(string: path)
        }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "\(config.baseURL)/\(trimmed)")
    }

    private static func fallbackCaptionBaseURL(sceneID: String) -> URL? {
        guard let config = ServerConfigManager.shared.activeConfig ?? ServerConfigManager.shared.loadConfig() else {
            return nil
        }
        return URL(string: "\(config.baseURL)/scene/\(sceneID)/caption")
    }

    private static func parseCaptionFile(_ raw: String) -> [SubtitleCue] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // Stash normally converts SRT→WebVTT server-side; keep a tolerant parse either way.
        return WebVTTParser.parse(raw)
    }

    /// Take over the normal caption channel for on-device live speech (same overlay as server VTT).
    func beginLiveCaptions(timelineSynced: Bool = false) {
        loadTask?.cancel()
        loadTask = nil
        selectedCaption = nil
        cues = []
        cueIndex = 0
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
        cues = []
        cueIndex = 0
    }

    func attach(player: AVPlayer?) {
        detachTimeObserver()
        self.player = player
        guard let player else { return }

        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            Task { @MainActor in
                self?.updateText(at: seconds)
            }
        }
    }

    func detach() {
        loadTask?.cancel()
        loadTask = nil
        endLiveCaptions()
        detachTimeObserver()
        player = nil
        currentText = ""
        cues = []
        cueIndex = 0
    }

    func url(for caption: VideoCaption) -> URL? {
        guard let base = captionBaseURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        var items = (components.queryItems ?? []).filter {
            let name = $0.name.lowercased()
            return name != "lang" && name != "type" && name != "apikey"
        }
        items.append(URLQueryItem(name: "lang", value: caption.languageCode))
        items.append(URLQueryItem(name: "type", value: caption.captionType))
        components.queryItems = items
        return signedURL(components.url)
    }

    private func detachTimeObserver() {
        if let token = timeObserver, let player {
            player.removeTimeObserver(token)
        }
        timeObserver = nil
    }

    private func updateText(at seconds: TimeInterval) {
        if isLiveCaptionsActive {
            if !liveCaptionsTimelineSynced, Date() >= liveHoldUntil, !currentText.isEmpty {
                currentText = ""
            }
            return
        }

        guard selectedCaption != nil, !cues.isEmpty else {
            if !currentText.isEmpty { currentText = "" }
            return
        }

        var lo = 0
        var hi = cues.count - 1
        var match: String?
        while lo <= hi {
            let mid = (lo + hi) / 2
            let cue = cues[mid]
            if seconds < cue.start {
                hi = mid - 1
            } else if seconds >= cue.end {
                lo = mid + 1
            } else {
                match = cue.text
                cueIndex = mid
                break
            }
        }

        let next = match ?? ""
        if currentText != next {
            currentText = next
        }
    }

    private static func fetchCaptionText(from url: URL) async -> String? {
        var request = authenticatedStashRequest(for: url)
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                AppLog.debug("💬 Caption fetch failed: HTTP \(http.statusCode) for \(redactedURLString(url))")
                return nil
            }
            guard !data.isEmpty else {
                AppLog.debug("💬 Caption fetch returned empty body for \(redactedURLString(url))")
                return nil
            }
            if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
            if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
            AppLog.debug("💬 Caption fetch: unsupported encoding (\(data.count) bytes)")
            return nil
        } catch {
            AppLog.debug("💬 Caption fetch error: \(error.localizedDescription)")
            return nil
        }
    }
}

extension VideoCaption {
    var displayName: String {
        if languageCode == "00" { return "Unknown" }
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
