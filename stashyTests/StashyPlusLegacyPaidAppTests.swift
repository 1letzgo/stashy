//
//  StashyPlusLegacyPaidAppTests.swift
//  stashyTests
//
//  Note: wire into the stashyTests target in Xcode if it is not already compiled.
//

import Testing
import Foundation
import StoreKit
@testable import stashy

struct StashyPlusLegacyPaidAppTests {

    private var cutoff: Date { StashyPlusManager.utcDate(year: 2026, month: 8, day: 1) }

    @Test func paidBuildNumbers() {
        #expect(StashyPlusManager.isLegacyPaidAppVersion("1"))
        #expect(StashyPlusManager.isLegacyPaidAppVersion("99"))
    }

    @Test func freemiumVersionsAreNotPaid() {
        #expect(!StashyPlusManager.isLegacyPaidAppVersion("100"))
        #expect(!StashyPlusManager.isLegacyPaidAppVersion("3.0"))
        #expect(!StashyPlusManager.isLegacyPaidAppVersion("3.1"))
    }

    @Test func sandboxOnePointZeroIsNotPaid() {
        let decision = StashyPlusManager.legacyPaidAppDecision(
            environment: .sandbox,
            originalAppVersion: "1.0",
            originalPurchaseDate: utcDate(2025, 1, 1),
            firstFreemiumReleaseDate: cutoff
        )
        #expect(decision == .no)
    }

    @Test func xcodeEnvironmentIsNotPaid() {
        let decision = StashyPlusManager.legacyPaidAppDecision(
            environment: .xcode,
            originalAppVersion: "1",
            originalPurchaseDate: utcDate(2025, 1, 1),
            firstFreemiumReleaseDate: cutoff
        )
        #expect(decision == .no)
    }

    @Test func productionLegacyBuildIsPaid() {
        let decision = StashyPlusManager.legacyPaidAppDecision(
            environment: .production,
            originalAppVersion: "1",
            originalPurchaseDate: nil
        )
        #expect(decision == .yes)
    }

    @Test func productionPollutedVersionBeforeCutoffIsPaid() {
        let decision = StashyPlusManager.legacyPaidAppDecision(
            environment: .production,
            originalAppVersion: "120",
            originalPurchaseDate: utcDate(2026, 5, 4),
            firstFreemiumReleaseDate: cutoff
        )
        #expect(decision == .yes)
    }

    @Test func productionPollutedVersionAfterCutoffIsNotPaid() {
        let decision = StashyPlusManager.legacyPaidAppDecision(
            environment: .production,
            originalAppVersion: "120",
            originalPurchaseDate: utcDate(2026, 8, 15),
            firstFreemiumReleaseDate: cutoff
        )
        #expect(decision == .no)
    }

    @Test func dateFallbackDisabledWithoutCutoff() {
        let decision = StashyPlusManager.legacyPaidAppDecision(
            environment: .production,
            originalAppVersion: "120",
            originalPurchaseDate: utcDate(2026, 5, 4),
            firstFreemiumReleaseDate: nil
        )
        #expect(decision == .no)
    }

    @Test func shippedCutoffUnlocksPollutedVersionFromPaidEra() {
        guard let shipped = StashyPlusManager.firstFreemiumReleaseDate else {
            Issue.record("firstFreemiumReleaseDate must be set so TestFlight-polluted App Store buyers get Lifetime")
            return
        }
        let decision = StashyPlusManager.legacyPaidAppDecision(
            environment: .production,
            originalAppVersion: "120",
            originalPurchaseDate: shipped.addingTimeInterval(-86_400)
        )
        #expect(decision == .yes)
    }

    @Test func shippedCutoffDoesNotUnlockFreemiumDownload() {
        guard let shipped = StashyPlusManager.firstFreemiumReleaseDate else {
            Issue.record("firstFreemiumReleaseDate must be set")
            return
        }
        let decision = StashyPlusManager.legacyPaidAppDecision(
            environment: .production,
            originalAppVersion: "120",
            originalPurchaseDate: shipped.addingTimeInterval(86_400)
        )
        #expect(decision == .no)
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        StashyPlusManager.utcDate(year: year, month: month, day: day)
    }
}
