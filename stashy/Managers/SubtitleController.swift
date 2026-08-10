#if !os(tvOS)
import Foundation
import AVFoundation
import Combine
import UIKit

// MARK: - Cue model

struct SubtitleCue: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
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

    private var cues: [SubtitleCue] = []
    private var cueIndex: Int = 0
    private weak var player: AVPlayer?
    private var timeObserver: Any?
    private var loadTask: Task<Void, Never>?
    private var captionBaseURL: URL?

    var hasCaptions: Bool { !availableCaptions.isEmpty }

    func configure(scene: Scene, player: AVPlayer?) {
        let previousCaptions = availableCaptions
        let previousBase = captionBaseURL
        availableCaptions = scene.captions ?? []
        captionBaseURL = {
            guard let path = scene.paths?.caption else { return nil }
            return URL(string: path)
        }()
        attach(player: player)

        guard hasCaptions else {
            select(nil)
            return
        }

        // Keep current choice across detail refreshes.
        if previousCaptions == availableCaptions,
           previousBase == captionBaseURL,
           selectedCaption == nil || availableCaptions.contains(where: { $0 == selectedCaption }) {
            return
        }

        if let selected = selectedCaption,
           let stillThere = availableCaptions.first(where: { $0 == selected }) {
            select(stillThere)
            return
        }

        // Restore preference, else match device language (Stash web behavior).
        if let preferred = UserDefaults.standard.string(forKey: Self.preferredLanguageKey),
           let match = availableCaptions.first(where: { $0.languageCode == preferred }) {
            select(match)
        } else if let deviceLang = Locale.current.language.languageCode?.identifier,
                  let match = availableCaptions.first(where: { $0.languageCode == deviceLang }) {
            select(match)
        } else {
            select(nil)
        }
    }

    func select(_ caption: VideoCaption?) {
        selectedCaption = caption
        currentText = ""
        cues = []
        cueIndex = 0
        loadTask?.cancel()

        if let caption {
            UserDefaults.standard.set(caption.languageCode, forKey: Self.preferredLanguageKey)
        }

        guard let caption, let url = url(for: caption) else { return }

        loadTask = Task { [weak self] in
            let text = await Self.fetchVTT(from: url)
            guard !Task.isCancelled, let self else { return }
            guard self.selectedCaption == caption else { return }
            self.cues = WebVTTParser.parse(text ?? "")
            self.cueIndex = 0
            if let seconds = self.player?.currentTime().seconds, seconds.isFinite {
                self.updateText(at: seconds)
            }
        }
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
        detachTimeObserver()
        player = nil
        currentText = ""
        cues = []
        cueIndex = 0
    }

    func url(for caption: VideoCaption) -> URL? {
        guard var components = URLComponents(url: captionBaseURL ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false),
              captionBaseURL != nil else { return nil }
        var items = (components.queryItems ?? []).filter {
            let name = $0.name.lowercased()
            return name != "lang" && name != "type"
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

    private static func fetchVTT(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let apiKey = ServerConfigManager.shared.activeConfig?.secureApiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("💬 Caption fetch failed: HTTP \(http.statusCode)")
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch {
            print("💬 Caption fetch error: \(error.localizedDescription)")
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
