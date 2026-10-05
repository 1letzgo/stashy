//
//  StashImageDateSort.swift
//  stashy
//
//  Set grouping for the 1/row image feeds (Feeds › Pics, Images 1/row, detail image lists).
//  Feed order always trusts the Stash API (no client-side reorder). Mirrored 1:1 on Android
//  in `ImageSetGrouping.kt` — keep both in step.

import Foundation

/// How the 1/row image feeds bundle images into sets (`stashline_group_mode`).
enum StashImageGroupMode: String, CaseIterable {
    case off
    case gallery
    case gallerySession

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .gallery: return "By gallery"
        case .gallerySession: return "By gallery + session"
        }
    }
}

/// UserDefaults keys + migration of the grouping settings.
enum StashImageGroupingPrefs {
    static let modeKey = "stashline_group_mode"
    static let gapKey = "stashline_group_gap_minutes"
    /// Old on/off switch; still written (true unless off) so older readers behave.
    static let legacySetsKey = "stashline_group_sets"
    static let gapOptions = [2, 10, 60]
    static let defaultGapMinutes = 10

    /// First read of `stashline_group_mode`: the old switch decides (missing = on).
    static func migratedMode(legacyGroupSets: Bool?) -> StashImageGroupMode {
        legacyGroupSets == false ? .off : .gallerySession
    }

    /// Only 2 / 10 / 60 are offered; anything else falls back to 10.
    static func normalizedGap(_ minutes: Int?) -> Int {
        guard let minutes, gapOptions.contains(minutes) else { return defaultGapMinutes }
        return minutes
    }

    /// Stored mode raw value; migrates (and persists) it from the old switch on first read.
    /// Used as the `@AppStorage` default so every reader sees the migrated value.
    static func resolvedModeRaw(_ defaults: UserDefaults = .standard) -> String {
        if let raw = defaults.string(forKey: modeKey), StashImageGroupMode(rawValue: raw) != nil {
            return raw
        }
        let legacy = defaults.object(forKey: legacySetsKey) as? Bool
        let mode = migratedMode(legacyGroupSets: legacy)
        defaults.set(mode.rawValue, forKey: modeKey)
        return mode.rawValue
    }

    static func mode(fromRaw raw: String) -> StashImageGroupMode {
        StashImageGroupMode(rawValue: raw) ?? .gallerySession
    }

    /// Keeps the old `stashline_group_sets` key in sync after the mode changed.
    static func syncLegacyKey(for mode: StashImageGroupMode, _ defaults: UserDefaults = .standard) {
        defaults.set(mode != .off, forKey: legacySetsKey)
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

    /// Parses a `yyyy-MM-dd_HH-mm-ss` session timestamp from common Stash / importer filename patterns.
    static func parseSessionFromFilename(_ filename: String) -> String? {
        // Stash: "042_-_2026-01-12_12-39-43_0" -> "2026-01-12_12-39-43"
        if filename.contains("_-_"),
           let match = filename.range(of: #"(?<=_-_).+(?=_\d+$)"#, options: .regularExpression) {
            return String(filename[match])
        }
        // Importer: "wolke11-2026-06-24_07-42-44_0" -> "2026-06-24_07-42-44"
        if let match = filename.range(
            of: #"\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}(?=_\d+$)"#,
            options: .regularExpression
        ) {
            return String(filename[match])
        }
        return nil
    }

    /// Basename / path / title candidates in a consistent order.
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
}

/// Set grouping of the 1/row image feeds. Pure; mirrored by Android's `ImageSetGrouping`.
///
/// Only **consecutive** images (API order) can form a set: the list is walked once and an image
/// joins the current (last) post when `canJoin` allows it, otherwise it starts a new post. A new
/// page can therefore only extend the last post; everything above stays as it was.
enum StashImageSetGrouping {
    static let maxSetSize = 30

    // MARK: Timestamps (epoch seconds, hand-parsed so Swift and Kotlin agree exactly)

    /// `created_at` → epoch seconds. Accepts `2026-06-24T07:42:44Z`, `…+02:00`, `…+0200`,
    /// fractional seconds and `2026-06-24 07:42:44 +0000`; no zone = UTC. Anything else → nil.
    static func parseCreatedAt(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let s = Array(raw.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard let base = parseFields(s, dateSep: UInt8(ascii: "-"), mid: [UInt8(ascii: "T"), UInt8(ascii: " ")], timeSep: UInt8(ascii: ":")) else {
            return nil
        }
        var i = 19
        if i < s.count, s[i] == UInt8(ascii: ".") {
            i += 1
            while i < s.count, isDigit(s[i]) { i += 1 }
        }
        let zone = String(decoding: s[i...], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        let offset: Int
        if zone.isEmpty || zone == "Z" || zone == "z" {
            offset = 0
        } else if let parsed = parseOffset(zone) {
            offset = parsed
        } else {
            return nil
        }
        return base - offset
    }

    /// Filename session `yyyy-MM-dd_HH-mm-ss` → epoch seconds, read as UTC.
    static func parseFilenameSession(_ key: String) -> Int? {
        let s = Array(key.utf8)
        guard s.count == 19 else { return nil }
        return parseFields(s, dateSep: UInt8(ascii: "-"), mid: [UInt8(ascii: "_")], timeSep: UInt8(ascii: "-"))
    }

    /// `created_at`, else a timestamp in the file name; nil = none (the image never joins by time).
    static func timestamp(for image: StashImage) -> Int? {
        if let t = parseCreatedAt(image.createdAt) { return t }
        for raw in StashImageFilenameKeys.filenameCandidates(for: image) {
            let stem = StashImageFilenameKeys.filenameStem(from: raw)
            guard let key = StashImageFilenameKeys.parseSessionFromFilename(stem) else { continue }
            if let t = parseFilenameSession(key) { return t }
        }
        return nil
    }

    private static func isDigit(_ c: UInt8) -> Bool { c >= 48 && c <= 57 }

    private static func num(_ s: [UInt8], _ from: Int, _ len: Int) -> Int? {
        guard from + len <= s.count else { return nil }
        var v = 0
        for k in from..<(from + len) {
            guard isDigit(s[k]) else { return nil }
            v = v * 10 + Int(s[k] - 48)
        }
        return v
    }

    /// Fixed layout `yyyy?MM?dd?HH?mm?ss` (first 19 bytes) → epoch seconds (UTC).
    private static func parseFields(_ s: [UInt8], dateSep: UInt8, mid: Set<UInt8>, timeSep: UInt8) -> Int? {
        guard s.count >= 19,
              s[4] == dateSep, s[7] == dateSep, mid.contains(s[10]), s[13] == timeSep, s[16] == timeSep,
              let y = num(s, 0, 4), let mo = num(s, 5, 2), let d = num(s, 8, 2),
              let h = num(s, 11, 2), let mi = num(s, 14, 2), let se = num(s, 17, 2),
              (1...12).contains(mo), (1...31).contains(d), h <= 23, mi <= 59, se <= 60 else { return nil }
        return daysFromCivil(y, mo, d) * 86_400 + h * 3_600 + mi * 60 + se
    }

    /// `+02:00` / `-0530` → seconds east of UTC.
    private static func parseOffset(_ z: String) -> Int? {
        guard let signChar = z.first, signChar == "+" || signChar == "-" else { return nil }
        let sign = signChar == "+" ? 1 : -1
        let body = Array(z.dropFirst().replacingOccurrences(of: ":", with: "").utf8)
        guard body.count == 4, let h = num(body, 0, 2), let m = num(body, 2, 2), h <= 23, m <= 59 else { return nil }
        return sign * (h * 3_600 + m * 60)
    }

    /// Howard Hinnant's days_from_civil (proleptic Gregorian).
    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month + (month > 2 ? -3 : 9)
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    // MARK: Grouping

    /// Only the date / created sorts keep a set's images adjacent.
    static func supportsGrouping(for sort: StashDBViewModel.ImageSortOption) -> Bool {
        switch sort {
        case .dateAsc, .dateDesc, .createdAtAsc, .createdAtDesc:
            return true
        default:
            return false
        }
    }

    private static func galleryIDs(_ image: StashImage) -> Set<String> { Set((image.galleries ?? []).map(\.id)) }
    private static func performerIDs(_ image: StashImage) -> Set<String> { Set((image.performers ?? []).map(\.id)) }
    private static func studioID(_ image: StashImage) -> String { image.studio?.id ?? "" }

    /// Whether `image` may join `post` (non-empty, API order):
    /// - at most `maxSetSize` images; a clip and a photo never share a set;
    /// - galleries first, against the post's last image: both have galleries → join when they
    ///   share one; exactly one has galleries → no join;
    /// - `.gallerySession`, both without galleries: performers equal to the post's first image
    ///   and non-empty, or same non-empty studio with equal performers — and the `created_at` gap
    ///   to the post's last image ≤ `gapMinutes`. Untagged loose images never join.
    static func canJoin(_ post: [StashImage], _ image: StashImage, mode: StashImageGroupMode, gapMinutes: Int) -> Bool {
        guard mode != .off, let first = post.first, let last = post.last else { return false }
        guard post.count < maxSetSize else { return false }
        guard first.isVideo == image.isVideo else { return false }

        let lastGalleries = galleryIDs(last)
        let galleries = galleryIDs(image)
        if !lastGalleries.isEmpty && !galleries.isEmpty { return !lastGalleries.isDisjoint(with: galleries) }
        if !lastGalleries.isEmpty || !galleries.isEmpty { return false }
        guard mode == .gallerySession else { return false }

        let performers = performerIDs(image)
        guard performerIDs(first) == performers else { return false }
        let firstStudio = studioID(first)
        let sameStudio = !firstStudio.isEmpty && firstStudio == studioID(image)
        guard !performers.isEmpty || sameStudio else { return false }

        guard let t0 = timestamp(for: last), let t1 = timestamp(for: image) else { return false }
        return abs(t1 - t0) <= gapMinutes * 60
    }

    /// Walks `images` in API order and builds the feed posts. Ids are `single|<imageId>` /
    /// `set|<firstImageId>`, so a set keeps its id while a later page extends it.
    static func buildPosts(
        from images: [StashImage],
        sort: StashDBViewModel.ImageSortOption,
        mode: StashImageGroupMode = .gallerySession,
        gapMinutes: Int = StashImageGroupingPrefs.defaultGapMinutes
    ) -> [(id: String, images: [StashImage])] {
        guard mode != .off, supportsGrouping(for: sort) else {
            return images.map { (id: "single|\($0.id)", images: [$0]) }
        }
        var groups: [[StashImage]] = []
        for image in images {
            if let current = groups.last, canJoin(current, image, mode: mode, gapMinutes: gapMinutes) {
                groups[groups.count - 1].append(image)
            } else {
                groups.append([image])
            }
        }
        return groups.map { g in
            (id: g.count == 1 ? "single|\(g[0].id)" : "set|\(g[0].id)", images: g)
        }
    }
}
