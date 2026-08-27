//
//  StashyPlusManager.swift
//  stashy
//
//  Entitlement gate for stashy+ (AI subtitles, Downloads, Advanced Statistics, Match, RateMe, AI Motion, App Icon, Channels).
//  Unlocked via subscription, lifetime IAP, or a paid App Store purchase before 3.0.
//  Tips never grant stashy+.
//

import Foundation
import Combine
import StoreKit

/// `nonisolated`: reine Konstanten, werden auch aus `Task.detached` gelesen.
nonisolated enum StashyPlusProduct {
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
    /// Nur bei lokalem Start aus Xcode. Wird nie gespeichert — siehe
    /// `StashyPlusManager.localUnlockActive`.
    case localDevelopment

    var statusTitle: String {
        switch self {
        case .none, .legacyTip: return "Not unlocked"
        case .localDevelopment: return "stashy+ (Local Build)"
        case .subscription: return "stashy+ active"
        case .lifetime: return "stashy+ Lifetime"
        case .legacyPaidApp: return "stashy+ Lifetime"
        }
    }

    var statusDetail: String {
        switch self {
        case .none, .legacyTip:
            return "Subscribe or buy Lifetime to unlock premium features."
        case .localDevelopment:
            return "Unlocked automatically because the app was launched from Xcode. Not active in any distributed build."
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

    /// First freemium release is **3.0**. Every **App Store** purchase before that
    /// was paid and gets stashy+ Lifetime.
    ///
    /// On iOS, `AppTransaction.originalAppVersion` is `CFBundleVersion` (build), not
    /// the marketing version. `CFBundleVersion` was hardcoded in `Info.plist` and
    /// stayed at `106` from April 2026 (marketing 1.4.5) through the freemium 3.0 and
    /// 3.1 releases, so **builds 100…299 do not identify the era on their own** — the
    /// paid 1.x/2.x releases and the free 3.0/3.1 releases share them. Only
    /// `originalPurchaseDate` separates those two groups.
    ///
    /// Builds below `firstAmbiguousBuild` shipped exclusively in paid releases, and
    /// builds from `firstFreemiumBuild` on ship exclusively after this fix, so both
    /// ends are decided by version alone. macOS reports marketing strings (`2.1`),
    /// which are compared against `3.0` instead. Sandbox / Xcode always report `"1.0"`
    /// and must be ignored — TestFlight-only installs are not App Store purchases.
    nonisolated static let firstFreemiumMarketingVersion = "3.0"
    /// Lowest build that a freemium release ever shipped with (see `Info.plist`).
    /// Everything from here on is unambiguously post-paid-era.
    nonisolated static let firstFreemiumBuild = "300"
    /// Lowest build that both a paid and a freemium release shipped with.
    /// Builds below this are unambiguously paid-era.
    nonisolated static let firstAmbiguousBuild = "100"
    /// Calendar day the freemium 3.0 listing went live on the App Store (UTC).
    ///
    /// This is the decisive signal, so it is deliberately rounded **up**: 3.0 went live
    /// somewhere between 2026-08-21 and 2026-08-23, and the 24th covers that whole
    /// window. Erring late costs at most a handful of free downloads from those three
    /// days; erring early would lock paying customers out of what they bought.
    nonisolated static let firstFreemiumReleaseDate: Date? = utcDate(year: 2026, month: 8, day: 24)

    /// Which pricing era an `originalAppVersion` belongs to.
    nonisolated enum OriginalVersionEra: Equatable, Sendable {
        case paid
        case freemium
        /// Build number reused across both eras — only the purchase date can decide.
        case ambiguous
    }

    nonisolated static func utcDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    nonisolated enum LegacyPaidAppDecision: Equatable, Sendable {
        case yes
        case no
    }

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
        // Der Kaufweg muss lokal weiterhin testbar bleiben.
        if source == .localDevelopment { return true }
        if !isUnlocked { return true }
        // Subscribers can still buy Lifetime.
        return source == .subscription
    }

    private static var storedSourceGrantsLifetime: Bool {
        let raw = UserDefaults.standard.string(forKey: sourceKey) ?? ""
        let stored = StashyPlusSource(rawValue: raw) ?? .none
        return stored == .lifetime || stored == .legacyPaidApp
    }

    // MARK: - Freischaltung beim lokalen Entwickeln

    /// In Debug-Builds immer true, sonst nie.
    ///
    /// Bewusst zur Compile-Zeit statt über `AppTransaction`: der StoreKit-Aufruf
    /// verlangt einen angemeldeten App-Store-Account, zeigte beim lokalen Start
    /// einen Anmeldedialog und schaltete ohne Anmeldung gar nicht frei. Debug
    /// entsteht ohnehin nur lokal — TestFlight- und App-Store-Archive sind
    /// Release, dort ist der Wert hart `false` und gar nicht erst erreichbar.
    ///
    /// Wird nirgends gespeichert, kann also nicht in eine verteilte Installation
    /// mitwandern.
    #if DEBUG
    nonisolated(unsafe) private(set) static var localUnlockActive = true
    #else
    nonisolated(unsafe) private(set) static var localUnlockActive = false
    #endif

    /// Thread-safe read for non-`MainActor` call sites.
    nonisolated static var isUnlockedNow: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: debugForceLockedKey) { return false }
        if localUnlockActive { return true }
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
            if Self.localUnlockActive, self.source == .none || self.source == .legacyTip {
                self.source = .localDevelopment
            }
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
        isUnlocked = permanent || subActive || Self.localUnlockActive
        if Self.localUnlockActive, newSource == .none {
            // Anzeige-Quelle; in `defaults` steht weiterhin `newSource`.
            source = .localDevelopment
        }
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

    /// Classifies the customer's original App Store version into a pricing era.
    nonisolated static func originalVersionEra(_ originalAppVersion: String) -> OriginalVersionEra {
        let raw = originalAppVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty or non-numeric value tells us nothing — let the purchase date decide.
        guard !raw.isEmpty else { return .ambiguous }
        if raw.contains(".") {
            return version(raw, isLessThan: firstFreemiumMarketingVersion) ? .paid : .freemium
        }
        guard raw.allSatisfy(\.isNumber) else { return .ambiguous }
        if version(raw, isLessThan: firstAmbiguousBuild) { return .paid }
        if version(raw, isLessThan: firstFreemiumBuild) { return .ambiguous }
        return .freemium
    }

    /// `true` when the original App Store version alone proves a paid purchase.
    nonisolated static func isLegacyPaidAppVersion(_ originalAppVersion: String) -> Bool {
        originalVersionEra(originalAppVersion) == .paid
    }

    /// Production-only grandfathering. Sandbox / Xcode always report `"1.0"` and
    /// must not unlock (TestFlight-only ≠ App Store purchase).
    ///
    /// `originalPurchaseDate` is the authoritative signal and decides on its own
    /// whenever it is available: build numbers were reused across both pricing eras
    /// on iOS (100…299) and the tvOS target — which shares the `de.letzgo.stashy`
    /// Universal Purchase — still ships build `1`, so a free download that starts on
    /// Apple TV would otherwise look like an early paid purchase. The version era is
    /// the fallback for the (practically nonexistent) case of a missing date.
    nonisolated static func legacyPaidAppDecision(
        environment: AppStore.Environment,
        originalAppVersion: String,
        originalPurchaseDate: Date?,
        firstFreemiumReleaseDate: Date? = StashyPlusManager.firstFreemiumReleaseDate
    ) -> LegacyPaidAppDecision {
        guard environment == .production else { return .no }
        let era = originalVersionEra(originalAppVersion)
        if era == .freemium { return .no }
        guard let cutoff = firstFreemiumReleaseDate,
              let purchased = originalPurchaseDate else {
            // No date to check against — trust the version only when it is unambiguous.
            return era == .paid ? .yes : .no
        }
        return purchased < cutoff ? .yes : .no
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
