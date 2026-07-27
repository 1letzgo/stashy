//
//  IntelligentCropAnalyzer.swift
//  stashy
//
//  Vision-based genital / primary-sex-organ focus for portrait immersive crop (Markers).

#if !os(tvOS)
import Foundation
import UIKit
import Vision

/// Horizontal + vertical focus (0…1) for smart landscape→portrait crop.
/// Targets pelvis / primary sex organs — not faces.
enum IntelligentCropAnalyzer {
    struct FocusPoint: Equatable {
        var x: CGFloat
        var y: CGFloat

        static let center = FocusPoint(x: 0.5, y: 0.38)
    }

    private static let cache = NSCache<NSString, NSValue>()

    /// Pelvis / genital band (Vision coords: origin bottom-left, y up).
    private static let genitalYMin: CGFloat = 0.12
    private static let genitalYMax: CGFloat = 0.48

    static func focus(for image: UIImage, cacheKey: String) async -> FocusPoint {
        if let cached = cache.object(forKey: cacheKey as NSString) {
            let point = cached.cgPointValue
            return FocusPoint(x: point.x, y: point.y)
        }
        let value = await analyze(image)
        cache.setObject(NSValue(cgPoint: CGPoint(x: value.x, y: value.y)), forKey: cacheKey as NSString)
        return value
    }

    static func focus(fromImageURL url: URL, cacheKey: String) async -> FocusPoint {
        if let cached = cache.object(forKey: cacheKey as NSString) {
            let point = cached.cgPointValue
            return FocusPoint(x: point.x, y: point.y)
        }
        guard let image = await loadUIImage(url: url) else { return .center }
        return await focus(for: image, cacheKey: cacheKey)
    }

    /// Legacy X-only API.
    static func focusX(fromImageURL url: URL, cacheKey: String) async -> CGFloat {
        await focus(fromImageURL: url, cacheKey: cacheKey).x
    }

    private static func loadUIImage(url: URL) async -> UIImage? {
        if let cached = await ImageCache.shared.loadObject(forKey: url as NSURL) {
            return cached
        }
        var request = authenticatedStashRequest(for: url)
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let image = UIImage(data: data) else { return nil }
            ImageCache.shared.setData(data, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
    }

    private static func analyze(_ image: UIImage) async -> FocusPoint {
        guard let cgImage = image.cgImage else { return .center }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        // 1) Pose: hip midpoint / root ≈ primary sex organs
        if let p = try? await genitalPoseFocus(handler: handler) {
            return p
        }
        // 2) Person mask centroid in genital band
        if let p = try? await segmentationGenitalFocus(handler: handler) {
            return p
        }
        // 3) Objectness saliency in genital band
        if let p = try? await saliencyFocus(handler: handler, attentionBased: false) {
            return p
        }
        if let p = try? await saliencyFocus(handler: handler, attentionBased: true) {
            return p
        }
        return .center
    }

    /// Prefer left/right hip midpoint (genital X), root as fallback. Never face/neck.
    private static func genitalPoseFocus(handler: VNImageRequestHandler) async throws -> FocusPoint? {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectHumanBodyPoseRequest { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = req.results as? [VNHumanBodyPoseObservation], !observations.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                var points: [FocusPoint] = []
                for obs in observations where obs.confidence > 0.12 {
                    guard let genital = genitalPoint(from: obs) else { continue }
                    points.append(genital)
                }

                guard !points.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                // Multiple bodies → midpoint (interaction / penetration zone)
                let x = points.map(\.x).reduce(0, +) / CGFloat(points.count)
                let y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
                continuation.resume(returning: FocusPoint(x: clamp01(x), y: clamp01(y)))
            }
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Estimate primary sex-organ location from hips + root.
    private static func genitalPoint(from obs: VNHumanBodyPoseObservation) -> FocusPoint? {
        let leftHip = try? obs.recognizedPoint(.leftHip)
        let rightHip = try? obs.recognizedPoint(.rightHip)
        let root = try? obs.recognizedPoint(.root)
        let leftKnee = try? obs.recognizedPoint(.leftKnee)
        let rightKnee = try? obs.recognizedPoint(.rightKnee)

        var xs: [(CGFloat, CGFloat)] = [] // (value, weight)
        var ys: [(CGFloat, CGFloat)] = []

        if let l = leftHip, let r = rightHip, l.confidence > 0.1, r.confidence > 0.1 {
            // Mid-hip = strongest proxy for genitals
            let midX = (l.location.x + r.location.x) / 2
            let midY = (l.location.y + r.location.y) / 2
            // Slightly below hip line toward knees (genital offset)
            var genitalY = midY
            if let lk = leftKnee, let rk = rightKnee, lk.confidence > 0.08, rk.confidence > 0.08 {
                let kneeY = (lk.location.y + rk.location.y) / 2
                genitalY = midY * 0.65 + kneeY * 0.35
            } else {
                genitalY = midY - 0.04
            }
            xs.append((midX, 2.0 * CGFloat(min(l.confidence, r.confidence))))
            ys.append((genitalY, 2.0))
        }

        if let root, root.confidence > 0.1 {
            xs.append((root.location.x, 1.6 * CGFloat(root.confidence)))
            ys.append((root.location.y - 0.02, 1.6))
        }

        // Single hip fallback
        if xs.isEmpty, let l = leftHip, l.confidence > 0.15 {
            xs.append((l.location.x, 1.0))
            ys.append((l.location.y - 0.04, 1.0))
        }
        if xs.isEmpty, let r = rightHip, r.confidence > 0.15 {
            xs.append((r.location.x, 1.0))
            ys.append((r.location.y - 0.04, 1.0))
        }

        guard !xs.isEmpty else { return nil }

        let totalWX = xs.reduce(CGFloat(0)) { $0 + $1.1 }
        let totalWY = ys.reduce(CGFloat(0)) { $0 + $1.1 }
        guard totalWX > 0, totalWY > 0 else { return nil }
        let x = xs.reduce(CGFloat(0)) { $0 + $1.0 * $1.1 } / totalWX
        let y = ys.reduce(CGFloat(0)) { $0 + $1.0 * $1.1 } / totalWY

        // Reject if we somehow landed in face territory
        guard y <= genitalYMax + 0.08 else { return nil }
        return FocusPoint(x: clamp01(x), y: clamp01(max(y, genitalYMin)))
    }

    private static func segmentationGenitalFocus(handler: VNImageRequestHandler) async throws -> FocusPoint? {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNGeneratePersonSegmentationRequest { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observation = req.results?.first as? VNPixelBufferObservation else {
                    continuation.resume(returning: nil)
                    return
                }
                let point = maskCentroid(in: observation.pixelBuffer, yMin: genitalYMin, yMax: genitalYMax)
                continuation.resume(returning: point.map { FocusPoint(x: clamp01($0.x), y: clamp01($0.y)) })
            }
            request.qualityLevel = .balanced
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func saliencyFocus(handler: VNImageRequestHandler, attentionBased: Bool) async throws -> FocusPoint? {
        try await withCheckedThrowingContinuation { continuation in
            let completion: VNRequestCompletionHandler = { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observation = req.results?.first as? VNSaliencyImageObservation else {
                    continuation.resume(returning: nil)
                    return
                }
                if let peak = peakPoint(in: observation.pixelBuffer, yMin: genitalYMin, yMax: genitalYMax) {
                    continuation.resume(returning: FocusPoint(x: clamp01(peak.x), y: clamp01(peak.y)))
                    return
                }
                let objects = (observation.salientObjects ?? []).filter {
                    $0.boundingBox.midY >= genitalYMin && $0.boundingBox.midY <= genitalYMax
                }
                guard !objects.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let weighted = objects.reduce(into: (sx: CGFloat(0), sy: CGFloat(0), w: CGFloat(0))) { acc, obj in
                    let weight = CGFloat(obj.confidence) * obj.boundingBox.width * obj.boundingBox.height
                    acc.sx += obj.boundingBox.midX * weight
                    acc.sy += obj.boundingBox.midY * weight
                    acc.w += weight
                }
                guard weighted.w > 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: FocusPoint(
                    x: clamp01(weighted.sx / weighted.w),
                    y: clamp01(weighted.sy / weighted.w)
                ))
            }
            let request: VNRequest = attentionBased
                ? VNGenerateAttentionBasedSaliencyImageRequest(completionHandler: completion)
                : VNGenerateObjectnessBasedSaliencyImageRequest(completionHandler: completion)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func peakPoint(in pixelBuffer: CVPixelBuffer, yMin: CGFloat, yMax: CGFloat) -> CGPoint? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0,
              let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let rowStart = max(0, Int((1.0 - yMax) * CGFloat(height)))
        let rowEnd = min(height, Int((1.0 - yMin) * CGFloat(height)))
        guard rowStart < rowEnd else { return nil }

        var best: Float = -Float.greatestFiniteMagnitude
        var bestX = width / 2
        var bestY = (rowStart + rowEnd) / 2
        var found = false

        if format == kCVPixelFormatType_OneComponent32Float {
            for y in rowStart..<rowEnd {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
                for x in 0..<width {
                    let v = row[x]
                    if v > best {
                        best = v
                        bestX = x
                        bestY = y
                        found = true
                    }
                }
            }
        } else {
            for y in rowStart..<rowEnd {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    let v = Float(row[x])
                    if v > best {
                        best = v
                        bestX = x
                        bestY = y
                        found = true
                    }
                }
            }
        }

        guard found, best > 0 else { return nil }
        // Buffer y=0 is top → Vision y from bottom
        let visionY = 1.0 - (CGFloat(bestY) / CGFloat(max(height - 1, 1)))
        let visionX = CGFloat(bestX) / CGFloat(max(width - 1, 1))
        return CGPoint(x: visionX, y: visionY)
    }

    private static func maskCentroid(in pixelBuffer: CVPixelBuffer, yMin: CGFloat, yMax: CGFloat) -> CGPoint? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0,
              let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let rowStart = max(0, Int((1.0 - yMax) * CGFloat(height)))
        let rowEnd = min(height, Int((1.0 - yMin) * CGFloat(height)))
        guard rowStart < rowEnd else { return nil }

        var sumX: Double = 0
        var sumY: Double = 0
        var count: Double = 0
        for y in rowStart..<rowEnd {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                if row[x] > 40 {
                    sumX += Double(x)
                    sumY += Double(y)
                    count += 1
                }
            }
        }
        guard count > 50 else { return nil }
        let visionX = CGFloat(sumX / count) / CGFloat(max(width - 1, 1))
        let visionY = 1.0 - (CGFloat(sumY / count) / CGFloat(max(height - 1, 1)))
        return CGPoint(x: visionX, y: visionY)
    }

    private static func clamp01(_ v: CGFloat) -> CGFloat {
        min(1, max(0, v))
    }
}
#endif
