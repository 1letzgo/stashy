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
        #expect(StashyPlusManager.originalVersionEra("1") == .paid)
        #expect(StashyPlusManager.originalVersionEra("49") == .paid)
        #expect(StashyPlusManager.originalVersionEra("98") == .paid)
        #expect(StashyPlusManager.originalVersionEra("2.1") == .paid)
        #expect(StashyPlusManager.originalVersionEra("2.0.1") == .paid)
    }

    /// Builds 105/106 shipped in paid 1.4.5–2.2 *and* in free 3.0/3.1.
    @Test func buildsSharedByBothErasAreAmbiguous() {
        #expect(StashyPlusManager.originalVersionEra("100") == .ambiguous)
        #expect(StashyPlusManager.originalVersionEra("105") == .ambiguous)
        #expect(StashyPlusManager.originalVersionEra("106") == .ambiguous)
        #expect(StashyPlusManager.originalVersionEra("299") == .ambiguous)
    }

    @Test func freemiumVersionsAreNotPaid() {
        #expect(StashyPlusManager.originalVersionEra("300") == .freemium)
        #expect(StashyPlusManager.originalVersionEra("301") == .freemium)
        #expect(StashyPlusManager.originalVersionEra("3.0") == .freemium)
        #expect(StashyPlusManager.originalVersionEra("3.1") == .freemium)
        #expect(!StashyPlusManager.isLegacyPaidAppVersion("300"))
        #expect(!StashyPlusManager.isLegacyPaidAppVersion("3.1"))
    }

    /// Build 106 was the last one shared with a paid release. If a future build ever
    /// drops below `firstFreemiumBuild`, every new free download would be
    /// grandfathered into Lifetime.
    @Test func freemiumBuildThresholdClearsEveryShippedPaidBuild() {
        let highestPaidEraBuild = "106"
        #expect(StashyPlusManager.version(highestPaidEraBuild, isLessThan: StashyPlusManager.firstFreemiumBuild))
    }

    /// A paid buyer on build 106 must stay unlocked once the ambiguous range is
    /// resolved by the purchase date.
    @Test func paidBuyerOnSharedBuildIsUnlocked() {
        let decision = StashyPlusManager.legacyPaidAppDecision(
            environment: .production,
            originalAppVersion: "106",
            originalPurchaseDate: utcDate(2026, 5, 4),
            firstFreemiumReleaseDate: cutoff
        )
        #expect(decision == .yes)
    }

    @Test func freeDownloadOnSharedBuildStaysLocked() {
        let decision = StashyPlusManager.legacyPaidAppDecision(
            environment: .production,
            originalAppVersion: "106",
            originalPurchaseDate: utcDate(2026, 8, 15),
            firstFreemiumReleaseDate: cutoff
        )
        #expect(decision == .no)
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

    /// stashyTV shares the `de.letzgo.stashy` Universal Purchase and shipped build `1`.
    /// A free download that starts on Apple TV must not look like an early purchase.
    @Test func tvOSBuildOneAfterFreemiumLaunchStaysLocked() {
        let decision = StashyPlusManager.legacyPaidAppDecision(
            environment: .production,
            originalAppVersion: "1",
            originalPurchaseDate: utcDate(2026, 8, 30),
            firstFreemiumReleaseDate: cutoff
        )
        #expect(decision == .no)
    }

    @Test func tvOSBuildOneFromPaidEraIsUnlocked() {
        let decision = StashyPlusManager.legacyPaidAppDecision(
            environment: .production,
            originalAppVersion: "1",
            originalPurchaseDate: utcDate(2026, 2, 20),
            firstFreemiumReleaseDate: cutoff
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
