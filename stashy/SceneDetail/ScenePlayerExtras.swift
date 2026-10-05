//
//  ScenePlayerExtras.swift
//  stashy
//
//  Die Sonderfunktionen der Szenen-Detailseite (Set Image, AI Subtitles, AI Motion,
//  Auflösungs-Info) leben nicht mehr in einer Pillenleiste unter dem Player, sondern im
//  "…"-Menü des Players selbst. Damit Inline-Karte und Fullscreen-Cover dieselben Aktionen
//  und denselben Zustand teilen, hält dieser Controller den Zustand, die Menüzeilen und die
//  dazugehörigen Sheets/Alerts an einer Stelle.
//

#if !os(tvOS)

import SwiftUI
import Combine
#if canImport(AetherEngine)
import AetherEngine
#endif

/// Wer die Sheets gerade präsentieren darf. Inline-Karte und Fullscreen-Cover hängen beide
/// den Sheet-Modifier an; nur der sichtbare von beiden präsentiert tatsächlich.
enum ScenePlayerExtrasScope {
    case inline
    case fullscreen
}

@MainActor
final class ScenePlayerExtrasController: ObservableObject {

    // MARK: Published state

    @Published var showingSetTagImageSheet = false
    @Published var showingSetSceneCoverConfirm = false
    @Published var isCapturingTagFrame = false
    @Published var isSettingSceneCover = false
    @Published var capturedTagImageDataURL: String?
    @Published var showSpeechModelDownloadOffer = false
    @Published var speechSupportedLanguageOptions: [(id: String, label: String)] = []
    /// The spoken-language list is expanded inside the AI Subtitles menu. Picking a language
    /// folds it back to one row while the menu stays open.
    @Published var isPickingSpokenLanguage = false
    /// The language just picked, shown at once while the menu is still open — the scene
    /// binding only catches up on the host's next full update. Cleared again on failure.
    @Published private var pickedSpokenLanguage: String?

    /// The "…" menu closed: fold the language list, and let the scene binding (caught up by
    /// now) be the only source for the spoken language again.
    func optionsMenuClosed() {
        isPickingSpokenLanguage = false
        pickedSpokenLanguage = nil
    }
    /// Welche Fläche gerade oben ist — entscheidet, wer Sheets präsentiert.
    @Published var isFullscreenActive = false

    var isBusyCapturing: Bool { isCapturingTagFrame || isSettingSceneCover }

    // MARK: Context (bewusst nicht @Published — sonst rebuildet jede Player-Änderung das Menü)

    private var sceneBinding: Binding<Scene>?
    private(set) var viewModel: StashDBViewModel?
    private(set) var subtitleController: SubtitleController?
    private(set) var transcriptionController: SceneLiveTranscriptionController?
    private(set) var captionTranslator: SceneCaptionTranslator?
    #if canImport(AetherEngine)
    private(set) var engine: AetherSceneEngine?
    #endif

    private var captionRestoreInFlight = false
    private var forwardedObjects = Set<ObjectIdentifier>()
    private var cancellables = Set<AnyCancellable>()
    private static var cachedSpeechLanguageOptions: [(id: String, label: String)]?

    var scene: Scene? { sceneBinding?.wrappedValue }

    // MARK: Wiring

    #if canImport(AetherEngine)
    func configure(
        scene: Binding<Scene>,
        engine: AetherSceneEngine?,
        viewModel: StashDBViewModel,
        subtitleController: SubtitleController,
        transcriptionController: SceneLiveTranscriptionController,
        captionTranslator: SceneCaptionTranslator
    ) {
        self.sceneBinding = scene
        self.engine = engine
        self.viewModel = viewModel
        self.subtitleController = subtitleController
        self.transcriptionController = transcriptionController
        self.captionTranslator = captionTranslator
        forward(subtitleController)
        forward(transcriptionController)
        forward(captionTranslator)
    }
    #else
    func configure(
        scene: Binding<Scene>,
        viewModel: StashDBViewModel,
        subtitleController: SubtitleController,
        transcriptionController: SceneLiveTranscriptionController,
        captionTranslator: SceneCaptionTranslator
    ) {
        self.sceneBinding = scene
        self.viewModel = viewModel
        self.subtitleController = subtitleController
        self.transcriptionController = transcriptionController
        self.captionTranslator = captionTranslator
        forward(subtitleController)
        forward(transcriptionController)
        forward(captionTranslator)
    }
    #endif

    /// Die Menüzeilen beobachten nur diesen Controller — also reicht er die Änderungen der
    /// drei Untertitel-Controller einmalig weiter.
    private func forward<T: ObservableObject>(_ object: T) where T.ObjectWillChangePublisher == ObservableObjectPublisher {
        let id = ObjectIdentifier(object)
        guard !forwardedObjects.contains(id) else { return }
        forwardedObjects.insert(id)
        object.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func updateScene(_ newValue: Scene) {
        sceneBinding?.wrappedValue = newValue
        // The menu is data rebuilt on the host's next render; nudge it so a changed scene
        // language shows up the next time the menu opens, in fullscreen as well.
        objectWillChange.send()
    }

    // MARK: Menu

    /// Die Zeilen, die der Player in sein "…"-Menü einhängt — als Daten, nicht als View:
    /// das Menü wird von UIKit präsentiert (siehe `PlayerMenuButton`).
    func menuItems() -> [PlayerMenuItem] {
        // AI subtitles are their own submenu next to the video's Subtitles — see `aiSubtitleMenuItems()`.
        // Here only the scene tools, as one group.
        var items: [PlayerMenuItem] = [.separator(id: "extras.section.scene", title: "Scene")]

        #if canImport(AetherEngine)
        // AI Motion braucht ein echtes Player-Item zum Abtasten (`.loopback` /
        // `.remoteBypass`); die Software-Route hat keins.
        let sync = StashSyncManager.shared
        if let engine, engine.analysisPlayerItem != nil, sync.isStashSyncEnabled {
            let isSyncing = sync.isSyncing
            items.append(.action(
                id: "extras.aiMotion",
                title: "AI Motion",
                systemImage: isSyncing ? "bolt.horizontal.fill" : "bolt.horizontal",
                isChecked: isSyncing
            ) {
                HapticManager.selection()
                StashSyncManager.shared.setSyncing(!isSyncing)
            })
        }
        #endif

        // Watch without it counting: play count, history, resume point, watch time (only while
        // Settings › Playback activity is on; the pause lasts until the app restarts).
        if TabManager.isPlaybackActivityTracked, let sceneId = sceneBinding?.wrappedValue.id {
            let counts = !TabManager.activityPausedSceneIds.contains(sceneId)
            items.append(.action(
                id: "extras.countPlayback",
                title: "Count this playback",
                systemImage: "clock.arrow.circlepath",
                isChecked: counts,
                keepsMenuOpen: true
            ) { [weak self] in
                HapticManager.selection()
                if counts {
                    TabManager.activityPausedSceneIds.insert(sceneId)
                } else {
                    TabManager.activityPausedSceneIds.remove(sceneId)
                }
                self?.objectWillChange.send()
            })
        }

        items.append(.action(
            id: "extras.sceneCover",
            title: "Use frame as scene cover",
            systemImage: "photo",
            isDisabled: isBusyCapturing
        ) { [weak self] in
            self?.requestSceneCoverReplacement()
        })
        items.append(.action(
            id: "extras.tagImage",
            title: "Use frame as tag image",
            systemImage: "tag",
            isDisabled: isBusyCapturing
        ) { [weak self] in
            self?.captureTagImageFrameAndPresentSheet()
        })

        if let resolution = sourceResolutionLabel {
            items.append(.separator(id: "extras.section.info"))
            items.append(.info(id: "extras.resolution", title: resolution, systemImage: "video.fill"))
        }

        return items
    }

    /// True while AI captions are on.
    var isAISubtitleActive: Bool {
        (transcriptionController?.mode ?? .off) != .off
            || (transcriptionController?.isTeleprompterModeActive ?? false)
            || (subtitleController?.isLiveCaptionsActive ?? false)
    }

    /// Picking one of the video's own subtitle tracks ends AI captions — one line at a time.
    func turnOffAISubtitles() {
        guard isAISubtitleActive else { return }
        setTeleprompterMode(.off)
        selectNoCaption()
    }

    // MARK: AI Subtitles submenu

    /// The "AI Subtitles" submenu, placed by the player right under its own Subtitles menu.
    /// Empty on devices without on-device speech recognition; a single locked row without
    /// stashy+, so the feature is discoverable but not a dead end of disabled rows.
    func aiSubtitleMenuItems() -> [PlayerMenuItem] {
        guard let transcription = transcriptionController, transcription.isReadAlongAvailable else { return [] }
        guard StashyPlusManager.shared.isUnlocked else {
            return [.action(
                id: "extras.aiSubtitles.locked",
                title: "AI Subtitles · stashy+",
                systemImage: "lock"
            ) {
                ToastManager.shared.show("AI subtitles are part of stashy+ — unlock in Settings", icon: "sparkles", style: .error)
            }]
        }
        let translator = captionTranslator
        let userLanguage = SubtitleTargetLanguage.load()
        let languageOptions = speechSupportedLanguageOptions
        let storedLanguage = (pickedSpokenLanguage ?? scene?.spokenLanguageCode)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedLanguage = SpeechTranscriberAvailability.matchingPickerId(
            stored: storedLanguage,
            optionIds: languageOptions.map(\.id)
        )
        let mode = transcription.mode
        let aiOn = isAISubtitleActive

        var rows: [PlayerMenuItem] = [
            .action(
                id: "extras.captions.off",
                title: "Off",
                isChecked: !aiOn
            ) { [weak self] in self?.setTeleprompterMode(.off) }
        ]
        rows.append(.action(
            id: "extras.captions.english",
            title: SceneTeleprompterMode.english.title,
            isChecked: aiOn && mode.captionTargetCode == "en"
        ) { [weak self] in self?.setTeleprompterMode(.english) })
        if SubtitleTargetLanguage.languageCode(from: userLanguage)?.lowercased() != "en" {
            rows.append(.action(
                id: "extras.captions.userLanguage",
                title: SubtitleTargetLanguage.displayName(for: userLanguage),
                isChecked: aiOn && mode == .userLanguage
            ) { [weak self] in self?.setTeleprompterMode(.userLanguage) })
        }
        if transcription.needsSpeechModelDownload {
            let name = transcription.downloadingModelLanguage ?? "speech"
            rows.append(.action(
                id: "extras.captions.downloadSpeechModel",
                title: "Download \(name) speech model",
                systemImage: "arrow.down.circle"
            ) { transcription.approveSpeechModelDownload() })
        }
        if translator?.needsLanguageDownload == true {
            rows.append(.action(
                id: "extras.captions.downloadPack",
                title: "Download \(userLanguage.uppercased()) language pack",
                systemImage: "arrow.down.circle"
            ) { translator?.approveDownload() })
        }

        rows.append(.separator(id: "extras.section.spoken", title: "Spoken in this scene"))
        // Spoken language: one row with the current language (or "Set spoken language"). Tapping
        // it unfolds the list right here, picking folds it again — the menu stays open, so the
        // new language shows immediately.
        let hasLanguage = selectedLanguage != nil || storedLanguage?.isEmpty == false
        let languageLabel = selectedLanguage.flatMap { id in languageOptions.first(where: { $0.id == id })?.label }
            ?? storedLanguage.flatMap { Locale.current.localizedString(forIdentifier: $0) }
            ?? (selectedLanguage ?? storedLanguage ?? "").uppercased()
        if languageOptions.isEmpty {
            rows.append(.info(
                id: "extras.language",
                title: hasLanguage ? "Spoken: \(languageLabel)" : "Loading languages…",
                systemImage: "globe"
            ))
        } else {
            rows.append(.action(
                id: "extras.language",
                title: hasLanguage ? "Spoken: \(languageLabel)" : "Set spoken language",
                systemImage: isPickingSpokenLanguage ? "chevron.up" : "globe",
                keepsMenuOpen: true
            ) { [weak self] in self?.isPickingSpokenLanguage.toggle() })
            if isPickingSpokenLanguage {
                rows.append(.separator(id: "extras.section.languages"))
                rows.append(contentsOf: languageOptions.map { option in
                    .action(
                        id: "extras.language.\(option.id)",
                        title: option.label,
                        isChecked: selectedLanguage == option.id,
                        keepsMenuOpen: true
                    ) { [weak self] in
                        self?.isPickingSpokenLanguage = false
                        self?.applySceneLanguage(option.id)
                    }
                })
            }
        }

        let current: String = {
            guard aiOn else { return "Off" }
            switch mode {
            case .off: return "On"
            case .english, .sceneLanguage: return SceneTeleprompterMode.english.title
            case .userLanguage: return SubtitleTargetLanguage.displayName(for: userLanguage)
            }
        }()
        return [.submenu(
            id: "extras.aiSubtitles",
            title: "AI Subtitles: \(current)",
            systemImage: aiOn ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack",
            items: rows
        )]
    }

    /// Dateihöhe → kurzer Qualitäts-Text (`4K`, `1080p`, …).
    var sourceResolutionLabel: String? {
        guard let height = scene?.files?.first?.height, height > 0 else { return nil }
        if height >= 2160 { return "4K" }
        if height >= 1080 { return "1080p" }
        if height >= 720 { return "720p" }
        return "\(height)p"
    }

    // MARK: Set image

    /// Ein Einstiegspunkt für beide "Set Image"-Aktionen: die Frame-Extraktion der Engine,
    /// als `data:image/jpeg;base64,…`.
    private func captureCurrentFrameDataURL() async -> String? {
        #if canImport(AetherEngine)
        guard let engine else { return nil }
        guard let image = await engine.captureFrame(at: engine.currentTime,
                                                    maxSize: kCaptureFrameMaxSize) else {
            return nil
        }
        return videoFrameDataURL(from: image)
        #else
        return nil
        #endif
    }

    func captureTagImageFrameAndPresentSheet() {
        guard !isBusyCapturing else { return }
        isCapturingTagFrame = true
        HapticManager.light()

        Task { @MainActor in
            let dataURL = await captureCurrentFrameDataURL()
            isCapturingTagFrame = false
            guard let dataURL else {
                ToastManager.shared.show(
                    "Could not capture video frame",
                    icon: "exclamationmark.triangle",
                    style: .error
                )
                return
            }
            capturedTagImageDataURL = dataURL
            showingSetTagImageSheet = true
        }
    }

    func requestSceneCoverReplacement() {
        guard !isBusyCapturing else { return }
        HapticManager.light()
        showingSetSceneCoverConfirm = true
    }

    func captureAndSetSceneCover() {
        guard !isBusyCapturing else { return }
        guard let viewModel, let current = scene else { return }
        isSettingSceneCover = true

        Task { @MainActor in
            let dataURL = await captureCurrentFrameDataURL()
            guard let dataURL else {
                isSettingSceneCover = false
                ToastManager.shared.show(
                    "Could not capture video frame",
                    icon: "exclamationmark.triangle",
                    style: .error
                )
                return
            }

            viewModel.setSceneCoverImage(sceneId: current.id, image: dataURL) { [weak self] success in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isSettingSceneCover = false
                    if success {
                        let bust = String(Int(Date().timeIntervalSince1970 * 1000))
                        let updated = current.withUpdatedAt(bust)
                        self.updateScene(updated)
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SceneCoverUpdated"),
                            object: nil,
                            userInfo: [
                                "sceneId": updated.id,
                                "updatedAt": bust,
                                "screenshotPath": updated.paths?.screenshot as Any
                            ]
                        )
                        updated.postListMetadataUpdated()
                        ToastManager.shared.show("Scene cover updated", icon: "photo", style: .success)
                    } else {
                        ToastManager.shared.show(
                            "Failed to update scene cover",
                            icon: "exclamationmark.triangle",
                            style: .error
                        )
                    }
                }
            }
        }
    }

    // MARK: Scene language

    func loadSpeechSupportedLanguagesIfNeeded() async {
        if let cached = Self.cachedSpeechLanguageOptions, !cached.isEmpty {
            if speechSupportedLanguageOptions.isEmpty {
                speechSupportedLanguageOptions = cached
            }
            return
        }
        let options = await SpeechTranscriberAvailability.sceneLanguagePickerOptions()
        Self.cachedSpeechLanguageOptions = options
        speechSupportedLanguageOptions = options
    }

    /// `detected` marks a language read from the file rather than picked by the user: the caller
    /// is about to start captions with it, so nothing is restarted, and the toast says where the
    /// language came from.
    func applySceneLanguage(_ code: String, detected: Bool = false) {
        guard let viewModel, let previous = scene else { return }
        pickedSpokenLanguage = code
        updateScene(previous.withSpokenLanguage(code))
        // Running AI captions keep transcribing in the language they were started with; restart
        // them so the speech model (and the translation source) switch to the new language.
        if !detected, let transcriptionController,
           transcriptionController.isTeleprompterModeActive || transcriptionController.mode != .off {
            let mode = transcriptionController.mode
            stopLiveCaptionsIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.setTeleprompterMode(mode, userInitiated: false)
            }
        }
        viewModel.updateSceneLanguage(sceneId: previous.id, languageCode: code) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    if detected {
                        let name = Locale.current.localizedString(forIdentifier: code) ?? code.uppercased()
                        ToastManager.shared.show("Spoken language from the file: \(name)", icon: "globe", style: .success)
                    } else {
                        ToastManager.shared.show("Language set to \(code.uppercased())", icon: "globe", style: .success)
                    }
                } else {
                    self?.pickedSpokenLanguage = nil
                    self?.updateScene(previous)
                    ToastManager.shared.show("Failed to save language", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }

    // MARK: Spoken language from the file

    /// ISO 639-2/B codes that differ from the terminology codes `Locale` understands.
    private static let bibliographicLanguageCodes: [String: String] = [
        "ger": "de", "fre": "fr", "dut": "nl", "chi": "zh", "cze": "cs", "gre": "el",
        "per": "fa", "rum": "ro", "slo": "sk", "alb": "sq", "arm": "hy", "baq": "eu",
        "bur": "my", "geo": "ka", "ice": "is", "mac": "mk", "mao": "mi", "may": "ms",
        "tib": "bo", "wel": "cy",
    ]
    /// Tags that name no actual language: undetermined, multiple, no linguistic content, …
    private static let nonLanguageTags: Set<String> = ["und", "mul", "zxx", "mis", "qaa", "unknown", "none"]

    /// The spoken language the playing audio track declares (MKV / MP4 metadata), as a scene
    /// language tag. Falls back to a language name in the track title ("English", "Deutsch").
    /// `nil` when the file says nothing usable.
    func audioTrackLanguageTag() -> String? {
        #if canImport(AetherEngine)
        guard let engine, !engine.audioTracks.isEmpty else { return nil }
        let tracks = engine.audioTracks
        let track = engine.activeAudioTrackIndex.flatMap { index in tracks.first(where: { $0.id == index }) }
            ?? tracks.first(where: \.isDefault)
            ?? tracks.first
        guard let track else { return nil }

        if let raw = track.language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !raw.isEmpty, !Self.nonLanguageTags.contains(raw) {
            let base = raw.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? raw
            let alpha2 = Self.bibliographicLanguageCodes[base]
                ?? Locale.LanguageCode(base).identifier(.alpha2)
                ?? base
            if let tag = SubtitleTargetLanguage.normalizedSceneLanguageTag(from: alpha2) {
                return tag
            }
        }
        if let alias = SubtitleTargetLanguage.aliasCode(forName: track.name),
           let tag = SubtitleTargetLanguage.normalizedSceneLanguageTag(from: alias) {
            return tag
        }
        #endif
        return nil
    }

    // MARK: Captions / AI Subs

    func selectNoCaption() {
        stopLiveCaptionsIfNeeded()
        subtitleController?.select(nil, userInitiated: true)
    }

    func stopLiveCaptionsIfNeeded() {
        guard let transcriptionController, let subtitleController else { return }
        guard transcriptionController.isTeleprompterModeActive || subtitleController.isLiveCaptionsActive else { return }
        transcriptionController.liveCaptionHandler = nil
        transcriptionController.onLookaheadModeChanged = nil
        transcriptionController.translationRequestHandler = nil
        subtitleController.endLiveCaptions()
        captionTranslator?.deactivate()
        Task { await transcriptionController.disable() }
    }

    func restorePreferredCaptionsIfNeeded() {
        guard let transcriptionController else { return }
        guard !captionRestoreInFlight else { return }
        guard transcriptionController.mode == .off, !transcriptionController.isTeleprompterModeActive else { return }
        let preferred = SceneTeleprompterMode.preferred
        guard preferred != .off else { return }
        captionRestoreInFlight = true
        setTeleprompterMode(preferred, userInitiated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.captionRestoreInFlight = false
        }
    }

    func setTeleprompterMode(_ mode: SceneTeleprompterMode, userInitiated: Bool = true) {
        guard let transcriptionController, let subtitleController, let captionTranslator else { return }
        if userInitiated {
            SceneTeleprompterMode.persist(mode)
        }
        guard mode != .off else {
            stopLiveCaptionsIfNeeded()
            return
        }
        #if canImport(AetherEngine)
        // One subtitle at a time: an embedded / sidecar track would win over the AI line.
        engine?.clearSubtitle()
        #endif
        guard StashyPlusManager.shared.isUnlocked else {
            if userInitiated {
                ToastManager.shared.show("AI captions are part of stashy+ — unlock in Settings", icon: "sparkles", style: .error)
            }
            return
        }
        guard transcriptionController.isReadAlongAvailable else {
            if userInitiated {
                ToastManager.shared.show("Teleprompter requires iOS 26+ and supported hardware", icon: "text.viewfinder", style: .error)
            }
            return
        }
        #if canImport(AetherEngine)
        let engineURL = engine?.currentURL
        #else
        let engineURL: URL? = nil
        #endif
        guard engineURL != nil else {
            if userInitiated {
                ToastManager.shared.show("Start playback first", icon: "play.circle", style: .error)
            }
            return
        }
        guard let activeScene = scene else { return }
        // No language on the scene yet: take the one the file declares on its audio track and
        // save it, so the next start (and every other device) has it too.
        var resolvedLanguage = activeScene.spokenLanguageCode
        if resolvedLanguage == nil, let fromFile = audioTrackLanguageTag() {
            applySceneLanguage(fromFile, detected: true)
            resolvedLanguage = fromFile
        }
        guard let sceneLanguage = resolvedLanguage else {
            if userInitiated {
                ToastManager.shared.show("Set scene language first", icon: "globe", style: .error)
            }
            return
        }
        let url = activeScene.transcriptionStreamURL ?? engineURL
        var extras: [URL] = []
        if let original = activeScene.aetherVideoURL, original != url {
            extras.append(original)
        }

        let targetLanguage = mode.captionTargetCode ?? SubtitleTargetLanguage.load()
        let wantsTranslation = !SubtitleTargetLanguage.sameLanguage(sceneLanguage, targetLanguage)

        // Jedes CC-Einschalten bekommt einen sauberen Caption-Kanal + frische Speech-Session.
        Task { @MainActor in
            await transcriptionController.disable(resetError: true)
            guard !Task.isCancelled else { return }

            switch await transcriptionController.probeSpeechModel(for: sceneLanguage) {
            case .ready:
                break
            case .unsupported(let name):
                ToastManager.shared.show(
                    "Live CC has no SpeechTranscriber language for \(name)",
                    icon: "captions.bubble",
                    style: .error
                )
                return
            case .needsDownload(let name, _), .downloading(let name, _):
                ToastManager.shared.show(
                    "\(name) speech model required",
                    icon: "arrow.down.circle",
                    style: .info
                )
            }

            var translates = false
            if wantsTranslation {
                switch await SceneCaptionTranslator.availability(from: sceneLanguage, to: targetLanguage) {
                case .ready:
                    translates = true
                case .needsDownload:
                    translates = true
                case .sourceUnsupported(let code):
                    ToastManager.shared.show(
                        "No translation from \(code) — showing captions in the scene language",
                        icon: "character.bubble",
                        style: .info
                    )
                case .targetUnsupported(let code):
                    ToastManager.shared.show(
                        "No translation to \(code) on this device — showing captions in the scene language",
                        icon: "character.bubble",
                        style: .info
                    )
                case .pairUnsupported(let source, let target):
                    ToastManager.shared.show(
                        "No translation \(source) → \(target) — showing captions in the scene language",
                        icon: "character.bubble",
                        style: .info
                    )
                }
            }

            if translates {
                captionTranslator.activate(
                    source: sceneLanguage,
                    target: targetLanguage,
                    downloadApproved: false
                )
                transcriptionController.translationRequestHandler = { [weak captionTranslator] cueID, text in
                    captionTranslator?.requestTranslation(id: cueID, text: text)
                }
            } else {
                captionTranslator.deactivate()
                transcriptionController.translationRequestHandler = nil
            }

            subtitleController.beginLiveCaptions(timelineSynced: true)
            transcriptionController.onLookaheadModeChanged = { [weak subtitleController] lookahead in
                subtitleController?.setLiveCaptionsTimelineSynced(true)
                _ = lookahead
            }
            transcriptionController.liveCaptionHandler = { [weak subtitleController] text in
                subtitleController?.pushLiveCaption(text)
            }
            #if canImport(AetherEngine)
            if let engine {
                transcriptionController.start(
                    mode: mode,
                    aether: engine,
                    sceneID: activeScene.id,
                    sceneDuration: activeScene.sceneDuration,
                    sceneLanguage: sceneLanguage,
                    streamURL: url,
                    extraCandidateURLs: extras
                )
            }
            #endif

            // Auf das Parken in ensureSpeechModel warten und das Angebot erst nach dem
            // Menü-Teardown präsentieren (SwiftUI verschluckt Alerts in diesem Fenster).
            for _ in 0..<20 {
                if transcriptionController.needsSpeechModelDownload { break }
                if transcriptionController.errorMessage != nil { break }
                if transcriptionController.isTeleprompterReady { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if transcriptionController.needsSpeechModelDownload {
                try? await Task.sleep(nanoseconds: 450_000_000)
                showSpeechModelDownloadOffer = true
            }
            if let err = transcriptionController.errorMessage, !err.isEmpty {
                subtitleController.endLiveCaptions()
                captionTranslator.deactivate()
                transcriptionController.liveCaptionHandler = nil
                transcriptionController.onLookaheadModeChanged = nil
                transcriptionController.translationRequestHandler = nil
                ToastManager.shared.show(err, icon: "captions.bubble", style: .error)
            }
        }
    }
}

// MARK: - Sheets / alerts

/// Hängt die Sheets und Alerts der Sonderfunktionen an. Wird sowohl an die Inline-Karte als
/// auch an das Fullscreen-Cover gehängt; präsentiert wird nur aus der sichtbaren Fläche.
struct ScenePlayerExtrasSheetsModifier: ViewModifier {
    @ObservedObject var controller: ScenePlayerExtrasController
    let scope: ScenePlayerExtrasScope

    private var isPresenter: Bool {
        (scope == .fullscreen) == controller.isFullscreenActive
    }

    private func scoped(_ keyPath: ReferenceWritableKeyPath<ScenePlayerExtrasController, Bool>) -> Binding<Bool> {
        Binding(
            get: { isPresenter && controller[keyPath: keyPath] },
            set: { newValue in
                guard isPresenter else { return }
                controller[keyPath: keyPath] = newValue
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .background {
                // Der Engine-Zustand ist hier ein einfaches `let`, also über den Publisher.
                #if canImport(AetherEngine)
                if isPresenter, let engine = controller.engine {
                    Color.clear
                        .onReceive(engine.$isPlaying) { playing in
                            if playing { controller.restorePreferredCaptionsIfNeeded() }
                        }
                }
                #endif
            }
            .task {
                await controller.loadSpeechSupportedLanguagesIfNeeded()
            }
            .onChange(of: controller.transcriptionController?.errorMessage) { _, message in
                guard isPresenter, let message, !message.isEmpty else { return }
                ToastManager.shared.show(message, icon: "captions.bubble", style: .error)
            }
            .onChange(of: controller.captionTranslator?.statusMessage) { _, message in
                guard isPresenter, let message, !message.isEmpty else { return }
                ToastManager.shared.show(message, icon: "translate", style: .error)
            }
            .onChange(of: controller.transcriptionController?.needsSpeechModelDownload) { _, needs in
                if needs == true { controller.showSpeechModelDownloadOffer = true }
            }
            .sheet(isPresented: scoped(\.showingSetTagImageSheet)) {
                if let imageDataURL = controller.capturedTagImageDataURL,
                   let viewModel = controller.viewModel {
                    SetTagImageFromFrameSheet(
                        imageDataURL: imageDataURL,
                        sceneTags: controller.scene?.tags ?? [],
                        viewModel: viewModel
                    )
                }
            }
            .alert("Replace Scene Cover?", isPresented: scoped(\.showingSetSceneCoverConfirm)) {
                Button("Cancel", role: .cancel) {}
                Button("Replace", role: .destructive) {
                    controller.captureAndSetSceneCover()
                }
            } message: {
                Text("The current video frame will replace this scene’s cover image. This cannot be undone from the app.")
            }
            .alert("Download speech model?", isPresented: scoped(\.showSpeechModelDownloadOffer)) {
                Button("Download") {
                    controller.transcriptionController?.approveSpeechModelDownload()
                }
                Button("Not now", role: .cancel) {}
            } message: {
                let name = controller.transcriptionController?.downloadingModelLanguage ?? "this language"
                Text(
                    "Live captions need the on-device \(name) speech model. "
                    + "The download is managed by iOS and can be several hundred megabytes."
                )
            }
    }
}

extension View {
    func scenePlayerExtrasSheets(
        controller: ScenePlayerExtrasController,
        scope: ScenePlayerExtrasScope
    ) -> some View {
        modifier(ScenePlayerExtrasSheetsModifier(controller: controller, scope: scope))
    }
}

#endif
