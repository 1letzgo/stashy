//
//  SharedUtilities.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import Foundation
import AVKit
import AVFoundation
import WebKit

// MARK: - Global Helper Functions

func isHeadphonesConnected() -> Bool {
    let currentRoute = AVAudioSession.sharedInstance().currentRoute
    return currentRoute.outputs.contains(where: { port in
        [AVAudioSession.Port.headphones, AVAudioSession.Port.bluetoothA2DP, AVAudioSession.Port.bluetoothLE, AVAudioSession.Port.bluetoothHFP].contains(port.portType)
    })
}

func createPlayer(for url: URL) -> AVPlayer {
    // Enable audio even in silent mode
    do {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try AVAudioSession.sharedInstance().setActive(true)
    } catch {
        print("🎬 VIDEO PLAYER: Error setting up AVAudioSession: \(error)")
    }
    
    var headers: [String: String] = [:]
    if let config = ServerConfigManager.shared.loadConfig(),
       let apiKey = config.secureApiKey, !apiKey.isEmpty {
        headers["ApiKey"] = apiKey
    }
    
    let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    let playerItem = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: playerItem)
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
    
    var headers: [String: String] = [:]
    if let config = ServerConfigManager.shared.loadConfig(),
       let apiKey = config.secureApiKey, !apiKey.isEmpty {
        headers["ApiKey"] = apiKey
    }
    
    let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
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
    /// Applies the .searchable modifier conditionally.
    /// Search field is only visible when isSearchVisible is true.
    @ViewBuilder
    func conditionalSearchable(isVisible: Bool, text: Binding<String>, prompt: String = "Search") -> some View {
        if isVisible {
            self.searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt))
        } else {
            self
        }
    }
    
    /// Applies the standard app background color.
    func applyAppBackground() -> some View {
        self.background(Color.appBackground)
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

/// A view that plays animated GIFs using WKWebView for reliability and simple looping.
struct GIFView: UIViewRepresentable {
    let data: Data
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(data, mimeType: "image/gif", characterEncodingName: "UTF-8", baseURL: URL(string: "about:blank")!)
    }
}

/// A wrapper around UIScrollView that provides pinch-to-zoom and panning for any SwiftUI view.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private var content: Content
    
    init(@ViewBuilder content: () -> Content) {
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
        
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(hostingController: UIHostingController(rootView: content))
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>
        
        init(hostingController: UIHostingController<Content>) {
            self.hostingController = hostingController
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController.view
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Zoom to localized point
                let pointInView = gesture.location(in: hostingController.view)
                let zoomRect = calculateRectFor(scale: 2.5, center: pointInView, in: scrollView)
                scrollView.zoom(to: zoomRect, animated: true)
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
