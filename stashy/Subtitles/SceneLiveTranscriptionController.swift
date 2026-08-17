#if !os(tvOS)
import AVFoundation
import Combine
import Foundation
import Speech
import SwiftUI

enum SceneLiveTranscriptionError: LocalizedError {
    case noActivePlayback
    case speechRecognitionDenied
    case localeNotSupported
    case modelDownloadFailed(String?)
    /// Model is supported but not on disk yet — UI should offer an explicit download.
    case speechModelNeedsDownload(String)
    case conversionFailed
    case audioSourceUnavailable
    case missingSceneLanguage
    case requiresNewerOS

    var errorDescription: String? {
        switch self {
        case .noActivePlayback:
            return "Nothing is playing."
        case .speechRecognitionDenied:
            return "Speech recognition is not allowed. Enable it in Settings → Privacy & Security → Speech Recognition."
        case .localeNotSupported:
            return "This scene language is not supported by Apple’s SpeechTranscriber (e.g. Czech is not on the list)."
        case .modelDownloadFailed(let reason):
            if let reason, !reason.isEmpty {
                return "Speech model download failed: \(reason)"
            }
            return "Could not download the speech model. Check your connection and try again."
        case .speechModelNeedsDownload(let name):
            return "Download the \(name) speech model to enable live captions."
        case .conversionFailed:
            return "Audio could not be prepared for transcription."
        case .audioSourceUnavailable:
            return "No readable audio from the player. Start playback and try again."
        case .missingSceneLanguage:
            return "Set the scene language first."
        case .requiresNewerOS:
            return "Teleprompter requires iOS 26 or newer."
        }
    }
}

/// Live transcription for Scene Detail.
///
/// Audio reaches the recognizer through one of three tiers, in order of caption lag:
/// 1. `AVAssetReader` straight on a byte-range readable original (no server cost, zero lag),
/// 2. a dedicated low-res Stash transcode pulled ahead of the playhead (works for MKV/AV1/HLS),
/// 3. the realtime player audio tap, where the 1-2s recognition lag cannot be compensated.
@MainActor
final class SceneLiveTranscriptionController: ObservableObject {
    static let preRollSeconds: Double = 2
    /// Keeping the feed ~1 minute ahead is plenty for stable captions; more only means longer
    /// chunk downloads, more server transcode load and slower recovery after a seek.
    static let leadBufferSeconds: Double = 58
    static let feedReseekLagSeconds: Double = 40
    /// Safety net for the case the playhead outruns the feed without a detectable jump.
    static let feedBehindRestartSeconds: Double = 12
    nonisolated static let feedBuffersPerStateCheck = 12
    static let maxAnalyzerBacklogSeconds: Double = 45
    static let minClosedLinesForDisplay = 1
    static let minTranscribedSecondsForDisplay: Double = 1.5
    static let maxClosedLinesKept = 80
    /// Early bias so captions appear at the spoken first word despite ASR lag.
    static let displayLookaheadSeconds: Double = 0.35
    static let sentenceGapFlushSeconds: Double = 0.85
    static let maxPendingSentenceCharacters = 110
    static let maxPendingSentenceSeconds: Double = 7
    static let maxDisplayLeadSeconds: Double = 4.5
    /// Recognized lead at which the lookahead buffer counts as fully built.
    static let readyLookaheadSeconds: Double = 20
    /// A playhead jump larger than this is a seek, not normal playback progress.
    static let seekDetectionSeconds: Double = 1.5
    /// Behind the playhead the feed must be before a seek forces a feed restart.
    static let seekRestartLagSeconds: Double = 4

    @Published private(set) var isTeleprompterModeActive = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isTeleprompterReady = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var localeFallbackNotice: String?
    @Published private(set) var modelDownloadProgress: Double?
    /// Localized name of the speech model currently being fetched, for the download hint.
    @Published private(set) var downloadingModelLanguage: String?
    /// Supported locale is missing on disk — wait for an explicit download tap.
    @Published private(set) var needsSpeechModelDownload = false
    /// Human-readable AssetInventory status for the CC pill / debug toasts.
    @Published private(set) var speechAssetStatusText: String?
    @Published private(set) var words: [SceneTranscriptWord] = []

    enum SpeechModelProbe: Equatable {
        case ready
        case needsDownload(languageName: String, localeIdentifier: String)
        case downloading(languageName: String, localeIdentifier: String)
        case unsupported(languageName: String)
    }
    @Published private(set) var transcriptLines: [SceneTranscriptLine] = []
    @Published private(set) var currentSubtitleText: String = ""
    @Published private(set) var isReadAlongAvailable = false
    /// Build-up of the transcription buffer, `0...1`, or `nil` when there is nothing to prebuild
    /// (realtime tap) or the session is off. Drives the progress ring in the CC button.
    @Published private(set) var prepProgress: Double?
    /// Seconds of already recognized speech sitting ahead of the playhead.
    @Published private(set) var lookaheadSeconds: Double = 0
    @Published var mode: SceneTeleprompterMode = .off
    /// Shared caption channel (`SubtitleController`).
    var liveCaptionHandler: ((String) -> Void)?
    /// `true` when captions are timed to the playhead (lookahead feed).
    var onLookaheadModeChanged: ((Bool) -> Void)?
    /// Hands a finished sentence to on-device translation; the result comes back via
    /// `applyTranslation(cueID:text:)`. Set when captions are translated into the target language.
    var translationRequestHandler: ((UUID, String) -> Void)?

    private weak var player: AVPlayer?
    private var sceneLanguageTag: String?
    private var sceneID: String?
    private var sceneDuration: Double?
    private var candidateURLs: [URL] = []
    private var generation: UInt = 0
    private var subtitleTimeObserver: Any?
    private var usesLookaheadFeed = false
    /// Set when the dedicated transcode feed dies, so the restart lands on the audio tap.
    private var transcodePrefetchFailed = false
    private var captionHoldUntil = Date.distantPast
    private static let captionHoldSeconds: TimeInterval = 2.2
    private static let maxCaptionCharacters = 160

    private var speechSession: AnyObject?
    private var feedTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var enableTask: Task<Void, Never>?

    private var lineAccumulator = SceneTranscriptLineAccumulator()
    private var finalizedWords: [SceneTranscriptWord] = []
    private var volatileTailWords: [SceneTranscriptWord] = []
    private var lastVolatilePublish = Date.distantPast
    /// Closed subtitle sentences timed like classic SRT/VTT cues.
    private var subtitleCues: [SubtitleCue] = []
    private var pendingSentenceWords: [SceneTranscriptWord] = []
    /// Prevents `flushPendingSentence` → translation cache-hit → `applyTranslation` →
    /// `refreshSubtitleText` → `flushPendingSentence` from overflowing the stack.
    private var isFlushingPendingSentence = false
    /// In-progress sentence from volatile ASR — shown at first-word time before finalization.
    private var draftCue: SubtitleCue?
    /// Extra seconds to bring captions forward when ASR consistently finishes late.
    private var adaptiveDisplayLead: Double = 0.8

    private struct FeedTimelineSegment {
        let analyzerStart: Double
        let globalStart: Double
    }
    private var feedTimeline: [FeedTimelineSegment] = []
    private var lastObservedPlayhead: Double?
    /// Feed source resolved once per scene so restarts skip the candidate probing.
    private var cachedFeedSource: FeedSource?
    private var cachedLocaleResolution: SpeechTranscriptionLocaleResolver.Resolution?
    private var pendingSpeechModelLocale: Locale?
    /// Set only after the user taps the download offer — never auto-fetch models.
    private var speechModelDownloadApproved = false
    private var seekRestartTask: Task<Void, Never>?
    private var sessionFeedStartGlobalTime: Double = 0
    private var fedLocalSeconds: Double = 0
    private var fedAnalyzerSeconds: Double = 0

    init() {
        Task { isReadAlongAvailable = await SpeechTranscriberAvailability.isSupported() }
    }

    @available(iOS 26.0, *)
    private final class SpeechSessionBox {
        var analyzer: SpeechAnalyzer?
        var transcriber: SpeechTranscriber?
        var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
        var analyzerFormat: AVAudioFormat?
    }

    // MARK: - Public API

    func updateCharacterLimit(_ limit: Int) {
        lineAccumulator.maxCharactersPerLine = max(12, limit)
        publishLines()
    }

    func fractionalActiveLinePosition(at time: Double) -> Double {
        let lines = transcriptLines
        guard !lines.isEmpty else { return 0 }
        guard let idx = lines.lastIndex(where: { $0.globalStart <= time }) else { return 0 }
        let line = lines[idx]
        let span = max(0.05, line.globalEnd - line.globalStart)
        let progress = min(1, max(0, (time - line.globalStart) / span))
        return Double(idx) + progress
    }

    func start(
        mode: SceneTeleprompterMode,
        player: AVPlayer,
        sceneID: String?,
        sceneDuration: Double? = nil,
        sceneLanguage: String?,
        streamURL: URL? = nil,
        extraCandidateURLs: [URL] = []
    ) {
        self.mode = mode
        guard mode != .off else {
            Task { await disable() }
            return
        }

        guard let sceneLanguage, !sceneLanguage.isEmpty else {
            errorMessage = SceneLiveTranscriptionError.missingSceneLanguage.localizedDescription
            return
        }
        guard #available(iOS 26.0, *) else {
            errorMessage = SceneLiveTranscriptionError.requiresNewerOS.localizedDescription
            isTeleprompterModeActive = false
            return
        }
        guard player.currentItem != nil else {
            errorMessage = SceneLiveTranscriptionError.noActivePlayback.localizedDescription
            return
        }

        // Always start a brand-new session (cancel any previous feed/analyzer first).
        enableTask?.cancel()
        enableTask = Task { [weak self] in
            guard let self else { return }
            await self.tearDownForRestart()
            guard !Task.isCancelled else { return }

            self.player = player
            self.sceneLanguageTag = sceneLanguage
            self.sceneID = sceneID
            self.sceneDuration = sceneDuration
            self.candidateURLs = Self.buildCandidateURLs(
                player: player,
                primary: streamURL,
                extras: extraCandidateURLs
            )
            self.mode = mode
            self.errorMessage = nil
            self.isTeleprompterModeActive = true
            self.attachSubtitleClock(player: player)
            await self.runEnableSession()
        }
    }

    /// Hard reset of speech/feed state without flipping the public "off" UX.
    private func tearDownForRestart() async {
        generation &+= 1
        await stopSession()
        detachSubtitleClock()
        isPreparing = false
        isTeleprompterReady = false
        usesLookaheadFeed = false
        transcodePrefetchFailed = false
        cachedFeedSource = nil
        cachedLocaleResolution = nil
        seekRestartTask?.cancel()
        seekRestartTask = nil
        lastObservedPlayhead = nil
        prepProgress = nil
        lookaheadSeconds = 0
        onLookaheadModeChanged?(false)
        localeFallbackNotice = nil
        modelDownloadProgress = nil
        downloadingModelLanguage = nil
        needsSpeechModelDownload = false
        // Keep an in-flight download approval across soft restarts; disable() clears it.
        currentSubtitleText = ""
        captionHoldUntil = Date.distantPast
        adaptiveDisplayLead = 0.8
        resetTranscriptContent()
    }

    /// Probe without starting a session — used by the UI to show a download offer *before*
    /// Menu dismissal can swallow a SwiftUI alert.
    ///
    /// Important: this must NOT fall back to another language (e.g. `cs` → `de`). Czech is not
    /// in `SpeechTranscriber.supportedLocales`; a fallback would look like a broken download.
    func probeSpeechModel(for languageTag: String?) async -> SpeechModelProbe {
        guard #available(iOS 26.0, *) else {
            return .unsupported(languageName: languageTag ?? "?")
        }
        let preferred = SpeechTranscriptionLocaleResolver.locale(fromMetadataLanguage: languageTag)
            ?? Locale(identifier: languageTag ?? "")
        let name = SpeechTranscriberAvailability.speechLocaleDisplayName(for: preferred)

        guard let locale = await SpeechTranscriptionLocaleResolver.supportedLocaleMatching(preferred) else {
            // Dictation covers more languages; report that separately so the UI can explain.
            if let _ = await DictationTranscriber.supportedLocale(equivalentTo: preferred) {
                return .unsupported(languageName: "\(name) (SpeechTranscriber; dictation-only)")
            }
            return .unsupported(languageName: name)
        }
        do {
            return try await Self.probe(locale: locale)
        } catch {
            return .unsupported(languageName: name)
        }
    }

    /// User accepted the speech-model download offer. Installs first, then starts captions.
    func approveSpeechModelDownload() {
        speechModelDownloadApproved = true
        needsSpeechModelDownload = false
        errorMessage = nil
        enableTask?.cancel()
        enableTask = Task { [weak self] in
            guard let self else { return }
            do {
                if #available(iOS 26.0, *), let locale = self.pendingSpeechModelLocale {
                    try await self.downloadSpeechModel(for: locale)
                }
                await self.runEnableSession()
            } catch is CancellationError {
                // ignore
            } catch {
                self.speechModelDownloadApproved = false
                self.needsSpeechModelDownload = true
                self.isPreparing = false
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func rebindStreamURL(_ url: URL?, extraCandidateURLs: [URL] = []) {
        if let player {
            candidateURLs = Self.buildCandidateURLs(player: player, primary: url, extras: extraCandidateURLs)
        } else if let url {
            candidateURLs = [url]
        }
        guard isTeleprompterModeActive, mode != .off else { return }
        // A stream rebind must not cancel a multi-hundred-MB model install or hide the offer.
        guard modelDownloadProgress == nil, !needsSpeechModelDownload else { return }
        enableTask?.cancel()
        enableTask = Task { [weak self] in
            await self?.runEnableSession()
        }
    }

    private static func buildCandidateURLs(player: AVPlayer, primary: URL?, extras: [URL]) -> [URL] {
        var ordered: [URL] = []
        var seen = Set<String>()
        func append(_ url: URL?) {
            guard let url else { return }
            let key = urlByRemovingApiKeyQuery(url).absoluteString
            guard seen.insert(key).inserted else { return }
            ordered.append(url)
        }
        let pooled = extras + [primary].compactMap { $0 } + [(player.currentItem?.asset as? AVURLAsset)?.url].compactMap { $0 }
        let progressive = pooled.filter { !$0.path.lowercased().contains(".m3u8") }
        let hls = pooled.filter { $0.path.lowercased().contains(".m3u8") }
        progressive.forEach { append($0) }
        hls.forEach { append($0) }
        return ordered
    }

    private func attachSubtitleClock(player: AVPlayer) {
        detachSubtitleClock()
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        subtitleTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            Task { @MainActor in
                self?.handlePlayheadTick(at: seconds)
            }
        }
    }

    private func handlePlayheadTick(at time: Double) {
        let previous = lastObservedPlayhead
        lastObservedPlayhead = time
        if let previous, abs(time - previous) > Self.seekDetectionSeconds {
            handleSeek(to: time)
        }
        refreshSubtitleText(at: time)
        updatePrepProgress(at: time)
    }

    /// After a jump the transcript usually no longer covers the playhead. Restart the feed there
    /// instead of waiting for the coarse backlog guard to notice minutes later.
    private func handleSeek(to time: Double) {
        // Never tear down a multi-hundred-MB model install just because the playhead moved.
        guard isTeleprompterModeActive, usesLookaheadFeed else { return }
        guard modelDownloadProgress == nil, !isPreparing || isTeleprompterReady else { return }

        let frontier = max(
            fedLocalSeconds,
            finalizedWords.last?.globalEnd ?? volatileTailWords.last?.globalEnd ?? sessionFeedStartGlobalTime
        )
        // A silent passage has no cue either, so coverage is judged by the fed range plus the
        // oldest cue still kept — not by finding a cue around the playhead.
        let insideFedRange = time >= sessionFeedStartGlobalTime - 1
            && time <= frontier + Self.seekRestartLagSeconds
        let cuesReachBack = subtitleCues.first.map { $0.start <= time } ?? true
        guard !(insideFedRange && cuesReachBack) else { return }

        currentSubtitleText = ""
        liveCaptionHandler?("")
        prepProgress = 0
        lookaheadSeconds = 0

        // Scrubbing produces a burst of jumps; only the position it settles on should be fed.
        seekRestartTask?.cancel()
        seekRestartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self, self.isTeleprompterModeActive else { return }
            self.enableTask?.cancel()
            self.enableTask = Task { [weak self] in
                await self?.runEnableSession()
            }
        }
    }

    private func updatePrepProgress(at time: Double) {
        guard isTeleprompterModeActive, usesLookaheadFeed else {
            if prepProgress != nil {
                prepProgress = nil
                lookaheadSeconds = 0
            }
            return
        }
        let frontier = finalizedWords.last?.globalEnd
            ?? volatileTailWords.last?.globalEnd
            ?? sessionFeedStartGlobalTime
        let lead = max(0, frontier - time)
        // Nothing left to prebuild once the whole scene is transcribed.
        let remaining = sceneDuration.map { max(0, $0 - time) } ?? .greatestFiniteMagnitude
        let target = min(Self.readyLookaheadSeconds, max(1, remaining))
        let progress = min(1, lead / target)

        if abs(lead - lookaheadSeconds) >= 0.5 { lookaheadSeconds = lead }
        if prepProgress == nil || abs((prepProgress ?? 0) - progress) >= 0.02 {
            prepProgress = progress
        }
    }

    private func detachSubtitleClock() {
        if let token = subtitleTimeObserver, let player {
            player.removeTimeObserver(token)
        }
        subtitleTimeObserver = nil
    }

    private func refreshSubtitleText(at time: Double) {
        guard isTeleprompterModeActive else {
            if !currentSubtitleText.isEmpty {
                currentSubtitleText = ""
                liveCaptionHandler?("")
            }
            return
        }

        if !isFlushingPendingSentence,
           !pendingSentenceWords.isEmpty,
           let last = pendingSentenceWords.last(where: { !$0.isWhitespaceOnly }),
           time - last.globalEnd >= Self.sentenceGapFlushSeconds {
            flushPendingSentence(force: true)
        }

        updateDisplayedSubtitle(at: time)
    }

    private func updateDisplayedSubtitle(at time: Double) {
        // Show only when the playhead is inside a cue — i.e. at/after the first word.
        let timed = captionText(at: time)
        if currentSubtitleText != timed {
            currentSubtitleText = timed
            liveCaptionHandler?(timed)
        }
    }

    /// Patches a translated sentence into its cue and re-renders if it is on screen right now.
    func applyTranslation(cueID: UUID, text: String) {
        guard let index = subtitleCues.firstIndex(where: { $0.id == cueID }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtitleCues[index].translated = clipCaption(trimmed)
        // Display-only: a full `refreshSubtitleText` can flush pending words and re-enter
        // translation while `flushPendingSentence` is still on the stack (cache hits are sync).
        if let seconds = player?.currentTime().seconds, seconds.isFinite {
            updateDisplayedSubtitle(at: seconds)
        }
    }

    private func captionText(at time: Double) -> String {
        // With a lookahead feed the cues are already minutes ahead of the playhead, so they can be
        // shown exactly on their own timestamps. Only the realtime tap needs a forward bias, and
        // there it just means "show the late cue as soon as it exists".
        let probe = usesLookaheadFeed ? time : time + Self.displayLookaheadSeconds + adaptiveDisplayLead
        if let draft = draftCue, probe >= draft.start && time < draft.end {
            return draft.text
        }
        if let cue = subtitleCues.last(where: { probe >= $0.start && time < $0.end }) {
            return cue.displayText
        }
        return ""
    }

    private func noteRecognitionLag(speechStart: Double) {
        guard let now = player?.currentTime().seconds, now.isFinite else { return }
        let lag = now - speechStart
        guard lag > 0.25 else { return }
        let target = min(Self.maxDisplayLeadSeconds, lag + 0.35)
        adaptiveDisplayLead = min(Self.maxDisplayLeadSeconds, adaptiveDisplayLead * 0.65 + target * 0.35)
    }

    private func updateDraftCue(from words: [SceneTranscriptWord]) {
        // Drafts only buy time on the realtime tap. With a lookahead feed the final arrives long
        // before the playhead gets there, and showing the hypothesis first only causes flicker.
        guard !usesLookaheadFeed else { return }
        let spoken = words.filter { !$0.isWhitespaceOnly }
        guard let first = spoken.first, let last = spoken.last else { return }
        let text = spoken.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        noteRecognitionLag(speechStart: first.globalStart)

        let readingHold = max(1.6, Double(text.count) * 0.05)
        var end = max(last.globalEnd + 0.55, first.globalStart + readingHold)
        if let now = player?.currentTime().seconds, now.isFinite {
            end = max(end, now + 1.0)
        }

        draftCue = SubtitleCue(
            start: first.globalStart,
            end: end,
            text: clipCaption(text)
        )
        if let seconds = player?.currentTime().seconds, seconds.isFinite {
            refreshSubtitleText(at: seconds)
        }
    }

    private func clipCaption(_ text: String) -> String {
        let plain = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard plain.count > Self.maxCaptionCharacters else { return plain }
        return String(plain.prefix(Self.maxCaptionCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appendFinalToSentenceCues(_ words: [SceneTranscriptWord]) {
        let spoken = words.filter { !$0.isWhitespaceOnly }
        guard !spoken.isEmpty else { return }

        // Each Speech final is a phrase/sentence unit — store timed cue, display at first-word time.
        pendingSentenceWords.append(contentsOf: words)
        flushPendingSentence(force: true)
    }

    private func pendingSentencePlainText() -> String {
        pendingSentenceWords
            .filter { !$0.isWhitespaceOnly }
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pendingSentenceSpanSeconds() -> Double {
        let spoken = pendingSentenceWords.filter { !$0.isWhitespaceOnly }
        guard let first = spoken.first, let last = spoken.last else { return 0 }
        return max(0, last.globalEnd - first.globalStart)
    }

    private func flushPendingSentence(force: Bool) {
        guard !isFlushingPendingSentence else { return }
        isFlushingPendingSentence = true
        defer { isFlushingPendingSentence = false }

        let text = pendingSentencePlainText()
        let spoken = pendingSentenceWords.filter { !$0.isWhitespaceOnly }
        guard force, !text.isEmpty, let first = spoken.first, let last = spoken.last else {
            if force {
                pendingSentenceWords = []
            }
            return
        }

        noteRecognitionLag(speechStart: first.globalStart)

        // Always anchor at the first spoken word — never shift start to "now".
        let start = first.globalStart
        let readingHold = max(1.6, Double(text.count) * 0.05)
        var end = max(last.globalEnd + 0.55, start + readingHold)
        if let now = player?.currentTime().seconds, now.isFinite {
            end = max(end, now + readingHold)
        }

        if let lastIdx = subtitleCues.indices.last, subtitleCues[lastIdx].end > start {
            let previous = subtitleCues[lastIdx]
            subtitleCues[lastIdx] = SubtitleCue(
                id: previous.id,
                start: previous.start,
                end: max(previous.start + 0.35, start - 0.05),
                text: previous.text,
                translated: previous.translated
            )
        }

        let clipped = clipCaption(text)
        let cue = SubtitleCue(start: start, end: end, text: clipped)
        subtitleCues.append(cue)
        if subtitleCues.count > 40 {
            subtitleCues.removeFirst(subtitleCues.count - 40)
        }
        pendingSentenceWords = []
        draftCue = nil
        captionHoldUntil = Date.distantPast
        // Translate after clearing pending words. Cache hits call `applyTranslation`
        // synchronously and must not see the same pending sentence still sitting here.
        translationRequestHandler?(cue.id, clipped)

        if let seconds = player?.currentTime().seconds, seconds.isFinite {
            updateDisplayedSubtitle(at: seconds)
        }
    }

    private static func endsSentence(_ text: String) -> Bool {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, "'\"»」)]}".contains(last) {
            t.removeLast()
        }
        guard let last = t.last else { return false }
        return ".!?…".contains(last)
    }

    func disable(resetError: Bool = true) async {
        enableTask?.cancel()
        enableTask = nil
        seekRestartTask?.cancel()
        seekRestartTask = nil
        generation &+= 1
        await stopSession()
        detachSubtitleClock()
        isTeleprompterModeActive = false
        isPreparing = false
        isTeleprompterReady = false
        usesLookaheadFeed = false
        cachedFeedSource = nil
        cachedLocaleResolution = nil
        lastObservedPlayhead = nil
        prepProgress = nil
        lookaheadSeconds = 0
        onLookaheadModeChanged?(false)
        mode = .off
        translationRequestHandler = nil
        if resetError { errorMessage = nil }
        localeFallbackNotice = nil
        modelDownloadProgress = nil
        downloadingModelLanguage = nil
        needsSpeechModelDownload = false
        pendingSpeechModelLocale = nil
        speechModelDownloadApproved = false
        speechAssetStatusText = nil
        currentSubtitleText = ""
        liveCaptionHandler?("")
        resetTranscriptContent()
    }

    // MARK: - Session

    private func runEnableSession() async {
        let gen = generation &+ 1
        generation = gen
        await stopSession()
        guard sessionIsCurrent(gen) else { return }
        guard isTeleprompterModeActive, mode != .off else { return }
        isPreparing = true
        isTeleprompterReady = false
        resetTranscriptContent()
        currentSubtitleText = ""
        captionHoldUntil = Date.distantPast
        do {
            try await startSession(generation: gen)
            if sessionIsCurrent(gen) {
                isPreparing = false
            }
        } catch is CancellationError {
            // ignored
        } catch {
            guard sessionIsCurrent(gen) else { return }
            if let known = error as? SceneLiveTranscriptionError,
               case .speechModelNeedsDownload = known {
                // Park in "offer download" state — do not flip the mode off.
                isPreparing = false
                needsSpeechModelDownload = true
                return
            }
            if Self.isBenignStopError(error) { return }
            isPreparing = false
            isTeleprompterModeActive = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            currentSubtitleText = ""
        }
    }

    private static func isBenignStopError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let known = error as? SceneLiveTranscriptionError {
            switch known {
            case .modelDownloadFailed, .speechModelNeedsDownload:
                return false
            default:
                break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        let message = ns.localizedDescription.lowercased()
        return message.contains("cancelled") || message.contains("canceled")
    }

    private func startSession(generation: UInt) async throws {
        guard #available(iOS 26.0, *) else {
            throw SceneLiveTranscriptionError.requiresNewerOS
        }
        try await startSessionIOS26(generation: generation)
    }

    @available(iOS 26.0, *)
    private func startSessionIOS26(generation: UInt) async throws {
        guard sessionIsCurrent(generation) else { return }
        try await ensureSpeechRecognitionAuthorized()
        guard sessionIsCurrent(generation), let player else {
            throw SceneLiveTranscriptionError.noActivePlayback
        }

        let languageTag = sceneLanguageTag
        // Refuse unsupported scene languages early. Falling back to de/en made Czech look like a
        // broken download of another language.
        if let languageTag,
           let preferred = SpeechTranscriptionLocaleResolver.locale(fromMetadataLanguage: languageTag),
           await SpeechTranscriptionLocaleResolver.supportedLocaleMatching(preferred) == nil {
            throw SceneLiveTranscriptionError.localeNotSupported
        }

        let localeResolution: SpeechTranscriptionLocaleResolver.Resolution
        if let cachedLocaleResolution {
            localeResolution = cachedLocaleResolution
        } else {
            localeResolution = try await SpeechTranscriptionLocaleResolver.resolve(
                preferredLanguageTag: languageTag
            )
            cachedLocaleResolution = localeResolution
        }
        // Always use Apple's asset-table name (`de-DE`), never a short tag (`de`).
        let speechLocale = await Self.canonicalSpeechLocale(for: localeResolution.locale)
        if localeResolution.usedFallback {
            let code = speechLocale.language.languageCode?.identifier
                ?? speechLocale.identifier(.bcp47)
            let name = Locale.current.localizedString(forLanguageCode: code) ?? code
            localeFallbackNotice = "Using \(name) speech recognition (scene language not installed)."
        } else {
            localeFallbackNotice = nil
        }

        try await ensureSpeechModel(locale: speechLocale)
        guard sessionIsCurrent(generation) else { return }
        guard sessionIsCurrent(generation) else { return }

        let playback = max(0, player.currentTime().seconds)
        let localStart = max(0, playback - Self.preRollSeconds)

        let source = await resolveFeedSource(startSeconds: localStart)
        usesLookaheadFeed = source.isLookahead
        onLookaheadModeChanged?(usesLookaheadFeed)

        if case .playerTap = source {
            guard let item = player.currentItem else {
                throw SceneLiveTranscriptionError.noActivePlayback
            }
            if StashVideoSyncManager.shared.currentItem !== item {
                StashVideoSyncManager.shared.setup(for: item)
            }
            let tapReady = await waitForPlayerAudioTap(timeoutSeconds: 8)
            guard tapReady else {
                throw SceneLiveTranscriptionError.audioSourceUnavailable
            }
        }

        let box = SpeechSessionBox()
        speechSession = box

        // Documented preset — asset requests must use the same module configuration.
        let speechTranscriber = SpeechTranscriber(
            locale: speechLocale,
            preset: .timeIndexedProgressiveTranscription
        )
        box.transcriber = speechTranscriber
        let speechAnalyzer = SpeechAnalyzer(modules: [speechTranscriber])
        box.analyzer = speechAnalyzer
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [speechTranscriber])
        else {
            throw SceneLiveTranscriptionError.conversionFailed
        }
        box.analyzerFormat = format

        // The lookahead feed runs far faster than realtime, so a bounded policy would silently
        // drop buffers and shift every following timestamp. Backlog is capped by
        // `maxAnalyzerBacklogSeconds` instead, which is a few MB of 16 kHz audio at most.
        let (stream, continuation) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .unbounded
        )
        box.inputBuilder = continuation

        let feedStart = usesLookaheadFeed ? localStart : playback
        sessionFeedStartGlobalTime = feedStart
        fedLocalSeconds = feedStart
        fedAnalyzerSeconds = 0
        feedTimeline = [FeedTimelineSegment(analyzerStart: 0, globalStart: feedStart)]

        try await speechAnalyzer.start(inputSequence: stream)
        guard sessionIsCurrent(generation) else { return }

        resultsTask = Task { [weak self] in
            await self?.consumeResults(from: speechTranscriber, generation: generation)
        }

        switch source {
        case .assetReader(let url):
            feedTask = Task { [weak self] in
                await self?.lookaheadFeedLoop(
                    url: url,
                    localStart: localStart,
                    targetFormat: format,
                    input: continuation,
                    generation: generation
                )
            }
        case .transcodePrefetch(let sceneID):
            feedTask = Task { [weak self] in
                await self?.transcodePrefetchFeedLoop(
                    sceneID: sceneID,
                    localStart: localStart,
                    targetFormat: format,
                    input: continuation,
                    generation: generation
                )
            }
        case .playerTap:
            feedTask = Task { [weak self] in
                await self?.playerTapFeedLoop(
                    targetFormat: format,
                    input: continuation,
                    generation: generation
                )
            }
        }
    }

    // MARK: - Feed source selection

    private enum FeedSource {
        case assetReader(URL)
        case transcodePrefetch(sceneID: String)
        case playerTap

        var isLookahead: Bool {
            if case .playerTap = self { return false }
            return true
        }
    }

    private func resolveFeedSource(startSeconds: Double) async -> FeedSource {
        // Probing candidates costs seconds; a seek must not pay that price again.
        if let cachedFeedSource {
            let staleTranscode: Bool
            if case .transcodePrefetch = cachedFeedSource { staleTranscode = transcodePrefetchFailed }
            else { staleTranscode = false }
            if !staleTranscode { return cachedFeedSource }
        }
        let source = await pickFeedSource(startSeconds: startSeconds)
        cachedFeedSource = source
        return source
    }

    private func pickFeedSource(startSeconds: Double) async -> FeedSource {
        if let url = await firstReadableCandidate(from: candidateURLs, startSeconds: startSeconds) {
            return .assetReader(url)
        }
        if #available(iOS 26.0, *),
           !transcodePrefetchFailed,
           TabManager.shared.isLiveCaptionLookaheadEnabled,
           let sceneID,
           SceneTranscodeAudioPrefetcher.isAvailable() {
            return .transcodePrefetch(sceneID: sceneID)
        }
        return .playerTap
    }

    /// Live transcodes are piped without range support, so `AVAssetReader` can never seek them.
    private static func isLiveTranscodeURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix("stream.mp4")
            || path.hasSuffix("stream.webm")
            || path.hasSuffix("stream.mkv")
            || path.contains(".m3u8")
            || path.contains(".mpd")
    }

    /// Seconds a single candidate may spend proving itself before the next tier is tried.
    private static let candidateProbeTimeout: Double = 1.8
    /// Total probing budget — beyond this the transcode feed starts sooner than any winner could.
    private static let candidateProbeBudget: Double = 4.0

    private func firstReadableCandidate(from urls: [URL], startSeconds: Double) async -> URL? {
        let deadline = Date().addingTimeInterval(Self.candidateProbeBudget)
        for url in urls where !Self.isLiveTranscodeURL(url) {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0.3 else { return nil }
            let probe = Task.detached(priority: .userInitiated) {
                await Self.canReadAudio(from: url, startSeconds: startSeconds)
            }
            let timeout = Task {
                let limit = min(Self.candidateProbeTimeout, remaining)
                try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
                probe.cancel()
            }
            let readable = await probe.value
            timeout.cancel()
            if readable { return url }
        }
        return nil
    }

    private nonisolated static func canReadAudio(from url: URL, startSeconds: Double) async -> Bool {
        do {
            let asset = await MainActor.run { makeAuthenticatedAsset(for: url) }
            _ = try await asset.load(.isPlayable)
            guard !Task.isCancelled else { return false }
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard !Task.isCancelled, let audioTrack = tracks.first else { return false }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            guard reader.canAdd(output) else { return false }
            reader.add(output)
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: startSeconds, preferredTimescale: 600),
                duration: CMTime(seconds: 0.5, preferredTimescale: 600)
            )
            guard reader.startReading() else { return false }
            // Pull one sample to confirm the reader actually works.
            let ok = output.copyNextSampleBuffer() != nil || reader.status == .completed
            reader.cancelReading()
            return ok && !Task.isCancelled
        } catch {
            return false
        }
    }

    private func waitForPlayerAudioTap(timeoutSeconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if StashVideoSyncManager.shared.hasAudioTapInstalled { return true }
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return StashVideoSyncManager.shared.hasAudioTapInstalled
    }

    private func stopSession() async {
        feedTask?.cancel()
        resultsTask?.cancel()
        feedTask = nil
        resultsTask = nil
        StashVideoSyncManager.shared.transcriptionPCMHandler = nil
        if #available(iOS 26.0, *), let box = speechSession as? SpeechSessionBox {
            box.inputBuilder?.finish()
            box.inputBuilder = nil
            if let analyzer = box.analyzer {
                await analyzer.cancelAndFinishNow()
            }
            box.analyzer = nil
            box.transcriber = nil
            box.analyzerFormat = nil
        }
        speechSession = nil
        feedTimeline = []
    }

    // MARK: - Lookahead feed (low lag)

    @available(iOS 26.0, *)
    private func lookaheadFeedLoop(
        url: URL,
        localStart: Double,
        targetFormat: AVAudioFormat,
        input: AsyncStream<AnalyzerInput>.Continuation,
        generation: UInt
    ) async {
        do {
            try await feedSingleTrack(
                url: url,
                localStartSeconds: localStart,
                targetFormat: targetFormat,
                input: input,
                generation: generation
            )
            input.finish()
        } catch is CancellationError {
            input.finish()
        } catch {
            input.finish()
            if sessionIsCurrent(generation), !Self.isBenignStopError(error) {
                // Reader died mid-session — fall back to tap without killing captions entirely.
                print("💬 Lookahead feed failed, falling back to tap: \(error.localizedDescription)")
                if let item = player?.currentItem {
                    usesLookaheadFeed = false
                    onLookaheadModeChanged?(false)
                    if StashVideoSyncManager.shared.currentItem !== item {
                        StashVideoSyncManager.shared.setup(for: item)
                    }
                    // Can't easily restart analyzer input after finish; restart whole session.
                    enableTask?.cancel()
                    enableTask = Task { [weak self] in
                        // Drop failed progressive URL so next attempt uses tap.
                        self?.candidateURLs.removeAll { $0 == url }
                        await self?.runEnableSession()
                    }
                } else if sessionIsCurrent(generation) {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private nonisolated func feedSingleTrack(
        url: URL,
        localStartSeconds: Double,
        targetFormat: AVAudioFormat,
        input: AsyncStream<AnalyzerInput>.Continuation,
        generation: UInt
    ) async throws {
        let asset = await MainActor.run { makeAuthenticatedAsset(for: url) }
        _ = try await asset.load(.isPlayable, .duration)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else {
            throw SceneLiveTranscriptionError.audioSourceUnavailable
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else { throw SceneLiveTranscriptionError.conversionFailed }
        reader.add(output)

        let startTime = CMTime(seconds: localStartSeconds, preferredTimescale: 600)
        reader.timeRange = CMTimeRange(start: startTime, duration: .positiveInfinity)
        guard reader.startReading() else {
            throw reader.error ?? SceneLiveTranscriptionError.audioSourceUnavailable
        }
        defer { if reader.status == .reading { reader.cancelReading() } }

        var localFed = localStartSeconds
        var audioConverter: SceneTranscriptionAudioConverter?

        while reader.status == .reading, !Task.isCancelled {
            let step = await nextFeedStep(fedLocalSeconds: localFed, generation: generation)
            switch step {
            case .restart:
                return
            case .wait(let ns):
                try await Task.sleep(nanoseconds: ns)
                continue
            case .feed:
                break
            }

            for _ in 0..<Self.feedBuffersPerStateCheck {
                guard reader.status == .reading, !Task.isCancelled else { break }
                guard let sample = output.copyNextSampleBuffer() else {
                    if reader.status == .failed {
                        throw reader.error ?? SceneLiveTranscriptionError.audioSourceUnavailable
                    }
                    if reader.status == .completed { return }
                    try await Task.sleep(nanoseconds: 40_000_000)
                    break
                }
                guard let buffer = Self.sampleBufferToPCMBuffer(sample) else { continue }
                if audioConverter == nil
                    || audioConverter?.sourceFormat.sampleRate != buffer.format.sampleRate
                    || audioConverter?.sourceFormat.channelCount != buffer.format.channelCount {
                    audioConverter = SceneTranscriptionAudioConverter(
                        sourceFormat: buffer.format,
                        targetFormat: targetFormat
                    )
                }
                guard let converter = audioConverter else {
                    throw SceneLiveTranscriptionError.conversionFailed
                }
                let converted = try converter.convert(buffer, to: targetFormat)
                guard converted.frameLength > 0 else { continue }
                input.yield(AnalyzerInput(buffer: converted))

                let dur = CMSampleBufferGetDuration(sample).seconds
                let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                if pts.isFinite {
                    localFed = pts + (dur.isFinite ? dur : 0)
                }
                await updateFedSeconds(local: localFed, analyzerDelta: Double(converted.frameLength) / targetFormat.sampleRate)
            }
            await Task.yield()
        }
        if Task.isCancelled { throw CancellationError() }
        if reader.status == .failed {
            throw reader.error ?? SceneLiveTranscriptionError.audioSourceUnavailable
        }
    }

    private enum FeedStep {
        case feed
        case wait(UInt64)
        case restart
    }

    private func nextFeedStep(fedLocalSeconds: Double, generation: UInt) async -> FeedStep {
        guard sessionIsCurrent(generation), let player else { return .restart }
        let playback = max(0, player.currentTime().seconds)
        if playback - fedLocalSeconds > Self.feedBehindRestartSeconds {
            enableTask?.cancel()
            enableTask = Task { [weak self] in
                await self?.runEnableSession()
            }
            return .restart
        }
        let transcribedFrontier = finalizedWords.last?.globalEnd
            ?? volatileTailWords.last?.globalEnd
            ?? sessionFeedStartGlobalTime
        let backlog = fedLocalSeconds - transcribedFrontier
        if backlog > Self.maxAnalyzerBacklogSeconds {
            return .wait(80_000_000)
        }
        let lead = fedLocalSeconds - playback
        if lead > Self.preRollSeconds + Self.leadBufferSeconds {
            let playing = player.timeControlStatus == .playing
            return .wait(playing ? 120_000_000 : 300_000_000)
        }
        return .feed
    }

    private func updateFedSeconds(local: Double, analyzerDelta: Double) {
        fedLocalSeconds = local
        fedAnalyzerSeconds += analyzerDelta
    }

    /// Chunked feeds jump in media time; record where the analyzer timeline continues.
    private func appendFeedTimeline(globalStart: Double) {
        feedTimeline.append(FeedTimelineSegment(analyzerStart: fedAnalyzerSeconds, globalStart: globalStart))
        if feedTimeline.count > 60 {
            feedTimeline.removeFirst(feedTimeline.count - 60)
        }
    }

    // MARK: - Dedicated transcode feed (low lag on transcoded sources)

    @available(iOS 26.0, *)
    private func transcodePrefetchFeedLoop(
        sceneID: String,
        localStart: Double,
        targetFormat: AVAudioFormat,
        input: AsyncStream<AnalyzerInput>.Continuation,
        generation: UInt
    ) async {
        let prefetcher = SceneTranscodeAudioPrefetcher(sceneID: sceneID, mediaDuration: sceneDuration)
        let delegate = SceneTranscodeAudioPrefetcher.Delegate(
            anchor: { [weak self] globalStart in
                await self?.appendFeedTimeline(globalStart: globalStart)
            },
            progress: { [weak self] frontier, analyzerDelta in
                await self?.updateFedSeconds(local: frontier, analyzerDelta: analyzerDelta)
            },
            step: { [weak self] frontier in
                guard let self else { return .restart }
                switch await self.nextFeedStep(fedLocalSeconds: frontier, generation: generation) {
                case .feed: return .feed
                case .wait(let nanoseconds): return .wait(nanoseconds)
                case .restart: return .restart
                }
            }
        )

        do {
            _ = try await prefetcher.run(
                from: localStart,
                targetFormat: targetFormat,
                input: input,
                delegate: delegate
            )
            input.finish()
        } catch is CancellationError {
            input.finish()
        } catch {
            input.finish()
            guard sessionIsCurrent(generation), !Self.isBenignStopError(error) else { return }
            print("💬 Transcode prefetch failed, falling back to tap: \(error.localizedDescription)")
            transcodePrefetchFailed = true
            usesLookaheadFeed = false
            onLookaheadModeChanged?(false)
            enableTask?.cancel()
            enableTask = Task { [weak self] in
                await self?.runEnableSession()
            }
        }
    }

    // MARK: - Tap fallback

    @available(iOS 26.0, *)
    private func playerTapFeedLoop(
        targetFormat: AVAudioFormat,
        input: AsyncStream<AnalyzerInput>.Continuation,
        generation: UInt
    ) async {
        // Dropping tap buffers tears holes into the transcript; keep the oldest audio instead.
        let (pcmStream, pcmCont) = AsyncStream.makeStream(
            of: AVAudioPCMBuffer.self,
            bufferingPolicy: .bufferingOldest(96)
        )
        StashVideoSyncManager.shared.transcriptionPCMHandler = { buffer in
            pcmCont.yield(buffer)
        }
        defer {
            StashVideoSyncManager.shared.transcriptionPCMHandler = nil
            pcmCont.finish()
            input.finish()
        }

        var audioConverter: SceneTranscriptionAudioConverter?
        var lastPlayback = sessionFeedStartGlobalTime

        do {
            for await buffer in pcmStream {
                guard sessionIsCurrent(generation), !Task.isCancelled else { break }

                let playback = max(0, player?.currentTime().seconds ?? lastPlayback)
                if abs(playback - lastPlayback) > Self.feedReseekLagSeconds {
                    enableTask?.cancel()
                    enableTask = Task { [weak self] in
                        await self?.runEnableSession()
                    }
                    break
                }
                lastPlayback = playback

                if audioConverter == nil
                    || audioConverter?.sourceFormat.sampleRate != buffer.format.sampleRate
                    || audioConverter?.sourceFormat.channelCount != buffer.format.channelCount {
                    audioConverter = SceneTranscriptionAudioConverter(
                        sourceFormat: buffer.format,
                        targetFormat: targetFormat
                    )
                }
                guard let converter = audioConverter else {
                    throw SceneLiveTranscriptionError.conversionFailed
                }
                let converted = try converter.convert(buffer, to: targetFormat)
                guard converted.frameLength > 0 else { continue }
                input.yield(AnalyzerInput(buffer: converted))

                let delta = Double(converted.frameLength) / targetFormat.sampleRate
                fedAnalyzerSeconds += delta
                fedLocalSeconds = sessionFeedStartGlobalTime + fedAnalyzerSeconds
            }
        } catch is CancellationError {
            // ignored
        } catch {
            if sessionIsCurrent(generation), !Self.isBenignStopError(error) {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Results

    @available(iOS 26.0, *)
    private func consumeResults(from transcriber: SpeechTranscriber, generation: UInt) async {
        do {
            for try await result in transcriber.results {
                guard sessionIsCurrent(generation) else { return }
                if result.isFinal {
                    applyFinal(result)
                } else {
                    let now = Date()
                    let minInterval: TimeInterval = 0.04
                    guard now.timeIntervalSince(lastVolatilePublish) >= minInterval else { continue }
                    lastVolatilePublish = now
                    applyVolatile(result)
                }
            }
        } catch is CancellationError {
            // ignored
        } catch {
            if sessionIsCurrent(generation), !Self.isBenignStopError(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    @available(iOS 26.0, *)
    private func applyFinal(_ result: SpeechTranscriber.Result) {
        let newWords = words(from: result.text, volatile: false)
        guard !newWords.isEmpty else { return }
        finalizedWords.append(contentsOf: newWords)
        lineAccumulator.appendFinalizedWords(newWords)
        lineAccumulator.pruneClosedLines(keeping: Self.maxClosedLinesKept, chunk: 20)
        volatileTailWords = []
        appendFinalToSentenceCues(newWords)
        publishWords()
        updateReadiness()
        if let seconds = player?.currentTime().seconds, seconds.isFinite {
            refreshSubtitleText(at: seconds)
        }
    }

    @available(iOS 26.0, *)
    private func applyVolatile(_ result: SpeechTranscriber.Result) {
        // Publish a full-hypothesis draft early so the sentence can appear at the first word
        // once the playhead reaches it (instead of waiting for the late final).
        volatileTailWords = words(from: result.text, volatile: true)
        updateDraftCue(from: volatileTailWords)
        publishWords()
    }

    @available(iOS 26.0, *)
    private func words(from text: AttributedString, volatile: Bool) -> [SceneTranscriptWord] {
        var out: [SceneTranscriptWord] = []
        for run in text.runs {
            guard let tr = run.audioTimeRange else { continue }
            let start = globalTime(forAnalyzerSeconds: tr.start.seconds)
            let end = max(start, globalTime(forAnalyzerSeconds: tr.end.seconds))
            let chunk = String(text[run.range].characters)
            guard !chunk.isEmpty else { continue }
            out.append(contentsOf: splitIntoWords(chunk: chunk, start: start, end: end, volatile: volatile))
        }
        if out.isEmpty {
            let plain = String(text.characters)
            guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            let fallback = finalizedWords.last?.globalEnd ?? sessionFeedStartGlobalTime
            out.append(contentsOf: splitIntoWords(
                chunk: plain, start: fallback, end: fallback + 0.01, volatile: volatile
            ))
        }
        return out
    }

    private func splitIntoWords(chunk: String, start: Double, end: Double, volatile: Bool) -> [SceneTranscriptWord] {
        var tokens: [String] = []
        var current = ""
        for ch in chunk {
            if ch.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(ch))
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        let spoken = tokens.filter { !$0.allSatisfy(\.isWhitespace) }
        let spokenCount = max(1, spoken.count)
        var spokenIndex = 0
        let duration = max(0.01, end - start)
        var result: [SceneTranscriptWord] = []

        for token in tokens {
            let isSpace = token.allSatisfy(\.isWhitespace)
            let wStart: Double
            let wEnd: Double
            if isSpace {
                wStart = start
                wEnd = start
            } else {
                wStart = start + duration * Double(spokenIndex) / Double(spokenCount)
                wEnd = start + duration * Double(spokenIndex + 1) / Double(spokenCount)
                spokenIndex += 1
            }
            let display = isSpace ? token : token + " "
            result.append(SceneTranscriptWord(
                id: "w-\(Int((wStart * 1000).rounded()))-\(result.count)",
                text: display,
                globalStart: wStart,
                globalEnd: wEnd,
                isVolatile: volatile
            ))
        }
        return result
    }

    private func globalTime(forAnalyzerSeconds analyzerSeconds: Double) -> Double {
        guard let segment = feedTimeline.last(where: { analyzerSeconds >= $0.analyzerStart })
                ?? feedTimeline.first else {
            return sessionFeedStartGlobalTime + analyzerSeconds
        }
        return segment.globalStart + (analyzerSeconds - segment.analyzerStart)
    }

    private func publishWords() {
        words = finalizedWords + volatileTailWords
        publishLines()
    }

    private func publishLines() {
        let closed = lineAccumulator.publishedLines()
        let volatileLines = SceneTranscriptLineAccumulator.makeLines(
            from: volatileTailWords,
            maxCharactersPerLine: lineAccumulator.maxCharactersPerLine,
            volatile: true
        )
        transcriptLines = closed + volatileLines
    }

    private func updateReadiness() {
        let transcribed = max(0, (finalizedWords.last?.globalEnd ?? words.last?.globalEnd ?? 0) - sessionFeedStartGlobalTime)
        if lineAccumulator.closedLines.count >= Self.minClosedLinesForDisplay
            || transcribed >= Self.minTranscribedSecondsForDisplay
            || !currentSubtitleText.isEmpty {
            isTeleprompterReady = true
        }
    }

    private func resetTranscriptContent() {
        finalizedWords = []
        volatileTailWords = []
        words = []
        transcriptLines = []
        subtitleCues = []
        pendingSentenceWords = []
        isFlushingPendingSentence = false
        draftCue = nil
        lineAccumulator.reset()
    }

    private func sessionIsCurrent(_ gen: UInt) -> Bool { gen == generation }

    // MARK: - Auth / model

    private func ensureSpeechRecognitionAuthorized() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
            }
            guard granted == .authorized else {
                throw SceneLiveTranscriptionError.speechRecognitionDenied
            }
        case .denied, .restricted:
            throw SceneLiveTranscriptionError.speechRecognitionDenied
        @unknown default:
            throw SceneLiveTranscriptionError.speechRecognitionDenied
        }
    }

    /// Skill pattern: request assets for the exact module configuration the session will use.
    /// Never auto-download — missing models surface as an explicit user offer.
    @available(iOS 26.0, *)
    private func ensureSpeechModel(locale: Locale) async throws {
        let installLocale = await Self.canonicalSpeechLocale(for: locale)
        switch try await Self.probe(locale: installLocale) {
        case .ready:
            needsSpeechModelDownload = false
            pendingSpeechModelLocale = nil
            speechModelDownloadApproved = false
            modelDownloadProgress = nil
            downloadingModelLanguage = nil
            speechAssetStatusText = nil
            return
        case .unsupported:
            throw SceneLiveTranscriptionError.localeNotSupported
        case .needsDownload(let name, _), .downloading(let name, _):
            pendingSpeechModelLocale = installLocale
            downloadingModelLanguage = name
            if speechModelDownloadApproved {
                try await downloadSpeechModel(for: installLocale)
                return
            }
            needsSpeechModelDownload = true
            modelDownloadProgress = nil
            throw SceneLiveTranscriptionError.speechModelNeedsDownload(name)
        }
    }

    /// Apple docs: `downloadAndInstall()` returns after the *initial* attempt. Status can stay
    /// `.downloading` (queued) with `fractionCompleted == 0` — we must wait until `.installed`.
    @available(iOS 26.0, *)
    private func downloadSpeechModel(for locale: Locale) async throws {
        let installLocale = await Self.canonicalSpeechLocale(for: locale)
        let code = installLocale.language.languageCode?.identifier
            ?? installLocale.identifier(.bcp47)
        let languageName = Locale.current.localizedString(forLanguageCode: code) ?? code
        downloadingModelLanguage = languageName
        pendingSpeechModelLocale = installLocale
        isPreparing = true
        modelDownloadProgress = 0
        speechAssetStatusText = "requesting"

        await Self.makeReservationRoom(for: installLocale)

        let transcriber = SpeechTranscriber(
            locale: installLocale,
            preset: .timeIndexedProgressiveTranscription
        )

        // Prefer a fresh request; nil means already installed.
        var request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
        if request == nil {
            let status = await AssetInventory.status(forModules: [transcriber])
            speechAssetStatusText = "\(status)"
            if status == .installed {
                finishModelDownloadSuccess()
                return
            }
            // Status downloading/supported but no request — free slots and retry once.
            await Self.makeReservationRoom(for: installLocale, force: true)
            request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
        }

        guard let request else {
            let status = await AssetInventory.status(forModules: [transcriber])
            let reservedCount = await AssetInventory.reservedLocales.count
            throw SceneLiveTranscriptionError.modelDownloadFailed(
                "No install request (status: \(status), reserved: \(reservedCount)/\(AssetInventory.maximumReservedLocales))"
            )
        }

        let progress = request.progress
        let reporter = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let fraction = max(0, min(1, progress.fractionCompleted))
                self?.modelDownloadProgress = fraction
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { reporter.cancel() }

        // Kick (and periodically re-kick) the system installer. Idempotent per Apple docs.
        let deadline = Date().addingTimeInterval(15 * 60)
        var lastKick = Date.distantPast
        while Date() < deadline {
            try Task.checkCancellation()
            let status = await AssetInventory.status(forModules: [transcriber])
            speechAssetStatusText = "\(status)"
            print("💬 Speech asset \(installLocale.identifier(.bcp47)): \(status) progress=\(progress.fractionCompleted)")

            let installed = await SpeechTranscriber.installedLocales
            if status == .installed
                || SpeechTranscriptionLocaleResolver.matchLocale(installLocale, in: installed) != nil {
                finishModelDownloadSuccess()
                return
            }
            if status == .unsupported {
                throw SceneLiveTranscriptionError.localeNotSupported
            }

            if Date().timeIntervalSince(lastKick) >= 8 {
                lastKick = Date()
                do {
                    try await request.downloadAndInstall()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Initial attempt often fails while the system queues a later retry.
                    print("💬 downloadAndInstall interim error: \(error.localizedDescription)")
                    speechAssetStatusText = error.localizedDescription
                }
            }

            // Progress often stays 0 while queued — still show activity via status text.
            if progress.fractionCompleted > (modelDownloadProgress ?? 0) {
                modelDownloadProgress = progress.fractionCompleted
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        throw SceneLiveTranscriptionError.modelDownloadFailed(
            "Timed out while iOS reported \(speechAssetStatusText ?? "unknown") for \(languageName)"
        )
    }

    private func finishModelDownloadSuccess() {
        needsSpeechModelDownload = false
        pendingSpeechModelLocale = nil
        speechModelDownloadApproved = false
        modelDownloadProgress = nil
        downloadingModelLanguage = nil
        speechAssetStatusText = nil
    }

    @available(iOS 26.0, *)
    private static func probe(locale: Locale) async throws -> SpeechModelProbe {
        let code = locale.language.languageCode?.identifier ?? locale.identifier(.bcp47)
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code
        let id = locale.identifier(.bcp47)

        let installedLocales = await SpeechTranscriber.installedLocales
        if SpeechTranscriptionLocaleResolver.matchLocale(locale, in: installedLocales) != nil {
            return .ready
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedProgressiveTranscription
        )
        let status = await AssetInventory.status(forModules: [transcriber])
        let reservedIDs = await AssetInventory.reservedLocales.map { $0.identifier(.bcp47) }
        print("💬 probe \(id): status=\(status) reserved=\(reservedIDs)")

        switch status {
        case .installed:
            return .ready
        case .downloading:
            return .downloading(languageName: name, localeIdentifier: id)
        case .supported:
            return .needsDownload(languageName: name, localeIdentifier: id)
        case .unsupported:
            return .unsupported(languageName: name)
        @unknown default:
            // Fall back to whether an install request can be created.
            if let _ = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                return .needsDownload(languageName: name, localeIdentifier: id)
            }
            return .unsupported(languageName: name)
        }
    }

    @available(iOS 26.0, *)
    private static func canonicalSpeechLocale(for locale: Locale) async -> Locale {
        await SpeechTranscriptionLocaleResolver.supportedLocaleMatching(locale) ?? locale
    }

    /// Free reservation slots so `assetInstallationRequest` can auto-reserve the target locale.
    @available(iOS 26.0, *)
    private static func makeReservationRoom(for locale: Locale, force: Bool = false) async {
        var reserved = await AssetInventory.reservedLocales
        if reserved.contains(where: {
            SpeechTranscriptionLocaleResolver.matchLocale(locale, in: [$0]) != nil
        }) {
            return
        }

        let limit = max(1, AssetInventory.maximumReservedLocales)
        let targetCount = force ? max(0, limit - 1) : limit - 1
        while reserved.count > targetCount {
            guard let victim = reserved.last(where: {
                SpeechTranscriptionLocaleResolver.matchLocale(locale, in: [$0]) == nil
            }) else { break }
            _ = await AssetInventory.release(reservedLocale: victim)
            reserved = await AssetInventory.reservedLocales
        }
    }

    nonisolated private static func sampleBufferToPCMBuffer(_ sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(sample) else { return nil }
        guard let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else { return nil }
        var asbd = asbdPtr.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return buffer
    }
}
#endif
