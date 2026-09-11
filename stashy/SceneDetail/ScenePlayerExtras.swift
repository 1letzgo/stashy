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
    }

    // MARK: Menu

    @ViewBuilder
    func menuItems() -> some View {
        ScenePlayerExtrasMenuItems(controller: self)
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

    func applySceneLanguage(_ code: String) {
        guard let viewModel, let previous = scene else { return }
        updateScene(previous.withSpokenLanguage(code))
        viewModel.updateSceneLanguage(sceneId: previous.id, languageCode: code) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    ToastManager.shared.show("Language set to \(code.uppercased())", icon: "globe", style: .success)
                } else {
                    self?.updateScene(previous)
                    ToastManager.shared.show("Failed to save language", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
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
        guard let sceneLanguage = activeScene.spokenLanguageCode else {
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

// MARK: - Menu rows

/// Die Zeilen, die der Player in sein "…"-Menü einhängt. Eigene View, damit sie den
/// Controller beobachten, ohne dass die Player-Oberfläche das tun muss.
struct ScenePlayerExtrasMenuItems: View {
    @ObservedObject var controller: ScenePlayerExtrasController
    @ObservedObject private var stashSyncManager = StashSyncManager.shared

    var body: some View {
        Section {
            Button {
                controller.requestSceneCoverReplacement()
            } label: {
                Label("Set as scene cover", systemImage: "photo")
            }
            .disabled(controller.isBusyCapturing)

            Button {
                controller.captureTagImageFrameAndPresentSheet()
            } label: {
                Label("Set as tag image…", systemImage: "tag.fill")
            }
            .disabled(controller.isBusyCapturing)
        }

        Section {
            aiSubtitlesMenu
            #if canImport(AetherEngine)
            // AI Motion braucht ein echtes Player-Item zum Abtasten (`.loopback` /
            // `.remoteBypass`); die Software-Route hat keins.
            if let engine = controller.engine, stashSyncManager.isStashSyncEnabled {
                ScenePlayerAnalysisGate(engine: engine) {
                    Button {
                        HapticManager.selection()
                        stashSyncManager.setSyncing(!stashSyncManager.isSyncing)
                    } label: {
                        Label {
                            Text(stashSyncManager.isSyncing ? "AI Motion: On" : "AI Motion: Off")
                        } icon: {
                            Image(systemName: stashSyncManager.isSyncing
                                  ? "bolt.horizontal.fill"
                                  : "bolt.horizontal")
                        }
                    }
                }
            }
            #endif
        }

        if let resolution = controller.sourceResolutionLabel {
            Section {
                Button {} label: {
                    Label(resolution, systemImage: "video.fill")
                }
                .disabled(true)
            }
        }
    }

    @ViewBuilder
    private var aiSubtitlesMenu: some View {
        let transcription = controller.transcriptionController
        let translator = controller.captionTranslator
        let subtitles = controller.subtitleController
        let userLang = SubtitleTargetLanguage.load()
        let selected = SpeechTranscriberAvailability.matchingPickerId(
            stored: controller.scene?.spokenLanguageCode,
            optionIds: controller.speechSupportedLanguageOptions.map(\.id)
        )
        let isActive = transcription?.isTeleprompterModeActive ?? false

        Menu {
            ScenePlayerCaptionsMenuContent(
                languageOptions: controller.speechSupportedLanguageOptions,
                selectedLanguageCode: selected,
                onSelectLanguage: { controller.applySceneLanguage($0) },
                mode: transcription?.mode ?? .off,
                userLanguage: userLang,
                needsSpeechModelDownload: transcription?.needsSpeechModelDownload ?? false,
                speechModelName: transcription?.downloadingModelLanguage,
                needsTranslationPack: translator?.needsLanguageDownload ?? false,
                showsCaptionsOffRow: (controller.scene?.hasCaptions ?? false)
                    || (subtitles?.isLiveCaptionsActive ?? false),
                hasCaptionSelection: (subtitles?.selectedCaption != nil)
                    || (subtitles?.isLiveCaptionsActive ?? false),
                onSelectMode: { controller.setTeleprompterMode($0) },
                onCaptionsOff: { controller.selectNoCaption() },
                onDownloadSpeechModel: { transcription?.approveSpeechModelDownload() },
                onDownloadTranslationPack: { translator?.approveDownload() }
            )
        } label: {
            Label {
                Text(isActive ? "AI Subtitles: On" : "AI Subtitles")
            } icon: {
                Image(systemName: isActive ? "captions.bubble.fill" : "captions.bubble")
            }
        }
    }
}

/// Szenensprache + AI Captions als Menüinhalt (ohne eigenes Label) — dieselben Optionen,
/// die früher die "AI Subs"-Pille unter dem Player angeboten hat.
private struct ScenePlayerCaptionsMenuContent: View {
    let languageOptions: [(id: String, label: String)]
    let selectedLanguageCode: String?
    let onSelectLanguage: (String) -> Void

    let mode: SceneTeleprompterMode
    let userLanguage: String
    let needsSpeechModelDownload: Bool
    let speechModelName: String?
    let needsTranslationPack: Bool
    let showsCaptionsOffRow: Bool
    let hasCaptionSelection: Bool
    let onSelectMode: (SceneTeleprompterMode) -> Void
    let onCaptionsOff: () -> Void
    let onDownloadSpeechModel: () -> Void
    let onDownloadTranslationPack: () -> Void

    private var showUserLanguageRow: Bool {
        SubtitleTargetLanguage.languageCode(from: userLanguage)?.lowercased() != "en"
    }

    private var isSceneLanguageSet: Bool { selectedLanguageCode != nil }

    private var selectedLanguageLabel: String {
        guard let selectedLanguageCode,
              let label = languageOptions.first(where: { $0.id == selectedLanguageCode })?.label
        else { return selectedLanguageCode?.uppercased() ?? "Language" }
        return label
    }

    var body: some View {
        Section("AI Captions") {
            aiCaptionsPicker(collapsed: !isSceneLanguageSet)
        }

        Section("Scene Language") {
            if isSceneLanguageSet {
                sceneLanguagePicker(collapsed: true)
            } else if languageOptions.isEmpty {
                Text("Loading languages…")
            } else {
                sceneLanguagePicker(collapsed: false)
            }
        }

        if showsCaptionsOffRow {
            Section("Captions") {
                Button(action: onCaptionsOff) {
                    Label {
                        Text("Off")
                    } icon: {
                        if !hasCaptionSelection { Image(systemName: "checkmark") }
                    }
                }
            }
        }
    }

    private var selectedCaptionModeLabel: String {
        switch mode {
        case .off:
            return SceneTeleprompterMode.off.title
        case .english, .sceneLanguage:
            return SceneTeleprompterMode.english.title
        case .userLanguage:
            return SubtitleTargetLanguage.displayName(for: userLanguage)
        }
    }

    @ViewBuilder
    private func aiCaptionsPicker(collapsed: Bool) -> some View {
        let picker = Group {
            Button { onSelectMode(.off) } label: {
                Label {
                    Text(SceneTeleprompterMode.off.title)
                } icon: {
                    if mode == .off { Image(systemName: "checkmark") }
                }
            }
            Button { onSelectMode(.english) } label: {
                Label {
                    Text(SceneTeleprompterMode.english.title)
                } icon: {
                    if mode.captionTargetCode == "en" { Image(systemName: "checkmark") }
                }
            }
            if showUserLanguageRow {
                Button { onSelectMode(.userLanguage) } label: {
                    Label {
                        Text(SubtitleTargetLanguage.displayName(for: userLanguage))
                    } icon: {
                        if mode == .userLanguage { Image(systemName: "checkmark") }
                    }
                }
            }
            if needsSpeechModelDownload {
                Button(action: onDownloadSpeechModel) {
                    Label(
                        "Download \(speechModelName ?? "speech") speech model",
                        systemImage: "arrow.down.circle"
                    )
                }
            }
            if needsTranslationPack {
                Button(action: onDownloadTranslationPack) {
                    Label(
                        "Download \(userLanguage.uppercased()) language pack",
                        systemImage: "arrow.down.circle"
                    )
                }
            }
        }

        if collapsed {
            Menu {
                picker
            } label: {
                Label(selectedCaptionModeLabel, systemImage: "captions.bubble")
            }
        } else {
            picker
        }
    }

    @ViewBuilder
    private func sceneLanguagePicker(collapsed: Bool) -> some View {
        let picker = Group {
            ForEach(languageOptions, id: \.id) { option in
                Button {
                    onSelectLanguage(option.id)
                } label: {
                    Label {
                        Text(option.label)
                    } icon: {
                        if selectedLanguageCode == option.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        if collapsed {
            Menu {
                picker
            } label: {
                Label(selectedLanguageLabel, systemImage: "globe")
            }
        } else {
            picker
        }
    }
}

#if canImport(AetherEngine)
/// Zeigt seinen Inhalt nur, solange die Engine auf einer Route mit echtem Player-Item läuft.
private struct ScenePlayerAnalysisGate<Content: View>: View {
    @ObservedObject var engine: AetherSceneEngine
    @ViewBuilder let content: () -> Content

    var body: some View {
        if engine.analysisPlayerItem != nil { content() }
    }
}
#endif

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
