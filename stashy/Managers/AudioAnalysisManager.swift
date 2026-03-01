#if !os(tvOS)
import Foundation
import AVFoundation
import MediaToolbox
import Combine
import SwiftUI

class AudioAnalysisManager: ObservableObject {
    static let shared = AudioAnalysisManager()
    
    @Published var currentLevel: Float = 0.0
    @Published var visualLevel: Float = 0.0 // Scaled level reflecting sensitivity for UI
    @Published var isActive: Bool = false
    
    @AppStorage("audio_vibe_sensitivity") var sensitivity: Double = 0.15
    @AppStorage("audio_vibe_intensity") var maxIntensity: Double = 1.0
    @AppStorage("audio_vibe_delay_ms") var delayMs: Double = 230.0 {
        didSet {
            if let format = currentFormat {
                prepareBuffer(format: format)
            }
        }
    }
    
    private var tap: MTAudioProcessingTap?
    private var cancellables = Set<AnyCancellable>()
    private var currentFormat: AudioStreamBasicDescription?
    private weak var lastItem: AVPlayerItem?
    
    // Detection state
    private var lastSample: Float = 0
    private var hpfState: Float = 0
    private var peakLevel: Float = 0
    private var agcEnvelope: Float = 0.05 // Adaptive Gain Control state
    private let peakDecay: Float = 0.90 // Faster decay for better transient response
    
    // Ring buffer for audio delay
    private var ringBuffer: [Float] = []
    private var writeIndex: Int = 0
    private var bufferSize: Int = 0
    
    private init() {}
    
    func setup(for playerItem: AVPlayerItem) {
        // Idempotency: Don't re-setup for the same item if we already have a tap
        if lastItem == playerItem && tap != nil {
            print("🎙️ AudioAnalysis: Already setup for this item, skipping.")
            return
        }
        
        print("🎙️ AudioAnalysis: Setting up tap for new item.")
        self.lastItem = playerItem
        
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            init: { (tap, clientInfo, tapStorageOut) in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                // Cleanup if needed
            },
            prepare: { (tap, maxFrames, processingFormat) in
                // Prepare buffer based on format and maxFrames
                let selfPeer = Unmanaged<AudioAnalysisManager>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                selfPeer.prepareBuffer(format: processingFormat.pointee)
            },
            unprepare: { tap in
                // Unprepare
            },
            process: { (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
                let selfPeer = Unmanaged<AudioAnalysisManager>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                selfPeer.processAudio(tap: tap, numberFrames: numberFrames, flags: flags, bufferList: bufferListInOut, numberFramesOut: numberFramesOut, flagsOut: flagsOut)
            }
        )
        
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        
        if status == noErr {
            self.tap = tap
            // Attach tap to audio track
            playerItem.asset.loadTracks(withMediaType: .audio) { tracks, error in
                guard let audioTrack = tracks?.first else { return }
                
                DispatchQueue.main.async {
                    let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
                    inputParams.audioTapProcessor = tap
                    let audioMix = AVMutableAudioMix()
                    audioMix.inputParameters = [inputParams]
                    playerItem.audioMix = audioMix
                }
            }
        }
    }
    
    private func prepareBuffer(format: AudioStreamBasicDescription) {
        self.currentFormat = format
        let sampleRate = format.mSampleRate
        let newBufferSize = Int((delayMs / 1000.0) * sampleRate)
        let safeBufferSize = max(1, newBufferSize)
        
        // Reset buffer safely
        DispatchQueue.main.async {
            self.ringBuffer = Array(repeating: 0, count: safeBufferSize)
            self.writeIndex = 0
            self.bufferSize = safeBufferSize
        }
    }
    
    private func processAudio(tap: MTAudioProcessingTap, numberFrames: CMItemCount, flags: MTAudioProcessingTapFlags, bufferList: UnsafeMutablePointer<AudioBufferList>, numberFramesOut: UnsafeMutablePointer<CMItemCount>, flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
        
        let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferList, flagsOut, nil, numberFramesOut)
        if status != noErr { return }
        
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let buffer = abl.first else { return }
        let ptr = buffer.mData?.assumingMemoryBound(to: Float.self)
        
        var maxInBatch: Float = 0
        
        for i in 0..<Int(numberFramesOut.pointee) {
            let sample = ptr?[i] ?? 0
            
            // Analyze the CURRENT sample
            // 1. High-Pass Filter (focus on impacts, ignore low rumble)
            hpfState = 0.97 * (hpfState + sample - lastSample)
            lastSample = sample
            
            let filteredSample = hpfState
            let level = abs(filteredSample)
            
            // 2. Adaptive Gain Control (AGC) - Very gentle, strictly capped
            let attack: Float = 0.05
            let release: Float = 0.0005
            if level > agcEnvelope {
                agcEnvelope += attack * (level - agcEnvelope)
            } else {
                agcEnvelope += release * (level - agcEnvelope)
            }
            
            // Calculate a target gain based on the envelope (loud -> 1.0, quiet -> >1.0)
            // We strictly cap this at a maximum of 2.0x boost to prevent background noise 
            // from being amplified so much that it triggers vibration at 0% sensitivity.
            let targetGain = 1.0 / max(0.20, agcEnvelope)
            let appliedGain = min(2.0, targetGain)
            
            let normalizedLevel = level * appliedGain
            
            // 3. Transient Detection
            let diff = abs(filteredSample - (ptr?[max(0, i-1)] ?? 0))
            let normalizedDiff = diff * appliedGain
            
            // Apply base multiplier similar to the original reliable logic (was 1.8x, now 1.5x * up to 2.0x dynamic)
            let detectionValue = ((normalizedLevel * 0.5) + (normalizedDiff * 0.5 * 4.0)) * 1.5
            maxInBatch = min(1.0, max(maxInBatch, detectionValue))
        }
        
        // Apply envelope/peak hold logic
        peakLevel = max(maxInBatch, peakLevel * peakDecay)
        
        let currentPeak = peakLevel
        let threshold = Float(0.32 * pow(0.04, sensitivity))
        let shouldTrigger = currentPeak > threshold
        let delaySeconds = max(0.0, delayMs / 1000.0) // How far AHEAD to send the signal
        
        // The visual UI bar will now hit 100% *exactly* when the signal triggers vibration.
        let calculatedVisual = min(1.0, currentPeak / threshold)
        
        DispatchQueue.main.async {
            self.currentLevel = currentPeak
            self.visualLevel = calculatedVisual
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) {
            self.isActive = shouldTrigger
        }
    }
    
    func stop() {
        DispatchQueue.main.async {
            self.isActive = false
            self.currentLevel = 0
            self.visualLevel = 0
            self.peakLevel = 0
            self.hpfState = 0
            self.agcEnvelope = 0.05
        }
    }
}
#endif
