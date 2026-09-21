//
//  StashImageDateSort.swift
//  stashy
//
//  Session helpers and set grouping for Pics (StashLine) feed.
//  Feed order always trusts the Stash API (no client-side filename reorder).

import Foundation

/// How exact the `created` timestamp has to match for two images to land in one set.
enum StashImageSessionPrecision: String, CaseIterable {
    case day
    case hour
    case minute

    var displayName: String {
        switch self {
        case .day: return "Same day"
        case .hour: return "Same hour"
        case .minute: return "Same minute"
        }
    }

    /// Characters of the normalized `YYYY-MM-DD_HH-MM-SS` key that still count.
    var keyLength: Int {
        switch self {
        case .day: return 10      // 2026-01-12
        case .hour: return 13     // 2026-01-12_12
        case .minute: return 16   // 2026-01-12_12-39
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
        // Importer: "wolke11-2026-06-24_07-42-44_0" -> "2026-06-24_07-42-44". Wie genau davon
        // zählt, entscheidet `StashImageSessionPrecision` beim Kürzen.
        if let match = filename.range(
            of: #"\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}(?=_\d+$)"#,
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

    /// The image's `created` timestamp as `YYYY-MM-DD_HH-MM-SS`, cut to the configured
    /// precision. One import run writes its images within the same second-to-minute window, so
    /// this groups a set far more reliably than a filename ever did. Files whose `created` is
    /// missing fall back to a timestamp in the filename. The cache always holds the full
    /// timestamp, so changing the precision setting needs no cache reset.
    static func sessionKey(
        for image: StashImage,
        cache: inout [String: String],
        precision: StashImageSessionPrecision = .hour
    ) -> String {
        if let cached = cache[image.id] {
            return String(cached.prefix(precision.keyLength))
        }

        if let key = createdTimestampKey(for: image) {
            cache[image.id] = key
            return String(key.prefix(precision.keyLength))
        }

        for raw in filenameCandidates(for: image) {
            let filename = filenameStem(from: raw)
            if let key = parseSessionFromFilename(filename) {
                cache[image.id] = key
                return String(key.prefix(precision.keyLength))
            }
        }

        cache[image.id] = ""
        return ""
    }

    /// `2026-06-24T07:42:44Z` / `2026-06-24 07:42:44 +0000` → `2026-06-24_07-42-44`, so it cuts
    /// with the same `keyLength` offsets as a filename timestamp.
    static func createdTimestampKey(for image: StashImage) -> String? {
        guard let raw = image.createdAt?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 19 else { return nil }
        let day = String(raw.prefix(10))
        guard day.count == 10, day.dropFirst(4).first == "-" else { return nil }
        let timeStart = raw.index(raw.startIndex, offsetBy: 11)
        let time = String(raw[timeStart...].prefix(8)).replacingOccurrences(of: ":", with: "-")
        guard time.count == 8 else { return nil }
        return "\(day)_\(time)"
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

    /// Builds feed posts with stable ids.
    ///
    /// Two images share a post when they were added in the same window **and** belong together
    /// by their metadata: same galleries, and performer sets that are equal or one a subset of
    /// the other. The timestamp narrows the rule, it does not replace it — two unrelated
    /// galleries imported in the same minute stay two posts. Images without a timestamp fall
    /// back to the same day plus those same metadata rules. Post order and frame order follow
    /// API appearance order.
    static func buildPosts(
        from images: [StashImage],
        sort: StashDBViewModel.ImageSortOption,
        precision: StashImageSessionPrecision = .hour,
        groupEnabled: Bool = true,
        sessionCache: inout [String: String]
    ) -> [(id: String, images: [StashImage])] {
        guard groupEnabled, supportsGrouping(for: sort) else {
            return images.map { (id: "single|\($0.id)", images: [$0]) }
        }

        var sessions: [String] = []
        sessions.reserveCapacity(images.count)
        for image in images {
            sessions.append(sessionKey(for: image, cache: &sessionCache, precision: precision))
        }
        let days = images.map { createdDayKey(for: $0) }
        let galleries = images.map { galleryKey($0) }
        let performerSets = images.map { performerIDSet($0) }

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

        for i in 0..<images.count {
            for j in (i + 1)..<images.count {
                // Metadata first: it holds for every pair, whatever the timestamps say.
                guard galleries[i] == galleries[j],
                      performersCompatible(performerSets[i], performerSets[j]) else { continue }
                let sharesSession = !sessions[i].isEmpty && sessions[i] == sessions[j]
                // No timestamp on either side: the metadata alone has to carry the set, and it
                // needs a day to hold on to.
                let sharesDay = sessions[i].isEmpty && sessions[j].isEmpty
                    && !days[i].isEmpty && days[i] == days[j]
                    && (!performerSets[i].isEmpty || !galleries[i].isEmpty)
                guard sharesSession || sharesDay else { continue }
                union(i, j)
            }
        }

        var members: [Int: [Int]] = [:]
        var order: [Int] = []
        for i in 0..<images.count {
            let root = find(i)
            if members[root] == nil {
                order.append(root)
                members[root] = []
            }
            members[root]?.append(i)
        }

        return order.compactMap { root in
            guard let indices = members[root], let seed = indices.first else { return nil }
            let image = images[seed]
            // Stable id from the first image of the set, so a post keeps its identity while
            // later pages add frames to it.
            let key = sessions[seed].isEmpty ? "day|\(days[seed])" : "session|\(sessions[seed])"
            let id = indices.count == 1
                ? "single|\(image.id)"
                : "set|\(key)|\(performerKey(image))|\(galleries[seed])"
            return (id: id, images: indices.map { images[$0] })
        }
    }

}
