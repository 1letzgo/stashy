//
//  StashImageDateSort.swift
//  stashy
//
//  Session helpers and set grouping for Pics (StashLine) feed.
//  Feed order always trusts the Stash API (no client-side filename reorder).

import Foundation

enum StashImageSetGroupingPolicy: String, CaseIterable {
    /// Only merge when a filename session timestamp is present.
    case sessionOnly
    /// Session first; otherwise same created day + performers + galleries.
    case sessionThenMeta

    var displayName: String {
        switch self {
        case .sessionOnly: return "Session only"
        case .sessionThenMeta: return "Session + metadata"
        }
    }
}

enum StashImageFilenameKeys {
    static func filenameStem(from path: String) -> String {
        let raw = path.components(separatedBy: "?").first ?? path
        if let url = URL(string: raw), url.scheme != nil {
            return url.deletingPathExtension().lastPathComponent
        }
        return URL(fileURLWithPath: raw).deletingPathExtension().lastPathComponent
    }

    /// Parses a normalized session timestamp from common Stash / importer filename patterns.
    static func parseSessionFromFilename(_ filename: String) -> String? {
        // Stash: "042_-_2026-01-12_12-39-43_0" -> "2026-01-12_12-39-43"
        if filename.contains("_-_"),
           let match = filename.range(of: #"(?<=_-_).+(?=_\d+$)"#, options: .regularExpression) {
            return String(filename[match])
        }
        // Importer: "wolke11-2026-06-24_07-42-44_0" -> "2026-06-24_07-42-44"
        if let match = filename.range(
            of: #"(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})(?=_\d+$)"#,
            options: .regularExpression
        ) {
            return String(filename[match])
        }
        return nil
    }

    /// Basename / path / title candidates in a consistent order for session + filename keys.
    static func filenameCandidates(for image: StashImage) -> [String] {
        var candidates: [String] = []
        if let visualFiles = image.visual_files {
            for file in visualFiles {
                if let basename = file.basename, !basename.isEmpty {
                    candidates.append(basename)
                }
                if !file.path.isEmpty {
                    candidates.append(file.path)
                }
            }
        }
        if let imagePath = image.paths?.image, !imagePath.isEmpty {
            candidates.append(imagePath)
        }
        if let title = image.title, !title.isEmpty {
            candidates.append(title)
        }
        return candidates
    }

    static func sessionKey(for image: StashImage, cache: inout [String: String]) -> String {
        if let cached = cache[image.id] { return cached }

        for raw in filenameCandidates(for: image) {
            let filename = filenameStem(from: raw)
            if let key = parseSessionFromFilename(filename) {
                cache[image.id] = key
                return key
            }
        }

        cache[image.id] = ""
        return ""
    }

    /// Calendar day for meta grouping (`date`, else `created_at` prefix).
    static func createdDayKey(for image: StashImage) -> String {
        if let d = image.date, !d.isEmpty { return String(d.prefix(10)) }
        if let c = image.createdAt, c.count >= 10 { return String(c.prefix(10)) }
        return ""
    }

    static func performerIDSet(_ image: StashImage) -> Set<String> {
        Set((image.performers ?? []).map(\.id))
    }

    static func performerKey(_ image: StashImage) -> String {
        performerIDSet(image).sorted().joined(separator: ",")
    }

    static func galleryKey(_ image: StashImage) -> String {
        (image.galleries ?? []).map(\.id).sorted().joined(separator: ",")
    }

    /// Same or subset performer sets (order-independent). Empty only matches empty.
    /// So a duo frame `[A,B]` still groups with a frame tagged only `[A]` or only `[B]` is NOT enough —
    /// `[A]` and `[A,B]` merge; `[A]` and `[B]` do not unless a bridging `[A,B]` exists.
    static func performersCompatible(_ a: Set<String>, _ b: Set<String>) -> Bool {
        if a == b { return true }
        if a.isEmpty || b.isEmpty { return a.isEmpty && b.isEmpty }
        return a.isSubset(of: b) || b.isSubset(of: a)
    }

    static func supportsGrouping(for sort: StashDBViewModel.ImageSortOption) -> Bool {
        switch sort {
        case .dateAsc, .dateDesc, .createdAtAsc, .createdAtDesc, .titleAsc, .titleDesc:
            return true
        default:
            return false
        }
    }

    /// Preliminary key for set identity. Meta uses day+gallery+exact performers;
    /// final posts may further merge compatible multi-performer subsets.
    static func groupKey(
        for image: StashImage,
        policy: StashImageSetGroupingPolicy = .sessionThenMeta,
        sessionCache: inout [String: String]
    ) -> String {
        let session = sessionKey(for: image, cache: &sessionCache)
        if !session.isEmpty {
            return "session|\(session)"
        }

        guard policy == .sessionThenMeta else {
            return "single|\(image.id)"
        }

        let day = createdDayKey(for: image)
        let performers = performerKey(image)
        let galleries = galleryKey(image)
        guard !day.isEmpty, !performers.isEmpty || !galleries.isEmpty else {
            return "single|\(image.id)"
        }
        return "meta|\(day)|\(performers)|\(galleries)"
    }

    /// Builds feed posts with stable ids. Session keys merge exactly; meta merges same
    /// day+galleries when performer sets are equal or subsets (multi-performer safe).
    /// Post order and frame order inside sets follow API appearance order.
    static func buildPosts(
        from images: [StashImage],
        sort: StashDBViewModel.ImageSortOption,
        policy: StashImageSetGroupingPolicy = .sessionThenMeta,
        groupEnabled: Bool = true,
        sessionCache: inout [String: String]
    ) -> [(id: String, images: [StashImage])] {
        guard groupEnabled, supportsGrouping(for: sort) else {
            return images.map { (id: "single|\($0.id)", images: [$0]) }
        }

        var sessionGroups: [String: [StashImage]] = [:]
        var metaCandidates: [StashImage] = []

        for image in images {
            let session = sessionKey(for: image, cache: &sessionCache)
            if !session.isEmpty {
                let key = "session|\(session)"
                if sessionGroups[key] == nil {
                    sessionGroups[key] = []
                }
                sessionGroups[key]?.append(image)
                continue
            }

            if policy == .sessionThenMeta {
                let day = createdDayKey(for: image)
                let performers = performerKey(image)
                let galleries = galleryKey(image)
                if !day.isEmpty, !performers.isEmpty || !galleries.isEmpty {
                    metaCandidates.append(image)
                    continue
                }
            }
        }

        let metaClusters = clusterMetaImages(metaCandidates)
        var metaById: [String: [StashImage]] = [:]
        for cluster in metaClusters {
            metaById[cluster.id] = cluster.images
        }

        return orderedPostsPreservingAppearance(
            ordered: images,
            sessionGroups: sessionGroups,
            metaById: metaById,
            sessionCache: &sessionCache,
            policy: policy
        )
    }

    private struct MetaCluster {
        let id: String
        let images: [StashImage]
    }

    /// Same created day + same galleries; performers equal or subset (supports multi-performer frames).
    private static func clusterMetaImages(_ images: [StashImage]) -> [MetaCluster] {
        guard !images.isEmpty else { return [] }

        var parent = Array(0..<images.count)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[rb] = ra }
        }

        let days = images.map { createdDayKey(for: $0) }
        let galleries = images.map { galleryKey($0) }
        let performerSets = images.map { performerIDSet($0) }

        for i in 0..<images.count {
            for j in (i + 1)..<images.count {
                guard days[i] == days[j], galleries[i] == galleries[j] else { continue }
                guard performersCompatible(performerSets[i], performerSets[j]) else { continue }
                union(i, j)
            }
        }

        var clusters: [Int: [Int]] = [:]
        var rootOrder: [Int] = []
        for i in 0..<images.count {
            let r = find(i)
            if clusters[r] == nil {
                rootOrder.append(r)
                clusters[r] = []
            }
            clusters[r]?.append(i)
        }

        return rootOrder.compactMap { root in
            guard let idxs = clusters[root], !idxs.isEmpty else { return nil }
            // Stable id from first-seen image in this cluster (not the merged performer union).
            let seed = idxs[0]
            let seedImage = images[seed]
            let id = "meta|\(days[seed])|\(performerKey(seedImage))|\(galleries[seed])"
            let members = idxs.map { images[$0] }
            return MetaCluster(id: id, images: members)
        }
    }

    private static func orderedPostsPreservingAppearance(
        ordered: [StashImage],
        sessionGroups: [String: [StashImage]],
        metaById: [String: [StashImage]],
        sessionCache: inout [String: String],
        policy: StashImageSetGroupingPolicy
    ) -> [(id: String, images: [StashImage])] {
        var imageToMetaId: [String: String] = [:]
        for (id, imgs) in metaById {
            for img in imgs { imageToMetaId[img.id] = id }
        }

        var seen: Set<String> = []
        var result: [(id: String, images: [StashImage])] = []

        for image in ordered {
            let session = sessionKey(for: image, cache: &sessionCache)
            if !session.isEmpty {
                let key = "session|\(session)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let imgs = sessionGroups[key] ?? [image]
                result.append((id: key, images: imgs))
                continue
            }

            if let metaId = imageToMetaId[image.id] {
                guard !seen.contains(metaId) else { continue }
                seen.insert(metaId)
                let imgs = metaById[metaId] ?? [image]
                result.append((id: metaId, images: imgs))
                continue
            }

            let key = "single|\(image.id)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append((id: key, images: [image]))
        }

        return result
    }
}
