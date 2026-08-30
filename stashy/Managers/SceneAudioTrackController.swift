#if !os(tvOS)
import AVFoundation
import Combine
import Foundation

/// Last exclusive asset-track id so StashSync's audio tap can mute every other track.
enum SceneExclusiveAudio {
    static var selectedTrackID: CMPersistentTrackID?

    static func makeMix(
        tracks: [AVAssetTrack],
        selectedTrackID: CMPersistentTrackID?,
        tap: MTAudioProcessingTap? = nil
    ) -> AVAudioMix {
        let chosen = selectedTrackID ?? tracks.first?.trackID
        let params: [AVMutableAudioMixInputParameters] = tracks.map { track in
            let parameter = AVMutableAudioMixInputParameters(track: track)
            let enabled = chosen != nil && track.trackID == chosen
            parameter.setVolume(enabled ? 1 : 0, at: .zero)
            if enabled, let tap {
                parameter.audioTapProcessor = tap
            }
            return parameter
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        return mix
    }
}

/// Discovers audio on the current `AVPlayerItem` and keeps exactly one audible.
/// Language choices go through AVPlayer's native Audio menu (Enhance Dialogue).
@MainActor
final class SceneAudioTrackController: ObservableObject {
    static let preferredLanguageKey = "stashy_preferred_audio_lang"

    struct Track: Identifiable, Equatable {
        let id: String
        let label: String
        let shortLabel: String
        let languageCode: String?
        let trackID: CMPersistentTrackID?
    }

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var selectedID: String?

    var hasChoices: Bool { tracks.count > 1 }

    private weak var player: AVPlayer?
    private var mediaGroup: AVMediaSelectionGroup?
    private var mediaOptions: [String: AVMediaSelectionOption] = [:]
    private var assetTracks: [String: AVAssetTrack] = [:]
    private var assetTrackLanguages: [CMPersistentTrackID: String] = [:]
    private var reloadTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var tracksObservation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private var selectionObserver: NSObjectProtocol?
    private var audioTapObserver: NSObjectProtocol?
    private var syncingFromPlayer = false

    init() {
        // The analysis tap owns `item.audioMix` while it runs; when it releases it, a muxed
        // multi-track file needs our exclusive mix back.
        audioTapObserver = NotificationCenter.default.addObserver(
            forName: .sceneAudioTapChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applySelection() }
        }
    }

    deinit {
        if let audioTapObserver {
            NotificationCenter.default.removeObserver(audioTapObserver)
        }
    }

    func attach(player: AVPlayer?) {
        detachObservers()
        self.player = player
        guard let player else {
            resetState()
            return
        }

        currentItemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.observeCurrentItem()
                self?.reload()
            }
        }
        observeCurrentItem()
        reload()
    }

    func detach() {
        reloadTask?.cancel()
        reloadTask = nil
        detachObservers()
        player = nil
        resetState()
        SceneExclusiveAudio.selectedTrackID = nil
    }

    func reload() {
        reloadTask?.cancel()
        let item = player?.currentItem
        reloadTask = Task { [weak self] in
            await self?.reload(from: item)
        }
    }

    func select(_ track: Track) {
        selectedID = track.id
        persistLanguage(track.languageCode)
        applySelection()
        rebindStashSyncIfNeeded()
    }

    private func resetState() {
        tracks = []
        selectedID = nil
        mediaGroup = nil
        mediaOptions = [:]
        assetTracks = [:]
        assetTrackLanguages = [:]
    }

    private func detachObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        tracksObservation?.invalidate()
        tracksObservation = nil
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        if let selectionObserver {
            NotificationCenter.default.removeObserver(selectionObserver)
            self.selectionObserver = nil
        }
    }

    private func observeCurrentItem() {
        statusObservation?.invalidate()
        tracksObservation?.invalidate()
        if let selectionObserver {
            NotificationCenter.default.removeObserver(selectionObserver)
            self.selectionObserver = nil
        }

        guard let item = player?.currentItem else { return }

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            Task { @MainActor in self?.reload() }
        }
        tracksObservation = item.observe(\.tracks, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.applyExclusiveAssetTracksIfNeeded() }
        }
        selectionObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.mediaSelectionDidChangeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncFromNativeSelection() }
        }
    }

    private func reload(from item: AVPlayerItem?) async {
        guard let item else {
            resetState()
            return
        }

        let asset = item.asset
        _ = try? await asset.load(.availableMediaCharacteristicsWithMediaSelectionOptions)

        let loadedTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let group = try? await asset.loadMediaSelectionGroup(for: .audible)

        var trackLanguages: [CMPersistentTrackID: String] = [:]
        var trackChannels: [CMPersistentTrackID: Int] = [:]
        for assetTrack in loadedTracks {
            let tag = try? await assetTrack.load(.extendedLanguageTag)
            let code = try? await assetTrack.load(.languageCode)
            if let language = tag ?? code, !language.isEmpty {
                trackLanguages[assetTrack.trackID] = language
            }
            if let formats = try? await assetTrack.load(.formatDescriptions),
               let channels = Self.channelCount(from: formats) {
                trackChannels[assetTrack.trackID] = channels
            }
        }

        guard !Task.isCancelled else { return }

        var nextTracks: [Track] = []
        var nextOptions: [String: AVMediaSelectionOption] = [:]
        var nextAssetTracks: [String: AVAssetTrack] = [:]

        // Native AVPlayer Audio menu (Enhance Dialogue) lists AVMediaSelectionOptions.
        // Always prefer that group so languages appear next to Enhance Dialogue.
        if let group, !group.options.isEmpty {
            mediaGroup = group
            for (index, option) in group.options.enumerated() {
                let id = "opt-\(index)-\(option.extendedLanguageTag ?? option.displayName)"
                let language = option.extendedLanguageTag ?? option.locale?.language.languageCode?.identifier
                let track = Track(
                    id: id,
                    label: Self.displayName(for: option, fallbackIndex: index),
                    shortLabel: Self.shortName(languageCode: language, fallbackIndex: index),
                    languageCode: language,
                    trackID: Self.trackID(matching: option, in: loadedTracks, languages: trackLanguages)
                )
                nextTracks.append(track)
                nextOptions[id] = option
            }
        } else {
            mediaGroup = nil
        }

        // Muxed files often have extra AVAssetTracks that are not in the selection group.
        // Keep them exclusive so they don't play on top of the native selection.
        for (index, assetTrack) in loadedTracks.enumerated() {
            let id = "trk-\(assetTrack.trackID)"
            if nextAssetTracks[id] != nil { continue }
            if nextTracks.contains(where: { $0.trackID == assetTrack.trackID }) {
                nextAssetTracks[id] = assetTrack
                continue
            }
            nextAssetTracks[id] = assetTrack
            if mediaGroup == nil {
                let language = trackLanguages[assetTrack.trackID]
                nextTracks.append(Track(
                    id: id,
                    label: Self.displayName(
                        language: language,
                        channelCount: trackChannels[assetTrack.trackID],
                        index: index
                    ),
                    shortLabel: Self.shortName(languageCode: language, fallbackIndex: index),
                    languageCode: language,
                    trackID: assetTrack.trackID
                ))
            }
        }

        tracks = nextTracks
        mediaOptions = nextOptions
        assetTracks = nextAssetTracks
        assetTrackLanguages = trackLanguages

        applyPreferredLanguageCriteria()

        selectedID = mediaGroup.flatMap { matchingNativeSelection(in: item, group: $0) }?.id
            ?? Self.preferredTrack(in: nextTracks)?.id
            ?? nextTracks.first?.id
        SceneExclusiveAudio.selectedTrackID = nextTracks.first(where: { $0.id == selectedID })?.trackID
            ?? nextTracks.first?.trackID
        applySelection()
    }

    private func applyPreferredLanguageCriteria() {
        guard let player else { return }
        var languages: [String] = []
        if let stored = UserDefaults.standard.string(forKey: Self.preferredLanguageKey), !stored.isEmpty {
            languages.append(stored)
        }
        languages.append(contentsOf: Locale.preferredLanguages)
        let criteria = AVPlayerMediaSelectionCriteria(
            preferredLanguages: languages,
            preferredMediaCharacteristics: nil
        )
        player.setMediaSelectionCriteria(criteria, forMediaCharacteristic: .audible)

        if #available(iOS 26.0, *), let scheme = mediaGroup?.customMediaSelectionScheme {
            player.currentItem?.preferredCustomMediaSelectionSchemes = [scheme]
        }
    }

    private var usesNativeAudioMenu: Bool {
        (mediaGroup?.options.count ?? 0) > 1
    }

    private func applySelection() {
        guard let item = player?.currentItem, let selectedID else { return }

        // Leave automatic selection on so AVKit lists languages next to Enhance Dialogue.
        player?.appliesMediaSelectionCriteriaAutomatically = true

        if usesNativeAudioMenu, let group = mediaGroup, let option = mediaOptions[selectedID] {
            // Any leftover mix keeps AVKit's Audio menu collapsed — drop it unless the
            // analysis tap is actively using it.
            if item.audioMix != nil, !StashVideoSyncManager.shared.hasAudioTapInstalled {
                item.audioMix = nil
            }
            syncingFromPlayer = true
            item.select(option, in: group)
            syncingFromPlayer = false
            SceneExclusiveAudio.selectedTrackID = tracks.first(where: { $0.id == selectedID })?.trackID
                ?? Self.trackID(matching: option, in: Array(assetTracks.values), languages: assetTrackLanguages)
            return
        }

        let mixTracks = Array(assetTracks.values)
        let selectedTrackID = assetTracks[selectedID]?.trackID
            ?? tracks.first(where: { $0.id == selectedID })?.trackID
            ?? mixTracks.first?.trackID
        SceneExclusiveAudio.selectedTrackID = selectedTrackID
        applyExclusiveAssetTracksIfNeeded()

        // audioMix collapses AVKit's Audio menu to Enhance Dialogue only. Use it
        // solely when item.tracks is not ready yet and several asset tracks exist.
        if !usesNativeAudioMenu,
           item.tracks.filter({ $0.assetTrack?.mediaType == .audio }).count <= 1,
           mixTracks.count > 1,
           !StashVideoSyncManager.shared.hasAudioTapInstalled {
            item.audioMix = SceneExclusiveAudio.makeMix(
                tracks: mixTracks,
                selectedTrackID: selectedTrackID
            )
        }
    }

    private func applyExclusiveAssetTracksIfNeeded() {
        guard !usesNativeAudioMenu, let item = player?.currentItem else { return }
        let audioPlayerTracks = item.tracks.filter { $0.assetTrack?.mediaType == .audio }
        guard audioPlayerTracks.count > 1 else { return }

        let selected = SceneExclusiveAudio.selectedTrackID ?? audioPlayerTracks.first?.assetTrack?.trackID
        for playerTrack in audioPlayerTracks {
            playerTrack.isEnabled = playerTrack.assetTrack?.trackID == selected
        }
    }

    private func syncFromNativeSelection() {
        guard !syncingFromPlayer, let item = player?.currentItem, let group = mediaGroup else { return }
        guard let current = item.currentMediaSelection.selectedMediaOption(in: group) else { return }
        guard let track = matchingNativeSelection(in: item, group: group) else { return }
        if selectedID != track.id {
            selectedID = track.id
            persistLanguage(track.languageCode)
            SceneExclusiveAudio.selectedTrackID = track.trackID
                ?? Self.trackID(matching: current, in: Array(assetTracks.values), languages: assetTrackLanguages)
            applyExclusiveAssetTracksIfNeeded()
            rebindStashSyncIfNeeded()
        }
    }

    private func matchingNativeSelection(in item: AVPlayerItem, group: AVMediaSelectionGroup) -> Track? {
        guard let current = item.currentMediaSelection.selectedMediaOption(in: group) else { return nil }
        return mediaOptions.first(where: { $0.value == current }).flatMap { id, _ in
            tracks.first(where: { $0.id == id })
        }
    }

    private func persistLanguage(_ code: String?) {
        guard let code, !code.isEmpty else { return }
        UserDefaults.standard.set(code, forKey: Self.preferredLanguageKey)
    }

    private func rebindStashSyncIfNeeded() {
        if let item = player?.currentItem, StashVideoSyncManager.shared.currentItem === item {
            StashVideoSyncManager.shared.setup(for: item)
        }
    }

    private static func trackID(
        matching option: AVMediaSelectionOption,
        in tracks: [AVAssetTrack],
        languages: [CMPersistentTrackID: String]
    ) -> CMPersistentTrackID? {
        let optionLang = (option.extendedLanguageTag ?? option.locale?.language.languageCode?.identifier)?
            .lowercased()
        if let optionLang {
            let needle = optionLang.split(separator: "-").first.map(String.init) ?? optionLang
            if let match = tracks.first(where: {
                let code = languages[$0.trackID]?.lowercased()
                let short = code?.split(separator: "-").first.map(String.init)
                return short == needle || code == optionLang
            }) {
                return match.trackID
            }
        }
        return tracks.count == 1 ? tracks.first?.trackID : nil
    }

    private static func preferredTrack(in tracks: [Track]) -> Track? {
        var codes: [String] = []
        if let stored = UserDefaults.standard.string(forKey: preferredLanguageKey), !stored.isEmpty {
            codes.append(stored)
        }
        codes.append(contentsOf: Locale.preferredLanguages)
        codes.append(Locale.current.language.languageCode?.identifier ?? "en")

        for raw in codes {
            let needle = raw.lowercased().split(separator: "-").first.map(String.init) ?? raw.lowercased()
            if let match = tracks.first(where: {
                ($0.languageCode ?? "").lowercased().split(separator: "-").first.map(String.init) == needle
            }) {
                return match
            }
        }
        return tracks.first
    }

    private static func displayName(for option: AVMediaSelectionOption, fallbackIndex: Int) -> String {
        let language = option.extendedLanguageTag ?? option.locale?.language.languageCode?.identifier
        let pretty = language.flatMap { Self.languageName($0) }
        let optionName = option.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pretty, !optionName.isEmpty, optionName.caseInsensitiveCompare(pretty) != .orderedSame {
            return "\(pretty) · \(optionName)"
        }
        if let pretty { return pretty }
        if !optionName.isEmpty { return optionName }
        return "Track \(fallbackIndex + 1)"
    }

    private static func displayName(language: String?, channelCount: Int?, index: Int) -> String {
        var parts: [String] = []
        if let language, let name = languageName(language) {
            parts.append(name)
        }
        if let channels = channelCount {
            parts.append(channels == 1 ? "Mono" : channels == 2 ? "Stereo" : "\(channels) ch")
        }
        if parts.isEmpty {
            parts.append("Track \(index + 1)")
        }
        return parts.joined(separator: " · ")
    }

    private static func shortName(languageCode: String?, fallbackIndex: Int) -> String {
        guard let languageCode, !languageCode.isEmpty else {
            return "A\(fallbackIndex + 1)"
        }
        return String(languageCode.prefix(2)).uppercased()
    }

    private static func languageName(_ code: String) -> String? {
        let trimmed = code.replacingOccurrences(of: "_", with: "-")
        let locale = Locale.current
        if let name = locale.localizedString(forLanguageCode: trimmed) {
            return name.localizedCapitalized
        }
        let short = trimmed.split(separator: "-").first.map(String.init) ?? trimmed
        return locale.localizedString(forLanguageCode: short)?.localizedCapitalized
    }

    private static func channelCount(from formatDescriptions: [CMFormatDescription]) -> Int? {
        for desc in formatDescriptions {
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                let count = Int(asbd.pointee.mChannelsPerFrame)
                if count > 0 { return count }
            }
        }
        return nil
    }
}
#endif
