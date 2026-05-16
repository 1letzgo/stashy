//
//  SharedUtilities.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import Foundation
import AVKit
import AVFoundation

/// Protocol for types that provide a user-facing display name (used by tvOS sort picker)
protocol DisplayNameProvider {
    var displayName: String { get }
}
#if !os(tvOS)
import WebKit
#endif
import StoreKit

// MARK: - Shared Enums

enum PerformerBadgeType {
    case sceneCount
    case oCount
    case rating
}

// MARK: - Global Helper Functions

/// Adds the API key as a query parameter to the URL for authentication
func signedURL(_ url: URL?) -> URL? {
    guard let url = url else { return nil }
    guard let config = ServerConfigManager.shared.activeConfig, 
          let key = config.secureApiKey, !key.isEmpty else { return url }
    
    // Check if apikey is already present (case-insensitive check)
    if url.query?.lowercased().contains("apikey=") == true { return url }
    
    var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    var items = comps?.queryItems ?? []
    items.append(URLQueryItem(name: "apikey", value: key))
    comps?.queryItems = items
    return comps?.url ?? url
}

private var _cachedIsTestFlight: Bool?

func isTestFlightBuild() -> Bool {
    #if targetEnvironment(simulator) || DEBUG
    return true
    #else
    if let cached = _cachedIsTestFlight {
        return cached
    }
    
    let isTestFlight: Bool
    if #available(iOS 18.0, *) {
        // For iOS 18+, we rely primarily on the async Task below to update the cache.
        isTestFlight = Bundle.main.bundleURL.lastPathComponent.contains("sandbox")
        
        // Start an async task to update the cache properly via AppTransaction
        Task {
            if let result = try? await AppTransaction.shared,
               case .verified(let appTransaction) = result {
                _cachedIsTestFlight = appTransaction.environment == .sandbox
            }
        }
    } else {
        isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
    
    _cachedIsTestFlight = isTestFlight
    return isTestFlight
    #endif
}

func isHeadphonesConnected() -> Bool {
    let currentRoute = AVAudioSession.sharedInstance().currentRoute
    return currentRoute.outputs.contains(where: { port in
        [AVAudioSession.Port.headphones, AVAudioSession.Port.bluetoothA2DP, AVAudioSession.Port.bluetoothLE, AVAudioSession.Port.bluetoothHFP].contains(port.portType)
    })
}

// MARK: - Scene live updates (from SceneDetailView)

/// Keeps scene lists in sync with live updates coming from `SceneDetailView`.
///
/// `SceneDetailView` publishes changes (resume time, play count, deletions) through
/// `NotificationCenter`. Views that display scenes should apply `sceneLiveUpdates(using:)`
/// so they update in-place when navigating back.
struct SceneLiveUpdatesModifier: ViewModifier {
    @ObservedObject var viewModel: StashDBViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneResumeTimeUpdated"))) { notification in
                if let sceneId = notification.userInfo?["sceneId"] as? String,
                   let resumeTime = notification.userInfo?["resumeTime"] as? Double {
                    viewModel.updateSceneResumeTime(id: sceneId, newResumeTime: resumeTime)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScenePlayAdded"))) { notification in
                if let sceneId = notification.userInfo?["sceneId"] as? String {
                    viewModel.incrementScenePlayCount(id: sceneId, by: 1)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneDeleted"))) { notification in
                if let sceneId = notification.userInfo?["sceneId"] as? String {
                    viewModel.removeScene(id: sceneId)
                }
            }
    }
}

extension View {
    func sceneLiveUpdates(using viewModel: StashDBViewModel) -> some View {
        modifier(SceneLiveUpdatesModifier(viewModel: viewModel))
    }
}

/// Ensures `.playback` audio session for main scene/catalog playback (honors silent switch vs ambient previews).
func prepareStashPlaybackAudioSession() {
    let session = AVAudioSession.sharedInstance()
    if session.category != .playback {
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("🎬 VIDEO PLAYER: Error setting up AVAudioSession: \(error)")
        }
    }
}

func createPlayer(for url: URL) -> AVPlayer {
    prepareStashPlaybackAudioSession()
    
    // Use signed URL with API key as query parameter for maximum compatibility
    let authenticatedURL = signedURL(url) ?? url
    print("🎬 VIDEO PLAYER: Creating player for URL: \(authenticatedURL.absoluteString)")
    
    var headers: [String: String] = [:]
    if let config = ServerConfigManager.shared.loadConfig(),
       let apiKey = config.secureApiKey, !apiKey.isEmpty {
        headers["ApiKey"] = apiKey
    }
    
    let asset = AVURLAsset(url: authenticatedURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    let playerItem = AVPlayerItem(asset: asset)
    
    // Performance Optimizations for scrubbing and playback.
    // A small forward buffer (2s) keeps seeks snappy on HLS — a 10s buffer
    // forces AVPlayer to download/transcode ~10s per jump before playback.
    playerItem.preferredForwardBufferDuration = 2
    // Stash scenes are VOD; preserving live offset breaks seeks/resume on HLS.
    playerItem.automaticallyPreservesTimeOffsetFromLive = false
    playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true

    let player = AVPlayer(playerItem: playerItem)
    // Scrubbing responsiveness: `automaticallyWaitsToMinimizeStalling` makes
    // AVPlayer hold playback after every seek until a buffer threshold is met.
    // Disabling it returns control instantly after `seek`/`play`.
    player.automaticallyWaitsToMinimizeStalling = false
    player.allowsExternalPlayback = true
    player.preventsDisplaySleepDuringVideoPlayback = true
    return player
}

/// Creates a muted preview player that doesn't interrupt other audio
func createMutedPreviewPlayer(for url: URL) -> AVPlayer {
    // Use ambient category to mix with other audio and not interrupt
    do {
        try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: .mixWithOthers)
    } catch {
        print("🎬 PREVIEW PLAYER: Error setting up AVAudioSession: \(error)")
    }
    
    // Use signed URL with API key
    let authenticatedURL = signedURL(url) ?? url
    
    var headers: [String: String] = [:]
    if let config = ServerConfigManager.shared.loadConfig(),
       let apiKey = config.secureApiKey, !apiKey.isEmpty {
        headers["ApiKey"] = apiKey
    }
    
    let asset = AVURLAsset(url: authenticatedURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    let playerItem = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: playerItem)
    player.isMuted = true
    return player
}

// MARK: - Generic JSON Handling

enum StashJSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: StashJSONValue])
    case array([StashJSONValue])
    case null
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode([String: StashJSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([StashJSONValue].self) { self = .array(value) }
        else if container.decodeNil() { self = .null }
        else { throw DecodingError.typeMismatch(StashJSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid StashJSONValue")) }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
    
    var value: Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .object(let o): return o.mapValues { $0.value }
        case .array(let a): return a.map { $0.value }
        case .null: return NSNull()
        }
    }
}

// MARK: - View Extensions

import SwiftUI

extension View {
    /// Applies a transformation to the view if a condition is met.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Applies the .searchable modifier conditionally.
    /// Search field is only visible when isSearchVisible is true.
    #if !os(tvOS)
    @ViewBuilder
    func conditionalSearchable(isVisible: Bool, text: Binding<String>, prompt: String = "Search") -> some View {
        if isVisible {
            self.searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt))
        } else {
            self
        }
    }
    #endif
    
    /// Applies the standard app background color.
    @ViewBuilder
    func applyAppBackground() -> some View {
        #if os(tvOS)
        self.background(Color.appBackground)
        #else
        self
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
        #endif
    }
    
    /// Adds a shimmering effect to the view (usually for loading states)
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
    
    /// Replaces/Overlays the view with a skeleton loading placeholder
    func skeleton() -> some View {
        self.modifier(SkeletonModifier())
    }
}

// MARK: - GIF / Zoom Components

#if !os(tvOS)
/// Full-screen loading UI shared across catalog-style screens (same idea as `PerformersView`):
/// `Color.appBackground` + centered `ProgressView` with label.
struct StandardLoadingView: View {
    let message: String
    /// When `false`, use inside `ScrollView` / lists (e.g. search) — same colors, no full-screen spacers.
    var fillsScreen: Bool = true

    var body: some View {
        Group {
            if fillsScreen {
                VStack {
                    Spacer()
                    ProgressView(message)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Spacer()
                    ProgressView(message)
                    Spacer()
                }
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appBackground)
    }
}

/// A view that plays animated GIFs and WebP images using WKWebView for reliability and simple looping.
struct AnimatedWebView: UIViewRepresentable {
    let data: Data
    var fillMode: Bool = false
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var lastDataHash: Int?
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = false
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let currentHash = data.hashValue
        if context.coordinator.lastDataHash == currentHash {
            return
        }
        context.coordinator.lastDataHash = currentHash
        
        // Determine MIME type
        let mimeType = isWebP(data) ? "image/webp" : "image/gif"
        
        let base64 = data.base64EncodedString()
        let objectFit = fillMode ? "cover" : "contain"
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body {
                    width: 100%;
                    height: 100%;
                    background-color: black;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    overflow: hidden;
                }
                img {
                    width: 100vw;
                    height: 100vh;
                    object-fit: \(objectFit);
                    display: block;
                }
            </style>
        </head>
        <body>
            <img src="data:\(mimeType);base64,\(base64)">
        </body>
        </html>
        """
        uiView.loadHTMLString(html, baseURL: nil)
    }
}





/// A wrapper around UIScrollView that provides pinch-to-zoom and panning for any SwiftUI view.
class HorizontalSeekPanGesture: UIPanGestureRecognizer {
    weak var scrollView: UIScrollView?
}

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private var content: Content
    private var onTap: ((CGPoint) -> Void)?
    private var onLongPress: ((Bool) -> Void)?
    private var onHorizontalPan: ((CGFloat, UIGestureRecognizer.State) -> Void)?
    @Binding var isZoomed: Bool

    init(isZoomed: Binding<Bool> = .constant(false), onTap: ((CGPoint) -> Void)? = nil, onLongPress: ((Bool) -> Void)? = nil, onHorizontalPan: ((CGFloat, UIGestureRecognizer.State) -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self._isZoomed = isZoomed
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.onHorizontalPan = onHorizontalPan
        self.content = content()
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5.0
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        
        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        scrollView.addSubview(hostedView)
        
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            
            hostedView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostedView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
        
        // Add double tap to reset
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        
        // Add single tap for UI toggle
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap) // Ensure double tap takes precedence
        scrollView.addGestureRecognizer(singleTap)
        
        // Add long press
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.3
        scrollView.addGestureRecognizer(longPress)

        #if !os(tvOS)
        let seekPan = HorizontalSeekPanGesture(target: context.coordinator, action: #selector(Coordinator.handleSeekPan(_:)))
        seekPan.scrollView = scrollView
        seekPan.delegate = context.coordinator
        scrollView.addGestureRecognizer(seekPan)
        #endif

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
        context.coordinator.onHorizontalPan = onHorizontalPan
        context.coordinator.isZoomed = $isZoomed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hostingController: UIHostingController(rootView: content), isZoomed: $isZoomed, onTap: onTap, onLongPress: onLongPress, onHorizontalPan: onHorizontalPan)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var hostingController: UIHostingController<Content>
        var isZoomed: Binding<Bool>
        var onTap: ((CGPoint) -> Void)?
        var onLongPress: ((Bool) -> Void)?
        var onHorizontalPan: ((CGFloat, UIGestureRecognizer.State) -> Void)?

        init(hostingController: UIHostingController<Content>, isZoomed: Binding<Bool>, onTap: ((CGPoint) -> Void)? = nil, onLongPress: ((Bool) -> Void)? = nil, onHorizontalPan: ((CGFloat, UIGestureRecognizer.State) -> Void)? = nil) {
            self.hostingController = hostingController
            self.isZoomed = isZoomed
            self.onTap = onTap
            self.onLongPress = onLongPress
            self.onHorizontalPan = onHorizontalPan
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController.view
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let zoomed = scrollView.zoomScale > scrollView.minimumZoomScale
            if isZoomed.wrappedValue != zoomed {
                isZoomed.wrappedValue = zoomed
            }
        }
        
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            let zoomed = scale > scrollView.minimumZoomScale
            if isZoomed.wrappedValue != zoomed {
                isZoomed.wrappedValue = zoomed
            }
        }
        
        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view?.window)
            onTap?(location)
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                onLongPress?(true)
            case .ended, .cancelled, .failed:
                onLongPress?(false)
            default:
                break
            }
        }
        
        @objc func handleSeekPan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            onHorizontalPan?(translation.x, gesture.state)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let seekPan = gestureRecognizer as? HorizontalSeekPanGesture else { return true }
            guard let scrollView = seekPan.scrollView, scrollView.zoomScale <= 1.01 else { return false }
            let vel = seekPan.velocity(in: seekPan.view)
            return abs(vel.x) > abs(vel.y) * 1.5
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer is HorizontalSeekPanGesture { return true }
            return false
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                isZoomed.wrappedValue = false
            } else {
                // Zoom to localized point
                let pointInView = gesture.location(in: hostingController.view)
                let zoomRect = calculateRectFor(scale: 2.5, center: pointInView, in: scrollView)
                scrollView.zoom(to: zoomRect, animated: true)
                isZoomed.wrappedValue = true
            }
        }
        
        private func calculateRectFor(scale: CGFloat, center: CGPoint, in scrollView: UIScrollView) -> CGRect {
            let width = scrollView.frame.size.width / scale
            let height = scrollView.frame.size.height / scale
            let x = center.x - (width / 2.0)
            let y = center.y - (height / 2.0)
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }
}

func isGIF(_ data: Data) -> Bool {
    return data.count >= 3 && data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46
}

func isWebP(_ data: Data) -> Bool {
    guard data.count >= 12 else { return false }
    // RIFF....WEBP (bytes 0-3 are "RIFF", bytes 8-11 are "WEBP")
    return data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
           data[8] == 0x57 && data[9] == 0x45 && data[10] == 0x42 && data[11] == 0x50
}

func isAnimatedData(_ data: Data) -> Bool {
    return isGIF(data) || isWebP(data)
}
#endif // !os(tvOS)

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.4), location: 0.5),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .scaleEffect(2)
                    .rotationEffect(.degrees(30))
                    .offset(x: -geometry.size.width + (phase * (geometry.size.width * 2.5)))
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}


struct SkeletonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .opacity(0.5)
            .overlay(Color.gray.opacity(0.2))
            .shimmer()
    }
}

// MARK: - Shared UI Components

struct InfoPill: View {
    let icon: String?
    let text: String
    var color: Color? = nil
    
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    
    private var activeColor: Color {
        color ?? appearanceManager.tintColor
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon, !icon.isEmpty {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(activeColor)
            }
            Text(text)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(activeColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            ZStack {
                #if os(tvOS)
                Color.black
                #else
                Color(UIColor.systemBackground)
                #endif
                activeColor.opacity(0.1)
            }
        )
        .clipShape(Capsule())
        .overlay(Capsule().stroke(activeColor, lineWidth: 0.5))
    }
}

struct WrappedHStack<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    let content: (Data.Element) -> Content
    var spacing: CGFloat = 8
    
    @State private var totalHeight: CGFloat = .zero
    
    var body: some View {
        VStack {
            GeometryReader { geometry in
                self.generateContent(in: geometry)
            }
        }
        .frame(height: totalHeight)
    }
    
    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        
        return ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                self.content(item)
                    .padding([.horizontal, .vertical], 4)
                    .alignmentGuide(.leading, computeValue: { d in
                        if (abs(width - d.width) > g.size.width) {
                            width = 0
                            height -= d.height
                        }
                        let result = width
                        if item.id == self.items.last?.id {
                            width = 0 // last item
                        } else {
                            width -= d.width
                        }
                        return result
                    })
                    .alignmentGuide(.top, computeValue: {d in
                        let result = height
                        if item.id == self.items.last?.id {
                            height = 0 // last item
                        }
                        return result
                    })
            }
        }.background(viewHeightReader($totalHeight))
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        return GeometryReader { geometry -> Color in
            let rect = geometry.frame(in: .local)
            DispatchQueue.main.async {
                binding.wrappedValue = rect.size.height
            }
            return .clear
        }
    }
}

// MARK: - Shared Reels Components

struct SidebarButton: View {
    let icon: String
    let label: String
    let count: Int
    var hideCount: Bool = false
    let color: Color
    var action: () -> Void

    var body: some View {
        Button(action: {
            #if !os(tvOS)
            HapticManager.light()
            #endif
            action()
        }) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(color)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                
                // Fixed height container for the count to prevent shifting
                ZStack {
                    if !hideCount && count > 0 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    }
                }
                .frame(height: 12)
            }
            .frame(width: 45, height: 45) // Fixed total height for the button
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct BottomBarButton: View {
    let icon: String
    var count: Int = 0
    var hideCount: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: {
            #if !os(tvOS)
            HapticManager.light()
            #endif
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                .overlay(alignment: .topTrailing) {
                    if !hideCount && count > 0 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.5))
                            .offset(x: 10, y: -8)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                    }
                }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        #if !os(tvOS)
        .focusEffectDisabled()
        #endif
    }
}

struct CustomVideoScrubber: View {
    @Binding var value: Double
    var total: Double
    var onEditingChanged: (Bool) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Background Track (Interactive Area)
                Rectangle()
                    .fill(Color.white.opacity(0.3)) // Slight visible track
                    .frame(height: 2) // Very thin default
                
                // Progress Bar
                Rectangle()
                    .fill(Color.white)
                    .frame(width: max(0, min(geometry.size.width, geometry.size.width * (value / total))), height: 2)
                
                // Expanded Touch Area (Invisible) for easier scrubbing
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    #if !os(tvOS)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                onEditingChanged(true)
                                let percentage = min(max(0, value.location.x / geometry.size.width), 1)
                                self.value = percentage * total
                            }
                            .onEnded { _ in
                                onEditingChanged(false)
                            }
                    )
                    #endif
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 20) // Match touch area height
        .focusable(false)
        #if !os(tvOS)
        .focusEffectDisabled()
        #endif
    }
}


// MARK: - Center Play Button
struct CenterPlayButton: View {
    var action: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.7))
                    .shadow(radius: 10)
                Spacer()
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }
}

// MARK: - Filter Mapper

/// Utility to map and sanitize Stash filters from UI/Saved format to GraphQL-ready Searchable format.
public struct FilterMapper {
    
    /// Main entry point to sanitize a filter dictionary.
    /// - Parameters:
    ///   - dict: The raw filter dictionary (either from saved_filter or UI).
    ///   - isMarker: Whether this is a marker filter (requires nesting some scene criteria).
    /// - Returns: A sanitized dictionary ready for GraphQL.
    public static func sanitize(_ dict: [String: Any], isMarker: Bool = false) -> [String: Any] {
        var newDict = dict
        
        // 1. Handle the "c" (criteria) array format used by Stash UI
        if let criteria = newDict["c"] as? [[String: Any]] {
            var rules: [[String: Any]] = []
            
            for item in criteria {
                if var key = item["id"] as? String {
                    let outputItem = item
                    
                    // Map "rating" to "rating100" for GraphQL compatibility
                    if key == "rating" { key = "rating100" }
                    
                    // If this is a nested logic node (has its own "c" array), sanitize recursively.
                    // Otherwise, it's a leaf criterion - process it directly using its ID as the field key.
                    let processedItem: Any
                    if outputItem["c"] != nil || outputItem["AND"] != nil || outputItem["OR"] != nil || outputItem["NOT"] != nil {
                        processedItem = sanitize(outputItem, isMarker: false)
                    } else {
                        processedItem = processCriterion(key: key, dict: outputItem)
                    }
                    
                    // Add to rules list
                    if isMarker && isSceneSpecificKey(key) {
                        rules.append(["scene_filter": [key: processedItem]])
                    } else {
                        if let dict = processedItem as? [String: Any] {
                            rules.append([key: dict])
                        } else if let b = processedItem as? Bool {
                            rules.append([key: b])
                        } else {
                            rules.append([key: processedItem])
                        }
                    }
                }
            }
            
            // Merge all rules as top-level keys (Stash implicitly ANDs all top-level criteria).
            // Do NOT use AND:[array] — Stash's AND field is a single nested FilterType object, not an array.
            for rule in rules {
                for (k, v) in rule {
                    newDict[k] = v
                }
            }
            
            newDict.removeValue(forKey: "c")
        }
        
        // 2. Clean up top-level UI-only keys
        let invalidTopKeys = ["id", "sort", "direction", "mode", "displayMode", "zoomIndex", "sortDirection", "type", "inputType", "criterionOption"]
        for key in invalidTopKeys {
            newDict.removeValue(forKey: key)
        }
        
        // 3. Process all remaining keys recursively
        for (key, value) in newDict {
            // Handle Logic Operators (AND, OR, NOT) which can be Arrays or Dicts
            if ["AND", "OR", "NOT"].contains(key) {
                if let filterArray = value as? [[String: Any]] {
                    newDict[key] = filterArray.map { sanitize($0, isMarker: false) }
                } else if let filterDict = value as? [String: Any] {
                    newDict[key] = sanitize(filterDict, isMarker: false)
                }
                continue
            }
            
            // Handle nested sub-filters (e.g., performers_filter, scene_filter)
            if key.hasSuffix("_filter") || key == "scene_filter" {
                if let subFilter = value as? [String: Any] {
                    newDict[key] = sanitize(subFilter, isMarker: false)
                }
                continue
            }
            
            // Handle Criterion Input objects (which often have "value", "modifier", etc.)
            if let subDict = value as? [String: Any] {
                newDict[key] = processCriterion(key: key, dict: subDict)
            }
        }
        
        return newDict
    }
    
    // MARK: - Private Helpers
    
    private static func isSceneSpecificKey(_ key: String) -> Bool {
        // "tags" is NOT scene-specific for markers — SceneMarkerFilterType has its own
        // top-level "tags" field (the marker's tag). Only truly scene-only fields go here.
        let keys: Set<String> = ["orientation", "duration", "rating100", "organized", "performers", "studios", "movies"]
        return keys.contains(key)
    }
    
    private static func processCriterion(key: String, dict: [String: Any]) -> Any {
        var subDict = dict
        
        // Strip UI-only metadata inside criteria
        for uiKey in ["id", "type", "inputType", "criterionOption"] {
            subDict.removeValue(forKey: uiKey)
        }
        
        // Unwrap nested value structures
        if let valueDict = subDict["value"] as? [String: Any] {
            if let inner = valueDict["value"] { subDict["value"] = inner }
            else if let inner = valueDict["id"] { subDict["value"] = inner }
            else if let items = valueDict["items"] as? [Any] {
                subDict["value"] = items
                if let depth = valueDict["depth"] { subDict["depth"] = depth }
            }
        }
        if let vd2 = subDict["value2"] as? [String: Any], let iv2 = vd2["value"] {
            subDict["value2"] = iv2
        }
        if let excludesDict = subDict["excludes"] as? [String: Any] {
            if let inner = excludesDict["value"] { subDict["excludes"] = inner }
            else if let inner = excludesDict["id"] { subDict["excludes"] = inner }
            else if let items = excludesDict["items"] as? [Any] {
                subDict["excludes"] = items
                if subDict["depth"] == nil, let depth = excludesDict["depth"] {
                    subDict["depth"] = depth
                }
            }
        }
        
        // String extraction fields (Stash API expects simple String for these, not a criterion object)
        // Note: `has_image` is treated as boolean in practice (see booleanFields below).
        let stringExtractionFields: Set<String> = ["is_missing", "has_markers"]
        if stringExtractionFields.contains(key) {
            if let vd = subDict["value"] as? [String: Any], let inner = vd["value"] as? String { return inner }
            if let valArray = subDict["value"] as? [Any], let first = valArray.first as? String { return first }
            if let s = subDict["value"] as? String { return s }
            if let s = subDict["id"] as? String { return s }
            return ""
        }
        
        // Orientation mapping (must be Uppercased array, no modifier)
        if key == "orientation" {
            if let arr = subDict["value"] as? [Any] {
                subDict["value"] = arr.compactMap { item -> String? in
                    if let s = item as? String { return s.uppercased() }
                    if let obj = item as? [String: Any], let id = obj["id"] as? String { return id.uppercased() }
                    return nil
                }
            } else if let s = subDict["value"] as? String {
                subDict["value"] = [s.uppercased()]
            }
            subDict.removeValue(forKey: "modifier")
        }
        
        // Resolution mapping
        if key == "resolution" || key == "average_resolution" {
            if let s = subDict["value"] as? String { subDict["value"] = s.uppercased() }
        }
        
        // Integer field casting
        let intFields: Set<String> = ["rating", "rating100", "play_count", "resume_time", "scene_count", "duration", "o_counter", "id"]
        if intFields.contains(key) || key.hasSuffix("_count") {
            if let v = subDict["value"] { subDict["value"] = castToInt(v) }
            if let v = subDict["value2"] { subDict["value2"] = castToInt(v) }
        }
        
        // Multi-select/ID mapping
        let multiSelectFields: Set<String> = ["performers", "studios", "tags", "galleries", "scenes", "groups", "movies"]
        if multiSelectFields.contains(key) {
            if let valArray = subDict["value"] as? [Any] {
                subDict["value"] = mapToIds(valArray)
            }
            if let exArr = subDict["excludes"] as? [Any] {
                subDict["excludes"] = mapToIds(exArr)
            }
        }
        
        // Single enum field mapping (flatten array to string, uppercase)
        let singleEnumFields: Set<String> = ["gender", "ethnicity", "fake_tits", "hair_color", "eye_color", "career_length"]
        if singleEnumFields.contains(key) {
            if let valArray = subDict["value"] as? [Any], let first = valArray.first as? String {
                subDict["value"] = first.uppercased()
            } else if let s = subDict["value"] as? String {
                subDict["value"] = s.uppercased()
            }
        }
        
        // Boolean field flattening (Stash API expects simple Bool for these, not a criterion object)
        let booleanFields: Set<String> = ["interactive", "organized", "favorite", "performer_favorite", "studio_favorite", "gallery_favorite", "filter_favorites", "has_image"]
        if booleanFields.contains(key) {
            if let v = subDict["value"] {
                return castToBool(v)
            }
        }
        
        return subDict
    }
    
    private static func castToBool(_ val: Any) -> Bool {
        if let b = val as? Bool { return b }
        if let s = val as? String {
            return s.lowercased() == "true" || s == "1" || s.lowercased() == "yes"
        }
        if let i = val as? Int { return i != 0 }
        return false
    }
    
    private static func castToInt(_ val: Any) -> Any {
        if let i = val as? Int { return i }
        if let d = val as? Double { return Int(d) }
        if let s = val as? String, let i = Int(s) { return i }
        return val
    }
    
    
    private static func mapToIds(_ array: [Any]) -> [String] {
        return array.compactMap { item -> String? in
            if let s = item as? String { return s }
            if let i = item as? Int { return String(i) }
            if let obj = item as? [String: Any] {
                if let id = obj["id"] as? String { return id }
                if let id = obj["id"] as? Int { return String(id) }
                // Stash sometimes uses "value" key instead of "id" for exclude items
                if let id = obj["value"] as? String { return id }
                if let id = obj["value"] as? Int { return String(id) }
            }
            return nil
        }
    }
}


#if !os(tvOS)
struct StashSyncCard: View {
    var showVideoAnalysis: Bool = true
    @ObservedObject var stashSync = StashSyncManager.shared
    @ObservedObject var videoManager = StashVideoSyncManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var handyManager = HandyManager.shared
    @ObservedObject var buttplugManager = ButtplugManager.shared
    @ObservedObject var loveSpouseManager = LoveSpouseManager.shared
    @State private var isChannelsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header and Device Toggles
            HStack(alignment: .center) {
                Text("StashSync")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Device Toggle Pills in Header (Style matching Interactive Card)
                let anyDeviceEnabled = handyManager.isEnabled || buttplugManager.isEnabled || loveSpouseManager.isEnabled
                if anyDeviceEnabled {
                    HStack(spacing: 8) {
                        if handyManager.isEnabled {
                            deviceTogglePill(
                                label: "Handy",
                                icon: handyManager.isStashSyncMode ? "hand.tap.fill" : "hand.tap",
                                isOn: $handyManager.isStashSyncMode
                            )
                        }
                        if buttplugManager.isEnabled {
                            deviceTogglePill(
                                label: "Intiface",
                                icon: buttplugManager.isStashSyncMode ? "cable.connector.fill" : "cable.connector",
                                isOn: $buttplugManager.isStashSyncMode
                            )
                        }
                        if loveSpouseManager.isEnabled {
                            deviceTogglePill(
                                label: "LoveSpouse",
                                icon: loveSpouseManager.isStashSyncMode ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right",
                                isOn: $loveSpouseManager.isStashSyncMode
                            )
                        }
                    }
                }
            }
            .padding(.top, 4)

            // Video Analysis — combined banner + expandable channels
            if showVideoAnalysis {
            VStack(alignment: .leading, spacing: 6) {
                // Combined output banner
                let combined = videoManager.currentIntensity
                Button(action: { withAnimation(.spring(duration: 0.25)) { isChannelsExpanded.toggle() } }) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Combined Output")
                                .font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(combined * 100))%")
                                .font(.caption2).monospacedDigit().foregroundColor(.secondary)
                            Image(systemName: isChannelsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(appearanceManager.tintColor)
                                .padding(4)
                                .background(appearanceManager.tintColor.opacity(0.12))
                                .clipShape(Circle())
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.gray.opacity(0.15))
                                Rectangle().fill(appearanceManager.tintColor)
                                    .frame(width: max(0, geo.size.width * CGFloat(combined)))
                                    .animation(.linear(duration: 0.1), value: combined)
                            }.clipShape(Capsule())
                        }.frame(height: 7)
                    }
                }.buttonStyle(.plain)

                // Individual channels — collapsed by default
                if isChannelsExpanded {
                    VStack(alignment: .leading, spacing: 5) {
                        compactBar(label: "Hip / Body", value: videoManager.hipIntensity,    color: appearanceManager.tintColor)
                        compactBar(label: "Pelvis",     value: videoManager.pelvisIntensity, color: .orange)
                        compactBar(label: "Head / Neck",value: videoManager.headIntensity,   color: .blue)
                        compactBar(label: "Wrist / Arm",value: videoManager.wristIntensity,  color: .purple)
                        compactBar(label: "Horizontal", value: videoManager.horzIntensity,   color: .green)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            } // showVideoAnalysis

            // Sensitivity Slider
            VStack(spacing: 4) {
                HStack {
                    Text("Motion Sensitivity")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(videoManager.sensitivity * 50))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                Slider(value: $videoManager.sensitivity, in: 0.1...2.0)
                    .tint(.orange)
            }
        }
        .padding(12)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
        .onChange(of: handyManager.isStashSyncMode) { _, _ in updateSyncState() }
        .onChange(of: buttplugManager.isStashSyncMode) { _, _ in updateSyncState() }
        .onChange(of: loveSpouseManager.isStashSyncMode) { _, _ in updateSyncState() }
    }

    private func updateSyncState() {
        let anyActive = handyManager.isStashSyncMode || buttplugManager.isStashSyncMode || loveSpouseManager.isStashSyncMode
        if anyActive {
            stashSync.start()
        } else {
            stashSync.stop()
        }
    }

    @ViewBuilder
    private func compactBar(label: String, value: Float, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("\(Int(value * 100))%").font(.caption2).monospacedDigit().foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.gray.opacity(0.15))
                    Rectangle().fill(color)
                        .frame(width: max(0, geo.size.width * CGFloat(value)))
                        .animation(.linear(duration: 0.1), value: value)
                }.clipShape(Capsule())
            }.frame(height: 5)
        }
    }

    @ViewBuilder
    private func deviceTogglePill(label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            HapticManager.medium()
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(isOn.wrappedValue ? "SYNC ON" : label)
            }
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(isOn.wrappedValue ? .white : Color.pillAccent)
            .padding(.horizontal, 8)
            .frame(minWidth: 92, minHeight: 28)
            .background(isOn.wrappedValue ? Color.green : appearanceManager.tintColor.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SyncBadge: View {
    let isVisible: Bool
    let icon: String
    let color: Color
    
    var body: some View {
        Image(systemName: icon)
            .font(.caption2)
            .foregroundColor(isVisible ? color : .secondary.opacity(0.3))
            .padding(6)
            .background(isVisible ? color.opacity(0.1) : Color.clear)
            .clipShape(Circle())
    }
}

private struct DeviceStatusDot: View {
    let isConnected: Bool
    let name: String
    
    var body: some View {
        if isConnected {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
        }
    }
}

struct StashSyncSheet: View {
    var showVideoAnalysis: Bool = true
    @ObservedObject var stashSync = StashSyncManager.shared
    @ObservedObject var videoManager = StashVideoSyncManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var handyManager = HandyManager.shared
    @ObservedObject var buttplugManager = ButtplugManager.shared
    @ObservedObject var loveSpouseManager = LoveSpouseManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var isChannelsExpanded = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Connected Devices")) {
                    if handyManager.isEnabled {
                        Toggle(isOn: $handyManager.isStashSyncMode) {
                            HStack(spacing: 12) {
                                Image(systemName: "bolt.horizontal.fill")
                                    .foregroundColor(handyManager.isStashSyncMode ? .orange : .secondary)
                                Text("The Handy")
                            }
                        }
                    }
                    if buttplugManager.isEnabled {
                        Toggle(isOn: $buttplugManager.isStashSyncMode) {
                            HStack(spacing: 12) {
                                Image(systemName: "bolt.horizontal.fill")
                                    .foregroundColor(buttplugManager.isStashSyncMode ? .orange : .secondary)
                                Text("Intiface")
                            }
                        }
                    }
                    if loveSpouseManager.isEnabled {
                        Toggle(isOn: $loveSpouseManager.isStashSyncMode) {
                            HStack(spacing: 12) {
                                Image(systemName: "bolt.horizontal.fill")
                                    .foregroundColor(loveSpouseManager.isStashSyncMode ? .orange : .secondary)
                                Text("LoveSpouse")
                            }
                        }
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
                if showVideoAnalysis {
                Section(header: Text("Live Signal Analysis")) {
                    VStack(spacing: 10) {
                        // Combined banner
                        let combined = videoManager.currentIntensity
                        Button(action: { withAnimation(.spring(duration: 0.25)) { isChannelsExpanded.toggle() } }) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label("Combined Output", systemImage: "waveform").font(.caption2)
                                    Spacer()
                                    Text("\(Int(combined * 100))%").font(.caption2).monospacedDigit()
                                    Image(systemName: isChannelsExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(appearanceManager.tintColor)
                                        .padding(4)
                                        .background(appearanceManager.tintColor.opacity(0.12))
                                        .clipShape(Circle())
                                }.foregroundColor(.secondary)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Rectangle().fill(Color.gray.opacity(0.1)).frame(height: 12)
                                        Rectangle().fill(appearanceManager.tintColor)
                                            .frame(width: max(0, geo.size.width * CGFloat(combined)), height: 12)
                                            .animation(.linear(duration: 0.1), value: combined)
                                    }.clipShape(Capsule())
                                }.frame(height: 12)
                            }
                        }.buttonStyle(.plain)

                        // Individual channels
                        if isChannelsExpanded {
                            VStack(spacing: 10) {
                                signalBar(label: "Hip / Body", icon: "figure.walk",         value: videoManager.hipIntensity,    color: appearanceManager.tintColor)
                                signalBar(label: "Pelvis",     icon: "figure.stand",         value: videoManager.pelvisIntensity, color: .orange)
                                signalBar(label: "Head / Neck",icon: "person.bust",          value: videoManager.headIntensity,   color: .blue)
                                signalBar(label: "Wrist / Arm",icon: "hand.raised",          value: videoManager.wristIntensity,  color: .purple)
                                signalBar(label: "Horizontal", icon: "arrow.left.and.right", value: videoManager.horzIntensity,   color: .green)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }.padding(.vertical, 8)
                }
                .listRowBackground(Color.secondaryAppBackground)
                } // showVideoAnalysis
                Section(header: Text("Analysis Sensitivity")) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Motion Analysis")
                            Spacer()
                            Text("\(Int(videoManager.sensitivity * 50))%").foregroundColor(.secondary)
                        }
                        Slider(value: $videoManager.sensitivity, in: 0.1...2.0).tint(.orange)
                    }.padding(.vertical, 4)
                }
                .listRowBackground(Color.secondaryAppBackground)
                Section(header: Text("Optical Flow Smoothing")) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Smoothing")
                            Spacer()
                            Text("\(Int(videoManager.smoothing * 100))%").foregroundColor(.secondary)
                        }
                        Slider(value: $videoManager.smoothing, in: 0.0...0.9).tint(.orange)
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .navigationTitle("StashSync")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { 
                        if handyManager.isStashSyncMode || buttplugManager.isStashSyncMode || loveSpouseManager.isStashSyncMode {
                            stashSync.isActive = true
                        } else {
                            stashSync.isActive = false
                        }
                        dismiss() 
                    }
                }
            }
        }
        .applyAppBackground()
        .onChange(of: handyManager.isStashSyncMode) { _, _ in syncSheetState() }
        .onChange(of: buttplugManager.isStashSyncMode) { _, _ in syncSheetState() }
        .onChange(of: loveSpouseManager.isStashSyncMode) { _, _ in syncSheetState() }
    }

    private func syncSheetState() {
        let anyActive = handyManager.isStashSyncMode || buttplugManager.isStashSyncMode || loveSpouseManager.isStashSyncMode
        if anyActive { stashSync.start() } else { stashSync.stop() }
    }

    @ViewBuilder
    private func signalBar(label: String, icon: String, value: Float, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(label, systemImage: icon).font(.caption2)
                Spacer()
                Text("\(Int(value * 100))%").font(.caption2).monospacedDigit()
            }.foregroundColor(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.gray.opacity(0.1)).frame(height: 8)
                    Rectangle().fill(color).frame(width: max(0, geo.size.width * CGFloat(value)), height: 8)
                        .animation(.linear(duration: 0.1), value: value)
                }.clipShape(Capsule())
            }.frame(height: 8)
        }
    }
}
#endif
