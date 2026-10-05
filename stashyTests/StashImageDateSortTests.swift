//
//  StashImageDateSortTests.swift
//  stashyTests
//
//  Set grouping of the 1/row image feeds (`StashImageSetGrouping`). Mirrors Android's
//  `ImageSetGroupingTest` case by case.
//  Note: wire into the stashyTests target in Xcode if it is not already compiled.

import Foundation
import Testing
@testable import stashy

struct StashImageDateSortTests {

    // MARK: - Timestamps

    @Test func parsesCreatedAtVariantsToEpoch() {
        let utc = StashImageSetGrouping.parseCreatedAt("2026-06-24T07:42:44Z")
        #expect(utc == 1_782_286_964)
        #expect(StashImageSetGrouping.parseCreatedAt("2026-06-24T09:42:44+02:00") == utc)
        #expect(StashImageSetGrouping.parseCreatedAt("2026-06-24 07:42:44 +0000") == utc)
        #expect(StashImageSetGrouping.parseCreatedAt("2026-06-24T07:42:44.517Z") == utc)
        #expect(StashImageSetGrouping.parseCreatedAt("2026-06-24T07:42:44") == utc)
        #expect(StashImageSetGrouping.parseCreatedAt("yesterday") == nil)
        #expect(StashImageSetGrouping.parseCreatedAt("2026-06-24T07:42:44+2") == nil)
        #expect(StashImageSetGrouping.parseCreatedAt(nil) == nil)
    }

    @Test func filenameSessionParsing() {
        #expect(StashImageFilenameKeys.parseSessionFromFilename("042_-_2026-01-12_12-39-43_0") == "2026-01-12_12-39-43")
        #expect(StashImageFilenameKeys.parseSessionFromFilename("wolke11-2026-06-24_07-42-44_0") == "2026-06-24_07-42-44")
        #expect(StashImageFilenameKeys.parseSessionFromFilename("IMG_1234") == nil)
        #expect(StashImageFilenameKeys.filenameStem(from: "/a/b/042_-_2026-01-12_12-39-43_0.jpg?x=1") == "042_-_2026-01-12_12-39-43_0")
        #expect(StashImageSetGrouping.parseFilenameSession("2026-06-24_07-42-44")
                == StashImageSetGrouping.parseCreatedAt("2026-06-24T07:42:44Z"))
    }

    // MARK: - Rules

    @Test func onlyConsecutiveImagesGroup() {
        let a = img("a", "2026-01-01T10:00:00Z", galleries: ["g1"])
        let b = img("b", "2026-01-01T10:00:30Z", galleries: ["g2"])
        let c = img("c", "2026-01-01T10:01:00Z", galleries: ["g1"])
        #expect(ids(group([a, b, c])) == [["a"], ["b"], ["c"]])
    }

    @Test func galleryIntersectionJoinsIndependentOfTime() {
        let a = img("a", "2026-01-01T10:00:00Z", galleries: ["g1", "g2"])
        let b = img("b", "2025-03-01T10:00:00Z", galleries: ["g2", "g3"])
        let c = img("c", nil, galleries: ["g3"])
        let d = img("d", "2026-01-01T10:00:00Z", galleries: ["g9"])
        #expect(ids(group([a, b, c, d])) == [["a", "b", "c"], ["d"]])
        #expect(ids(group([a, b, c, d], mode: .gallery)) == [["a", "b", "c"], ["d"]])
    }

    @Test func mixedGalleryAndNoGalleryNeverJoin() {
        let a = img("a", "2026-01-01T10:00:00Z", performers: ["p"], galleries: ["g1"])
        let b = img("b", "2026-01-01T10:00:01Z", performers: ["p"])
        let c = img("c", "2026-01-01T10:00:02Z", performers: ["p"], galleries: ["g1"])
        #expect(ids(group([a, b, c])) == [["a"], ["b"], ["c"]])
    }

    @Test func looseUntaggedImagesNeverGroup() {
        let a = img("a", "2026-01-01T10:00:00Z")
        let b = img("b", "2026-01-01T10:00:00Z")
        #expect(ids(group([a, b])) == [["a"], ["b"]])
    }

    @Test func equalNonEmptyPerformersWithinGapJoin() {
        let a = img("a", "2026-01-01T10:00:00Z", performers: ["p1", "p2"])
        let b = img("b", "2026-01-01T10:05:00Z", performers: ["p2", "p1"])
        let c = img("c", "2026-01-01T10:06:00Z", performers: ["p1"])
        #expect(ids(group([a, b, c])) == [["a", "b"], ["c"]])
        #expect(group([a, b, c], mode: .gallery).count == 3)
    }

    @Test func performersComparedToFirstImageNoTransitiveDrift() {
        let a = img("a", "2026-01-01T10:00:00Z", performers: ["A"])
        let ab = img("ab", "2026-01-01T10:01:00Z", performers: ["A", "B"])
        let b = img("b", "2026-01-01T10:02:00Z", performers: ["B"])
        #expect(ids(group([a, ab, b])) == [["a"], ["ab"], ["b"]])
    }

    @Test func studioRule() {
        let a = img("a", "2026-01-01T10:00:00Z", studio: "s1")
        let b = img("b", "2026-01-01T10:01:00Z", studio: "s1")
        let c = img("c", "2026-01-01T10:02:00Z", studio: "s2")
        let d = img("d", "2026-01-01T10:03:00Z", performers: ["p"], studio: "s2")
        #expect(ids(group([a, b, c, d])) == [["a", "b"], ["c"], ["d"]])
    }

    @Test func gapBoundaryAgainstLastImage() {
        let a = img("a", "2026-01-01T10:00:00Z", performers: ["p"])
        let b = img("b", "2026-01-01T10:10:00Z", performers: ["p"])
        let c = img("c", "2026-01-01T10:20:00Z", performers: ["p"])
        let d = img("d", "2026-01-01T10:30:01Z", performers: ["p"])
        #expect(ids(group([a, b, c, d])) == [["a", "b", "c"], ["d"]])
        #expect(group([a, b, c, d], gap: 2).count == 4)
        #expect(group([a, b, c, d], gap: 60).count == 1)
        #expect(ids(group([d, c, b, a])) == [["d"], ["c", "b", "a"]])
    }

    @Test func filenameFallbackAndMissingTimestamp() {
        let a = img("a", nil, performers: ["p"], basename: "042_-_2026-01-12_12-39-43_0.jpg")
        let b = img("b", "2026-01-12T12:41:00Z", performers: ["p"])
        let c = img("c", "garbage", performers: ["p"], basename: "wolke-2026-01-12_12-45-00_0.jpg")
        let d = img("d", nil, performers: ["p"])
        #expect(ids(group([a, b, c, d])) == [["a", "b", "c"], ["d"]])
    }

    @Test func setsAreCappedAtThirty() {
        let images = (0..<65).map { img("i\($0)", nil, galleries: ["g"]) }
        let posts = group(images)
        #expect(posts.map(\.images.count) == [30, 30, 5])
        #expect(posts.map(\.id) == ["set|i0", "set|i30", "set|i60"])
    }

    @Test func clipAndPhotoNeverShareASet() {
        let a = img("a", "2026-01-01T10:00:00Z", galleries: ["g"])
        let v = img("v", "2026-01-01T10:00:01Z", galleries: ["g"], video: true)
        let w = img("w", "2026-01-01T10:00:02Z", galleries: ["g"], video: true)
        #expect(ids(group([a, v, w])) == [["a"], ["v", "w"]])
    }

    @Test func unsupportedSortsAndOffKeepSingles() {
        let a = img("a", "2026-01-01T10:00:00Z", galleries: ["g"])
        let b = img("b", "2026-01-01T10:00:01Z", galleries: ["g"])
        for sort in [StashDBViewModel.ImageSortOption.dateAsc, .dateDesc, .createdAtAsc, .createdAtDesc] {
            #expect(group([a, b], sort: sort).count == 1)
        }
        for sort in [StashDBViewModel.ImageSortOption.titleAsc, .titleDesc, .random] {
            #expect(group([a, b], sort: sort).map(\.id) == ["single|a", "single|b"])
        }
        #expect(group([a, b], mode: .off).map(\.id) == ["single|a", "single|b"])
    }

    @Test func appendingAPageOnlyExtendsTheLastPost() {
        let page1 = [
            img("a", "2026-01-01T10:00:00Z", galleries: ["g1"]),
            img("b", "2026-01-01T10:00:01Z", galleries: ["g1"]),
            img("c", "2026-01-01T09:00:00Z", performers: ["p"]),
        ]
        let page2 = [
            img("d", "2026-01-01T09:01:00Z", performers: ["p"]),
            img("e", "2026-01-01T08:00:00Z", galleries: ["g1"]),
        ]
        let first = group(page1)
        let both = group(page1 + page2)
        #expect(first.map(\.id) == ["set|a", "single|c"])
        #expect(both.map(\.id) == ["set|a", "set|c", "single|e"])
        #expect(both[0].images.map(\.id) == first[0].images.map(\.id))
    }

    // MARK: - Settings

    @Test func migrationAndGapNormalization() {
        #expect(StashImageGroupingPrefs.migratedMode(legacyGroupSets: false) == .off)
        #expect(StashImageGroupingPrefs.migratedMode(legacyGroupSets: true) == .gallerySession)
        #expect(StashImageGroupingPrefs.migratedMode(legacyGroupSets: nil) == .gallerySession)
        #expect(StashImageGroupingPrefs.mode(fromRaw: "gallery") == .gallery)
        #expect(StashImageGroupingPrefs.mode(fromRaw: "bogus") == .gallerySession)
        #expect(StashImageGroupMode.allCases.map(\.rawValue) == ["off", "gallery", "gallerySession"])
        #expect(StashImageGroupingPrefs.normalizedGap(2) == 2)
        #expect(StashImageGroupingPrefs.normalizedGap(60) == 60)
        #expect(StashImageGroupingPrefs.normalizedGap(5) == 10)
        #expect(StashImageGroupingPrefs.normalizedGap(nil) == 10)
    }

    @Test func resolvedModeMigratesFromLegacyKey() {
        let suite = "stashy.tests.grouping.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(StashImageGroupingPrefs.resolvedModeRaw(defaults) == "gallerySession")
        defaults.removeObject(forKey: StashImageGroupingPrefs.modeKey)
        defaults.set(false, forKey: StashImageGroupingPrefs.legacySetsKey)
        #expect(StashImageGroupingPrefs.resolvedModeRaw(defaults) == "off")
        // Persisted: the legacy key no longer matters once the mode is stored.
        defaults.set(true, forKey: StashImageGroupingPrefs.legacySetsKey)
        #expect(StashImageGroupingPrefs.resolvedModeRaw(defaults) == "off")
    }

    // MARK: - Fixtures

    private func group(
        _ images: [StashImage],
        sort: StashDBViewModel.ImageSortOption = .dateDesc,
        mode: StashImageGroupMode = .gallerySession,
        gap: Int = 10
    ) -> [(id: String, images: [StashImage])] {
        StashImageSetGrouping.buildPosts(from: images, sort: sort, mode: mode, gapMinutes: gap)
    }

    private func ids(_ posts: [(id: String, images: [StashImage])]) -> [[String]] {
        posts.map { $0.images.map(\.id) }
    }

    private func img(
        _ id: String,
        _ createdAt: String?,
        performers: [String] = [],
        galleries: [String] = [],
        studio: String? = nil,
        basename: String? = nil,
        video: Bool = false
    ) -> StashImage {
        let name = basename ?? (video ? "\(id).mp4" : "\(id).jpg")
        return StashImage(
            id: id,
            title: nil,
            rating100: nil,
            o_counter: nil,
            organized: nil,
            date: nil,
            createdAt: createdAt,
            updatedAt: nil,
            paths: ImagePaths(thumbnail: nil, preview: nil, image: "/image/\(id)/image"),
            visual_files: [ImageFile(path: "/data/\(name)", height: 100, width: 100, duration: nil, basename: name)],
            performers: performers.map { GalleryPerformer(id: $0, name: $0, image_path: nil) },
            studio: studio.map { GalleryStudio(id: $0, name: $0) },
            galleries: galleries.map { ImageGallery(id: $0, title: $0) },
            tags: nil
        )
    }
}
