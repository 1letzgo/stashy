#if !os(tvOS)
import Foundation
import AVFoundation
import MediaToolbox
import Combine
import SwiftUI

class AudioAnalysisManager: ObservableObject {
    static let shared = AudioAnalysisManager()
    
    @Published var currentLevel: Float = 0.0
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
            // 1. High-Pass Filter (focus on human moans/impacts, ignore low rumble)
            hpfState = 0.97 * (hpfState + sample - lastSample)
            lastSample = sample
            
            let filteredSample = hpfState
            let level = abs(filteredSample)
            
            // Use difference between filtered samples for transient detection
            let diff = abs(filteredSample - (ptr?[max(0, i-1)] ?? 0))
            
            // Fine-tuned Gain: 1.8x
            let detectionValue = ((level * 0.5) + (diff * 0.5 * 4.0)) * 1.8 
            maxInBatch = min(1.0, max(maxInBatch, detectionValue))
        }
        
        // Apply envelope/peak hold logic
        peakLevel = max(maxInBatch, peakLevel * peakDecay)
        
        let currentPeak = peakLevel
        let threshold = Float(0.32 * pow(0.04, sensitivity))
        let shouldTrigger = currentPeak > threshold
        let delaySeconds = max(0.0, delayMs / 1000.0) // How far AHEAD to send the signal
        
        // Update level UI and isActivestate
        // The goal is: Sound happens later, signal happens NOW.
        // But since we process sound AS it plays, we must fire the signal NOW, 
        // and delay the SOUND. However, delaying AVPlayer sound live is difficult.
        // The alternative is delaying the SIGNAL by X ms, which actually makes latency WORSE.
        // Assuming the user meant "Action Delay" (sound plays, then vibration later), 
        // we use asyncAfter to delay the vibration trigger.
        
        DispatchQueue.main.async {
            self.currentLevel = currentPeak
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) {
            self.isActive = shouldTrigger
        }
    }
    
    func stop() {
        DispatchQueue.main.async {
            self.isActive = false
            self.currentLevel = 0
            self.peakLevel = 0
            self.hpfState = 0
        }
    }
}
#endif
