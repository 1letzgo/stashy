#if !os(tvOS)
import Foundation
import Combine
import SwiftUI

class StashSyncManager: ObservableObject {
    static let shared = StashSyncManager()

    @Published var currentIntensity: Float = 0.0
    @Published var headIntensity: Float = 0.0
    @Published var isActive: Bool = false

    var isStashSyncEnabled: Bool {
        get {
            StashyPlusManager.isUnlockedNow && StashVideoSyncManager.shared.isVideoSyncEnabled
        }
        set {
            guard StashyPlusManager.isUnlockedNow else {
                StashVideoSyncManager.shared.isVideoSyncEnabled = false
                return
            }
            StashVideoSyncManager.shared.isVideoSyncEnabled = newValue
        }
    }

    // Internal state
    private var cancellables = Set<AnyCancellable>()

    // Pulse oscillator state
    // The oscillator converts a steady intensity level into wave pulses.
    // phase advances each tick; frequency scales with detected motion intensity.
    private var oscillatorPhase: Double = 0.0
    private var pulseTimer: Timer?

    // Smoothed target intensity (from video analysis) — updated on every frame
    private var targetIntensity: Float = 0.0

    // Tick interval: ~30 Hz is sufficient for smooth waveform output
    private let tickInterval: TimeInterval = 1.0 / 30.0

    // Frequency range: slow pulse at low intensity, fast at high intensity
    // e.g. 0.3 Hz at intensity 0.0 → 2.5 Hz at intensity 1.0
    private let minFrequency: Double = 0.3
    private let maxFrequency: Double = 2.5

    private init() {
        setupTargetTracking()
    }

    // Forward video intensity into targetIntensity when active
    private func setupTargetTracking() {
        StashVideoSyncManager.shared.$currentIntensity
        .receive(on: RunLoop.main)
        .sink { [weak self] video in
            guard let self = self, self.isActive else { return }
            self.targetIntensity = video
        }
        .store(in: &cancellables)

        // Head intensity forwarded directly (no pulse needed — it's already rhythmic)
        StashVideoSyncManager.shared.$headIntensity
        .receive(on: RunLoop.main)
        .sink { [weak self] head in
            guard let self = self, self.isActive else { return }
            self.headIntensity = head
        }
        .store(in: &cancellables)
    }

    // MARK: - Pulse Oscillator

    private func startOscillator() {
        pulseTimer?.invalidate()
        oscillatorPhase = 0.0
        pulseTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.oscillatorTick()
        }
        RunLoop.main.add(pulseTimer!, forMode: .common)
    }

    private func stopOscillator() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        oscillatorPhase = 0.0
        targetIntensity = 0.0
        currentIntensity = 0.0  // synchronous zero — no more ticks after this
    }

    private func oscillatorTick() {
        let target = targetIntensity

        guard target > 0.03 else {
            // Below threshold: decay to zero and hold
            currentIntensity = max(0.0, currentIntensity - Float(tickInterval * 4.0))
            return
        }

        // Frequency scales linearly with intensity
        let freq = minFrequency + Double(target) * (maxFrequency - minFrequency)

        // Advance phase
        oscillatorPhase += 2.0 * .pi * freq * tickInterval

        // Rectified sine: only the positive half → 0…1 pulse shape
        // sin goes -1…1; using (sin+1)/2 gives 0…1 full wave.
        // We use a half-rectified version: max(0, sin) for sharper on/off pulses.
        let wave = Float(max(0.0, sin(oscillatorPhase)))

        // Scale wave by target intensity — peak amplitude matches detected intensity
        currentIntensity = wave * target
    }

    // MARK: - Lifecycle

    func start() {
        isActive = true
        StashVideoSyncManager.shared.isActive = true
        startOscillator()
    }

    func stop() {
        isActive = false
        targetIntensity = 0.0
        stopOscillator()
        headIntensity = 0.0
    }

    /// True when any device channel is in StashSync mode or the pulse engine is running.
    var isSyncing: Bool {
        isActive
            || HandyManager.shared.isStashSyncMode
            || ButtplugManager.shared.isStashSyncMode
            || LoveSpouseManager.shared.isStashSyncMode
    }

    /// Simple on/off used by Feeds settings (and `toggle()`).
    func setSyncing(_ enabled: Bool) {
        print("⚡ StashSyncManager.setSyncing(\(enabled)) handy.enabled:\(HandyManager.shared.isEnabled) handy.connected:\(HandyManager.shared.isConnected)")

        if enabled, !StashyPlusManager.isUnlockedNow {
            DispatchQueue.main.async {
                ToastManager.shared.show(
                    "StashSync is part of Stashy+ — unlock in Settings",
                    icon: "sparkles",
                    style: .error
                )
            }
            return
        }

        if enabled {
            StashVideoSyncManager.shared.isVideoSyncEnabled = true
        }

        HandyManager.shared.isStashSyncMode = enabled
        ButtplugManager.shared.isStashSyncMode = enabled
        LoveSpouseManager.shared.isStashSyncMode = enabled

        if enabled {
            start()
        } else {
            stop()
            StashVideoSyncManager.shared.stop()
        }
    }

    func toggle() {
        setSyncing(!isSyncing)
    }
}
#else
import Foundation
import SwiftUI
import Combine

class StashSyncManager: ObservableObject {
    static let shared = StashSyncManager()
    @Published var currentIntensity: Float = 0.0
    @Published var isActive: Bool = false

    private init() {}
    func start() {}
    func stop() {}
}
#endif
