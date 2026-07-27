//
//  StashImageDateSort.swift
//  stashy
//
//  Filename / session helpers for Pics set grouping. Feed Date sort trusts
//  the Stash API order (no client-side tie-breakers).

import Foundation

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

    /// Calendar day for grouping — Stash often gives each frame a unique `created_at` timestamp.
    static func createdKey(for image: StashImage, session: String) -> String {
        if !session.isEmpty, let day = session.split(separator: "_").first, !day.isEmpty {
            return String(day)
        }
        if let d = image.date, !d.isEmpty { return String(d.prefix(10)) }
        if let c = image.createdAt, c.count >= 10 { return String(c.prefix(10)) }
        return image.createdAt ?? ""
    }

    static func performerKey(_ image: StashImage) -> String {
        (image.performers ?? []).map(\.id).sorted().joined(separator: ",")
    }

    static func galleryKey(_ image: StashImage) -> String {
        (image.galleries ?? []).map(\.id).sorted().joined(separator: ",")
    }

    static func fileNameSortKey(_ image: StashImage) -> String {
        guard let raw = filenameCandidates(for: image).first else { return "" }
        return filenameStem(from: raw)
    }

    /// Always ascending — used for Pics carousel frame order inside a set.
    static func withinGroupSort(_ a: StashImage, _ b: StashImage) -> Bool {
        compareFileNames(a, b, ascending: true)
    }

    static func compareFileNames(_ a: StashImage, _ b: StashImage, ascending: Bool) -> Bool {
        let fa = fileNameSortKey(a)
        let fb = fileNameSortKey(b)
        if fa != fb {
            let ordered = fa.localizedStandardCompare(fb) == .orderedAscending
            return ascending ? ordered : !ordered
        }
        return ascending ? (a.id < b.id) : (a.id > b.id)
    }

    static func groupKey(for image: StashImage, sessionCache: inout [String: String]) -> String {
        let session = sessionKey(for: image, cache: &sessionCache)
        guard !session.isEmpty else {
            return image.id
        }
        let created = createdKey(for: image, session: session)
        return "\(performerKey(image))|\(galleryKey(image))|\(created)|\(session)"
    }
}
