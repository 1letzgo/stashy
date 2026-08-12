#if !os(tvOS)
import Foundation
import AVFoundation
import Vision
import Combine
import SwiftUI
import MediaToolbox

// MARK: - Motion Channel

enum MotionChannel: String {
    case hip    // optical-flow vertical rhythm (thrusting)
    case head   // head/neck centroid movement
    case wrist  // wrist/arm speed (handjob, fingering)
}

// MARK: - Sex Position Classification

enum SexPosition: String, Equatable {
    case unknown        = "Unknown"
    case blowjob        = "Blowjob"
    case cowgirl        = "Cowgirl"
    case reverseCowgirl = "Reverse Cowgirl"
    case doggyStyle     = "Doggy Style"
    case missionary     = "Missionary"
    case handjob        = "Handjob"
    case titfuck        = "Titfuck"
    case pussyLicking   = "Pussy Licking"
    case fingering      = "Fingering"

    /// SF Symbol for display
    var icon: String {
        switch self {
        case .unknown:        return "questionmark.circle"
        case .blowjob:        return "mouth.fill"
        case .cowgirl:        return "arrow.up.circle.fill"
        case .reverseCowgirl: return "arrow.uturn.up.circle.fill"
        case .doggyStyle:     return "figure.walk"
        case .missionary:     return "figure.2"
        case .handjob:        return "hand.raised.fill"
        case .titfuck:        return "teletype"
        case .pussyLicking:   return "mouth.fill"
        case .fingering:      return "hand.point.up.fill"
        }
    }
}

class StashVideoSyncManager: ObservableObject {
    static let shared = StashVideoSyncManager()

    // --- Published channels (0.0 – 1.0) ---
    @Published var hipIntensity: Float = 0.0       // vertical optical flow rhythm
    @Published var headIntensity: Float = 0.0      // head/neck centroid movement
    @Published var pelvisIntensity: Float = 0.0    // hip joint movement
    @Published var wristIntensity: Float = 0.0     // wrist/arm speed
    @Published var horzIntensity: Float = 0.0      // horizontal flow dominance
    @Published var audioIntensity: Float = 0.0     // audio RMS (AGC-normalized)
    @Published var rawMotionIntensity: Float = 0.0 // instantaneous optical-flow speed (no reversal window)
    @Published var dominantChannel: MotionChannel = .hip
    @Published var detectedPosition: SexPosition = .unknown

    // Backwards-compat: toy managers subscribe to $currentIntensity
    @Published var currentIntensity: Float = 0.0

    @Published var isActive: Bool = false
    @Published var frameCounter: Int = 0
    @Published var lastError: String?

    @AppStorage("video_sync_enabled") var isVideoSyncEnabled: Bool = false
    @AppStorage("video_sync_disclaimer_accepted") var isDisclaimerAccepted: Bool = false
    @AppStorage("video_sync_sensitivity") var sensitivity: Double = 0.5 {
        didSet { cachedSensitivity = Float(sensitivity) }
    }
    @AppStorage("video_sync_smoothing") var smoothing: Double = 0.3 {
        didSet { cachedSmoothing = Float(smoothing) }
    }

    // Thread-safe cached copies for background queue / audio thread access
    private var cachedSensitivity: Float = 0.5
    private var cachedSmoothing: Float = 0.3

    @Published var isRecording: Bool = false

    private var currentPlayerTime: Double = 0
    private var currentPlayerItem: AVPlayerItem?
    /// Item currently wired for video/audio taps (used by live captions).
    var currentItem: AVPlayerItem? { currentPlayerItem }
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var previousPixelBuffer: CVPixelBuffer?

    // Head tracking
    private var previousHeadCentroid: CGPoint?

    // Hip/optical-flow rhythm tracking
    private var previousDominantVy: Float = 0
    private var previousDominantVx: Float = 0
    private var recentSpeedHistory: [Float] = []
    private let speedHistorySize = 8
    private var reversalTimestamps: [Int] = []
    private let reversalWindowFrames = 45       // ~1.5s at 30fps

    // Pelvis joint tracking
    private var previousPelvisCentroid: CGPoint?
    private var previousPelvisY: Float = 0.5
    private var pelvisReversalTimestamps: [Int] = []

    // Wrist tracking
    private var previousLeftWrist: CGPoint?
    private var previousRightWrist: CGPoint?
    private var wristSpeedHistory: [Float] = []
    private let wristHistorySize = 6

    // Dominant channel EMA accumulators (slow decay, hysteresis switching)
    private var hipAccum: Float = 0.0
    private var headAccum: Float = 0.0
    private var wristAccum: Float = 0.0

    // Audio tap
    private var audioTap: MTAudioProcessingTap?
    private var audioAGCMax: Float = 0.01  // adaptive ceiling for AGC normalization
    private var tapASBD: AudioStreamBasicDescription?
    private let transcriptionHandlerLock = NSLock()
    private var _transcriptionPCMHandler: ((AVAudioPCMBuffer) -> Void)?
    /// Live PCM from the same decode path as playback (HLS-safe). Called on the audio thread; buffer is a copy.
    var transcriptionPCMHandler: ((AVAudioPCMBuffer) -> Void)? {
        get {
            transcriptionHandlerLock.lock()
            defer { transcriptionHandlerLock.unlock() }
            return _transcriptionPCMHandler
        }
        set {
            transcriptionHandlerLock.lock()
            _transcriptionPCMHandler = newValue
            transcriptionHandlerLock.unlock()
        }
    }
    var hasAudioTapInstalled: Bool { audioTap != nil }

    private var cancellables = Set<AnyCancellable>()
    private let analysisQueue = DispatchQueue(label: "com.stashko.videoanalysis", qos: .userInteractive)
    private let processingLock = NSLock()

    // Vision requests — reused across frames
    private let segmentationRequest: VNGeneratePersonSegmentationRequest = {
        let r = VNGeneratePersonSegmentationRequest()
        // .balanced: ~same usable mask quality for ROI filtering, far cheaper than .accurate
        if #available(iOS 15, *) { r.qualityLevel = .balanced }
        r.outputPixelFormat = kCVPixelFormatType_OneComponent32Float
        return r
    }()
    // VNDetectHumanBodyPoseRequest returns an array of observations (one per detected person)
    private let poseRequest = VNDetectHumanBodyPoseRequest()

    // Y-range (pixel coords, top-origin) of the dominant person from the last pose frame.
    // Used to restrict optical-flow sampling to the active person's region.
    private var dominantPersonPixelYRange: (min: Int, max: Int)? = nil

    // Cached segmentation mask — refreshed every `segmentationInterval` frames
    private var cachedPersonMask: CVPixelBuffer?
    private let segmentationInterval = 4

    // Optical flow runs every N frames (previous buffer still updated each frame for tight deltas)
    private let opticalFlowInterval = 2

    // Adaptive pose cadence state
    private var framesSinceLastPose = 0
    /// Background-safe snapshot of recent motion for pose interval selection
    private var cachedMotionForPose: Float = 0

    // Temporal dominant-person lock
    private var previousDominantCentroid: CGPoint?
    private var previousDominantScore: Float = 0
    private var dominantSwitchCount = 0

    private init() {
        cachedSensitivity = Float(sensitivity)
        cachedSmoothing = Float(smoothing)
    }

    func setup(for playerItem: AVPlayerItem) {
        cleanup()
        self.currentPlayerItem = playerItem

        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: settings)
        if let output = videoOutput { playerItem.add(output) }

        setupAudioTap(for: playerItem)

        displayLink = CADisplayLink(target: self, selector: #selector(updateDisplayLink))
        displayLink?.add(to: .main, forMode: .common)
    }

    // MARK: - Audio Tap (MTAudioProcessingTap + AGC)

    private func setupAudioTap(for playerItem: AVPlayerItem) {
        let asset = playerItem.asset
        if #available(iOS 16.0, *) {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let tracks = try await asset.loadTracks(withMediaType: .audio)
                    guard let audioTrack = tracks.first else { return }
                    await MainActor.run {
                        self.installAudioTap(on: playerItem, audioTrack: audioTrack)
                    }
                } catch {
                    // If track loading fails, skip audio tap gracefully
                }
            }
        } else {
            let tracks = asset.tracks(withMediaType: .audio)
            guard let audioTrack = tracks.first else { return }
            installAudioTap(on: playerItem, audioTrack: audioTrack)
        }
    }

    private func installAudioTap(on playerItem: AVPlayerItem, audioTrack: AVAssetTrack) {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()),
            init: { tap, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                Unmanaged<StashVideoSyncManager>.fromOpaque(storage).release()
            },
            prepare: { tap, _, processingFormat in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let manager = Unmanaged<StashVideoSyncManager>.fromOpaque(storage).takeUnretainedValue()
                manager.tapASBD = processingFormat.pointee
            },
            unprepare: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let manager = Unmanaged<StashVideoSyncManager>.fromOpaque(storage).takeUnretainedValue()
                manager.tapASBD = nil
            },
            process: { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let manager = Unmanaged<StashVideoSyncManager>.fromOpaque(storage).takeUnretainedValue()

                var outFrames: CMItemCount = 0
                MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, &outFrames)
                numberFramesOut.pointee = outFrames

                guard bufferListInOut.pointee.mNumberBuffers > 0,
                      outFrames > 0 else { return }

                let audioBuffer = bufferListInOut.pointee.mBuffers
                guard let dataPtr = audioBuffer.mData else { return }
                let sampleCount = min(Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size, 4096)
                guard sampleCount > 0 else { return }

                let samples = dataPtr.assumingMemoryBound(to: Float.self)
                var sumSquares: Float = 0
                for i in 0..<sampleCount { let s = samples[i]; sumSquares += s * s }
                let rms = sqrt(sumSquares / Float(sampleCount))
                manager.updateAudioIntensity(rms)

                manager.transcriptionHandlerLock.lock()
                let handler = manager._transcriptionPCMHandler
                let asbd = manager.tapASBD
                manager.transcriptionHandlerLock.unlock()
                if let handler, let asbd,
                   let pcm = manager.copyTapBuffer(bufferList: bufferListInOut, frames: outFrames, asbd: asbd) {
                    handler(pcm)
                }
            }
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap = tap else { return }
        self.audioTap = tap

        let audioParams = AVMutableAudioMixInputParameters(track: audioTrack)
        audioParams.audioTapProcessor = tap
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [audioParams]
        playerItem.audioMix = audioMix
    }

    // Called from audio real-time thread — only touches audioAGCMax (audio-thread-only) + dispatches to main
    private func updateAudioIntensity(_ rms: Float) {
        audioAGCMax = max(audioAGCMax * 0.9995, rms)
        let normalized = min(1.0, rms / max(0.001, audioAGCMax))
        let sm = cachedSmoothing
        DispatchQueue.main.async {
            self.audioIntensity = self.audioIntensity * sm + normalized * (1.0 - sm)
        }
    }

    /// Copy tap audio into an owned `AVAudioPCMBuffer` (safe to hand off the realtime thread).
    private func copyTapBuffer(
        bufferList: UnsafeMutablePointer<AudioBufferList>,
        frames: CMItemCount,
        asbd: AudioStreamBasicDescription
    ) -> AVAudioPCMBuffer? {
        guard frames > 0 else { return nil }
        var asbdCopy = asbd
        guard var format = AVAudioFormat(streamDescription: &asbdCopy) else { return nil }
        // Some taps report an incomplete ASBD; fall back to common float stereo @ 48k.
        if format.channelCount == 0 || format.sampleRate <= 0 {
            let rate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48_000
            let channels = AVAudioChannelCount(max(1, asbd.mChannelsPerFrame == 0 ? 2 : asbd.mChannelsPerFrame))
            let interleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            guard let fallback = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: rate,
                channels: channels,
                interleaved: interleaved
            ) else { return nil }
            format = fallback
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let destABL = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let count = min(abl.count, destABL.count)
        for i in 0..<count {
            guard let src = abl[i].mData, let dst = destABL[i].mData else { continue }
            let byteCount = min(Int(abl[i].mDataByteSize), Int(destABL[i].mDataByteSize))
            memcpy(dst, src, byteCount)
        }
        return buffer
    }

    // MARK: - Display Link

    @objc private func updateDisplayLink(link: CADisplayLink) {
        guard isActive, let output = videoOutput else { return }
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        self.currentPlayerTime = itemTime.seconds
        if output.hasNewPixelBuffer(forItemTime: itemTime) {
            if let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
                processFrame(pixelBuffer)
            }
        }
    }

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard processingLock.try() else { return }
        let localCounter = frameCounter
        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            defer { self.processingLock.unlock() }
            let mask = self.runSegmentation(pixelBuffer, frameCounter: localCounter)
            self.runOpticalFlow(pixelBuffer, mask: mask, frameCounter: localCounter)
            self.runPoseAnalysis(pixelBuffer, frameCounter: localCounter)
            DispatchQueue.main.async { self.frameCounter += 1 }
        }
    }

    private func runSegmentation(_ pixelBuffer: CVPixelBuffer, frameCounter: Int) -> CVPixelBuffer? {
        // Reuse cached mask between refreshes to cut Vision cost
        if frameCounter % segmentationInterval != 0, let cached = cachedPersonMask {
            return cached
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([segmentationRequest])
            let mask = segmentationRequest.results?.first?.pixelBuffer
            cachedPersonMask = mask
            return mask
        } catch {
            DispatchQueue.main.async { self.lastError = "Seg: \(error.localizedDescription)" }
            return cachedPersonMask
        }
    }

    private func runOpticalFlow(_ pixelBuffer: CVPixelBuffer, mask: CVPixelBuffer?, frameCounter: Int) {
        guard let previous = previousPixelBuffer else {
            previousPixelBuffer = pixelBuffer
            return
        }
        // Skip Vision optical-flow on odd intervals; keep previous buffer fresh for next delta
        guard frameCounter % opticalFlowInterval == 0 else {
            previousPixelBuffer = pixelBuffer
            return
        }
        let flowRequest = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: previous, options: [:])
        flowRequest.computationAccuracy = .low
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([flowRequest])
            if let result = flowRequest.results?.first as? VNPixelBufferObservation {
                analyzeOpticalFlow(result.pixelBuffer, mask: mask)
            }
        } catch {
            DispatchQueue.main.async { self.lastError = "Flow: \(error.localizedDescription)" }
        }
        previousPixelBuffer = pixelBuffer
    }

    /// Adaptive pose interval: denser when motion is high, sparse when idle.
    private func poseInterval() -> Int {
        let motion = cachedMotionForPose
        if motion > 0.45 { return 3 }
        if motion > 0.15 { return 6 }
        return 9
    }

    private func runPoseAnalysis(_ pixelBuffer: CVPixelBuffer, frameCounter: Int) {
        framesSinceLastPose += 1
        let interval = poseInterval()
        guard framesSinceLastPose >= interval else {
            DispatchQueue.main.async {
                self.headIntensity *= 0.90
                self.pelvisIntensity *= 0.95
                self.wristIntensity *= 0.93
            }
            return
        }
        framesSinceLastPose = 0
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([poseRequest])
            let observations = poseRequest.results ?? []
            if observations.isEmpty {
                decayPoseIntensities(strong: true)
                dominantPersonPixelYRange = nil
                previousDominantCentroid = nil
                previousDominantScore = 0
            } else {
                let dominant = selectDominantPerson(from: observations)
                updateDominantPersonBounds(from: dominant, frameHeight: CVPixelBufferGetHeight(pixelBuffer))
                analyzeHeadMovement(dominant)
                analyzePelvisMovement(dominant)
                analyzeWristMovement(dominant)
                classifyPosition(observations)
                if frameCounter % 30 == 0 {
                    NSLog("🧍 Pose persons: %d | dominant switches: %d | interval: %d",
                          observations.count, dominantSwitchCount, interval)
                }
            }
        } catch {
            dominantPersonPixelYRange = nil
            decayPoseIntensities(strong: true)
        }
    }

    private func decayPoseIntensities(strong: Bool) {
        let headFactor: Float = strong ? 0.5 : 0.90
        let pelvisFactor: Float = strong ? 0.7 : 0.95
        let wristFactor: Float = strong ? 0.7 : 0.93
        DispatchQueue.main.async {
            self.headIntensity *= headFactor
            self.pelvisIntensity *= pelvisFactor
            self.wristIntensity *= wristFactor
        }
    }

    // MARK: - Multi-Person Helpers

    private struct PersonScore {
        let observation: VNHumanBodyPoseObservation
        let score: Float
        let centroid: CGPoint?
    }

    /// Joint-count × avg confidence × temporal proximity × slight center preference.
    private func scorePerson(_ obs: VNHumanBodyPoseObservation) -> PersonScore {
        let keyJoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee
        ]
        var jointCount = 0
        var confSum: Float = 0
        var points: [CGPoint] = []
        for joint in keyJoints {
            if let p = try? obs.recognizedPoint(joint), p.confidence > 0.3 {
                jointCount += 1
                confSum += p.confidence
                points.append(p.location)
            }
        }
        guard jointCount > 0, !points.isEmpty else {
            return PersonScore(observation: obs, score: 0, centroid: nil)
        }
        let avgConf = confSum / Float(jointCount)
        let centroid = CGPoint(
            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
            y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
        )

        var temporalBonus: Float = 1.0
        if let prev = previousDominantCentroid {
            let dx = Float(centroid.x - prev.x)
            let dy = Float(centroid.y - prev.y)
            let dist = sqrt(dx * dx + dy * dy)
            // Full bonus within ~0.15; fades out by 0.4
            temporalBonus = max(0.0, 1.0 - dist / 0.4)
        }

        let centerDist = hypot(Float(centroid.x) - 0.5, Float(centroid.y) - 0.5)
        let centerBonus = max(0.5, 1.0 - centerDist)

        let score = Float(jointCount) * avgConf * (0.6 + 0.4 * temporalBonus) * (0.85 + 0.15 * centerBonus)
        return PersonScore(observation: obs, score: score, centroid: centroid)
    }

    /// Best-tracked person with temporal lock: prefer continuity unless a challenger
    /// clearly outscores the person nearest the previous dominant centroid.
    private func selectDominantPerson(from observations: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation {
        let scored = observations.map { scorePerson($0) }.sorted { $0.score > $1.score }
        guard let best = scored.first else { return observations[0] }

        guard let prev = previousDominantCentroid, observations.count > 1 else {
            previousDominantCentroid = best.centroid
            previousDominantScore = best.score
            return best.observation
        }

        // Continuity candidate = observation whose centroid is closest to last dominant
        var continuity = best
        var minDist = Float.greatestFiniteMagnitude
        for candidate in scored {
            guard let c = candidate.centroid else { continue }
            let dist = hypot(Float(c.x - prev.x), Float(c.y - prev.y))
            if dist < minDist {
                minDist = dist
                continuity = candidate
            }
        }

        // Keep continuity unless challenger beats it by hysteresis margin
        let hysteresis: Float = 0.25
        let keepContinuity = continuity.observation !== best.observation
            && best.score < continuity.score * (1.0 + hysteresis)
            && minDist < 0.25

        let chosen = keepContinuity ? continuity : best
        if !keepContinuity && continuity.observation !== best.observation {
            dominantSwitchCount += 1
        }

        previousDominantCentroid = chosen.centroid
        previousDominantScore = chosen.score
        return chosen.observation
    }

    /// Computes the pixel Y-range (top-origin) for the dominant person by looking at their joint positions.
    private func updateDominantPersonBounds(from obs: VNHumanBodyPoseObservation, frameHeight: Int) {
        let allJoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
            .leftWrist, .rightWrist, .leftHip, .rightHip, .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle
        ]
        var ys: [CGFloat] = []
        for joint in allJoints {
            if let p = try? obs.recognizedPoint(joint), p.confidence > 0.2 {
                // Vision y=0 is bottom → flip to pixel top-origin
                ys.append(1.0 - p.location.y)
            }
        }
        guard !ys.isEmpty else {
            dominantPersonPixelYRange = nil
            return
        }
        let minY = max(0, Int((ys.min()! - 0.05) * CGFloat(frameHeight)))
        let maxY = min(frameHeight, Int((ys.max()! + 0.05) * CGFloat(frameHeight)))
        dominantPersonPixelYRange = (min: minY, max: maxY)
    }

    // MARK: - Optical Flow → Hip Rhythm + Horizontal Motion

    private func analyzeOpticalFlow(_ flowBuffer: CVPixelBuffer, mask: CVPixelBuffer?) {
        CVPixelBufferLockBaseAddress(flowBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(flowBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(flowBuffer) else { return }
        let width = CVPixelBufferGetWidth(flowBuffer)
        let height = CVPixelBufferGetHeight(flowBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(flowBuffer)
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
        let floatsPerRow = bytesPerRow / 4
        let sampleStep = 6

        var maskBaseAddr: UnsafeMutableRawPointer? = nil
        var maskWidth = 0
        var maskHeight = 0
        var maskBytesPerRow = 0
        if let mask = mask {
            CVPixelBufferLockBaseAddress(mask, .readOnly)
            maskBaseAddr = CVPixelBufferGetBaseAddress(mask)
            maskWidth = CVPixelBufferGetWidth(mask)
            maskHeight = CVPixelBufferGetHeight(mask)
            maskBytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        }
        defer { if let mask = mask { CVPixelBufferUnlockBaseAddress(mask, .readOnly) } }

        // Region-of-interest: restrict sampling to the dominant person's joint Y-range
        let roiMinY = dominantPersonPixelYRange?.min ?? 0
        let roiMaxY = dominantPersonPixelYRange?.max ?? height

        var vySum: Float = 0
        var vxSum: Float = 0
        var magSum: Float = 0
        var vxAbsSum: Float = 0
        var vyAbsSum: Float = 0
        var sampleCount = 0
        let s = cachedSensitivity
        let noiseFloor = Float(0.35 / (Double(s) + 0.1))

        for y in stride(from: max(0, roiMinY), to: min(height, roiMaxY), by: sampleStep) {
            let rowOffset = y * floatsPerRow
            for x in stride(from: 0, to: width, by: sampleStep) {
                if let maskAddr = maskBaseAddr {
                    let maskX = x * maskWidth / width
                    let maskY = y * maskHeight / height
                    let maskFloatsPerRow = maskBytesPerRow / 4
                    let maskVal = maskAddr.assumingMemoryBound(to: Float.self)[maskY * maskFloatsPerRow + maskX]
                    if maskVal < 0.5 { continue }
                }
                let idx = rowOffset + x * 2
                let dx = floatBuffer[idx]
                let dy = floatBuffer[idx + 1]
                let mag = sqrt(dx * dx + dy * dy)
                if mag > noiseFloor {
                    vySum += dy
                    vxSum += dx
                    magSum += mag
                    vxAbsSum += abs(dx)
                    vyAbsSum += abs(dy)
                    sampleCount += 1
                }
            }
        }

        let currentFrame = frameCounter
        reversalTimestamps = reversalTimestamps.filter { currentFrame - $0 <= reversalWindowFrames }

        guard sampleCount > 4 else {
            DispatchQueue.main.async {
                self.rawMotionIntensity *= 0.7
                self.hipIntensity = self.hipIntensity * self.cachedSmoothing
                self.horzIntensity *= 0.85
                self.currentIntensity = self.computeCurrentIntensity()
            }
            return
        }

        let dominantVy = vySum / Float(sampleCount)
        let dominantVx = vxSum / Float(sampleCount)
        let avgMag = magSum / Float(sampleCount)

        let rawRatio = vxAbsSum / max(0.001, vxAbsSum + vyAbsSum)
        let horzRatio = max(0.0, (rawRatio - 0.55) / 0.45)

        recentSpeedHistory.append(avgMag)
        if recentSpeedHistory.count > speedHistorySize { recentSpeedHistory.removeFirst() }
        let recentAvgSpeed = recentSpeedHistory.reduce(0, +) / Float(recentSpeedHistory.count)

        // Fix 4: Detect when direction signal is weak (two people moving in opposite directions).
        // In that case vySum ≈ 0 even though avgMag is high. We measure how much the net direction
        // vector is "cancelled out" relative to the total magnitude energy.
        let netMag = sqrt(dominantVy * dominantVy + dominantVx * dominantVx)
        let directionCoherence = netMag / max(0.001, avgMag)  // 1.0 = all pixels same direction, 0 = cancel-out

        let prevVy = previousDominantVy
        let vertReversed = (prevVy > 0.25 && dominantVy < -0.25) || (prevVy < -0.25 && dominantVy > 0.25)
        previousDominantVy = dominantVy
        previousDominantVx = dominantVx

        if vertReversed { reversalTimestamps.append(currentFrame) }

        let updatedReversals = Float(reversalTimestamps.count)
        let updatedFreq = updatedReversals / (Float(reversalWindowFrames) / 30.0)

        let speedActive = recentAvgSpeed > (0.08 / max(0.1, s))
        let freqRaw: Float = !speedActive || updatedReversals < 2 ? 0.0 : min(1.0, updatedFreq / 3.0)

        // Weight hip level by speed so it decays when motion stops
        let freqBasedHip = freqRaw * min(1.0, recentAvgSpeed * 6.0)

        // Fix 2: Fallback for low-coherence frames (two people cancelling each other out).
        // When directionCoherence < 0.3, the net direction vector is unreliable.
        // Instead use raw magnitude energy as a proxy for activity — weighted by coherence inversion.
        let magnitudeBasedHip = speedActive ? min(1.0, recentAvgSpeed * 5.0 * s) : 0.0
        let incoherenceWeight = max(0.0, 0.3 - directionCoherence) / 0.3  // 0 when coherent, 1 when fully cancelled
        let hipLevel = freqBasedHip * (1.0 - incoherenceWeight) + magnitudeBasedHip * incoherenceWeight

        let rawLevel = min(1.0, avgMag * 6.0 * s)
        let horzLevel = min(1.0, recentAvgSpeed * horzRatio * s * 4.0)

        let sm = cachedSmoothing
        DispatchQueue.main.async {
            self.rawMotionIntensity = self.rawMotionIntensity * sm + rawLevel * (1.0 - sm)
            self.hipIntensity = min(1.0, self.hipIntensity * sm + hipLevel * (1.0 - sm))
            self.horzIntensity = self.horzIntensity * 0.6 + horzLevel * 0.4
            self.currentIntensity = self.computeCurrentIntensity()

            if currentFrame % 15 == 0 {
                NSLog("📊 VR: %d revs | Freq: %.2f | Coherence: %.2f | MagFallback: %.2f | HipLvl: %.2f | SmoothInt: %.2f",
                      Int(updatedReversals), updatedFreq, directionCoherence, magnitudeBasedHip, hipLevel, self.hipIntensity)
            }
        }
    }

    // MARK: - Head Pose Analysis

    private func analyzeHeadMovement(_ observation: VNHumanBodyPoseObservation) {
        let headJoints: [VNHumanBodyPoseObservation.JointName] = [.neck, .leftEar, .rightEar, .nose]
        var points: [CGPoint] = []
        for joint in headJoints {
            if let point = try? observation.recognizedPoint(joint), point.confidence > 0.3 {
                points.append(point.location)
            }
        }
        guard !points.isEmpty else {
            DispatchQueue.main.async { self.headIntensity *= 0.5 }
            return
        }
        let centroid = CGPoint(
            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
            y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
        )
        let sm = cachedSmoothing
        let s = cachedSensitivity
        if let prev = previousHeadCentroid {
            let dx = Float(centroid.x - prev.x)
            let dy = Float(centroid.y - prev.y)
            let delta = sqrt(dx * dx + dy * dy)
            let normalized = min(1.0, (delta / 0.05) * s)
            if normalized < 0.02 {
                DispatchQueue.main.async { self.headIntensity *= 0.5 }
            } else {
                DispatchQueue.main.async {
                    self.headIntensity = min(1.0, self.headIntensity * sm + normalized * (1.0 - sm))
                }
            }
        }
        previousHeadCentroid = centroid
    }

    // MARK: - Pelvis/Hip Joint Analysis

    private func analyzePelvisMovement(_ observation: VNHumanBodyPoseObservation) {
        let currentFrame = frameCounter
        pelvisReversalTimestamps = pelvisReversalTimestamps.filter { currentFrame - $0 <= reversalWindowFrames }

        let pelvisJoints: [VNHumanBodyPoseObservation.JointName] = [.leftHip, .rightHip, .root]
        var points: [CGPoint] = []
        for joint in pelvisJoints {
            if let point = try? observation.recognizedPoint(joint), point.confidence > 0.3 {
                points.append(point.location)
            }
        }
        guard !points.isEmpty else {
            DispatchQueue.main.async { self.pelvisIntensity *= 0.6 }
            return
        }
        let centroid = CGPoint(
            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
            y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
        )

        if let prev = previousPelvisCentroid {
            let dx = Float(centroid.x - prev.x)
            let dy = Float(centroid.y - prev.y)
            let delta = sqrt(dx * dx + dy * dy)
            let s = cachedSensitivity

            let normalized = min(1.0, (delta / 0.05) * s)

            guard normalized > 0.01 else {
                DispatchQueue.main.async { self.pelvisIntensity *= self.cachedSmoothing }
                return
            }

            let prevY = previousPelvisY
            if (prevY > 0.52 && normalized < 0.48) || (prevY < 0.48 && normalized > 0.52) {
                pelvisReversalTimestamps.append(currentFrame)
            }
            previousPelvisY = normalized

            let pelvisReversals = Float(pelvisReversalTimestamps.count)
            let pelvisFreq = pelvisReversals / (Float(reversalWindowFrames) / 30.0)
            let pelvisLevel = normalized > 0.05 ? min(1.0, pelvisFreq / 3.0) : normalized * 0.5

            let sm = cachedSmoothing
            DispatchQueue.main.async {
                self.pelvisIntensity = min(1.0, self.pelvisIntensity * sm + pelvisLevel * (1.0 - sm))
                self.currentIntensity = self.computeCurrentIntensity()
            }
        }
        previousPelvisCentroid = centroid
    }

    // MARK: - Wrist / Arm Speed Analysis

    private func analyzeWristMovement(_ observation: VNHumanBodyPoseObservation) {
        let joints: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            (.leftWrist, .leftElbow),
            (.rightWrist, .rightElbow)
        ]

        var totalDelta: Float = 0
        var count = 0

        for arm in joints {
            var armPoints: [CGPoint] = []
            if let w = try? observation.recognizedPoint(arm.0), w.confidence > 0.3 { armPoints.append(w.location) }
            if let e = try? observation.recognizedPoint(arm.1), e.confidence > 0.3 { armPoints.append(e.location) }

            if !armPoints.isEmpty {
                let centroid = CGPoint(x: armPoints.map(\.x).reduce(0, +) / CGFloat(armPoints.count),
                                      y: armPoints.map(\.y).reduce(0, +) / CGFloat(armPoints.count))
                let prev = arm.0 == .leftWrist ? previousLeftWrist : previousRightWrist
                if let prev = prev {
                    let dx = Float(centroid.x - prev.x)
                    let dy = Float(centroid.y - prev.y)
                    totalDelta += sqrt(dx * dx + dy * dy)
                    count += 1
                }
                if arm.0 == .leftWrist { previousLeftWrist = centroid }
                else { previousRightWrist = centroid }
            }
        }

        guard count > 0 else {
            DispatchQueue.main.async { self.wristIntensity *= 0.7 }
            return
        }

        let avgDelta = totalDelta / Float(count)
        let s = cachedSensitivity
        let normalized = min(1.0, (avgDelta / 0.04) * s)

        wristSpeedHistory.append(normalized)
        if wristSpeedHistory.count > wristHistorySize { wristSpeedHistory.removeFirst() }
        let smoothedWrist = min(1.0, wristSpeedHistory.reduce(0, +) / Float(wristSpeedHistory.count))

        let sm = cachedSmoothing
        DispatchQueue.main.async {
            if normalized < 0.03 {
                self.wristIntensity *= 0.6
            } else {
                self.wristIntensity = min(1.0, self.wristIntensity * sm + smoothedWrist * (1.0 - sm))
            }
            self.currentIntensity = self.computeCurrentIntensity()
        }
    }

    // MARK: - Sex Position Classification

    // Helper to extract a joint from an observation (Vision coords: y=0 bottom)
    private func joint(_ name: VNHumanBodyPoseObservation.JointName,
                       from obs: VNHumanBodyPoseObservation,
                       minConfidence: Float = 0.25) -> CGPoint? {
        guard let p = try? obs.recognizedPoint(name), p.confidence > minConfidence else { return nil }
        return p.location
    }

    // Compact body metrics for a single observation
    private struct BodyMetrics {
        let headY: CGFloat?       // Vision Y of head centroid (0=bottom)
        let hipY: CGFloat?        // Vision Y of hip centroid
        let shoulderY: CGFloat?   // Vision Y of shoulder centroid
        let bodySpan: CGFloat?    // headY - hipY (positive = upright)
        let jointCount: Int       // number of confident joints — proxy for person size/proximity
    }

    private func bodyMetrics(for obs: VNHumanBodyPoseObservation) -> BodyMetrics {
        let headPts = [joint(.nose, from: obs), joint(.neck, from: obs),
                       joint(.leftEar, from: obs), joint(.rightEar, from: obs)].compactMap { $0 }
        let hipPts  = [joint(.leftHip, from: obs), joint(.rightHip, from: obs)].compactMap { $0 }
        let shPts   = [joint(.leftShoulder, from: obs), joint(.rightShoulder, from: obs)].compactMap { $0 }

        let headY     = headPts.isEmpty ? nil : headPts.map(\.y).reduce(0,+) / CGFloat(headPts.count)
        let hipY      = hipPts.isEmpty  ? nil : hipPts.map(\.y).reduce(0,+)  / CGFloat(hipPts.count)
        let shoulderY = shPts.isEmpty   ? nil : shPts.map(\.y).reduce(0,+)   / CGFloat(shPts.count)
        let span: CGFloat? = headY.flatMap { hy in hipY.map { hy - $0 } }
        // Use visible joint count as a proxy for person size (more joints = closer to camera)
        let allJoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
            .leftWrist, .rightWrist, .leftHip, .rightHip, .leftKnee, .rightKnee
        ]
        let count = allJoints.filter { (try? obs.recognizedPoint($0))?.confidence ?? 0 > 0.25 }.count
        return BodyMetrics(headY: headY, hipY: hipY, shoulderY: shoulderY,
                           bodySpan: span, jointCount: count)
    }

    private func classifyPosition(_ observations: [VNHumanBodyPoseObservation]) {
        guard !observations.isEmpty else {
            DispatchQueue.main.async {
                if self.detectedPosition != .unknown { self.detectedPosition = .unknown }
            }
            return
        }

        // Current signal channels (read on background thread before dispatching)
        let wristDom = wristIntensity
        let headDom  = headIntensity
        let hipDom   = hipIntensity
        let horzDom  = horzIntensity

        // ── Build per-person metrics, sorted most-joints (dominant) → fewest ──────
        let metrics = observations
            .map { bodyMetrics(for: $0) }
            .sorted { $0.jointCount > $1.jointCount }

        let primary   = metrics[0]
        let secondary = metrics.count > 1 ? metrics[1] : nil

        // ── Multi-person geometry signals ─────────────────────────────────────
        // verticalSeparation > 0: primary person is higher in frame than secondary
        // (e.g. cowgirl: rider (primary=large) is above passive partner)
        let verticalSeparation: CGFloat? = secondary.flatMap { sec in
            primary.hipY.flatMap { pHip in sec.hipY.map { pHip - $0 } }
        }

        // headNearOtherHips: primary's head centroid is near secondary's hip region
        // → strong blowjob / pussy-licking signal
        let headNearOtherHips: Bool = {
            guard let pH = primary.headY, let sHip = secondary?.hipY else { return false }
            return abs(pH - sHip) < 0.15
        }()

        // ── Motion-channel primary classification ─────────────────────────────
        // Motion channels are primary; skeleton geometry is tie-breaker only.

        var position: SexPosition = .unknown

        // 1. HANDJOB: wrist motion dominant
        if wristDom > 0.30 && wristDom > hipDom * 1.4 && wristDom > headDom * 1.2 {
            position = .handjob
        }
        // 2. BLOWJOB / PUSSY LICKING: head bobbing dominant
        //    Multi-person boost: if primary head is near secondary hips, confidence rises
        else if headDom > 0.20 && headDom > hipDom * 1.1 && headDom > horzDom * 1.2 {
            position = headNearOtherHips ? .blowjob : .blowjob  // future: distinguish pussyLicking by position
        }
        // 3. DOGGY STYLE: horizontal thrust dominant
        else if horzDom > 0.22 && horzDom > hipDom * 1.0 {
            // With two people: if they are at similar heights → doggy; if stacked vertically → spooning candidate
            if let sep = verticalSeparation, abs(sep) < 0.10 {
                position = .doggyStyle
            } else {
                position = .doggyStyle
            }
        }
        // 4. COWGIRL / REVERSE COWGIRL / MISSIONARY: vertical hip rhythm dominant
        else if hipDom > 0.22 {
            if let span = primary.bodySpan {
                if span > 0.22 {
                    // Primary person is upright
                    // Reverse cowgirl: shoulders below hips in Vision coords (person leans back)
                    if let sy = primary.shoulderY, let hy = primary.hipY, sy < hy - 0.08 {
                        position = .reverseCowgirl
                    } else {
                        position = .cowgirl
                    }
                } else if let sep = verticalSeparation, sep < -0.08 {
                    // Primary person is lower than secondary (passive partner on top) → missionary
                    position = .missionary
                } else {
                    position = .missionary
                }
            } else {
                // No span: use vertical separation between two people as fallback
                if let sep = verticalSeparation, sep > 0.12 {
                    position = .cowgirl       // primary (larger) is higher
                } else {
                    position = .cowgirl
                }
            }
        }
        // If nothing matches clearly → stay .unknown

        DispatchQueue.main.async {
            if position != self.detectedPosition {
                self.detectedPosition = position
                NSLog("🎭 Position detected: %@ (persons: %d)", position.rawValue, observations.count)
            }
        }
    }

    // MARK: - Signal Fusion (dominant-channel routing + audio blend)
    // Must be called on main thread (reads/writes @Published properties)

    private func computeCurrentIntensity() -> Float {
        let s = cachedSensitivity

        // Snapshot for adaptive pose cadence (read from analysis queue)
        cachedMotionForPose = max(rawMotionIntensity, hipIntensity, headIntensity, wristIntensity)

        // --- Update dominant channel EMA accumulators (slow adaptation) ---
        let emaAlpha: Float = 0.03
        hipAccum   = hipAccum   * (1 - emaAlpha) + hipIntensity   * emaAlpha
        headAccum  = headAccum  * (1 - emaAlpha) + headIntensity  * emaAlpha
        wristAccum = wristAccum * (1 - emaAlpha) + wristIntensity * emaAlpha

        // Hysteresis: only switch dominant channel if new leader is clearly ahead
        let hysteresis: Float = 0.15
        let currentAccum: Float
        switch dominantChannel {
        case .hip:   currentAccum = hipAccum
        case .head:  currentAccum = headAccum
        case .wrist: currentAccum = wristAccum
        }
        let candidates: [(Float, MotionChannel)] = [(hipAccum, .hip), (headAccum, .head), (wristAccum, .wrist)]
        if let best = candidates.max(by: { $0.0 < $1.0 }),
           best.1 != dominantChannel,
           best.0 > currentAccum + hysteresis {
            dominantChannel = best.1
        }

        // --- Motion signal from dominant channel ---
        let motionSignal: Float
        switch dominantChannel {
        case .hip:
            // Hip rhythm + supplementary boosts from pelvis and horizontal flow
            let thrustBase = hipIntensity
            let pelvisBoost = pelvisIntensity * 0.25
            let horzBoost = horzIntensity * (1.0 - hipIntensity * 0.5) * 0.15
            motionSignal = min(1.0, thrustBase + pelvisBoost + horzBoost)
        case .head:
            motionSignal = headIntensity
        case .wrist:
            motionSignal = wristIntensity
        }

        // --- Blend motion (70%) + audio (30%) ---
        let blended = motionSignal * 0.7 + audioIntensity * 0.3
        let scaled = min(1.0, blended * (0.5 + s * 1.0))

        if frameCounter % 15 == 0 {
            NSLog("🎛 Ch:%@ | Hip:%.2f Head:%.2f Wrist:%.2f | Audio:%.2f | Motion:%.2f | Out:%.2f",
                  dominantChannel.rawValue, hipIntensity, headIntensity, wristIntensity, audioIntensity, motionSignal, scaled)
        }

        let ceiling: Float = s < 0.3 ? 0.4 : (s < 0.7 ? 0.8 : 1.0)
        return min(ceiling, scaled)
    }

    // MARK: - Lifecycle

    func stop() {
        isActive = false
        cleanup()
    }

    private func cleanup() {
        displayLink?.invalidate()
        displayLink = nil
        if let output = videoOutput, let item = currentPlayerItem { item.remove(output) }
        videoOutput = nil
        currentPlayerItem = nil
        audioTap = nil
        tapASBD = nil
        previousPixelBuffer = nil
        dominantPersonPixelYRange = nil
        cachedPersonMask = nil
        framesSinceLastPose = 0
        cachedMotionForPose = 0
        previousDominantCentroid = nil
        previousDominantScore = 0
        dominantSwitchCount = 0
        previousHeadCentroid = nil
        previousPelvisCentroid = nil
        previousPelvisY = 0.5
        previousLeftWrist = nil
        previousRightWrist = nil
        previousDominantVy = 0
        previousDominantVx = 0
        recentSpeedHistory = []
        wristSpeedHistory = []
        reversalTimestamps = []
        pelvisReversalTimestamps = []
        hipAccum = 0
        headAccum = 0
        wristAccum = 0
        audioAGCMax = 0.01
        dominantChannel = .hip
        hipIntensity = 0
        headIntensity = 0
        pelvisIntensity = 0
        wristIntensity = 0
        horzIntensity = 0
        audioIntensity = 0
        rawMotionIntensity = 0
        currentIntensity = 0
        detectedPosition = .unknown
        lastError = nil
    }

    func startRecording() {}
    func stopRecordingAndExport() -> String? { return nil }
}
#endif
