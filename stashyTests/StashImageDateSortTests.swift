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
}
