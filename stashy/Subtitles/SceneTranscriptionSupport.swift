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

    /// Language picker entries for scene language — one row per language
    /// (`en-US`/`en-GB` → English, `zh-CN`/`zh-HK`/`zh-TW` → Chinese).
    /// Cantonese (`yue`) stays its own row; its `forLanguageCode` name often equals "Chinese".
    static func sceneLanguagePickerOptions(
        locale: Locale = .current
    ) async -> [(id: String, label: String)] {
        guard #available(iOS 26.0, *) else { return [] }
        guard SpeechTranscriber.isAvailable else { return [] }
        var grouped: [String: [Locale]] = [:]
        for supported in await SpeechTranscriber.supportedLocales {
            let subtag = supported.identifier(.bcp47)
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
                .split(separator: "-")
                .first
                .map(String.init) ?? supported.identifier(.bcp47).lowercased()
            grouped[subtag, default: []].append(supported)
        }
        return grouped.keys.sorted {
            pickerLabel(forSubtag: $0, locale: locale)
                .localizedStandardCompare(pickerLabel(forSubtag: $1, locale: locale)) == .orderedAscending
        }
        .map { (id: $0, label: pickerLabel(forSubtag: $0, locale: locale)) }
    }

    static func speechLocaleDisplayName(for locale: Locale, locale display: Locale = .current) -> String {
        pickerLabel(forSubtag: SpeechTranscriptionLocaleResolver.speechLanguageSubtag(locale), locale: display)
    }

    private static func pickerLabel(forSubtag subtag: String, locale display: Locale) -> String {
        if subtag == "yue" {
            let yue = display.localizedString(forLanguageCode: "yue")
            let zh = display.localizedString(forLanguageCode: "zh")
            if let yue, !yue.isEmpty, yue != zh { return yue }
            if let name = display.localizedString(forIdentifier: "yue-CN"), !name.isEmpty {
                if let paren = name.firstIndex(of: "(") {
                    return String(name[..<paren]).trimmingCharacters(in: .whitespaces)
                }
                return name
            }
            return "Cantonese"
        }
        return SubtitleTargetLanguage.displayName(for: subtag, locale: display)
    }

    /// Maps a stored scene tag (`zh`, `yue`, `zh-CN`) onto the picker row that should stay selected.
    static func matchingPickerId(stored: String?, optionIds: [String]) -> String? {
        guard let stored else { return nil }
        let needle = stored.replacingOccurrences(of: "_", with: "-").lowercased()
        if let exact = optionIds.first(where: { $0.lowercased() == needle }) {
            return exact
        }
        let wanted = languageAndRegion(needle)
        if let wantedRegion = wanted.region,
           let match = optionIds.first(where: {
               let parts = languageAndRegion($0)
               return parts.lang == wanted.lang && parts.region == wantedRegion
           }) {
            return match
        }
        let lang = wanted.lang
        let preferredDefaults: [String: String] = [
            "yue": "yue-CN",
            "zh": "zh-CN",
            "cmn": "zh-CN",
            "de": "de-DE",
            "en": "en-US",
            "fr": "fr-FR",
            "es": "es-ES",
            "pt": "pt-BR",
            "nl": "nl-NL",
        ]
        if let preferred = preferredDefaults[lang],
           let match = optionIds.first(where: {
               let parts = languageAndRegion($0)
               let pref = languageAndRegion(preferred)
               return parts.lang == pref.lang && parts.region == pref.region
           }) {
            return match
        }
        let langMatches = optionIds.filter { languageAndRegion($0).lang == lang }
        if langMatches.count == 1 { return langMatches[0] }
        return nil
    }

    private static func languageAndRegion(_ id: String) -> (lang: String, region: String?) {
        let parts = id.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map(String.init)
        let lang = parts.first ?? ""
        let region = parts.reversed().first { $0.count == 2 && $0 != lang }
        return (lang, region)
    }

    static func shortPickerLabel(stored: String?, selectedId: String?) -> String {
        let tag = (selectedId ?? stored)?
            .replacingOccurrences(of: "_", with: "-")
            .uppercased()
        guard let tag, !tag.isEmpty else { return "Lang" }
        let parts = tag.split(separator: "-").map(String.init)
        guard let lang = parts.first else { return "Lang" }
        if lang == "YUE" { return "YUE" }
        return lang
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
        if let preferred {
            if let exact = matchLocale(preferred, in: supported) {
                return Resolution(locale: exact, usedFallback: false)
            }
            // `equivalentTo` can map generic `zh` onto Cantonese (`yue-CN`). Only accept
            // Apple's suggestion when the BCP-47 language subtag still matches.
            if let apple = await SpeechTranscriber.supportedLocale(equivalentTo: preferred),
               sameSpeechLanguage(apple, preferred) {
                return Resolution(locale: apple, usedFallback: false)
            }
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
                .flatMap { sameSpeechLanguage($0, candidate) ? $0 : nil }
                ?? matchLocale(candidate, in: supported)
            guard let match else { continue }
            let usedFallback =
                preferred != nil
                && !sameSpeechLanguage(match, preferred!)
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
            "italian": "it", "japanese": "ja", "korean": "ko",
            "portuguese": "pt", "russian": "ru", "dutch": "nl",
            "chinese": "zh-CN", "chinesisch": "zh-CN", "mandarin": "zh-CN",
            "cantonese": "yue-CN", "kantonesisch": "yue-CN",
            "zh": "zh-CN", "yue": "yue-CN",
        ]
        if let mapped = nameMap[lower] {
            return Locale(identifier: mapped)
        }
        return Locale(identifier: value)
    }

    static func matchLocale(_ requested: Locale, in supported: [Locale]) -> Locale? {
        let reqId = requested.identifier(.bcp47).lowercased().replacingOccurrences(of: "_", with: "-")
        if reqId.isEmpty { return nil }
        if let exact = supported.first(where: {
            $0.identifier(.bcp47).lowercased().replacingOccurrences(of: "_", with: "-") == reqId
        }) {
            return exact
        }
        let reqLang = speechLanguageSubtag(requested)
        guard !reqLang.isEmpty else { return nil }
        let langMatches = supported.filter { speechLanguageSubtag($0) == reqLang }
        if reqId.contains("-") {
            let reqRegion = reqId.split(separator: "-").dropFirst().first.map(String.init)
            if let reqRegion,
               let regional = langMatches.first(where: {
                   $0.identifier(.bcp47).lowercased().replacingOccurrences(of: "_", with: "-")
                       .split(separator: "-")
                       .map(String.init)
                       .contains(reqRegion)
               }) {
                return regional
            }
        }
        let preferredDefaults: [String: String] = [
            "yue": "yue-CN", "zh": "zh-CN", "de": "de-DE", "en": "en-US",
        ]
        if let preferred = preferredDefaults[reqLang] {
            let prefRegion = preferred.split(separator: "-").last.map(String.init)?.lowercased()
            if let prefRegion,
               let match = langMatches.first(where: {
                   $0.identifier(.bcp47)
                       .lowercased()
                       .replacingOccurrences(of: "_", with: "-")
                       .split(separator: "-")
                       .map(String.init)
                       .contains(prefRegion)
               }) {
                return match
            }
        }
        return langMatches.first { $0.identifier(.bcp47).contains("-") } ?? langMatches.first
    }

    /// BCP-47 language subtag (`yue`, `zh`). Do not use Foundation's `languageCode`,
    /// which can report Cantonese as `zh`.
    static func speechLanguageSubtag(_ locale: Locale) -> String {
        locale.identifier(.bcp47)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map(String.init) ?? ""
    }

    private static func sameSpeechLanguage(_ a: Locale, _ b: Locale) -> Bool {
        let ca = speechLanguageSubtag(a)
        let cb = speechLanguageSubtag(b)
        guard !ca.isEmpty, !cb.isEmpty else { return false }
        return ca == cb
    }

    /// Exact / same-subtag match first. Apple's `equivalentTo` is not trusted across
    /// `yue` (Cantonese) vs `zh` (Mandarin).
    static func supportedLocaleMatching(_ requested: Locale) async -> Locale? {
        guard #available(iOS 26.0, *) else { return nil }
        let supported = await SpeechTranscriber.supportedLocales
        if let exact = matchLocale(requested, in: supported) { return exact }
        if let apple = await SpeechTranscriber.supportedLocale(equivalentTo: requested),
           sameSpeechLanguage(apple, requested) {
            return apple
        }
        return nil
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
    case english
    /// Legacy: treated as English captions. Kept so old UserDefaults values still decode.
    case sceneLanguage
    case userLanguage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .english, .sceneLanguage: return "English"
        case .userLanguage: return "My language"
        }
    }

    /// Language the user wants captions in. Scene speech is detected separately.
    var captionTargetCode: String? {
        switch self {
        case .off: return nil
        case .english, .sceneLanguage: return "en"
        case .userLanguage: return SubtitleTargetLanguage.load()
        }
    }

    /// Last AI CC choice — restored when playback starts again after pause / leaving the scene.
    private static let preferredModeKey = "stashy_ai_cc_preferred_mode"

    static var preferred: SceneTeleprompterMode {
        let raw = UserDefaults.standard.string(forKey: preferredModeKey) ?? ""
        if raw == "sceneLanguage" { return .english }
        return SceneTeleprompterMode(rawValue: raw) ?? .off
    }

    static func persist(_ mode: SceneTeleprompterMode) {
        let stored = mode == .sceneLanguage ? SceneTeleprompterMode.english : mode
        UserDefaults.standard.set(stored.rawValue, forKey: preferredModeKey)
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
