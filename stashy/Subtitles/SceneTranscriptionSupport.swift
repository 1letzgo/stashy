#if !os(tvOS)
import AVFoundation
import Foundation
import Speech

// MARK: - Availability

enum SpeechTranscriberAvailability {
    static func isSupported() async -> Bool {
        if #available(iOS 26.0, *) {
            guard SpeechTranscriber.isAvailable else { return false }
            return !(await SpeechTranscriber.supportedLocales).isEmpty
        }
        return false
    }

    /// Language picker entries for scene language — only codes Apple’s SpeechTranscriber
    /// can actually recognize on this device (e.g. no Czech).
    static func sceneLanguagePickerOptions(
        locale: Locale = .current
    ) async -> [(id: String, label: String)] {
        guard #available(iOS 26.0, *) else { return [] }
        guard SpeechTranscriber.isAvailable else { return [] }
        var codes = Set<String>()
        for supported in await SpeechTranscriber.supportedLocales {
            if let code = supported.language.languageCode?.identifier.lowercased() {
                codes.insert(code)
            } else if let code = SubtitleTargetLanguage.languageCode(
                from: supported.identifier(.bcp47)
            ) {
                codes.insert(code)
            }
        }
        return codes
            .sorted {
                SubtitleTargetLanguage.displayName(for: $0, locale: locale)
                    < SubtitleTargetLanguage.displayName(for: $1, locale: locale)
            }
            .map {
                (id: $0, label: SubtitleTargetLanguage.displayName(for: $0, locale: locale))
            }
    }
}

// MARK: - Locale resolver

enum SpeechTranscriptionLocaleResolver {
    struct Resolution {
        let locale: Locale
        let usedFallback: Bool
    }

    enum ResolveError: LocalizedError {
        case localeNotSupported
        case requiresNewerOS
        var errorDescription: String? {
            switch self {
            case .localeNotSupported:
                return "Speech recognition is not available for this language on this device."
            case .requiresNewerOS:
                return "Teleprompter requires iOS 26 or newer."
            }
        }
    }

    static func resolve(preferredLanguageTag: String?) async throws -> Resolution {
        guard #available(iOS 26.0, *) else { throw ResolveError.requiresNewerOS }
        let supported = await SpeechTranscriber.supportedLocales
        guard !supported.isEmpty else { throw ResolveError.localeNotSupported }

        let preferred = locale(fromMetadataLanguage: preferredLanguageTag)
        // Prefer Apple's exact asset locale (`cs-CZ`) over a short tag that only looks supported.
        if let preferred, let exact = await SpeechTranscriber.supportedLocale(equivalentTo: preferred) {
            return Resolution(locale: exact, usedFallback: false)
        }

        var candidates: [Locale] = []
        if let preferred { candidates.append(preferred) }
        candidates.append(Locale.current)
        for id in Locale.preferredLanguages {
            candidates.append(Locale(identifier: id))
        }
        candidates.append(contentsOf: [
            Locale(identifier: "en-US"),
            Locale(identifier: "en"),
            Locale(identifier: "de-DE"),
            Locale(identifier: "de"),
        ])

        var seen = Set<String>()
        for candidate in candidates {
            let key = candidate.identifier(.bcp47).lowercased()
            guard seen.insert(key).inserted else { continue }
            let match = await SpeechTranscriber.supportedLocale(equivalentTo: candidate)
                ?? matchLocale(candidate, in: supported)
            guard let match else { continue }
            let usedFallback =
                preferred != nil
                && !sameLanguage(match, preferred!)
            return Resolution(locale: match, usedFallback: usedFallback)
        }
        if let first = supported.first {
            return Resolution(locale: first, usedFallback: true)
        }
        throw ResolveError.localeNotSupported
    }

    static func locale(fromMetadataLanguage raw: String?) -> Locale? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        value = value.replacingOccurrences(of: "_", with: "-")
        let lower = value.lowercased()
        let nameMap: [String: String] = [
            "german": "de", "english": "en", "french": "fr", "spanish": "es",
            "italian": "it", "japanese": "ja", "chinese": "zh", "korean": "ko",
            "portuguese": "pt", "russian": "ru", "dutch": "nl",
        ]
        if let mapped = nameMap[lower] {
            return Locale(identifier: mapped)
        }
        return Locale(identifier: value)
    }

    static func matchLocale(_ requested: Locale, in supported: [Locale]) -> Locale? {
        let reqId = requested.identifier(.bcp47).lowercased()
        if reqId.isEmpty { return nil }
        if let exact = supported.first(where: { $0.identifier(.bcp47).lowercased() == reqId }) {
            return exact
        }
        let reqLang = languageCode(from: requested) ?? (reqId.count >= 2 ? String(reqId.prefix(2)) : nil)
        guard let reqLang else { return nil }
        let langMatches = supported.filter { locale in
            let id = locale.identifier(.bcp47).lowercased()
            if id == reqLang || id.hasPrefix(reqLang + "-") { return true }
            return languageCode(from: locale) == reqLang
        }
        return langMatches.first { $0.identifier(.bcp47).contains("-") } ?? langMatches.first
    }

    private static func languageCode(from locale: Locale) -> String? {
        locale.language.languageCode?.identifier.lowercased()
    }

    private static func sameLanguage(_ a: Locale, _ b: Locale) -> Bool {
        guard let ca = languageCode(from: a), let cb = languageCode(from: b) else { return false }
        return ca == cb
    }
}

// MARK: - Audio converter

final class SceneTranscriptionAudioConverter {
    private let converter: AVAudioConverter
    let sourceFormat: AVAudioFormat

    init?(sourceFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
        guard let c = AVAudioConverter(from: sourceFormat, to: targetFormat) else { return nil }
        converter = c
        self.sourceFormat = sourceFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let ratio = max(0.01, targetFormat.sampleRate / max(0.01, buffer.format.sampleRate))
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(outCapacity, 4096))
        else {
            throw SceneLiveTranscriptionError.conversionFailed
        }
        var error: NSError?
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        let status = converter.convert(to: out, error: &error, withInputFrom: inputBlock)
        if let error { throw error }
        // Some format transitions need a drain pass after the input is marked consumed.
        if out.frameLength == 0, status == .haveData || status == .inputRanDry {
            var drainError: NSError?
            _ = converter.convert(to: out, error: &drainError, withInputFrom: { _, outStatus in
                outStatus.pointee = .endOfStream
                return nil
            })
            if let drainError { throw drainError }
        }
        return out
    }
}

// MARK: - Models

struct SceneTranscriptWord: Identifiable, Equatable {
    let id: String
    let text: String
    let globalStart: Double
    let globalEnd: Double
    let isVolatile: Bool

    var isWhitespaceOnly: Bool { text.allSatisfy(\.isWhitespace) }
}

struct SceneTranscriptLine: Identifiable, Equatable {
    let id: String
    let words: [SceneTranscriptWord]
    let globalStart: Double
    let globalEnd: Double
    let isVolatile: Bool

    var spokenWords: [SceneTranscriptWord] { words.filter { !$0.isWhitespaceOnly } }
}

struct SceneTranscriptionAudioContext: Equatable {
    let assetURL: URL
    let apiKey: String?
    let locale: Locale
}

enum SceneTeleprompterMode: String, CaseIterable, Identifiable {
    case off
    case sceneLanguage
    case userLanguage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .sceneLanguage: return "Scene language"
        case .userLanguage: return "My language"
        }
    }
}

// MARK: - Line accumulator

@MainActor
final class SceneTranscriptLineAccumulator {
    private(set) var closedLines: [SceneTranscriptLine] = []
    private var openWords: [SceneTranscriptWord] = []
    private var openCharCount = 0
    private var nextLineIndex = 0
    private var nextWordIndex = 0
    var maxCharactersPerLine = 84

    func reset() {
        closedLines = []
        openWords = []
        openCharCount = 0
        nextLineIndex = 0
        nextWordIndex = 0
    }

    func appendFinalizedWords(_ incoming: [SceneTranscriptWord]) {
        appendWords(incoming, includeVolatile: false, lineVolatile: false)
    }

    static func makeLines(
        from words: [SceneTranscriptWord],
        maxCharactersPerLine limit: Int,
        volatile: Bool
    ) -> [SceneTranscriptLine] {
        let builder = SceneTranscriptLineAccumulator()
        builder.maxCharactersPerLine = limit
        builder.appendWords(words, includeVolatile: true, lineVolatile: volatile)
        return builder.publishedLines(volatile: volatile)
    }

    private func appendWords(
        _ incoming: [SceneTranscriptWord],
        includeVolatile: Bool,
        lineVolatile: Bool
    ) {
        for raw in incoming where includeVolatile || !raw.isVolatile {
            let word = stabilized(raw, preserveVolatileFlag: lineVolatile)
            if word.isWhitespaceOnly {
                if !openWords.isEmpty { openWords.append(word) }
                continue
            }
            let add = word.text.count
            if openCharCount > 0, openCharCount + add > maxCharactersPerLine {
                closeOpenLine(volatile: lineVolatile)
            }
            openWords.append(word)
            openCharCount += add
            if endsSentence(in: word.text) {
                closeOpenLine(volatile: lineVolatile)
            }
        }
    }

    private var openLineId: String { "line-\(nextLineIndex)" }

    func publishedLines(volatile: Bool = false) -> [SceneTranscriptLine] {
        var all = closedLines
        if let open = openLineSnapshot(volatile: volatile) { all.append(open) }
        return all
    }

    func pruneClosedLines(keeping limit: Int, chunk: Int) {
        guard closedLines.count >= limit + chunk else { return }
        closedLines.removeFirst(closedLines.count - limit)
    }

    private func openLineSnapshot(volatile: Bool = false) -> SceneTranscriptLine? {
        let spoken = openWords.filter { !$0.isWhitespaceOnly }
        guard !spoken.isEmpty else { return nil }
        return SceneTranscriptLine(
            id: volatile ? "volatile-\(openLineId)" : openLineId,
            words: openWords,
            globalStart: spoken.first!.globalStart,
            globalEnd: max(spoken.last!.globalEnd, spoken.first!.globalStart + 0.05),
            isVolatile: volatile
        )
    }

    private func closeOpenLine(volatile: Bool = false) {
        guard let snapshot = openLineSnapshot(volatile: volatile) else {
            openWords = []
            openCharCount = 0
            return
        }
        closedLines.append(snapshot)
        nextLineIndex += 1
        openWords = []
        openCharCount = 0
    }

    private func stabilized(_ word: SceneTranscriptWord, preserveVolatileFlag: Bool = false) -> SceneTranscriptWord {
        let id = preserveVolatileFlag && word.isVolatile
            ? "vw-\(nextWordIndex)"
            : "w-\(nextWordIndex)"
        nextWordIndex += 1
        return SceneTranscriptWord(
            id: id,
            text: word.text,
            globalStart: word.globalStart,
            globalEnd: word.globalEnd,
            isVolatile: preserveVolatileFlag ? word.isVolatile : false
        )
    }

    private func endsSentence(in text: String) -> Bool {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, "'\"»」)]}".contains(last) {
            t.removeLast()
        }
        guard let last = t.last else { return false }
        return ".!?…".contains(last)
    }
}
#endif
