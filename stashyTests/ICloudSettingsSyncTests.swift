//
//  ICloudSettingsSyncTests.swift
//  stashyTests
//
//  The pure parts of the iCloud settings sync: the three-way merge, the key-value store quota
//  and the lifetime of deletion markers.
//  Note: wire into the stashyTests target in Xcode if it is not already compiled.

import Foundation
import Testing
@testable import stashy

struct ICloudSettingsSyncTests {

    // MARK: - Merge

    @Test func emptyStoreNeverDeletes() {
        #expect(ICloudSettingsMerge.action(local: "a", remote: nil, remoteIsDeletion: false, base: "a") == .pushLocal)
        #expect(ICloudSettingsMerge.action(local: nil, remote: nil, remoteIsDeletion: false, base: "a") == .none)
    }

    @Test func deletionOnlyRemovesAnUntouchedCopy() {
        #expect(ICloudSettingsMerge.action(local: "a", remote: "x", remoteIsDeletion: true, base: "a") == .applyRemoteDeletion)
        #expect(ICloudSettingsMerge.action(local: "b", remote: "x", remoteIsDeletion: true, base: "a") == .pushLocal)
        #expect(ICloudSettingsMerge.action(local: nil, remote: "x", remoteIsDeletion: true, base: nil) == .none)
    }

    @Test func localChangesAndDeletions() {
        #expect(ICloudSettingsMerge.action(local: "b", remote: "a", remoteIsDeletion: false, base: "a") == .pushLocal)
        #expect(ICloudSettingsMerge.action(local: nil, remote: "a", remoteIsDeletion: false, base: "a") == .pushLocalDeletion)
        #expect(ICloudSettingsMerge.action(local: nil, remote: "a", remoteIsDeletion: false, base: nil) == .applyRemote)
        #expect(ICloudSettingsMerge.action(local: "b", remote: "c", remoteIsDeletion: false, base: "a") == .applyRemote)
        #expect(ICloudSettingsMerge.action(local: "a", remote: "a", remoteIsDeletion: false, base: nil) == .none)
    }

    // MARK: - Quota

    @Test func countsKeyNamesWithValues() {
        let quota = ICloudSettingsQuota(entries: ["ab": "1234"])
        #expect(quota.usedBytes == 6)
        #expect(quota.usedKeys == 1)
    }

    @Test func rejectsAnEntryAboveTheEntryLimit() {
        var quota = ICloudSettingsQuota()
        quota.maxEntryBytes = 10
        #expect(!quota.take("k", String(repeating: "x", count: 10)))
        #expect(quota.take("k", String(repeating: "x", count: 9)))
        #expect(quota.usedBytes == 10)
    }

    @Test func replacingAnEntryCountsOnlyTheDifference() {
        var quota = ICloudSettingsQuota(entries: ["k": "12345"])
        quota.maxTotalBytes = 8
        #expect(quota.take("k", "1234567"))
        #expect(quota.usedBytes == 8)
        #expect(!quota.take("k", "12345678"))
        #expect(quota.usedBytes == 8)
    }

    @Test func keyLimitAppliesToNewKeysOnly() {
        var quota = ICloudSettingsQuota(entries: ["a": "1", "b": "1"])
        quota.maxKeyCount = 2
        #expect(!quota.take("c", "1"))
        #expect(quota.take("a", "2"))
        quota.remove("b")
        #expect(quota.take("c", "1"))
        #expect(quota.usedKeys == 2)
        #expect(quota.isWithinLimits)
    }

    @Test func pushOrderPutsServersThenSmallValuesFirst() {
        let ordered = ICloudSettingsQuota.pushOrder(
            [(key: "s.big", value: "xxxxxx"), (key: "s.small", value: "x"), (key: "server.1", value: "xxxxxxxxxx")],
            isServer: { $0.hasPrefix("server.") }
        )
        #expect(ordered.map(\.key) == ["server.1", "s.small", "s.big"])
    }

    @Test func pushOrderFitsTheMostEntries() {
        var quota = ICloudSettingsQuota()
        quota.maxTotalBytes = 20
        let pushes = [(key: "a", value: String(repeating: "x", count: 15)), (key: "b", value: "xx"), (key: "c", value: "xx")]
        var kept = 0
        for (key, value) in ICloudSettingsQuota.pushOrder(pushes, isServer: { _ in false }) {
            if !quota.take(key, value) { kept += 1 }
        }
        #expect(kept == 1)
        #expect(quota.entrySizes["a"] == nil)
    }

    // MARK: - Deletion markers

    @Test func markerLifetime() {
        let day = 86_400.0
        let now = 1_000 * day
        #expect(ICloudDeletionMarker.state(deletedAt: nil, now: now) == .undated)
        #expect(ICloudDeletionMarker.state(deletedAt: 0, now: now) == .undated)
        #expect(ICloudDeletionMarker.state(deletedAt: now - 10 * day, now: now) == .live)
        #expect(ICloudDeletionMarker.state(deletedAt: now - 91 * day, now: now) == .expired)
    }

    // MARK: - What syncs

    @Test func growingStateStaysOnTheDevice() {
        let server = UUID().uuidString
        #expect(!SettingsTransfer.isSyncable("scene_watchlist_\(server)"))
        #expect(!SettingsTransfer.isSyncable("last_played_hidden_\(server)"))
        #expect(!SettingsTransfer.isSyncable("mini_player_last_\(server)"))
        #expect(!SettingsTransfer.isSyncable("recommendations_last_picks_\(server)"))
        #expect(SettingsTransfer.isSyncable("HomeRowsConfig_\(server)"))
        #expect(SettingsTransfer.isSyncable("recommendations_adjustments_\(server)"))
    }
}
