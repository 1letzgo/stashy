#if !os(tvOS)
import AVFoundation
import Foundation
import Speech

/// Pulls a low-resolution Stash transcode ahead of the playhead so speech recognition can run
/// minutes before the audio is actually heard.
///
/// `GET /scene/{id}/stream.mp4?start=<sec>` makes ffmpeg seek server-side and emit a fragmented
/// MP4 over a non-seekable pipe. Fragmented MP4 stays readable when truncated, so each chunk is
/// downloaded into a temp file up to a byte budget and then decoded from that complete local file
/// — `AVAssetReader` on a local file avoids the remote-reader failures that force the realtime
/// audio tap (and its unavoidable 1-2s recognition lag).
@available(iOS 26.0, *)
final class SceneTranscodeAudioPrefetcher {
    enum Outcome {
        case completed
        case needsRestart
    }

    enum FeedDecision {
        case feed
        case wait(UInt64)
        case restart
    }

    /// Callbacks back into the transcription controller. All payloads are `Sendable` scalars.
    struct Delegate {
        /// Analyzer time from this point on maps to media time `globalStart`.
        let anchor: @Sendable (_ globalStart: Double) async -> Void
        /// `analyzerDelta` seconds of audio were fed; media is covered up to `mediaFrontier`.
        let progress: @Sendable (_ mediaFrontier: Double, _ analyzerDelta: Double) async -> Void
        /// Controller-side throttling: lead over the playhead, analyzer backlog and seek detection.
        let step: @Sendable (_ mediaFrontier: Double) async -> FeedDecision
    }

    /// 240p keeps the extra server transcode cheap; only the audio track is used.
    static let resolution = "LOW"
    /// Small first chunk so captions start within a few seconds.
    private static let firstChunkByteBudget = 1_200_000
    private static let minChunkByteBudget = 1_500_000
    private static let maxChunkByteBudget = 24_000_000
    private static let targetChunkSeconds: Double = 45
    /// How close to the end of the scene counts as "nothing left to transcribe".
    private static let endOfMediaSlack: Double = 2.0
    private static let maxConsecutiveFailures = 4
    /// Requested a little early so an imprecise server-side seek still covers the boundary.
    private static let overlapSeconds: Double = 0.75
    /// Fed between chunks so the analyzer finalizes the sentence at the seam.
    private static let silenceSeconds: Double = 0.3
    private static let downloadTimeout: TimeInterval = 45
    private static let progressReportInterval = 16

    private let sceneID: String
    /// Scene length in seconds; lets a truncated response be told apart from the real end.
    private let mediaDuration: Double?

    init(sceneID: String, mediaDuration: Double?) {
        self.sceneID = sceneID
        self.mediaDuration = (mediaDuration ?? 0) > 0 ? mediaDuration : nil
    }

    /// `true` when the active server config can build transcode URLs for this scene.
    static func isAvailable() -> Bool {
        ServerConfigManager.shared.activeConfig != nil
    }

    // MARK: - Feed loop

    func run(
        from startSeconds: Double,
        targetFormat: AVAudioFormat,
        input: AsyncStream<AnalyzerInput>.Continuation,
        delegate: Delegate
    ) async throws -> Outcome {
        var frontier = max(0, startSeconds)
        var budget = Self.firstChunkByteBudget
        var bytesPerMediaSecond: Double?
        var isFirstChunk = true
        var failures = 0

        while !Task.isCancelled {
            switch await delegate.step(frontier) {
            case .restart:
                return .needsRestart
            case .wait(let nanoseconds):
                try await Task.sleep(nanoseconds: nanoseconds)
                continue
            case .feed:
                break
            }

            if let duration = mediaDuration, frontier >= duration - Self.endOfMediaSlack {
                return .completed
            }

            let requestStart = isFirstChunk ? frontier : max(0, frontier - Self.overlapSeconds)
            let usedBudget = budget
            let fileURL = Self.makeTempURL()
            var downloaded = 0
            var chunk: ChunkResult?

            do {
                let request = try await Self.makeChunkRequest(sceneID: sceneID, start: requestStart)
                downloaded = try await SceneTranscodeChunkDownloader(fileURL: fileURL, byteBudget: usedBudget)
                    .download(request: request, timeout: Self.downloadTimeout)
                if downloaded > 0 {
                    chunk = try await feedChunk(
                        fileURL: fileURL,
                        requestedStart: requestStart,
                        skipBefore: isFirstChunk ? nil : frontier,
                        prependSilence: !isFirstChunk,
                        targetFormat: targetFormat,
                        input: input,
                        delegate: delegate
                    )
                }
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: fileURL)
                throw CancellationError()
            } catch {
                try? FileManager.default.removeItem(at: fileURL)
                failures += 1
                guard failures < Self.maxConsecutiveFailures else { throw error }
                try await Task.sleep(nanoseconds: Self.retryDelay(after: failures))
                continue
            }
            try? FileManager.default.removeItem(at: fileURL)

            // A truncated response is normal (dropped connection, transcode hiccup) and must not
            // end the session — only the scene duration decides when there is nothing left.
            guard let chunk, chunk.mediaEnd - frontier >= 0.25 else {
                failures += 1
                guard failures < Self.maxConsecutiveFailures else {
                    throw SceneLiveTranscriptionError.audioSourceUnavailable
                }
                try await Task.sleep(nanoseconds: Self.retryDelay(after: failures))
                continue
            }

            failures = 0
            frontier = chunk.mediaEnd
            isFirstChunk = false

            let measured = Double(downloaded) / max(0.25, chunk.decodedSeconds)
            bytesPerMediaSecond = bytesPerMediaSecond.map { $0 * 0.5 + measured * 0.5 } ?? measured
            if let rate = bytesPerMediaSecond {
                budget = min(
                    Self.maxChunkByteBudget,
                    max(Self.minChunkByteBudget, Int(rate * Self.targetChunkSeconds * 1.3))
                )
            }
        }

        throw CancellationError()
    }

    private static func retryDelay(after failures: Int) -> UInt64 {
        UInt64(min(4.0, pow(2.0, Double(failures - 1)) * 0.4) * 1_000_000_000)
    }

    private struct ChunkResult {
        let mediaEnd: Double
        let decodedSeconds: Double
    }

    private nonisolated func feedChunk(
        fileURL: URL,
        requestedStart: Double,
        skipBefore: Double?,
        prependSilence: Bool,
        targetFormat: AVAudioFormat,
        input: AsyncStream<AnalyzerInput>.Continuation,
        delegate: Delegate
    ) async throws -> ChunkResult {
        let asset = AVURLAsset(url: fileURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else {
            return ChunkResult(mediaEnd: requestedStart, decodedSeconds: 0)
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else { throw SceneLiveTranscriptionError.conversionFailed }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? SceneLiveTranscriptionError.audioSourceUnavailable
        }
        defer { if reader.status == .reading { reader.cancelReading() } }

        var converter: SceneTranscriptionAudioConverter?
        var mediaEnd = requestedStart
        var decodedSeconds: Double = 0
        var pendingAnalyzerSeconds: Double = 0
        var buffersSinceReport = 0
        var didAnchor = false
        var needsSilence = prependSilence

        while reader.status == .reading, !Task.isCancelled {
            guard let sample = output.copyNextSampleBuffer() else { break }

            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let duration = CMSampleBufferGetDuration(sample).seconds
            let sampleStart = requestedStart + (pts.isFinite ? pts : 0)
            let sampleEnd = sampleStart + (duration.isFinite ? duration : 0)

            // Drop the requested overlap so the seam neither duplicates nor loses words.
            if let skipBefore, sampleEnd <= skipBefore { continue }

            guard let pcm = Self.sampleBufferToPCMBuffer(sample) else { continue }
            if converter == nil
                || converter?.sourceFormat.sampleRate != pcm.format.sampleRate
                || converter?.sourceFormat.channelCount != pcm.format.channelCount {
                converter = SceneTranscriptionAudioConverter(
                    sourceFormat: pcm.format,
                    targetFormat: targetFormat
                )
            }
            guard let activeConverter = converter else {
                throw SceneLiveTranscriptionError.conversionFailed
            }
            let converted = try activeConverter.convert(pcm, to: targetFormat)
            guard converted.frameLength > 0 else { continue }

            if needsSilence {
                needsSilence = false
                if let silence = Self.makeSilence(seconds: Self.silenceSeconds, format: targetFormat) {
                    input.yield(AnalyzerInput(buffer: silence))
                    await delegate.progress(mediaEnd, Self.silenceSeconds)
                }
            }
            if !didAnchor {
                didAnchor = true
                await delegate.anchor(sampleStart)
            }

            input.yield(AnalyzerInput(buffer: converted))
            mediaEnd = max(mediaEnd, sampleEnd)
            decodedSeconds = mediaEnd - requestedStart
            pendingAnalyzerSeconds += Double(converted.frameLength) / targetFormat.sampleRate
            buffersSinceReport += 1

            if buffersSinceReport >= Self.progressReportInterval {
                await delegate.progress(mediaEnd, pendingAnalyzerSeconds)
                pendingAnalyzerSeconds = 0
                buffersSinceReport = 0
                switch await delegate.step(mediaEnd) {
                case .feed:
                    break
                case .wait(let nanoseconds):
                    try await Task.sleep(nanoseconds: nanoseconds)
                case .restart:
                    // The controller already scheduled a fresh session; stop feeding this one.
                    throw CancellationError()
                }
            }
        }

        if pendingAnalyzerSeconds > 0 {
            await delegate.progress(mediaEnd, pendingAnalyzerSeconds)
        }
        if Task.isCancelled { throw CancellationError() }
        // A truncated tail fragment is expected — only report a failure that produced nothing.
        if reader.status == .failed, decodedSeconds <= 0 {
            throw reader.error ?? SceneLiveTranscriptionError.audioSourceUnavailable
        }
        return ChunkResult(mediaEnd: mediaEnd, decodedSeconds: max(0, decodedSeconds))
    }

    // MARK: - Helpers

    @MainActor
    private static func makeChunkRequest(sceneID: String, start: Double) throws -> URLRequest {
        guard let config = ServerConfigManager.shared.activeConfig,
              var components = URLComponents(string: "\(config.baseURL)/scene/\(sceneID)/stream.mp4")
        else {
            throw SceneLiveTranscriptionError.audioSourceUnavailable
        }
        components.queryItems = [
            URLQueryItem(name: "start", value: String(format: "%.3f", max(0, start))),
            URLQueryItem(name: "resolution", value: resolution),
        ]
        guard let url = signedURL(components.url) ?? components.url else {
            throw SceneLiveTranscriptionError.audioSourceUnavailable
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let apiKey = config.secureApiKey, !apiKey.isEmpty {
            request.addValue(apiKey, forHTTPHeaderField: "ApiKey")
        }
        return request
    }

    private static func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("stashy-cc-\(UUID().uuidString).mp4")
    }

    private static func makeSilence(seconds: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(max(1, seconds * format.sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            if let floats = buffer.floatChannelData {
                memset(floats[channel], 0, Int(frames) * MemoryLayout<Float>.size)
            } else if let ints = buffer.int16ChannelData {
                memset(ints[channel], 0, Int(frames) * MemoryLayout<Int16>.size)
            }
        }
        return buffer
    }

    private static func sampleBufferToPCMBuffer(_ sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(sample),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else { return nil }
        var asbd = asbdPtr.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return buffer
    }
}

// MARK: - Chunk downloader

/// Streams a transcode response into a temp file and stops once the byte budget is reached.
/// The response has no `Content-Length` and no range support, so the budget is the only handle
/// we have on chunk size; the actual media duration is measured after decoding.
private final class SceneTranscodeChunkDownloader: NSObject, URLSessionDataDelegate {
    private let fileURL: URL
    private let byteBudget: Int
    private let lock = NSLock()
    private var handle: FileHandle?
    private var written = 0
    private var isFinished = false
    private var continuation: CheckedContinuation<Int, Error>?
    private var session: URLSession?

    init(fileURL: URL, byteBudget: Int) {
        self.fileURL = fileURL
        self.byteBudget = max(64_000, byteBudget)
    }

    func download(request: URLRequest, timeout: TimeInterval) async throws -> Int {
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try FileHandle(forWritingTo: fileURL)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 4
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                lock.lock()
                if isFinished {
                    let bytes = written
                    lock.unlock()
                    continuation.resume(returning: bytes)
                    return
                }
                self.continuation = continuation
                lock.unlock()
                session.dataTask(with: request).resume()
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }

    private func finish(_ result: Result<Int, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let pending = continuation
        continuation = nil
        try? handle?.close()
        handle = nil
        lock.unlock()

        session?.invalidateAndCancel()
        session = nil
        pending?.resume(with: result)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            completionHandler(.cancel)
            finish(.failure(SceneLiveTranscriptionError.audioSourceUnavailable))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !isFinished, let handle else {
            lock.unlock()
            return
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            lock.unlock()
            finish(.failure(error))
            return
        }
        written += data.count
        let reachedBudget = written >= byteBudget
        let total = written
        lock.unlock()

        if reachedBudget { finish(.success(total)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let total = written
        lock.unlock()
        if let error, total == 0 {
            finish(.failure(error))
        } else {
            finish(.success(total))
        }
    }
}
#endif
