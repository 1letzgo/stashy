//
//  StashImageDateSortTests.swift
//  stashyTests
//
//  Note: wire into the stashyTests target in Xcode if it is not already compiled.

import Testing
@testable import stashy

struct StashImageDateSortTests {

    @Test func parseSessionFromStashFilename() {
        let key = StashImageFilenameKeys.parseSessionFromFilename("042_-_2026-01-12_12-39-43_0")
        #expect(key == "2026-01-12_12-39-43")
    }

    @Test func parseSessionFromImporterFilename() {
        let key = StashImageFilenameKeys.parseSessionFromFilename("wolke11-2026-06-24_07-42-44_0")
        #expect(key == "2026-06-24_07-42-44")
    }

    @Test func parseSessionNoMatch() {
        #expect(StashImageFilenameKeys.parseSessionFromFilename("vacation_beach.jpg") == nil)
    }

    @Test func filenameStemStripsQuery() {
        let stem = StashImageFilenameKeys.filenameStem(from: "https://host/img/042_-_2026-01-12_12-39-43_0.jpg?width=800")
        #expect(stem == "042_-_2026-01-12_12-39-43_0")
    }

    @Test func sessionKeyGroupsWithoutMetaInKey() {
        var cache: [String: String] = [:]
        let a = makeImage(id: "1", basename: "042_-_2026-01-12_12-39-43_0.jpg", performerIds: ["p1"], galleryIds: ["g1"])
        let b = makeImage(id: "2", basename: "043_-_2026-01-12_12-39-43_1.jpg", performerIds: ["p2"], galleryIds: ["g9"])
        let ka = StashImageFilenameKeys.groupKey(for: a, policy: .sessionThenMeta, sessionCache: &cache)
        let kb = StashImageFilenameKeys.groupKey(for: b, policy: .sessionThenMeta, sessionCache: &cache)
        #expect(ka == "session|2026-01-12_12-39-43")
        #expect(ka == kb)
    }

    @Test func metaFallbackGroupsSameDayPerformerGallery() {
        var cache: [String: String] = [:]
        let a = makeImage(id: "1", basename: "shot_a.jpg", date: "2026-03-01", createdAt: "2026-03-01T10:00:00Z", performerIds: ["p1"], galleryIds: ["g1"])
        let b = makeImage(id: "2", basename: "shot_b.jpg", date: "2026-03-01", createdAt: "2026-03-01T10:01:00Z", performerIds: ["p1"], galleryIds: ["g1"])
        let ka = StashImageFilenameKeys.groupKey(for: a, policy: .sessionThenMeta, sessionCache: &cache)
        let kb = StashImageFilenameKeys.groupKey(for: b, policy: .sessionThenMeta, sessionCache: &cache)
        #expect(ka == "meta|2026-03-01|p1|g1")
        #expect(ka == kb)
    }

    @Test func metaFallbackSplitsDifferentPerformer() {
        var cache: [String: String] = [:]
        let a = makeImage(id: "1", basename: "a.jpg", date: "2026-03-01", performerIds: ["p1"], galleryIds: ["g1"])
        let b = makeImage(id: "2", basename: "b.jpg", date: "2026-03-01", performerIds: ["p2"], galleryIds: ["g1"])
        let ka = StashImageFilenameKeys.groupKey(for: a, policy: .sessionThenMeta, sessionCache: &cache)
        let kb = StashImageFilenameKeys.groupKey(for: b, policy: .sessionThenMeta, sessionCache: &cache)
        #expect(ka != kb)
    }

    @Test func sessionOnlyDoesNotUseMeta() {
        var cache: [String: String] = [:]
        let a = makeImage(id: "1", basename: "shot_a.jpg", date: "2026-03-01", performerIds: ["p1"], galleryIds: ["g1"])
        let key = StashImageFilenameKeys.groupKey(for: a, policy: .sessionOnly, sessionCache: &cache)
        #expect(key == "single|1")
    }

    @Test func untaggedSameDayStaysSingle() {
        var cache: [String: String] = [:]
        let a = makeImage(id: "1", basename: "a.jpg", date: "2026-03-01", performerIds: [], galleryIds: [])
        let key = StashImageFilenameKeys.groupKey(for: a, policy: .sessionThenMeta, sessionCache: &cache)
        #expect(key == "single|1")
    }

    @Test func buildPostsMergesAcrossPagesAndKeepsStableId() {
        var cache: [String: String] = [:]
        let page1 = [
            makeImage(id: "1", basename: "shot_a.jpg", date: "2026-03-01", performerIds: ["p1"], galleryIds: ["g1"]),
        ]
        let page2 = [
            makeImage(id: "2", basename: "shot_b.jpg", date: "2026-03-01", performerIds: ["p1"], galleryIds: ["g1"]),
        ]
        let first = StashImageFilenameKeys.buildPosts(
            from: page1, sort: .dateDesc, policy: .sessionThenMeta, groupEnabled: true, sessionCache: &cache
        )
        #expect(first.count == 1)
        #expect(first[0].id == "meta|2026-03-01|p1|g1")
        #expect(first[0].images.count == 1)

        let merged = StashImageFilenameKeys.buildPosts(
            from: page1 + page2, sort: .dateDesc, policy: .sessionThenMeta, groupEnabled: true, sessionCache: &cache
        )
        #expect(merged.count == 1)
        #expect(merged[0].id == first[0].id)
        #expect(merged[0].images.map(\.id) == ["1", "2"])
    }

    @Test func buildPostsRandomDoesNotGroup() {
        var cache: [String: String] = [:]
        let images = [
            makeImage(id: "1", basename: "042_-_2026-01-12_12-39-43_0.jpg", performerIds: ["p1"], galleryIds: ["g1"]),
            makeImage(id: "2", basename: "043_-_2026-01-12_12-39-43_1.jpg", performerIds: ["p1"], galleryIds: ["g1"]),
        ]
        let posts = StashImageFilenameKeys.buildPosts(
            from: images, sort: .random, policy: .sessionThenMeta, groupEnabled: true, sessionCache: &cache
        )
        #expect(posts.count == 2)
    }

    @Test func withinGroupSortsByFilename() {
        let a = makeImage(id: "2", basename: "b.jpg")
        let b = makeImage(id: "1", basename: "a.jpg")
        #expect(StashImageFilenameKeys.withinGroupSort(b, a))
    }

    @Test func multiPerformerExactMatchGroups() {
        var cache: [String: String] = [:]
        let a = makeImage(id: "1", basename: "a.jpg", date: "2026-03-01", performerIds: ["p2", "p1"], galleryIds: ["g1"])
        let b = makeImage(id: "2", basename: "b.jpg", date: "2026-03-01", performerIds: ["p1", "p2"], galleryIds: ["g1"])
        let posts = StashImageFilenameKeys.buildPosts(
            from: [a, b], sort: .dateDesc, policy: .sessionThenMeta, groupEnabled: true, sessionCache: &cache
        )
        #expect(posts.count == 1)
        #expect(posts[0].images.count == 2)
    }

    @Test func multiPerformerSubsetStillGroups() {
        var cache: [String: String] = [:]
        let duo = makeImage(id: "1", basename: "a.jpg", date: "2026-03-01", performerIds: ["p1", "p2"], galleryIds: ["g1"])
        let one = makeImage(id: "2", basename: "b.jpg", date: "2026-03-01", performerIds: ["p1"], galleryIds: ["g1"])
        let posts = StashImageFilenameKeys.buildPosts(
            from: [duo, one], sort: .dateDesc, policy: .sessionThenMeta, groupEnabled: true, sessionCache: &cache
        )
        #expect(posts.count == 1)
        #expect(Set(posts[0].images.map(\.id)) == Set(["1", "2"]))
    }

    @Test func differentPerformersSameGalleryDoNotGroup() {
        var cache: [String: String] = [:]
        let a = makeImage(id: "1", basename: "a.jpg", date: "2026-03-01", performerIds: ["p1"], galleryIds: ["g1"])
        let b = makeImage(id: "2", basename: "b.jpg", date: "2026-03-01", performerIds: ["p2"], galleryIds: ["g1"])
        let posts = StashImageFilenameKeys.buildPosts(
            from: [a, b], sort: .dateDesc, policy: .sessionThenMeta, groupEnabled: true, sessionCache: &cache
        )
        #expect(posts.count == 2)
    }

    // MARK: - Fixtures

    private func makeImage(
        id: String,
        basename: String,
        date: String? = nil,
        createdAt: String? = nil,
        performerIds: [String] = [],
        galleryIds: [String] = []
    ) -> StashImage {
        StashImage(
            id: id,
            title: nil,
            rating100: nil,
            o_counter: nil,
            organized: nil,
            date: date,
            createdAt: createdAt,
            updatedAt: nil,
            paths: nil,
            visual_files: [ImageFile(path: "/media/\(basename)", height: 100, width: 100, duration: nil, basename: basename)],
            performers: performerIds.map { GalleryPerformer(id: $0, name: $0, image_path: nil) },
            studio: nil,
            galleries: galleryIds.map { ImageGallery(id: $0, title: $0) },
            tags: nil
        )
    }
}
