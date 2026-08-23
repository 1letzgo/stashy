//
//  InfrastructureTests.swift
//  stashyTests
//

import Testing
import Foundation
@testable import stashy

struct StashTrustDelegateTests {

    @Test func acceptsSelfSignedForLocalhostVariants() {
        #expect(StashTrustDelegate.acceptsSelfSigned(host: "localhost"))
        #expect(StashTrustDelegate.acceptsSelfSigned(host: "127.0.0.1"))
        #expect(StashTrustDelegate.acceptsSelfSigned(host: "::1"))
        #expect(StashTrustDelegate.acceptsSelfSigned(host: "mynas.local"))
    }

    @Test func acceptsSelfSignedForPrivateRanges() {
        #expect(StashTrustDelegate.acceptsSelfSigned(host: "10.0.0.5"))
        #expect(StashTrustDelegate.acceptsSelfSigned(host: "10.255.1.1"))
        #expect(StashTrustDelegate.acceptsSelfSigned(host: "192.168.1.50"))
        #expect(StashTrustDelegate.acceptsSelfSigned(host: "172.16.0.1"))
        #expect(StashTrustDelegate.acceptsSelfSigned(host: "172.31.255.255"))
    }

    @Test func rejectsPublicHostsOutsideWhitelist() {
        #expect(!StashTrustDelegate.acceptsSelfSigned(host: "example.com"))
        #expect(!StashTrustDelegate.acceptsSelfSigned(host: "8.8.8.8"))
        #expect(!StashTrustDelegate.acceptsSelfSigned(host: "172.32.0.1"))
        #expect(!StashTrustDelegate.acceptsSelfSigned(host: "172.15.0.1"))
        #expect(!StashTrustDelegate.acceptsSelfSigned(host: "11.0.0.1"))
        #expect(!StashTrustDelegate.acceptsSelfSigned(host: "193.168.1.1"))
    }

    @Test func acceptsExplicitlyWhitelistedHosts() {
        #expect(StashTrustDelegate.acceptsSelfSigned(host: "gole.tz"))
        #expect(StashTrustDelegate.acceptsSelfSigned(host: "GOLE.TZ"))
    }
}

struct GraphQLRetryTests {

    @Test func retriesDatabaseLockedThenSucceeds() async throws {
        actor Counter {
            var attempts = 0
            func next() -> Int { attempts += 1; return attempts }
        }
        let counter = Counter()

        let result = try await GraphQLClient.withDatabaseRetry {
            let attempt = await counter.next()
            if attempt < 3 { throw GraphQLClient.DatabaseLockedError() }
            return attempt
        }
        #expect(result == 3)
    }

    @Test func throwsAfterMaxAttempts() async {
        do {
            _ = try await GraphQLClient.withDatabaseRetry(maxAttempts: 3) {
                throw GraphQLClient.DatabaseLockedError()
            }
            Issue.record("Expected graphQLError to be thrown")
        } catch let error as GraphQLNetworkError {
            if case .graphQLError(let message) = error {
                #expect(message.contains("Database is locked"))
            } else {
                Issue.record("Unexpected error variant: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func doesNotRetryOtherErrors() async {
        struct OtherError: Error {}
        actor Counter {
            var attempts = 0
            func next() -> Int { attempts += 1; return attempts }
        }
        let counter = Counter()

        do {
            _ = try await GraphQLClient.withDatabaseRetry {
                let attempt = await counter.next()
                throw OtherError()
            }
            Issue.record("Expected OtherError to be thrown")
        } catch is GraphQLClient.DatabaseLockedError {
            Issue.record("OtherError must not be swallowed")
        } catch is OtherError {
            let attempts = await counter.attempts
            #expect(attempts == 1)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

struct PerformerAgeFilterSupportTests {

    @Test func betweenRangesContainBothBounds() {
        let filter = PerformerAgeFilterSupport.birthdateFilter(for: "18-21")
        #expect(filter?["modifier"] as? String == "BETWEEN")
        #expect(filter?["value"] != nil)
        #expect(filter?["value2"] != nil)
    }

    @Test func thirtyPlusUsesLessThan() {
        let filter = PerformerAgeFilterSupport.birthdateFilter(for: "30+")
        #expect(filter?["modifier"] as? String == "LESS_THAN")
        #expect(filter?["value2"] == nil)
    }

    @Test func unknownRangeReturnsNil() {
        #expect(PerformerAgeFilterSupport.birthdateFilter(for: "13-17") == nil)
    }
}

struct AppLogRedactionTests {

    @Test func redactsSecretContent() {
        let output = AppLog.redacted("super-secret-api-key-123", label: "ApiKey")
        #expect(!output.contains("super-secret"))
        #expect(output.contains("ApiKey"))
        #expect(output.contains("chars"))
    }

    @Test func handlesEmptyAndNil() {
        #expect(AppLog.redacted(nil, label: "K") == "K<empty>")
        #expect(AppLog.redacted("", label: "K") == "K<empty>")
    }
}

@MainActor
struct PaginatedLoaderGenerationTests {

    @Test func refreshInvalidatesInFlightLoadMore() async {
        actor CallTracker {
            var loadMoreStarted = false
            var loadMoreAborted = false
            func markStarted() { loadMoreStarted = true }
            func markAborted() { loadMoreAborted = true }
        }

        let tracker = CallTracker()
        let loader = PaginatedLoader<Int>(perPage: 2) { page, _ in
            if page == 1 {
                return ([1, 2], 10)
            }
            await tracker.markStarted()
            // Simulate a slow page-2 fetch that gets invalidated by a concurrent refresh.
            try await Task.sleep(nanoseconds: 200_000_000)
            await tracker.markAborted()
            return ([3, 4], 10)
        }

        _ = await loader.loadInitial()
        #expect(loader.items.count == 2)
        #expect(loader.hasMore)

        async let more: Void = loader.loadMore()
        // Give loadMore time to start its fetch, then refresh underneath it.
        try? await Task.sleep(nanoseconds: 30_000_000)
        await loader.refresh()
        await more

        let aborted = await tracker.loadMoreAborted
        #expect(aborted)
        #expect(loader.items.count == 2)
        #expect(loader.isLoadingMore == false)
    }

    @Test func resetClearsStateAndInvalidatesFetches() async {
        let loader = PaginatedLoader<Int>(perPage: 2) { _, _ in
            try await Task.sleep(nanoseconds: 150_000_000)
            return ([1, 2], 4)
        }

        async let initial: Void = loader.loadInitial()
        try? await Task.sleep(nanoseconds: 20_000_000)
        loader.reset()
        await initial

        #expect(loader.items.isEmpty)
        #expect(loader.hasMore)
        #expect(loader.isLoading == false)
    }
}
