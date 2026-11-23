//
//  StashyDeepLink.swift
//  stashy
//
//  External links into the app (`stashy://…`), iOS and macOS. Android: `DeepLink.kt`.
//
//    stashy://scene/1234            scene page, no playback
//    stashy://scene/1234?t=754.5    scene page, plays from 754.5 s at once
//    stashy://marker/567[?t=…]      the marker's scene, plays from the marker (or `t`)
//    …&server=<name or URL>         on that configured server (switched to first)
//

#if !os(tvOS)
import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

/// One parsed `stashy://` link. Pure: no app state, so it reads the same everywhere.
struct StashyDeepLink: Equatable {
    enum Target: Equatable {
        case scene(id: String)
        case marker(id: String)
    }

    enum ParseError: Error, Equatable {
        /// Not a `stashy:` URL at all.
        case wrongScheme
        /// `stashy://something-else/…`
        case unknownPath
        /// Missing or non-numeric id.
        case invalidId
    }

    static let scheme = "stashy"

    let target: Target
    /// Start time in seconds; nil when absent, not a number, negative or not finite.
    let time: Double?
    /// The `server` parameter as given (a server name or address), trimmed; nil when absent or empty.
    let server: String?

    static func parse(_ url: URL) -> Result<StashyDeepLink, ParseError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme else { return .failure(.wrongScheme) }

        // `stashy://scene/12` has host "scene" and path "/12"; `stashy:scene/12` and
        // `stashy:///scene/12` carry everything in the path.
        var parts = components.percentEncodedPath.split(separator: "/").map(String.init)
        if let host = components.host, !host.isEmpty { parts.insert(host, at: 0) }
        guard let kind = parts.first?.lowercased() else { return .failure(.unknownPath) }
        guard kind == "scene" || kind == "marker" else { return .failure(.unknownPath) }
        guard parts.count == 2, let id = parts.last, !id.isEmpty, id.allSatisfy(\.isASCIIDigit) else {
            return .failure(.invalidId)
        }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let server = value("server").flatMap { $0.isEmpty ? nil : $0 }
        return .success(StashyDeepLink(
            target: kind == "scene" ? .scene(id: id) : .marker(id: id),
            time: parseTime(value("t")),
            server: server
        ))
    }

    /// `754`, `754.5` → seconds. Anything else (empty, `abc`, `-3`, `inf`, `1e400`) counts as absent.
    static func parseTime(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty,
              raw.allSatisfy({ $0.isASCIIDigit || $0 == "." }),
              let seconds = Double(raw), seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }

    /// The start time clamped to the scene: never past its end (one second before it, so the
    /// player does not open on the last frame and stop).
    static func clamp(_ seconds: Double, toDuration duration: Double?) -> Double {
        guard let duration, duration > 0 else { return max(0, seconds) }
        return min(max(0, seconds), max(0, duration - 1))
    }

    // MARK: Server matching

    /// Whether the `server` parameter names this server: its name (case-insensitive) or one of
    /// its addresses (regular or local). Scheme and host case, a trailing slash and a default
    /// port do not matter; a value without a scheme matches either scheme.
    static func serverMatches(_ value: String, name: String, addresses: [String]) -> Bool {
        let wanted = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return false }
        if wanted.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
            return true
        }
        guard let wantedKey = addressKey(wanted) else { return false }
        return addresses.contains { address in
            guard let key = addressKey(address) else { return false }
            // No scheme given: compare host, port and path only.
            if wantedKey.scheme == nil { return key.rest == wantedKey.rest }
            return key == wantedKey
        }
    }

    private struct AddressKey: Equatable {
        var scheme: String?
        var rest: String
    }

    private static func addressKey(_ raw: String) -> AddressKey? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasScheme = text.range(of: "://") != nil
        if !hasScheme { text = "http://" + text }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        var port = components.port
        if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) { port = nil }
        // Without a scheme the default port is unknown; keep what was typed.
        if !hasScheme { port = components.port }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        let rest = host + (port.map { ":\($0)" } ?? "") + path
        return AddressKey(scheme: hasScheme ? scheme : nil, rest: rest)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

// MARK: - Router

/// Runs `stashy://` links: waits for the app lock and the server, switches server when the link
/// names another one, fetches the scene (or marker) and opens its page through
/// `NavigationCoordinator.openScene`. One link waits at a time; a newer one replaces it.
@MainActor
final class StashyDeepLinkRouter {
    static let shared = StashyDeepLinkRouter()

    /// Set by the app root (SceneDelegate on iOS, `StashyMacApp` on macOS).
    weak var coordinator: NavigationCoordinator?

    private var pending: StashyDeepLink?
    /// The server finished its start-up sequence (`stashServerInitializationFinished`) since the
    /// last server change. False at launch.
    private var serverReady = false
    /// A link switched the server and waits for the new one.
    private var awaitsSwitch = false
    private var readyFallback: Task<Void, Never>?
    private var running: Task<Void, Never>?
    private var runningToken: UUID?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: .stashServerInitializationFinished)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.serverReady = true
                    self.awaitsSwitch = false
                    self.attempt()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.serverReady = false } }
            .store(in: &cancellables)
        // A link that came in while locked runs once the passcode / Face ID is through.
        SecurityManager.shared.$isAppLocked
            .removeDuplicates()
            .filter { !$0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.attempt() } }
            .store(in: &cancellables)
    }

    /// Entry point for every incoming URL. Returns false when it is no `stashy:` link.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        switch StashyDeepLink.parse(url) {
        case .failure(.wrongScheme):
            return false
        case .failure:
            AppLog.debug("[DeepLink] rejected \(url.absoluteString)")
            showError(tr("error_link_invalid"))
            return true
        case .success(let link):
            AppLog.debug("[DeepLink] queued \(url.absoluteString)")
            pending = link
            running?.cancel()
            running = nil
            runningToken = nil
            attempt()
            return true
        }
    }

    private func attempt() {
        guard let link = pending, running == nil else { return }
        // Never past the lock: the link waits for the unlock (observer above).
        guard !SecurityManager.shared.isAppLocked else { return }

        let manager = ServerConfigManager.shared
        guard let active = manager.activeConfig else {
            pending = nil
            showError(tr("error_link_no_server"))
            return
        }

        if let wanted = link.server, !awaitsSwitch {
            var candidates = manager.savedServers
            if !candidates.contains(where: { $0.id == active.id }) { candidates.insert(active, at: 0) }
            // The active server wins a tie (two servers with the same name).
            let ordered = [active] + candidates.filter { $0.id != active.id }
            guard let match = ordered.first(where: { Self.matches(wanted, $0) }) else {
                pending = nil
                showError(tr("error_link_unknown_server_arg", wanted))
                return
            }
            if match.id != active.id {
                AppLog.debug("[DeepLink] switching server to \(match.name)")
                awaitsSwitch = true
                serverReady = false
                // The normal switch path: `ServerConfigChanged` resets lists and stacks, the view
                // models initialise again and post `stashServerInitializationFinished`.
                manager.saveConfig(match)
                armReadyFallback()
                return
            }
        }

        guard serverReady else {
            armReadyFallback()
            return
        }
        readyFallback?.cancel()
        readyFallback = nil
        pending = nil
        let token = UUID()
        runningToken = token
        running = Task { [weak self] in
            await self?.open(link)
            // A newer link may have replaced this run meanwhile; only clear our own.
            if self?.runningToken == token {
                self?.running = nil
                self?.runningToken = nil
            }
        }
    }

    /// The start-up sequence runs from the dashboard; if it never reports (no dashboard on
    /// screen, a stalled request) the link still runs after a while and fails on its own fetch.
    private func armReadyFallback() {
        guard readyFallback == nil else { return }
        readyFallback = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.readyFallback = nil
            self.serverReady = true
            self.awaitsSwitch = false
            self.attempt()
        }
    }

    private static func matches(_ value: String, _ config: ServerConfig) -> Bool {
        var addresses = [config.externalBaseURL]
        if let local = config.localBaseURL { addresses.append(local) }
        return StashyDeepLink.serverMatches(value, name: config.name, addresses: addresses)
    }

    // MARK: Opening

    private func open(_ link: StashyDeepLink) async {
        let scene: Scene
        let autoPlay: Bool
        do {
            switch link.target {
            case .scene(let id):
                guard let found = try await SceneRepository().fetchSceneDetails(sceneId: id) else {
                    showError(tr("error_link_scene_not_found"))
                    return
                }
                if let time = link.time {
                    scene = found.withResumeTime(StashyDeepLink.clamp(time, toDuration: found.sceneDuration))
                    autoPlay = true
                } else {
                    scene = found
                    autoPlay = false
                }
            case .marker(let id):
                guard let marker = try await Self.fetchMarker(id: id),
                      let found = try await SceneRepository().fetchSceneDetails(sceneId: marker.sceneId) else {
                    showError(tr("error_link_marker_not_found"))
                    return
                }
                let start = link.time ?? marker.seconds
                scene = found.withResumeTime(StashyDeepLink.clamp(start, toDuration: found.sceneDuration))
                autoPlay = true
            }
        } catch {
            guard !Task.isCancelled else { return }
            AppLog.error("[DeepLink] fetch failed: \(error.localizedDescription)")
            showError(tr("error_link_open_failed"))
            return
        }
        guard !Task.isCancelled, let coordinator else { return }
        prepareForPush(sceneId: scene.id, startsAtTime: autoPlay)
        // Let a dismissed cover / sheet finish before the stack is rebuilt underneath.
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        coordinator.openScene(scene, autoPlay: autoPlay)
    }

    /// The page opens in the Home tab's stack. Whatever is presented above the tabs (Now
    /// Playing, the mini player's scene cover, a sheet, the fullscreen player) is closed first,
    /// or the new page would open hidden underneath it.
    private func prepareForPush(sceneId: String, startsAtTime: Bool) {
        let mini = MiniPlayerStore.shared
        mini.showsNowPlaying = false
        mini.expandedScene = nil
        // The page adopts a mini player that plays the same scene and keeps its position;
        // a link with a time must start there instead.
        if startsAtTime, mini.session?.scene.id == sceneId {
            mini.close(forget: false)
        }
        #if os(iOS)
        for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
            // Only the app's own window: the lock screen (`LockScreenWindow`, above `.alert`)
            // and system windows are left alone.
            for window in windowScene.windows
            where window.windowLevel == .normal && window.rootViewController?.presentedViewController != nil {
                window.rootViewController?.dismiss(animated: false)
            }
        }
        // A fullscreen player closed this way still gives the phone its orientations back.
        AetherSceneSurface.releaseOrientationOverride()
        #endif
    }

    // MARK: Marker lookup

    private struct MarkerRef {
        let seconds: Double
        let sceneId: String
    }

    private static func fetchMarker(id: String) async throws -> MarkerRef? {
        struct Response: Decodable {
            struct DataContainer: Decodable {
                struct Result: Decodable {
                    struct Marker: Decodable {
                        struct SceneRef: Decodable { let id: String }
                        let id: String
                        let seconds: Double
                        let scene: SceneRef?
                    }
                    let scene_markers: [Marker]
                }
                let findSceneMarkers: Result
            }
            let data: DataContainer?
        }
        let query = """
        query FindSceneMarkerById($ids: [ID!]) {
          findSceneMarkers(ids: $ids) { scene_markers { id seconds scene { id } } }
        }
        """
        let response: Response = try await GraphQLClient.shared.execute(query: query, variables: ["ids": [id]])
        guard let marker = response.data?.findSceneMarkers.scene_markers.first(where: { $0.id == id }),
              let sceneId = marker.scene?.id else { return nil }
        return MarkerRef(seconds: marker.seconds, sceneId: sceneId)
    }

    private func showError(_ message: String) {
        ToastManager.shared.show(message, icon: "exclamationmark.triangle.fill", style: .error, duration: 3.5)
    }
}
#endif
