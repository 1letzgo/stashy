//
//  StashyPlusManager.swift
//  stashy
//
//  Entitlement gate for stashy+ (AI subtitles, Downloads, Advanced Statistics, Match, RateMe, AI Motion, App Icon).
//  Unlocked via subscription, lifetime IAP, or a paid App Store purchase before 3.0.
//  Tips never grant stashy+.
//

#if !os(tvOS)
import Foundation
import Combine
import StoreKit

enum StashyPlusProduct {
    static let monthly = "de.stashy.plus.m"
    static let yearly = "de.stashy.plus.y"
    static let lifetime = "de.stashy.plus.l"

    static let allIDs: Set<String> = [monthly, yearly, lifetime]
    static let subscriptionIDs: Set<String> = [monthly, yearly]

    static let tipSmall = "de.stashy.tip1"
    static let tipMedium = "de.stashy.tip2"
    static let tipLarge = "de.stashy.tip3"

    /// Consumable tips — thank-you only, never grant stashy+.
    static let tipIDs: Set<String> = [tipSmall, tipMedium, tipLarge]
    static let legacyTipIDs: Set<String> = tipIDs

    static let displayNames: [String: String] = [
        monthly: "Monthly",
        yearly: "Yearly",
        lifetime: "Lifetime",
        tipSmall: "Small",
        tipMedium: "Medium",
        tipLarge: "Large",
    ]

    static let sortOrder: [String: Int] = [
        monthly: 0,
        yearly: 1,
        lifetime: 2,
        tipSmall: 0,
        tipMedium: 1,
        tipLarge: 2,
    ]
}

enum StashyPlusSource: String, Equatable {
    case none
    case subscription
    case lifetime
    case legacyPaidApp
    /// Stored by older builds that unlocked from tips — treated as locked.
    case legacyTip

    var statusTitle: String {
        switch self {
        case .none, .legacyTip: return "Not unlocked"
        case .subscription: return "stashy+ active"
        case .lifetime: return "stashy+ Lifetime"
        case .legacyPaidApp: return "stashy+ Lifetime"
        }
    }

    var statusDetail: String {
        switch self {
        case .none, .legacyTip:
            return "Subscribe or buy Lifetime to unlock premium features."
        case .subscription:
            return "Thanks for supporting stashy."
        case .lifetime:
            return "Unlocked forever on this Apple ID."
        case .legacyPaidApp:
            return "Included because you bought stashy at full price before 3.0."
        }
    }
}

/// Central gate for stashy+ features.
@MainActor
final class StashyPlusManager: ObservableObject {
    static let shared = StashyPlusManager()

    /// Permanent unlock (lifetime IAP or paid-app grandfathering).
    nonisolated static let lifetimeKey = "stashy_plus_lifetime"
    /// Legacy tip-era flag — no longer grants access.
    nonisolated static let unlockedKey = "stashy_plus_unlocked"
    nonisolated static let tipsCountKey = "totalTipsCount"
    nonisolated static let subscriptionExpirationKey = "stashy_plus_subscription_expiration"
    nonisolated static let activeProductIDKey = "stashy_plus_active_product_id"
    nonisolated static let sourceKey = "stashy_plus_source"
    /// Debug helper: keep the paywall locked even if StoreKit would re-grant access.
    nonisolated static let debugForceLockedKey = "stashy_plus_debug_force_locked"

    /// First freemium release is **3.0**. Every App Store purchase before that was paid
    /// and gets stashy+ Lifetime.
    ///
    /// On iOS, `AppTransaction.originalAppVersion` is `CFBundleVersion` (build), not
    /// the marketing version. Pre-3.0 binaries used build `1`; 3.0 starts at `100`.
    /// Marketing strings (`2.1`, `2.0.1`) are compared against `3.0` so a reported
    /// `"3.0"` is not treated as paid (which a naive `< 100` check would do).
    /// Sandbox always reports `"1.0"` and must be ignored.
    nonisolated static let firstFreemiumMarketingVersion = "3.0"
    nonisolated static let firstFreemiumBuild = "100"

    @Published private(set) var isUnlocked: Bool
    @Published private(set) var source: StashyPlusSource
    @Published private(set) var activeProductID: String?
    @Published private(set) var subscriptionExpiration: Date?

    var hasStashyPlus: Bool { isUnlocked }
    var hasLifetime: Bool {
        if UserDefaults.standard.bool(forKey: Self.debugForceLockedKey) { return false }
        return source == .lifetime || source == .legacyPaidApp
            || (UserDefaults.standard.bool(forKey: Self.lifetimeKey) && Self.storedSourceGrantsLifetime)
    }

    /// Whether the paywall / plan list should be shown.
    var shouldOfferPurchases: Bool {
        if UserDefaults.standard.bool(forKey: Self.debugForceLockedKey) { return true }
        if !isUnlocked { return true }
        // Subscribers can still buy Lifetime.
        return source == .subscription
    }

    private static var storedSourceGrantsLifetime: Bool {
        let raw = UserDefaults.standard.string(forKey: sourceKey) ?? ""
        let stored = StashyPlusSource(rawValue: raw) ?? .none
        return stored == .lifetime || stored == .legacyPaidApp
    }

    /// Thread-safe read for non-`MainActor` call sites.
    nonisolated static var isUnlockedNow: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: debugForceLockedKey) { return false }
        let stored = StashyPlusSource(rawValue: defaults.string(forKey: sourceKey) ?? "") ?? .none
        if defaults.bool(forKey: lifetimeKey), stored == .lifetime || stored == .legacyPaidApp {
            return true
        }
        let exp = defaults.double(forKey: subscriptionExpirationKey)
        return exp > Date().timeIntervalSince1970
    }

    private init() {
        let defaults = UserDefaults.standard
        Self.revokeTipEraUnlockIfNeeded()

        let storedSource = StashyPlusSource(rawValue: defaults.string(forKey: Self.sourceKey) ?? "") ?? .none
        self.source = storedSource == .legacyTip ? .none : storedSource
        self.activeProductID = defaults.string(forKey: Self.activeProductIDKey)
        let exp = defaults.double(forKey: Self.subscriptionExpirationKey)
        self.subscriptionExpiration = exp > 0 ? Date(timeIntervalSince1970: exp) : nil
        if defaults.bool(forKey: Self.debugForceLockedKey) {
            self.source = .none
            self.isUnlocked = false
        } else {
            self.isUnlocked = Self.isUnlockedNow
        }
    }

    /// Tips must not keep stashy+ from older builds.
    nonisolated private static func revokeTipEraUnlockIfNeeded() {
        let defaults = UserDefaults.standard
        let stored = StashyPlusSource(rawValue: defaults.string(forKey: sourceKey) ?? "") ?? .none
        let tipFlag = defaults.bool(forKey: unlockedKey) || defaults.integer(forKey: tipsCountKey) > 0
        guard stored == .legacyTip || (tipFlag && stored != .lifetime && stored != .legacyPaidApp && stored != .subscription) else {
            return
        }
        defaults.set(false, forKey: lifetimeKey)
        defaults.set(false, forKey: unlockedKey)
        defaults.set(StashyPlusSource.none.rawValue, forKey: sourceKey)
        if stored == .legacyTip {
            defaults.removeObject(forKey: activeProductIDKey)
        }
    }

    /// Apply a verified StoreKit entitlement snapshot.
    func applyStoreEntitlements(
        hasLifetimePurchase: Bool,
        subscriptionProductID: String?,
        subscriptionExpiration: Date?,
        legacyPaidApp: Bool
    ) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.debugForceLockedKey) {
            source = .none
            activeProductID = nil
            self.subscriptionExpiration = nil
            isUnlocked = false
            objectWillChange.send()
            return
        }

        let stored = StashyPlusSource(rawValue: defaults.string(forKey: Self.sourceKey) ?? "") ?? .none
        let persistedPaidLifetime = defaults.bool(forKey: Self.lifetimeKey)
            && (stored == .lifetime || stored == .legacyPaidApp)
        let permanent = hasLifetimePurchase || legacyPaidApp || persistedPaidLifetime

        if permanent {
            defaults.set(true, forKey: Self.lifetimeKey)
        } else {
            defaults.set(false, forKey: Self.lifetimeKey)
        }

        let subActive: Bool = {
            guard let subscriptionExpiration else { return false }
            return subscriptionExpiration > Date()
        }()

        if subActive, let subscriptionExpiration {
            defaults.set(subscriptionExpiration.timeIntervalSince1970, forKey: Self.subscriptionExpirationKey)
            defaults.set(subscriptionProductID, forKey: Self.activeProductIDKey)
        } else if !permanent {
            defaults.set(0, forKey: Self.subscriptionExpirationKey)
            defaults.removeObject(forKey: Self.activeProductIDKey)
        }

        let newSource: StashyPlusSource
        if hasLifetimePurchase {
            newSource = .lifetime
        } else if legacyPaidApp {
            newSource = .legacyPaidApp
        } else if subActive {
            newSource = .subscription
        } else if permanent {
            newSource = stored == .legacyPaidApp ? .legacyPaidApp : .lifetime
        } else {
            newSource = .none
        }

        defaults.set(newSource.rawValue, forKey: Self.sourceKey)

        let wasUnlocked = isUnlocked
        source = newSource
        activeProductID = permanent
            ? (hasLifetimePurchase ? StashyPlusProduct.lifetime : activeProductID)
            : (subActive ? subscriptionProductID : nil)
        self.subscriptionExpiration = subActive ? subscriptionExpiration : nil
        isUnlocked = permanent || subActive
        objectWillChange.send()

        if isUnlocked, !wasUnlocked {
            NotificationCenter.default.post(name: .stashyPlusUnlocked, object: nil)
        }
    }

    /// Permanent unlock after lifetime IAP.
    func unlockLifetime(source newSource: StashyPlusSource = .lifetime) {
        let defaults = UserDefaults.standard
        clearDebugForceLock()
        defaults.set(true, forKey: Self.lifetimeKey)
        defaults.set(newSource.rawValue, forKey: Self.sourceKey)
        if newSource == .lifetime {
            defaults.set(StashyPlusProduct.lifetime, forKey: Self.activeProductIDKey)
        }

        let wasUnlocked = isUnlocked
        source = newSource
        if newSource == .lifetime {
            activeProductID = StashyPlusProduct.lifetime
        }
        isUnlocked = true
        objectWillChange.send()
        if !wasUnlocked {
            NotificationCenter.default.post(name: .stashyPlusUnlocked, object: nil)
        }
    }

    /// Record a consumable tip. Does **not** unlock stashy+.
    func recordTip(incrementCount: Bool = true) {
        if incrementCount {
            let tips = UserDefaults.standard.integer(forKey: Self.tipsCountKey)
            UserDefaults.standard.set(tips + 1, forKey: Self.tipsCountKey)
        }
    }

    /// @available backward-compatible alias — tips never grant access.
    func unlockFromTip(incrementCount: Bool = true) {
        recordTip(incrementCount: incrementCount)
    }

    func unlockFromExistingPurchase() {
        unlockLifetime(source: .lifetime)
    }

    /// `true` when the customer's original App Store version was a paid build (before 3.0).
    nonisolated static func isLegacyPaidAppVersion(_ originalAppVersion: String) -> Bool {
        let raw = originalAppVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        if raw.contains(".") {
            return version(raw, isLessThan: firstFreemiumMarketingVersion)
        }
        return version(raw, isLessThan: firstFreemiumBuild)
    }

    nonisolated static func version(_ lhs: String, isLessThan rhs: String) -> Bool {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let ai = i < a.count ? a[i] : 0
            let bi = i < b.count ? b[i] : 0
            if ai != bi { return ai < bi }
        }
        return false
    }

    /// Debug helper: clear local unlock and keep the paywall locked until the next purchase.
    func resetUnlockForTesting() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.debugForceLockedKey)
        defaults.set(false, forKey: Self.lifetimeKey)
        defaults.set(false, forKey: Self.unlockedKey)
        defaults.set(0, forKey: Self.tipsCountKey)
        defaults.set(0, forKey: Self.subscriptionExpirationKey)
        defaults.removeObject(forKey: Self.activeProductIDKey)
        defaults.set(StashyPlusSource.none.rawValue, forKey: Self.sourceKey)
        source = .none
        activeProductID = nil
        subscriptionExpiration = nil
        isUnlocked = false
        objectWillChange.send()
    }

    /// Clears debug force-lock (e.g. before Restore or after a fresh purchase).
    func clearDebugForceLock() {
        UserDefaults.standard.set(false, forKey: Self.debugForceLockedKey)
    }
}

extension Notification.Name {
    static let stashyPlusUnlocked = Notification.Name("StashyPlusUnlocked")
}
#endif
