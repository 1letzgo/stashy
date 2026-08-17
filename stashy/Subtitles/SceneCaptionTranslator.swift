#if !os(tvOS)
import Foundation
import Translation

/// On-device translation for live captions.
///
/// `TranslationSession` has no public initializer — it is handed to us by SwiftUI's
/// `translationTask` modifier and is only valid for as long as that closure runs. So the session
/// never gets stored for later use; instead `run(session:)` stays parked inside the closure and
/// drains a queue of caption sentences until the view goes away or the language pair changes.
@MainActor
final class SceneCaptionTranslator: ObservableObject {
    struct Job: Identifiable {
        let id: UUID
        let key: String
        let text: String
    }

    @Published private(set) var configuration: TranslationSession.Configuration?
    /// A language pair is configured, so captions are expected to arrive translated.
    @Published private(set) var isEnabled = false
    @Published private(set) var isActive = false
    @Published private(set) var statusMessage: String?
    /// The pair is translatable but its language pack is still missing, and the user has not
    /// asked for the download yet. Captions keep running untranslated meanwhile.
    @Published private(set) var needsLanguageDownload = false
    @Published private(set) var isDownloadingLanguagePack = false

    /// Delivers `(cueID, translatedText)` once a sentence has been translated.
    var onTranslated: ((UUID, String) -> Void)?

    private var queue: [Job] = []
    private var cache: [String: String] = [:]
    private var waiter: CheckedContinuation<Void, Never>?
    private var sourceCode: String?
    private var targetCode: String?
    /// Set only after an explicit download tap — never from a flaky `.supported` status.
    private var downloadApproved = false
    /// Pairs that already prepared successfully this process. Apple's status API sometimes
    /// reports `.supported` for installed packs when short codes like `de` are used.
    private static var verifiedInstalledPairs = Set<String>()
    private static let maxBatchSize = 24
    private static let maxCacheEntries = 400
    private static let maxQueuedJobs = 60

    // MARK: - Lifecycle

    /// Why a language pair can or cannot be translated, so the UI can name the actual culprit
    /// instead of blaming the target language for an unsupported scene language.
    enum Availability {
        case ready
        case needsDownload
        case sourceUnsupported(String)
        case targetUnsupported(String)
        case pairUnsupported(source: String, target: String)
    }

    static func availability(from source: String?, to target: String) async -> Availability {
        guard let sourceCode = SubtitleTargetLanguage.canonicalCode(from: source) else {
            return .sourceUnsupported(source?.uppercased() ?? "?")
        }
        let targetCode = SubtitleTargetLanguage.canonicalCode(from: target) ?? target.lowercased()

        if verifiedInstalledPairs.contains(pairKey(sourceCode, targetCode)) {
            return .ready
        }

        let availability = LanguageAvailability()
        let supported = await availability.supportedLanguages

        // WWDC: prefer languages from `supportedLanguages`, not hand-rolled short identifiers.
        guard let sourceLanguage = matchSupportedLanguage(sourceCode, in: supported) else {
            return .sourceUnsupported(sourceCode.uppercased())
        }
        guard let targetLanguage = matchSupportedLanguage(targetCode, in: supported) else {
            return .targetUnsupported(targetCode.uppercased())
        }

        // Short `de` vs `de-DE` intermittently disagrees with the installed pack — try a few.
        var sawSupported = false
        for sourceCandidate in languageCandidates(for: sourceCode, matched: sourceLanguage) {
            for targetCandidate in languageCandidates(for: targetCode, matched: targetLanguage) {
                switch await availability.status(from: sourceCandidate, to: targetCandidate) {
                case .installed:
                    verifiedInstalledPairs.insert(pairKey(sourceCode, targetCode))
                    return .ready
                case .supported:
                    sawSupported = true
                case .unsupported:
                    continue
                @unknown default:
                    continue
                }
            }
        }

        if sawSupported { return .needsDownload }
        return .pairUnsupported(source: sourceCode.uppercased(), target: targetCode.uppercased())
    }

    func activate(source: String?, target: String, downloadApproved: Bool = false) {
        guard let sourceCode = SubtitleTargetLanguage.canonicalCode(from: source) else {
            deactivate()
            return
        }
        let targetCode = SubtitleTargetLanguage.canonicalCode(from: target) ?? target.lowercased()
        let sourceLanguage = Locale.Language(identifier: Self.preferredIdentifier(for: sourceCode))
        let targetLanguage = Locale.Language(identifier: Self.preferredIdentifier(for: targetCode))
        let next = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
        isEnabled = true
        self.sourceCode = sourceCode
        self.targetCode = targetCode
        let alreadyVerified = Self.verifiedInstalledPairs.contains(Self.pairKey(sourceCode, targetCode))
        self.downloadApproved = downloadApproved && !alreadyVerified
        needsLanguageDownload = false
        guard configuration != next else { return }
        queue.removeAll()
        cache.removeAll()
        configuration = next
    }

    /// Called from the user-facing download offer. Re-runs the session so `prepareTranslation()`
    /// may now bring up the system download sheet.
    func approveDownload() {
        guard isEnabled, configuration != nil else { return }
        needsLanguageDownload = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, self.isEnabled, var config = self.configuration else { return }
            self.downloadApproved = true
            config.invalidate()
            self.configuration = config
        }
    }

    func deactivate() {
        isEnabled = false
        configuration = nil
        queue.removeAll()
        cache.removeAll()
        statusMessage = nil
        needsLanguageDownload = false
        isDownloadingLanguagePack = false
        downloadApproved = false
        sourceCode = nil
        targetCode = nil
        resumeWaiter()
    }

    // MARK: - Requests

    func requestTranslation(id: UUID, text: String) {
        guard configuration != nil, !needsLanguageDownload else { return }
        let key = Self.cacheKey(for: text)
        guard !key.isEmpty else { return }
        if let cached = cache[key] {
            Task { @MainActor [weak self] in
                self?.onTranslated?(id, cached)
            }
            return
        }
        queue.append(Job(id: id, key: key, text: text))
        if queue.count > Self.maxQueuedJobs {
            queue.removeFirst(queue.count - Self.maxQueuedJobs)
        }
        resumeWaiter()
    }

    // MARK: - Session loop

    /// Runs inside `translationTask`; returns when the task is cancelled.
    func run(session: TranslationSession) async {
        isActive = true
        defer {
            isActive = false
            statusMessage = nil
            isDownloadingLanguagePack = false
        }

        let prepared = await prepareSession(session)
        guard prepared else { return }

        while !Task.isCancelled {
            if queue.isEmpty {
                await waitForWork()
                continue
            }
            let batch = Array(queue.prefix(Self.maxBatchSize))
            queue.removeFirst(batch.count)
            guard !Task.isCancelled else { return }

            let requests = batch.map {
                TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id.uuidString)
            }
            do {
                let responses = try await session.translations(from: requests)
                for response in responses {
                    guard let identifier = response.clientIdentifier,
                          let job = batch.first(where: { $0.id.uuidString == identifier })
                    else { continue }
                    let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !translated.isEmpty else { continue }
                    store(translated, for: job.key)
                    onTranslated?(job.id, translated)
                }
            } catch is CancellationError {
                return
            } catch {
                statusMessage = error.localizedDescription
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    /// Returns `true` when the session is ready to translate.
    private func prepareSession(_ session: TranslationSession) async -> Bool {
        let alreadyVerified: Bool = {
            guard let sourceCode, let targetCode else { return false }
            return Self.verifiedInstalledPairs.contains(Self.pairKey(sourceCode, targetCode))
        }()
        if alreadyVerified {
            // Still need prepare on a fresh session object, but never nag about downloads.
            do {
                try await session.prepareTranslation()
                needsLanguageDownload = false
                return true
            } catch is CancellationError {
                return false
            } catch {
                statusMessage = error.localizedDescription
                return false
            }
        }

        let statusSaysMissing = await isLanguagePackMissing()
        if statusSaysMissing {
            if downloadApproved {
                isDownloadingLanguagePack = true
            }
            // Always try prepare first. Installed packs sometimes report `.supported`;
            // prepare succeeds quietly and we remember the pair.
            do {
                try await session.prepareTranslation()
                markPairVerified()
                needsLanguageDownload = false
                return true
            } catch is CancellationError {
                return false
            } catch {
                if Self.isUserCancelled(error) || Self.isMissingLanguagePack(error) {
                    needsLanguageDownload = !downloadApproved || Self.isUserCancelled(error)
                    downloadApproved = false
                    return false
                }
                // Ambiguous error: do not claim the DE pack is missing.
                statusMessage = error.localizedDescription
                return false
            }
        }

        do {
            try await session.prepareTranslation()
            markPairVerified()
            needsLanguageDownload = false
            return true
        } catch is CancellationError {
            return false
        } catch {
            if Self.isUserCancelled(error) {
                downloadApproved = false
                needsLanguageDownload = true
            } else if Self.isMissingLanguagePack(error) {
                downloadApproved = false
                needsLanguageDownload = true
            } else {
                statusMessage = error.localizedDescription
            }
            return false
        }
    }

    private func markPairVerified() {
        guard let sourceCode, let targetCode else { return }
        Self.verifiedInstalledPairs.insert(Self.pairKey(sourceCode, targetCode))
    }

    private func isLanguagePackMissing() async -> Bool {
        guard let sourceCode, let targetCode else { return false }
        if Self.verifiedInstalledPairs.contains(Self.pairKey(sourceCode, targetCode)) {
            return false
        }
        if case .needsDownload = await Self.availability(from: sourceCode, to: targetCode) {
            return true
        }
        return false
    }

    private static func isUserCancelled(_ error: Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .userCancelled { return true }
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError
    }

    /// System download sheet / missing-asset failures — not generic prepare errors.
    private static func isMissingLanguagePack(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        if text.contains("download") || text.contains("install") || text.contains("language") {
            return true
        }
        let ns = error as NSError
        return ns.domain.lowercased().contains("translation")
    }

    private func waitForWork() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                guard queue.isEmpty, !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                waiter?.resume()
                waiter = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resumeWaiter() }
        }
    }

    private func resumeWaiter() {
        guard let pending = waiter else { return }
        waiter = nil
        pending.resume()
    }

    private func store(_ translated: String, for key: String) {
        if cache.count >= Self.maxCacheEntries { cache.removeAll() }
        cache[key] = translated
    }

    private static func cacheKey(for text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func pairKey(_ source: String, _ target: String) -> String {
        "\(source.lowercased())>\(target.lowercased())"
    }

    private static func preferredIdentifier(for code: String) -> String {
        let needle = code.lowercased()
        for preferred in Locale.preferredLanguages {
            if SubtitleTargetLanguage.languageCode(from: preferred)?.lowercased() == needle {
                return preferred
            }
        }
        return regionalFallback[needle] ?? needle
    }

    private static let regionalFallback: [String: String] = [
        "de": "de-DE", "en": "en-US", "fr": "fr-FR", "es": "es-ES",
        "it": "it-IT", "pt": "pt-BR", "nl": "nl-NL", "sv": "sv-SE",
        "da": "da-DK", "nb": "nb-NO", "fi": "fi-FI", "ja": "ja-JP",
        "ko": "ko-KR", "zh": "zh-CN", "yue": "yue-CN", "ru": "ru-RU", "ar": "ar-SA",
        "tr": "tr-TR", "th": "th-TH", "vi": "vi-VN", "he": "he-IL",
    ]

    private static func matchSupportedLanguage(
        _ code: String,
        in supported: [Locale.Language]
    ) -> Locale.Language? {
        let needle = code.lowercased()
        for preferred in Locale.preferredLanguages {
            guard SubtitleTargetLanguage.languageCode(from: preferred)?.lowercased() == needle
            else { continue }
            if let match = supported.first(where: {
                $0.maximalIdentifier.lowercased() == preferred.lowercased()
                    || $0.languageCode?.identifier.lowercased() == needle
            }) {
                return match
            }
        }
        if let exact = supported.first(where: {
            $0.languageCode?.identifier.lowercased() == needle
        }) {
            return exact
        }
        if let region = regionalFallback[needle] {
            return Locale.Language(identifier: region)
        }
        return nil
    }

    private static func languageCandidates(
        for code: String,
        matched: Locale.Language
    ) -> [Locale.Language] {
        var list: [Locale.Language] = [matched, Locale.Language(identifier: code)]
        if let region = regionalFallback[code.lowercased()] {
            list.append(Locale.Language(identifier: region))
        }
        var seen = Set<String>()
        return list.filter { seen.insert($0.maximalIdentifier.lowercased()).inserted }
    }
}
#endif
