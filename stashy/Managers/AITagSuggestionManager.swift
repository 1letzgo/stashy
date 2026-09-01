//
//  AITagSuggestionManager.swift
//  stashy
//
//  On-device tag suggestions ("AI Tags", stashy+).
//
//  Two Vision signals, no network model involved:
//  1. Feature-print kNN against a locally built index of the library's *already tagged*
//     images. This is what produces domain-specific tags — a generic classifier knows
//     nothing about a Stash tag vocabulary, but "looks like these 12 tagged images" does.
//  2. VNClassifyImageRequest labels, matched by name against the server's tag list.
//     Supplementary only, and always weaker than the kNN vote.
//
//  Everything runs on device; nothing leaves the phone. The index lives in Application
//  Support, scoped per server ID, and is discarded when the server changes.
//

#if !os(tvOS)

import Foundation
import Combine
import SwiftUI
import Vision
import AVFoundation
import ImageIO

// MARK: - Model

struct AITagSuggestion: Identifiable, Equatable {
    enum Source: String, Codable {
        case performer    // tag frequency across the performer's own content
        case studio       // tag frequency across the studio's own content
        case similar      // feature-print neighbours
        case classifier   // Vision image classification
    }

    let tag: Tag
    let confidence: Double
    let source: Source

    var id: String { tag.id }
}

/// How likely each tag is on one performer's content. Images and scenes are counted
/// separately and merged by strongest rate — a performer's scenes usually hold the
/// richer vocabulary, and a tag common there must not be diluted by an image sample
/// that never uses it.
struct PerformerTagStats {
    let probabilities: [String: Double]
    /// How many sampled items carry the tag — the ranking signal the user actually asked
    /// for ("this performer uses abc a lot"). Kept separate from the probability, which
    /// only decides auto-accept.
    let counts: [String: Int]
    let tags: [String: Tag]
    let sampleSize: Int
}

/// One indexed library image: normalized feature vector + the tags it carries.
private struct AITagIndexEntry: Codable {
    let imageId: String
    let tagIds: [String]
    /// L2-normalized feature print. Persisted as base64-packed Float32 — a JSON array of
    /// 768 floats costs ~3x the bytes, and these files now stay on the device for good.
    let vector: [Float]

    enum CodingKeys: String, CodingKey {
        case imageId, tagIds, vector
    }

    init(imageId: String, tagIds: [String], vector: [Float]) {
        self.imageId = imageId
        self.tagIds = tagIds
        self.vector = vector
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imageId = try container.decode(String.self, forKey: .imageId)
        tagIds = try container.decode([String].self, forKey: .tagIds)
        let packed = try container.decode(Data.self, forKey: .vector)
        vector = packed.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(imageId, forKey: .imageId)
        try container.encode(tagIds, forKey: .tagIds)
        try container.encode(vector.withUnsafeBufferPointer { Data(buffer: $0) }, forKey: .vector)
    }
}

private struct AITagIndexFile: Codable {
    var version: Int
    var serverId: String
    var builtAt: Date
    var entries: [AITagIndexEntry]
    var tags: [Tag]
}

// MARK: - Manager

@MainActor
final class AITagSuggestionManager: ObservableObject {

    static let shared = AITagSuggestionManager()

    enum IndexState: Equatable {
        case idle
        case loading
        case building(processed: Int, total: Int)
        case ready(entries: Int)
        case failed(String)
    }

    // MARK: Settings (kill-switch first — default OFF)

    /// Master kill switch. While false nothing here touches Reels or the fullscreen viewer.
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            if !isEnabled { cancelWork() }
        }
    }

    /// Minimum confidence a suggestion must reach to be shown (0…1).
    @Published var minConfidence: Double {
        didSet { UserDefaults.standard.set(minConfidence, forKey: Keys.minConfidence) }
    }

    /// How many suggestions the chip row shows at most.
    @Published var maxSuggestions: Int {
        didSet { UserDefaults.standard.set(maxSuggestions, forKey: Keys.maxSuggestions) }
    }

    /// Upper bound on indexed library images — keeps build time and memory predictable.
    @Published var indexLimit: Int {
        didSet { UserDefaults.standard.set(indexLimit, forKey: Keys.indexLimit) }
    }

    /// Rank tags by how often this item's performers already carry them. The cheap,
    /// strong signal — on by default.
    @Published var usePerformerStats: Bool {
        didSet { UserDefaults.standard.set(usePerformerStats, forKey: Keys.usePerformerStats) }
    }

    /// Same census over the item's studio.
    @Published var useStudioStats: Bool {
        didSet { UserDefaults.standard.set(useStudioStats, forKey: Keys.useStudioStats) }
    }

    /// Analyse the picture itself with Vision on top of the library statistics.
    /// Off by default: it needs an index and is the slower, weaker half of the signal.
    @Published var useVision: Bool {
        didSet {
            UserDefaults.standard.set(useVision, forKey: Keys.useVision)
            if useVision { Task { await loadIndexIfNeeded() } }
        }
    }

    /// Frames sampled from a clip (video or animation). Stills always use one frame.
    @Published var framesPerClip: Int {
        didSet { UserDefaults.standard.set(framesPerClip, forKey: Keys.framesPerClip) }
    }

    /// Apply high-confidence suggestions without a tap. Writes to the server, so it is
    /// off unless the user turns it on.
    @Published var autoAccept: Bool {
        didSet { UserDefaults.standard.set(autoAccept, forKey: Keys.autoAccept) }
    }

    /// Confidence a suggestion must reach before auto-accept applies it (0…1).
    @Published var autoAcceptThreshold: Double {
        didSet { UserDefaults.standard.set(autoAcceptThreshold, forKey: Keys.autoAcceptThreshold) }
    }

    // MARK: Published state

    @Published private(set) var indexState: IndexState = .idle
    @Published private(set) var lastBuiltAt: Date?

    /// Available and allowed to run right now.
    var isActive: Bool { isEnabled && StashyPlusManager.isUnlockedNow }

    var indexedCount: Int { entries.count }

    var indexProgress: Double {
        if case .building(let processed, let total) = indexState, total > 0 {
            return min(1, Double(processed) / Double(total))
        }
        return 0
    }

    // MARK: Private state

    private var entries: [AITagIndexEntry] = []
    private var tagsById: [String: Tag] = [:]
    private var tagsByNormalizedName: [String: Tag] = [:]
    private var buildTask: Task<Void, Never>?
    private var didLoadFromDisk = false
    private var serverObserver: NSObjectProtocol?

    /// Cached suggestions per image id, so re-opening an item does not re-run Vision.
    private var suggestionCache: [String: [AITagSuggestion]] = [:]

    /// Tag census per performer, plus the in-flight fetch so a feed that shows three
    /// clips of the same performer asks the server once.
    private var performerStatsCache: [String: (stats: PerformerTagStats, fetchedAt: Date)] = [:]
    private var performerStatsTasks: [String: Task<PerformerTagStats?, Never>] = [:]

    private enum Keys {
        static let enabled = "ai_tags_enabled"
        static let minConfidence = "ai_tags_min_confidence"
        static let maxSuggestions = "ai_tags_max_suggestions"
        static let indexLimit = "ai_tags_index_limit"
        static let framesPerClip = "ai_tags_frames_per_clip"
        static let useVision = "ai_tags_use_vision"
        static let usePerformerStats = "ai_tags_use_performer_stats"
        static let useStudioStats = "ai_tags_use_studio_stats"
        static let tuningVersion = "ai_tags_tuning_version"
        static let autoAccept = "ai_tags_auto_accept"
        static let autoAcceptThreshold = "ai_tags_auto_accept_threshold"
    }

    private static let performerStatsTTL: TimeInterval = 1800
    private static let performerSampleSize = 200
    /// Laplace-style damping: 1 of 1 tagged image is not a certainty. Kept small —
    /// at 3 it pushed genuinely common tags below the confidence floor.
    private static let priorSmoothing = 1.0
    private static let neighbourCount = 15
    private static let minNeighbourSimilarity: Float = 0.55
    private static let indexVersion = 3

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Keys.enabled)
        minConfidence = defaults.object(forKey: Keys.minConfidence) as? Double ?? 0.12
        maxSuggestions = defaults.object(forKey: Keys.maxSuggestions) as? Int ?? 8
        indexLimit = defaults.object(forKey: Keys.indexLimit) as? Int ?? 1500
        framesPerClip = defaults.object(forKey: Keys.framesPerClip) as? Int ?? 6
        useVision = defaults.bool(forKey: Keys.useVision)
        usePerformerStats = defaults.object(forKey: Keys.usePerformerStats) as? Bool ?? true
        useStudioStats = defaults.object(forKey: Keys.useStudioStats) as? Bool ?? true
        autoAccept = defaults.bool(forKey: Keys.autoAccept)
        autoAcceptThreshold = defaults.object(forKey: Keys.autoAcceptThreshold) as? Double ?? 0.8

        // The first defaults were tuned before scenes joined the census and left users
        // with three suggestions. Re-seed those two values once.
        if defaults.integer(forKey: Keys.tuningVersion) < 2 {
            minConfidence = 0.12
            maxSuggestions = max(maxSuggestions, 8)
            defaults.set(0.12, forKey: Keys.minConfidence)
            defaults.set(maxSuggestions, forKey: Keys.maxSuggestions)
            defaults.set(2, forKey: Keys.tuningVersion)
        }

        serverObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleServerChange() }
        }
    }

    deinit {
        if let serverObserver {
            NotificationCenter.default.removeObserver(serverObserver)
        }
    }

    // MARK: - Lifecycle

    /// Indexes are kept on the device permanently, one file per server. Switching
    /// servers swaps to that server's index instead of throwing anything away —
    /// tag IDs are server-specific, so a single shared index would map suggestions
    /// onto the wrong tags.
    private func handleServerChange() {
        cancelWork()
        entries = []
        tagsById = [:]
        tagsByNormalizedName = [:]
        suggestionCache = [:]
        performerStatsCache = [:]
        performerStatsTasks.values.forEach { $0.cancel() }
        performerStatsTasks = [:]
        didLoadFromDisk = false
        lastBuiltAt = nil
        indexState = .idle
        Task { await loadIndexIfNeeded() }
    }

    func cancelWork() {
        buildTask?.cancel()
        buildTask = nil
        if case .building = indexState {
            indexState = entries.isEmpty ? .idle : .ready(entries: entries.count)
        }
    }

    /// Loads a persisted index for the active server, if there is one. Cheap and idempotent.
    func loadIndexIfNeeded() async {
        guard !didLoadFromDisk, isActive else { return }
        guard let url = Self.indexURL() else { return }
        didLoadFromDisk = true
        indexState = .loading

        let loaded: AITagIndexFile? = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(AITagIndexFile.self, from: data)
        }.value

        guard let loaded, loaded.version == Self.indexVersion else {
            // A file from an older layout can never be read again — drop it rather than
            // leaving megabytes of dead index on the device.
            try? FileManager.default.removeItem(at: url)
            indexState = .idle
            return
        }
        apply(entries: loaded.entries, tags: loaded.tags, builtAt: loaded.builtAt)
    }

    private func apply(entries newEntries: [AITagIndexEntry], tags: [Tag], builtAt: Date) {
        entries = newEntries
        tagsById = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        tagsByNormalizedName = Dictionary(
            tags.map { (Self.normalize($0.name), $0) },
            uniquingKeysWith: { a, _ in a }
        )
        lastBuiltAt = builtAt
        suggestionCache = [:]
        indexState = entries.isEmpty ? .idle : .ready(entries: entries.count)
    }

    // MARK: - Index building

    func rebuildIndex() {
        guard isActive else { return }
        guard buildTask == nil else { return }
        buildTask = Task { [weak self] in
            await self?.performIndexBuild()
            await MainActor.run { self?.buildTask = nil }
        }
    }

    func deleteIndex() {
        cancelWork()
        entries = []
        suggestionCache = [:]
        lastBuiltAt = nil
        indexState = .idle
        if let url = Self.indexURL() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func performIndexBuild() async {
        indexState = .building(processed: 0, total: 0)

        let tags: [Tag]
        let images: [StashImage]
        do {
            tags = try await fetchAllTags()
            images = try await fetchTaggedImages(limit: indexLimit)
        } catch {
            AppLog.error("AITags: index build failed — \(error.localizedDescription)")
            indexState = .failed("Could not load library data")
            return
        }

        guard !images.isEmpty else {
            indexState = .failed("No tagged images found to learn from")
            return
        }

        indexState = .building(processed: 0, total: images.count)

        var built: [AITagIndexEntry] = []
        built.reserveCapacity(images.count)
        var processed = 0

        // Four in flight: enough to saturate a LAN Stash, low enough to keep memory flat.
        await withTaskGroup(of: AITagIndexEntry?.self) { group in
            var iterator = images.makeIterator()
            var inFlight = 0

            func addNext() {
                guard let image = iterator.next() else { return }
                inFlight += 1
                group.addTask(priority: .utility) {
                    await Self.makeEntry(for: image)
                }
            }

            for _ in 0..<4 { addNext() }

            while inFlight > 0, let result = await group.next() {
                inFlight -= 1
                processed += 1
                if let result { built.append(result) }
                if Task.isCancelled { break }
                if processed % 10 == 0 || processed == images.count {
                    indexState = .building(processed: processed, total: images.count)
                }
                addNext()
            }
            group.cancelAll()
        }

        guard !Task.isCancelled else {
            indexState = entries.isEmpty ? .idle : .ready(entries: entries.count)
            return
        }

        let now = Date()
        apply(entries: built, tags: tags, builtAt: now)
        persist(entries: built, tags: tags, builtAt: now)
        AppLog.debug("AITags: index built with \(built.count) entries")
    }

    private func persist(entries: [AITagIndexEntry], tags: [Tag], builtAt: Date) {
        guard let url = Self.indexURL(), let serverId = Self.indexKey() else { return }
        let file = AITagIndexFile(
            version: Self.indexVersion,
            serverId: serverId,
            builtAt: builtAt,
            entries: entries,
            tags: tags
        )
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try JSONEncoder().encode(file)
                try data.write(to: url, options: .atomic)
            } catch {
                AppLog.error("AITags: could not persist index — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Suggestions

    /// Cached suggestions for an image, if analysis already ran in this session.
    /// Tags the item meanwhile carries are dropped — a tag is never suggested twice.
    func cachedSuggestions(for image: StashImage) -> [AITagSuggestion]? {
        guard let cached = suggestionCache[image.id] else { return nil }
        let existing = Set((image.tags ?? []).map(\.id))
        return cached.filter { !existing.contains($0.tag.id) }
    }

    /// Analyses one image and returns ranked suggestions, excluding tags it already has.
    @discardableResult
    func suggestions(for image: StashImage, forceRefresh: Bool = false) async -> [AITagSuggestion] {
        guard isActive else { return [] }
        if !forceRefresh, let cached = cachedSuggestions(for: image) { return cached }

        let existing = Set((image.tags ?? []).map(\.id))
        var scores: [String: (score: Double, source: AITagSuggestion.Source)] = [:]
        var vocabulary: [String: Tag] = [:]
        // Tags the statistics vouch for. They are ranked, not filtered by confidence:
        // "this performer uses abc a lot" is a ranking question, and a hard probability
        // floor was cutting the list down to a handful.
        var statsBacked: Set<String> = []

        // 1. Library statistics — what this item's performers and studio are usually
        //    tagged with. The strong signal: no model, no index, no pixels.
        let (prior, priorTags) = await libraryPrior(for: image)
        vocabulary.merge(priorTags) { a, _ in a }
        for (tagId, entry) in prior {
            scores[tagId] = (entry.probability, entry.source)
            statsBacked.insert(tagId)
        }

        // 2. Optional: look at the picture itself. Statistics answer the same for every
        //    item a performer is in — only the pixels can tell one clip from the next.
        //    Frames are extracted once and shared by both picture-based signals.
        if useVision {
            // A clip is a moving thing — one thumbnail can miss the position, the second
            // performer, or the whole second half. Sample across its duration instead.
            let frameBudget = image.isVideo || image.isAnimated ? max(1, framesPerClip) : 1
            let frames = await Self.frames(of: image, frameCount: frameBudget)

            if !frames.isEmpty {
                await loadIndexIfNeeded()
                if !entries.isEmpty {
                    vocabulary.merge(tagsById) { a, _ in a }
                    for (tagId, value) in await visionScores(frames: frames) {
                        if let current = scores[tagId] {
                            scores[tagId] = (Self.combine(current.score, value.score), current.source)
                        } else {
                            scores[tagId] = value
                        }
                    }
                }
            }
        }

        let result = scores
            .filter { tagId, value in
                guard !existing.contains(tagId) else { return false }
                // The confidence floor guards the noisy half only. A statistically
                // backed tag has already earned its place by showing up repeatedly.
                return statsBacked.contains(tagId) || value.score >= minConfidence
            }
            .compactMap { (tagId, value) -> AITagSuggestion? in
                guard let tag = vocabulary[tagId] else { return nil }
                return AITagSuggestion(tag: tag, confidence: min(1, value.score), source: value.source)
            }
            .sorted { $0.confidence > $1.confidence }
            .prefix(max(1, maxSuggestions))

        let suggestions = Array(result)
        suggestionCache[image.id] = suggestions
        return suggestions
    }

    private struct PriorEntry {
        var probability: Double
        var source: AITagSuggestion.Source
    }

    /// How two independent signals for the same tag are folded into one score.
    /// The stronger one carries, agreement adds a modest bonus, and the result can
    /// never exceed certainty. Used for every pairing — performer vs. studio,
    /// performer vs. performer, statistics vs. Vision — so the ranking stays coherent.
    private static func combine(_ lhs: Double, _ rhs: Double) -> Double {
        min(1, max(lhs, rhs) + 0.15 * min(lhs, rhs))
    }

    /// Per-tag likelihood from the item's own metadata: its performers, and its studio.
    /// Several sources: the strongest claim wins — a tag typical for one performer is
    /// still a reasonable guess for a clip they share.
    private func libraryPrior(for image: StashImage) async -> ([String: PriorEntry], [String: Tag]) {
        var result: [String: PriorEntry] = [:]
        var vocabulary: [String: Tag] = [:]

        func merge(_ stats: PerformerTagStats, source: AITagSuggestion.Source, weight: Double) {
            vocabulary.merge(stats.tags) { a, _ in a }
            // One-off tags are noise, not a habit — but only once the sample is big
            // enough for "once" to mean anything.
            let minimumCount = stats.sampleSize >= 8 ? 2 : 1
            for (tagId, probability) in stats.probabilities {
                guard (stats.counts[tagId] ?? 0) >= minimumCount else { continue }
                let scaled = probability * weight
                guard let current = result[tagId] else {
                    result[tagId] = PriorEntry(probability: scaled, source: source)
                    continue
                }
                result[tagId] = PriorEntry(
                    probability: Self.combine(current.probability, scaled),
                    // Attribute the tag to whichever source made the stronger claim.
                    source: scaled > current.probability ? source : current.source
                )
            }
        }

        if usePerformerStats {
            for performerId in (image.performers ?? []).map(\.id) {
                guard let stats = await entityStats(scope: .performer, id: performerId),
                      stats.sampleSize > 0 else { continue }
                merge(stats, source: .performer, weight: 1.0)
            }
        }

        if useStudioStats, let studioId = image.studio?.id {
            guard let stats = await entityStats(scope: .studio, id: studioId), stats.sampleSize > 0 else {
                return (result, vocabulary)
            }
            // A studio's habits are real but less specific than a performer's.
            merge(stats, source: .studio, weight: 0.8)
        }

        return (result, vocabulary)
    }

    /// Vision half of the score: feature-print neighbours plus classifier labels.
    private func visionScores(
        frames: [CGImage]
    ) async -> [String: (score: Double, source: AITagSuggestion.Source)] {
        let analyses = await Self.analyzeFrames(frames)
        guard !analyses.isEmpty else { return [:] }

        var scores: [String: (score: Double, source: AITagSuggestion.Source)] = [:]

        var perFrameVotes: [[String: Double]] = []
        for analysis in analyses {
            guard let vector = analysis.vector else { continue }
            perFrameVotes.append(await Self.neighbourVotes(for: vector, in: entries))
        }

        if !perFrameVotes.isEmpty {
            var sums: [String: Double] = [:]
            var peaks: [String: Double] = [:]
            for votes in perFrameVotes {
                for (tagId, vote) in votes {
                    sums[tagId, default: 0] += vote
                    peaks[tagId] = max(peaks[tagId] ?? 0, vote)
                }
            }
            let frameCount = Double(perFrameVotes.count)
            for (tagId, sum) in sums {
                // Blend: a tag carried by every frame should win, but one that only shows
                // up in the two frames where the act is visible must not be averaged away.
                let mean = sum / frameCount
                let peak = peaks[tagId] ?? 0
                scores[tagId] = (0.4 * mean + 0.6 * peak, .similar)
            }
        }

        // Classifier labels matched against the server's own tag names — strongest frame wins.
        for analysis in analyses {
            for label in analysis.labels {
                guard let tag = tagsByNormalizedName[Self.normalize(label.identifier)] else { continue }
                // Deliberately capped below the kNN vote: a generic label is the weaker signal.
                let score = Double(label.confidence) * 0.8
                if let current = scores[tag.id] {
                    if score > current.score { scores[tag.id] = (score, .classifier) }
                } else {
                    scores[tag.id] = (score, .classifier)
                }
            }
        }
        return scores
    }

    /// Weighted tag votes from the k nearest indexed images. Runs off the main actor —
    /// a full-library scan is ~1M float ops and has no business blocking the feed.
    nonisolated private static func neighbourVotes(
        for vector: [Float],
        in entries: [AITagIndexEntry]
    ) async -> [String: Double] {
        await Task.detached(priority: .userInitiated) {
        var best: [(similarity: Float, tagIds: [String])] = []
        best.reserveCapacity(Self.neighbourCount)

        for entry in entries {
            let similarity = Self.dot(vector, entry.vector)
            guard similarity >= Self.minNeighbourSimilarity else { continue }
            if best.count < Self.neighbourCount {
                best.append((similarity, entry.tagIds))
                best.sort { $0.similarity > $1.similarity }
            } else if let last = best.last, similarity > last.similarity {
                best.removeLast()
                best.append((similarity, entry.tagIds))
                best.sort { $0.similarity > $1.similarity }
            }
        }

        guard !best.isEmpty else { return [:] }

        // Weight above the similarity floor so a barely-similar neighbour barely counts.
        let weights = best.map { Double($0.similarity - Self.minNeighbourSimilarity) + 0.05 }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return [:] }

        var votes: [String: Double] = [:]
        for (index, neighbour) in best.enumerated() {
            let weight = weights[index] / totalWeight
            for tagId in Set(neighbour.tagIds) {
                votes[tagId, default: 0] += weight
            }
        }
        return votes
        }.value
    }

    // MARK: - Accepting a suggestion

    /// Adds the tag to the image on the server. Returns the image's new tag list on success.
    func accept(_ suggestion: AITagSuggestion, on image: StashImage) async -> [Tag]? {
        await accept([suggestion], on: image)
    }

    /// Adds several tags in one mutation — auto-accept would otherwise fire a request per tag.
    func accept(_ accepted: [AITagSuggestion], on image: StashImage) async -> [Tag]? {
        let existing = image.tags ?? []
        let existingIds = Set(existing.map(\.id))
        let additions = accepted
            .map(\.tag)
            .filter { !existingIds.contains($0.id) }
        guard !additions.isEmpty else { return existing }
        let newTags = existing + additions

        let mutation = GraphQLQueries.imageUpdateTagsMutation
        let variables: [String: Any] = [
            "input": ["id": image.id, "tag_ids": newTags.map(\.id)]
        ]

        do {
            let response: ImageUpdateResponse = try await GraphQLClient.shared.execute(
                query: mutation,
                variables: variables
            )
            guard response.data?.imageUpdate?.id != nil else { return nil }
        } catch {
            AppLog.error("AITags: imageUpdate failed — \(error.localizedDescription)")
            return nil
        }

        // Drop the accepted tags from the cached suggestions so their chips disappear.
        let acceptedIds = Set(additions.map(\.id))
        if var cached = suggestionCache[image.id] {
            cached.removeAll { acceptedIds.contains($0.tag.id) }
            suggestionCache[image.id] = cached
        }

        NotificationCenter.default.post(
            name: NSNotification.Name("ImageTagsUpdated"),
            object: nil,
            userInfo: ["imageId": image.id, "tags": newTags]
        )
        return newTags
    }

    // MARK: - GraphQL

    private struct TagsResponse: Decodable {
        struct DataBlock: Decodable {
            struct FindTags: Decodable { let tags: [Tag] }
            let findTags: FindTags
        }
        let data: DataBlock?
    }

    private struct ImageUpdateResponse: Decodable {
        struct DataBlock: Decodable {
            struct Updated: Decodable { let id: String }
            let imageUpdate: Updated?
        }
        let data: DataBlock?
    }

    private struct ImagesResponse: Decodable {
        struct DataBlock: Decodable {
            struct FindImages: Decodable {
                let count: Int
                let images: [StashImage]
            }
            let findImages: FindImages
        }
        let data: DataBlock?
    }

    private struct TaggedItem: Decodable {
        let id: String
        let tags: [Tag]?
    }

    private struct PerformerImagesResponse: Decodable {
        struct DataBlock: Decodable {
            struct FindImages: Decodable {
                let count: Int
                let images: [TaggedItem]
            }
            let findImages: FindImages
        }
        let data: DataBlock?
    }

    private struct PerformerScenesResponse: Decodable {
        struct DataBlock: Decodable {
            struct FindScenes: Decodable {
                let count: Int
                let scenes: [TaggedItem]
            }
            let findScenes: FindScenes
        }
        let data: DataBlock?
    }

    /// What a tag census is taken over. Studios use the same queries with a different
    /// filter key.
    enum StatsScope: String {
        case performer = "performers"
        case studio = "studios"
    }

    private func entityStats(scope: StatsScope, id: String) async -> PerformerTagStats? {
        let key = "\(scope.rawValue):\(id)"
        if let cached = performerStatsCache[key],
           Date().timeIntervalSince(cached.fetchedAt) < Self.performerStatsTTL {
            return cached.stats
        }
        if let running = performerStatsTasks[key] {
            return await running.value
        }

        let task = Task { [weak self] () -> PerformerTagStats? in
            await self?.fetchEntityStats(scope: scope, id: id)
        }
        performerStatsTasks[key] = task
        let stats = await task.value
        performerStatsTasks[key] = nil
        if let stats {
            performerStatsCache[key] = (stats, Date())
        }
        return stats
    }

    private func fetchEntityStats(scope: StatsScope, id: String) async -> PerformerTagStats? {
        let filter: [String: Any] = [
            "page": 1,
            "per_page": Self.performerSampleSize,
            "sort": "updated_at",
            "direction": "DESC"
        ]
        let itemFilter: [String: Any] = [
            scope.rawValue: ["value": [id], "modifier": "INCLUDES"],
            "tag_count": ["value": 0, "modifier": "GREATER_THAN"]
        ]

        async let imagesTask: [TaggedItem] = {
            do {
                let response: PerformerImagesResponse = try await GraphQLClient.shared.execute(
                    query: GraphQLQueries.performerImageTagsQuery,
                    variables: ["filter": filter, "image_filter": itemFilter]
                )
                return response.data?.findImages.images ?? []
            } catch {
                AppLog.error("AITags: \(scope.rawValue) image tags failed — \(error.localizedDescription)")
                return []
            }
        }()

        async let scenesTask: [TaggedItem] = {
            do {
                let response: PerformerScenesResponse = try await GraphQLClient.shared.execute(
                    query: GraphQLQueries.performerSceneTagsQuery,
                    variables: ["filter": filter, "scene_filter": itemFilter]
                )
                return response.data?.findScenes.scenes ?? []
            } catch {
                AppLog.error("AITags: \(scope.rawValue) scene tags failed — \(error.localizedDescription)")
                return []
            }
        }()

        let images = await imagesTask
        let scenes = await scenesTask
        guard !images.isEmpty || !scenes.isEmpty else { return nil }

        var probabilities: [String: Double] = [:]
        var totals: [String: Int] = [:]
        var tags: [String: Tag] = [:]

        func absorb(_ items: [TaggedItem]) {
            guard !items.isEmpty else { return }
            var counts: [String: Int] = [:]
            for item in items {
                for tag in item.tags ?? [] {
                    counts[tag.id, default: 0] += 1
                    tags[tag.id] = tag
                }
            }
            let denominator = Double(items.count) + Self.priorSmoothing
            for (tagId, count) in counts {
                let rate = Double(count) / denominator
                probabilities[tagId] = max(probabilities[tagId] ?? 0, rate)
                totals[tagId, default: 0] += count
            }
        }

        absorb(images)
        absorb(scenes)

        return PerformerTagStats(
            probabilities: probabilities,
            counts: totals,
            tags: tags,
            sampleSize: images.count + scenes.count
        )
    }

    private func fetchAllTags() async throws -> [Tag] {
        let query = GraphQLQueries.queryWithFragments("findTags")
        let variables: [String: Any] = [
            "filter": ["per_page": -1, "sort": "name", "direction": "ASC"]
        ]
        let response: TagsResponse = try await GraphQLClient.shared.execute(query: query, variables: variables)
        return response.data?.findTags.tags ?? []
    }

    private func fetchTaggedImages(limit: Int) async throws -> [StashImage] {
        let query = GraphQLQueries.queryWithFragments("findImages")
        let perPage = 100
        var collected: [StashImage] = []
        var page = 1
        // One seed for the whole build: random keeps the index a representative cross
        // section of the tag vocabulary (a date sort would only ever index the newest
        // slice), and a stable seed keeps paging consistent across the pages.
        let sort = "random_\(Int.random(in: 1...1_000_000))"

        while collected.count < limit {
            let variables: [String: Any] = [
                "filter": [
                    "page": page,
                    "per_page": perPage,
                    "sort": sort,
                    "direction": "ASC"
                ],
                "image_filter": [
                    "tag_count": ["value": 0, "modifier": "GREATER_THAN"]
                ]
            ]
            let response: ImagesResponse = try await GraphQLClient.shared.execute(query: query, variables: variables)
            let images = response.data?.findImages.images ?? []
            if images.isEmpty { break }
            collected.append(contentsOf: images)
            if images.count < perPage { break }
            page += 1
            if Task.isCancelled { break }
        }

        return Array(collected.prefix(limit))
    }

    // MARK: - Vision

    private struct Analysis {
        var vector: [Float]?
        var labels: [(identifier: String, confidence: Float)] = []
    }

    nonisolated private static func makeEntry(for image: StashImage) async -> AITagIndexEntry? {
        guard let url = image.thumbnailURL else { return nil }
        let tagIds = (image.tags ?? []).map(\.id)
        guard !tagIds.isEmpty else { return nil }
        guard let vector = await analyze(url: url, wantsLabels: false).vector else { return nil }
        return AITagIndexEntry(imageId: image.id, tagIds: tagIds, vector: vector)
    }

    /// Frames to analyse for one item: a still contributes its thumbnail, a clip a
    /// spread across its duration. Falls back to the thumbnail whenever frame
    /// extraction fails (unreachable file, odd container, still-generating preview).
    nonisolated static func frames(of image: StashImage, frameCount: Int) async -> [CGImage] {
        func thumbnailFrame() async -> [CGImage] {
            guard let url = image.thumbnailURL,
                  let data = await loadThumbnailData(url: url),
                  let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else { return [] }
            return [cgImage]
        }

        guard frameCount > 1, let mediaURL = image.imageURL else {
            return await thumbnailFrame()
        }

        var frames: [CGImage] = []
        if image.isAnimated {
            frames = await animatedFrames(url: mediaURL, count: frameCount)
        } else if image.isVideo {
            frames = await videoFrames(url: mediaURL, count: frameCount)
        }
        return frames.isEmpty ? await thumbnailFrame() : frames
    }

    nonisolated private static func analyzeFrames(_ frames: [CGImage]) async -> [Analysis] {
        var analyses: [Analysis] = []
        for frame in frames {
            let analysis = await analyze(cgImage: frame)
            if analysis.vector != nil { analyses.append(analysis) }
            if Task.isCancelled { break }
        }
        return analyses
    }

    /// Evenly spaced sample times, avoiding the very first and last moments —
    /// clips often open on a black or title frame.
    nonisolated private static func sampleFractions(count: Int) -> [Double] {
        guard count > 1 else { return [0.5] }
        return (0..<count).map { (Double($0) + 0.5) / Double(count) }
    }

    nonisolated private static func videoFrames(url: URL, count: Int) async -> [CGImage] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 else {
            return []
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        // Nearest keyframe is plenty for a tag vote and avoids decoding whole GOPs.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let times = sampleFractions(count: count).map {
            CMTime(seconds: duration.seconds * $0, preferredTimescale: 600)
        }

        var frames: [CGImage] = []
        for await result in generator.images(for: times) {
            if case .success(_, let image, _) = result {
                frames.append(image)
            }
            if Task.isCancelled { break }
        }
        return frames
    }

    nonisolated private static func animatedFrames(url: URL, count: Int) async -> [CGImage] {
        guard let data = await loadThumbnailData(url: url) else { return [] }
        return await Task.detached(priority: .utility) { () -> [CGImage] in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
            let total = CGImageSourceGetCount(source)
            guard total > 0 else { return [] }
            let wanted = min(count, total)
            let indices = sampleFractions(count: wanted).map { min(total - 1, Int($0 * Double(total))) }
            var frames: [CGImage] = []
            for index in Array(NSOrderedSet(array: indices)) as? [Int] ?? indices {
                if let frame = CGImageSourceCreateImageAtIndex(source, index, nil) {
                    frames.append(frame)
                }
            }
            return frames
        }.value
    }

    nonisolated private static func analyze(url: URL, wantsLabels: Bool = true) async -> Analysis {
        guard let data = await loadThumbnailData(url: url),
              let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            return Analysis()
        }
        return await analyze(cgImage: cgImage, wantsLabels: wantsLabels)
    }

    nonisolated private static func analyze(cgImage: CGImage, wantsLabels: Bool = true) async -> Analysis {
        return await Task.detached(priority: .utility) { () -> Analysis in
            var analysis = Analysis()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            let printRequest = VNGenerateImageFeaturePrintRequest()
            let classifyRequest = VNClassifyImageRequest()
            let requests: [VNRequest] = wantsLabels ? [printRequest, classifyRequest] : [printRequest]

            do {
                try handler.perform(requests)
            } catch {
                AppLog.error("AITags: Vision failed — \(error.localizedDescription)")
                return analysis
            }

            if let observation = printRequest.results?.first as? VNFeaturePrintObservation {
                analysis.vector = normalizedVector(from: observation)
            }

            if wantsLabels, let results = classifyRequest.results {
                analysis.labels = results
                    .filter { $0.confidence >= 0.35 }
                    .prefix(12)
                    .map { ($0.identifier, $0.confidence) }
            }

            return analysis
        }.value
    }

    nonisolated private static func loadThumbnailData(url: URL) async -> Data? {
        if let cached = await ImageCache.shared.loadData(forKey: url as NSURL) {
            return cached
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, response) = try? await StashNetworking.session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        ImageCache.shared.setData(data, forKey: url as NSURL)
        return data
    }

    /// Feature prints come back as raw Float32 (or Float64) elements; normalize once so
    /// similarity is a plain dot product later.
    nonisolated private static func normalizedVector(from observation: VNFeaturePrintObservation) -> [Float]? {
        let data = observation.data
        var values: [Float] = []

        switch observation.elementType {
        case .float:
            values = data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
        case .double:
            values = data.withUnsafeBytes { buffer in
                buffer.bindMemory(to: Double.self).map { Float($0) }
            }
        default:
            return nil
        }

        guard !values.isEmpty else { return nil }
        var norm: Float = 0
        for value in values { norm += value * value }
        norm = norm.squareRoot()
        guard norm > 0 else { return nil }
        return values.map { $0 / norm }
    }

    nonisolated private static func dot(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count else { return -1 }
        var sum: Float = 0
        for index in 0..<lhs.count {
            sum += lhs[index] * rhs[index]
        }
        return sum
    }

    // MARK: - Helpers

    nonisolated private static func normalize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Keyed by host and port rather than the config's UUID: re-adding or re-editing a
    /// server keeps its index instead of silently starting from zero.
    nonisolated private static func indexKey() -> String? {
        guard let config = ServerConfigManager.shared.activeConfig else { return nil }
        let host = config.serverAddress.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        let port = config.port ?? config.serverProtocol.defaultPort
        let raw = "\(host):\(port)"
        return raw.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    nonisolated private static func indexURL() -> URL? {
        guard let key = indexKey() else { return nil }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("AITagIndex", isDirectory: true)
            .appendingPathComponent("\(key).json")
    }
}

#endif
