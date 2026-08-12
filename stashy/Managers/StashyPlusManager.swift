//
//  StashyPlusManager.swift
//  stashy
//
//  Entitlement gate for Stashy+ (AI subtitles, Downloads, Match, RateMe, StashSync).
//  Unlocked via subscription, lifetime IAP, legacy paid-app purchase, or prior tip jar.
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

    /// Retired tip-jar consumables — still grant lifetime if found in purchase history.
    static let legacyTipIDs: Set<String> = [
        "de.stashy.tip1",
        "de.stashy.tip2",
        "de.stashy.tip3",
    ]

    static let displayNames: [String: String] = [
        monthly: "Monthly",
        yearly: "Yearly",
        lifetime: "Lifetime",
    ]

    static let sortOrder: [String: Int] = [
        monthly: 0,
        yearly: 1,
        lifetime: 2,
    ]
}

enum StashyPlusSource: String, Equatable {
    case none
    case subscription
    case lifetime
    case legacyPaidApp
    case legacyTip

    var statusTitle: String {
        switch self {
        case .none: return "Not unlocked"
        case .subscription: return "Stashy+ active"
        case .lifetime: return "Stashy+ Lifetime"
        case .legacyPaidApp: return "Stashy+ Lifetime"
        case .legacyTip: return "Stashy+ Lifetime"
        }
    }

    var statusDetail: String {
        switch self {
        case .none:
            return "Subscribe or buy Lifetime to unlock premium features."
        case .subscription:
            return "Thanks for supporting stashy."
        case .lifetime:
            return "Unlocked forever on this Apple ID."
        case .legacyPaidApp:
            return "Included because you bought stashy at full price."
        case .legacyTip:
            return "Included from your earlier tip — thank you!"
        }
    }
}

/// Central gate for Stashy+ features.
@MainActor
final class StashyPlusManager: ObservableObject {
    static let shared = StashyPlusManager()

    /// Permanent unlock (lifetime IAP, paid-app grandfathering, or migrated tip jar).
    nonisolated static let lifetimeKey = "stashy_plus_lifetime"
    /// Legacy tip-era flag — treated as lifetime.
    nonisolated static let unlockedKey = "stashy_plus_unlocked"
    nonisolated static let tipsCountKey = "totalTipsCount"
    nonisolated static let subscriptionExpirationKey = "stashy_plus_subscription_expiration"
    nonisolated static let activeProductIDKey = "stashy_plus_active_product_id"
    nonisolated static let sourceKey = "stashy_plus_source"
    /// TestFlight-only: keep UI locked even if StoreKit would re-grant access.
    nonisolated static let debugForceLockedKey = "stashy_plus_debug_force_locked"

    /// First freemium **build** (`CFBundleVersion` / `CURRENT_PROJECT_VERSION`).
    /// On iOS, `AppTransaction.originalAppVersion` is the original build number —
    /// not the marketing version. Buyers with a lower original build get Lifetime.
    /// Sandbox / TestFlight always report `"1.0"` and must be ignored.
    nonisolated static let firstFreemiumBuild = "100"

    @Published private(set) var isUnlocked: Bool
    @Published private(set) var source: StashyPlusSource
    @Published private(set) var activeProductID: String?
    @Published private(set) var subscriptionExpiration: Date?

    var hasStashyPlus: Bool { isUnlocked }
    var hasLifetime: Bool {
        if UserDefaults.standard.bool(forKey: Self.debugForceLockedKey) { return false }
        return source == .lifetime || source == .legacyPaidApp || source == .legacyTip
            || UserDefaults.standard.bool(forKey: Self.lifetimeKey)
            || UserDefaults.standard.bool(forKey: Self.unlockedKey)
            || UserDefaults.standard.integer(forKey: Self.tipsCountKey) > 0
    }

    /// Whether the paywall / plan list should be shown.
    var shouldOfferPurchases: Bool {
        if UserDefaults.standard.bool(forKey: Self.debugForceLockedKey) { return true }
        if !isUnlocked { return true }
        // Subscribers can still buy Lifetime.
        return source == .subscription
    }

    /// Thread-safe read for non-`MainActor` call sites.
    nonisolated static var isUnlockedNow: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: debugForceLockedKey) { return false }
        if defaults.bool(forKey: lifetimeKey)
            || defaults.bool(forKey: unlockedKey)
            || defaults.integer(forKey: tipsCountKey) > 0 {
            return true
        }
        let exp = defaults.double(forKey: subscriptionExpirationKey)
        return exp > Date().timeIntervalSince1970
    }

    private init() {
        let defaults = UserDefaults.standard
        // Migrate tip-era unlock → lifetime.
        if defaults.bool(forKey: Self.unlockedKey) || defaults.integer(forKey: Self.tipsCountKey) > 0 {
            defaults.set(true, forKey: Self.lifetimeKey)
            if defaults.string(forKey: Self.sourceKey) == nil {
                defaults.set(StashyPlusSource.legacyTip.rawValue, forKey: Self.sourceKey)
            }
        }

        let storedSource = StashyPlusSource(rawValue: defaults.string(forKey: Self.sourceKey) ?? "") ?? .none
        self.source = storedSource
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

    /// Apply a verified StoreKit entitlement snapshot.
    func applyStoreEntitlements(
        hasLifetimePurchase: Bool,
        subscriptionProductID: String?,
        subscriptionExpiration: Date?,
        legacyPaidApp: Bool,
        legacyTip: Bool
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

        let permanent = hasLifetimePurchase || legacyPaidApp || legacyTip
            || defaults.bool(forKey: Self.lifetimeKey)
            || defaults.bool(forKey: Self.unlockedKey)
            || defaults.integer(forKey: Self.tipsCountKey) > 0

        if permanent {
            defaults.set(true, forKey: Self.lifetimeKey)
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
        } else if legacyTip || defaults.bool(forKey: Self.unlockedKey) || defaults.integer(forKey: Self.tipsCountKey) > 0 {
            newSource = .legacyTip
        } else if subActive {
            newSource = .subscription
        } else if permanent {
            newSource = StashyPlusSource(rawValue: defaults.string(forKey: Self.sourceKey) ?? "") ?? .lifetime
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

    /// Permanent unlock after lifetime IAP (or migrated tip).
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

    /// @available backward-compatible alias used by older call sites.
    func unlockFromTip(incrementCount: Bool = true) {
        if incrementCount {
            let tips = UserDefaults.standard.integer(forKey: Self.tipsCountKey)
            UserDefaults.standard.set(tips + 1, forKey: Self.tipsCountKey)
        }
        UserDefaults.standard.set(true, forKey: Self.unlockedKey)
        unlockLifetime(source: .legacyTip)
    }

    func unlockFromExistingPurchase() {
        unlockLifetime(source: .lifetime)
    }

    nonisolated static func isLegacyPaidAppVersion(_ originalAppVersion: String) -> Bool {
        version(originalAppVersion, isLessThan: firstFreemiumBuild)
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

    /// TestFlight helper: clear local unlock and keep the paywall locked until the next purchase.
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

    /// Clears TestFlight force-lock (e.g. before Restore or after a fresh purchase).
    func clearDebugForceLock() {
        UserDefaults.standard.set(false, forKey: Self.debugForceLockedKey)
    }
}

extension Notification.Name {
    static let stashyPlusUnlocked = Notification.Name("StashyPlusUnlocked")
}
#endif
