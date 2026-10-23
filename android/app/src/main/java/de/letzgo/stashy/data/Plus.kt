package de.letzgo.stashy.data

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesException
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import de.letzgo.stashy.BuildConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** iOS: `StashyPlusProduct` — same product IDs in the Play Console. */
object StashyPlusProduct {
    const val MONTHLY = "de.stashy.plus.m"
    const val YEARLY = "de.stashy.plus.y"
    const val LIFETIME = "de.stashy.plus.l"
    const val TIP_SMALL = "de.stashy.tip1"
    const val TIP_MEDIUM = "de.stashy.tip2"
    const val TIP_LARGE = "de.stashy.tip3"

    val subscriptionIDs = listOf(MONTHLY, YEARLY)
    val allIDs = subscriptionIDs + LIFETIME
    /** Consumable tips — thank-you only, never grant stashy+. */
    val tipIDs = listOf(TIP_SMALL, TIP_MEDIUM, TIP_LARGE)

    val displayNames = mapOf(
        MONTHLY to "Monthly", YEARLY to "Yearly", LIFETIME to "Lifetime",
        TIP_SMALL to "Small", TIP_MEDIUM to "Medium", TIP_LARGE to "Large",
    )
    val sortOrder = mapOf(MONTHLY to 0, YEARLY to 1, LIFETIME to 2, TIP_SMALL to 0, TIP_MEDIUM to 1, TIP_LARGE to 2)
}

/** iOS: `StashyPlusSource` (raw values identical; no pre-3.0 paid-app grant on Play). */
enum class StashyPlusSource(val raw: String) {
    None("none"), Subscription("subscription"), Lifetime("lifetime"), LocalDevelopment("localDevelopment"),
    /** Sideload builds (`BuildConfig.LICENSE_KEYS`): a valid offline license key ([LicenseKey]). */
    License("license");

    val statusTitle: String get() = when (this) {
        None -> "Not unlocked"
        LocalDevelopment -> "stashy+ (Local Build)"
        License -> "stashy+ licensed"
        Subscription -> "stashy+ active"
        Lifetime -> "stashy+ Lifetime"
    }

    val statusDetail: String get() = when (this) {
        None -> "Subscribe or buy Lifetime to unlock premium features."
        LocalDevelopment -> "Unlocked automatically because this is a debug build. Not active in any distributed build."
        License -> "Unlocked with a license key."
        Subscription -> "Thanks for supporting stashy."
        Lifetime -> "Unlocked forever on this Google account."
    }

    companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: None }
}

/**
 * One purchasable item of the current RevenueCat offering (stashy+ plan or tip).
 * iOS: `StashyStoreProduct`.
 */
class StashyStoreProduct(val pkg: Package) {
    /** Play product id without the `:basePlan` suffix RevenueCat adds to subscriptions. */
    val productId: String get() = pkg.product.id.substringBefore(':')
    val name: String get() = pkg.product.name
    val price: String get() = pkg.product.price.formatted
}

/**
 * iOS: `StashyPlusManager` + `StoreManager` — the single gate for stashy+ features and the
 * Google Play store via RevenueCat (subscriptions monthly/yearly, lifetime in-app product, tips).
 * RevenueCat's CustomerInfo is the source of truth; prefs (`stashy_plus_*`, same keys as iOS)
 * only make the app start in the right state before it answers.
 */
object StashyPlus {
    /** Public SDK key of the Play Store app in the RevenueCat project "stashy". */
    private const val REVENUECAT_API_KEY = "goog_GVtAIDhdpHDvyIbVYXsWOmVzmXm"

    private const val LIFETIME_KEY = "stashy_plus_lifetime"
    private const val SOURCE_KEY = "stashy_plus_source"
    private const val ACTIVE_PRODUCT_KEY = "stashy_plus_active_product_id"
    private const val TIPS_COUNT_KEY = "totalTipsCount"
    /** Debug helper like iOS: keep the paywall locked even in debug builds. */
    const val DEBUG_FORCE_LOCKED_KEY = "stashy_plus_debug_force_locked"

    /** The accepted license key (sideload flavor; global, not per server). */
    private const val LICENSE_KEY = "stashy_plus_license_key"

    /**
     * Debug builds unlock automatically — except in the license-key flavor, where the debug build
     * must behave like the shipped APK so the key flow can be tested.
     */
    private val localUnlockActive: Boolean get() = BuildConfig.DEBUG && !BuildConfig.LICENSE_KEYS && !Prefs.bool(DEBUG_FORCE_LOCKED_KEY)

    /** Valid stored license (re-verified on every start and resume; invalid/expired → null). */
    var license by mutableStateOf(storedLicense()); private set
    var source by mutableStateOf(initialSource()); private set
    var isUnlocked by mutableStateOf(source != StashyPlusSource.None); private set
    var activeProductID by mutableStateOf(Prefs.string(ACTIVE_PRODUCT_KEY)); private set

    var products by mutableStateOf<List<StashyStoreProduct>>(emptyList()); private set
    var tipProducts by mutableStateOf<List<StashyStoreProduct>>(emptyList()); private set
    var isLoadingProducts by mutableStateOf(false); private set
    var lastProductError by mutableStateOf<String?>(null); private set
    var purchasingProductID by mutableStateOf<String?>(null); private set
    var isRestoringPurchases by mutableStateOf(false); private set
    /** One-shot message for a toast after purchase/restore. */
    var message by mutableStateOf<String?>(null)

    val hasLifetime: Boolean get() = source == StashyPlusSource.Lifetime
    /** iOS: `shouldOfferPurchases` — subscribers can still buy Lifetime. */
    val shouldOfferPurchases: Boolean get() =
        !BuildConfig.LICENSE_KEYS && (Prefs.bool(DEBUG_FORCE_LOCKED_KEY) || source == StashyPlusSource.LocalDevelopment || !isUnlocked || source == StashyPlusSource.Subscription)
    val tipsCount: Int get() = Prefs.int(TIPS_COUNT_KEY)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private fun initialSource(): StashyPlusSource {
        if (localUnlockActive) return StashyPlusSource.LocalDevelopment
        if (Prefs.bool(DEBUG_FORCE_LOCKED_KEY)) return StashyPlusSource.None
        if (license != null) return StashyPlusSource.License
        return StashyPlusSource.from(Prefs.string(SOURCE_KEY)).takeIf { it != StashyPlusSource.License } ?: StashyPlusSource.None
    }

    private fun storedLicense(): License? {
        if (!BuildConfig.LICENSE_KEYS) return null
        val key = Prefs.string(LICENSE_KEY) ?: return null
        return (LicenseKey.verify(key, System.currentTimeMillis()) as? LicenseKey.Result.Valid)?.license
    }

    /** Whether this build unlocks stashy+ with license keys instead of Play (sideload flavor). */
    val usesLicenseKeys: Boolean get() = BuildConfig.LICENSE_KEYS

    /** The stored key once it no longer verifies (expired) — for the status text. */
    val expiredLicense: License? get() {
        if (!BuildConfig.LICENSE_KEYS || license != null) return null
        val key = Prefs.string(LICENSE_KEY) ?: return null
        return (LicenseKey.verify(key, System.currentTimeMillis()) as? LicenseKey.Result.Expired)?.license
    }

    /**
     * Verifies and stores a pasted license key. Returns null on success, otherwise the error text
     * for the input field (the previous license, if any, stays active).
     */
    fun activateLicense(input: String): String? {
        if (!BuildConfig.LICENSE_KEYS) return "License keys are not used in this version of stashy."
        return when (val result = LicenseKey.verify(input, System.currentTimeMillis())) {
            is LicenseKey.Result.Valid -> {
                Prefs.commitString(LICENSE_KEY, input.trim())
                license = result.license
                recompute()
                message = "stashy+ unlocked. Thank you!"
                null
            }
            is LicenseKey.Result.Expired -> "This license key expired on ${result.license.expiresText}."
            is LicenseKey.Result.Invalid -> result.reason
        }
    }

    fun removeLicense() {
        Prefs.commitString(LICENSE_KEY, null)
        license = null
        recompute()
    }

    /** Re-checks the stored key (an expiry date may have passed while the app was running). */
    private fun revalidateLicense() {
        if (!BuildConfig.LICENSE_KEYS) return
        val now = storedLicense()
        if (now != license) { license = now; recompute() }
    }

    private fun recompute() = apply(StashyPlusSource.from(Prefs.string(SOURCE_KEY)), activeProductID)

    /** Configures RevenueCat and syncs entitlements. Call at app start (Application.onCreate). */
    fun start(context: Context) {
        if (Purchases.isConfigured) return
        Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.WARN
        Purchases.configure(PurchasesConfiguration.Builder(context.applicationContext, REVENUECAT_API_KEY).build())
        // Purchases, renewals, restores and the cached info at launch all arrive here.
        Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { apply(it) }
        scope.launch { fetchProducts() }
    }

    /** Re-check on foreground (iOS: `willEnterForeground` → `syncUnlockFromStore`). */
    fun refresh() {
        revalidateLicense()
        if (Purchases.isConfigured) scope.launch { syncUnlockFromStore() }
    }

    suspend fun fetchProducts() {
        if (!Purchases.isConfigured) return
        isLoadingProducts = true
        lastProductError = null
        try {
            val all = Purchases.sharedInstance.awaitOfferings().current?.availablePackages.orEmpty().map(::StashyStoreProduct)
            products = all.filter { it.productId in StashyPlusProduct.allIDs }.sortedBy { StashyPlusProduct.sortOrder[it.productId] ?: 99 }
            tipProducts = all.filter { it.productId in StashyPlusProduct.tipIDs }.sortedBy { StashyPlusProduct.sortOrder[it.productId] ?: 99 }
            val missing = StashyPlusProduct.allIDs - products.map { it.productId }.toSet()
            lastProductError = when {
                products.isEmpty() -> "No stashy+ products returned. Install from the Play Store (internal testing) to load products."
                missing.isNotEmpty() -> "Missing from the store offering: ${missing.sorted().joinToString(", ")}"
                else -> null
            }
        } catch (e: PurchasesException) {
            lastProductError = e.error.message
        } finally {
            isLoadingProducts = false
        }
    }

    /** Reads the current CustomerInfo and applies it (iOS: `applyStoreEntitlements`). */
    suspend fun syncUnlockFromStore() {
        if (!Purchases.isConfigured) return
        try {
            apply(Purchases.sharedInstance.awaitCustomerInfo())
        } catch (_: PurchasesException) {
            // Offline / RevenueCat unreachable: keep the persisted state.
        }
    }

    private fun apply(info: CustomerInfo) {
        val lifetime = info.nonSubscriptionTransactions.any { it.productIdentifier.substringBefore(':') == StashyPlusProduct.LIFETIME }
        val subscription = info.activeSubscriptions.map { it.substringBefore(':') }.firstOrNull { it in StashyPlusProduct.subscriptionIDs }
        when {
            lifetime -> apply(StashyPlusSource.Lifetime, StashyPlusProduct.LIFETIME)
            subscription != null -> apply(StashyPlusSource.Subscription, subscription)
            else -> apply(StashyPlusSource.None, null)
        }
    }

    private fun apply(storeSource: StashyPlusSource, productID: String?) {
        Prefs.setString(SOURCE_KEY, storeSource.raw)
        Prefs.setBool(LIFETIME_KEY, storeSource == StashyPlusSource.Lifetime)
        Prefs.setString(ACTIVE_PRODUCT_KEY, productID)
        activeProductID = productID
        source = when {
            Prefs.bool(DEBUG_FORCE_LOCKED_KEY) -> StashyPlusSource.None
            storeSource == StashyPlusSource.None && license != null -> StashyPlusSource.License
            storeSource == StashyPlusSource.None && localUnlockActive -> StashyPlusSource.LocalDevelopment
            else -> storeSource
        }
        isUnlocked = source != StashyPlusSource.None
    }

    /** Starts the Play purchase sheet (iOS: `StoreManager.purchase`). */
    fun purchase(activity: Activity, product: StashyStoreProduct) {
        if (!Purchases.isConfigured) { message = "Google Play is not available."; return }
        purchasingProductID = product.productId
        scope.launch {
            try {
                val result = Purchases.sharedInstance.awaitPurchase(PurchaseParams.Builder(activity, product.pkg).build())
                if (product.productId in StashyPlusProduct.tipIDs) {
                    Prefs.setInt(TIPS_COUNT_KEY, tipsCount + 1)
                    message = "Thank you for your support! ❤️"
                } else {
                    apply(result.customerInfo)
                    message = "stashy+ unlocked. Thank you!"
                }
            } catch (e: PurchasesTransactionException) {
                if (!e.userCancelled) message = when (e.code) {
                    PurchasesErrorCode.PaymentPendingError -> "Purchase pending — it unlocks once payment completes."
                    PurchasesErrorCode.ProductAlreadyPurchasedError -> { syncUnlockFromStore(); "You already own this." }
                    else -> "Purchase failed: ${e.message}"
                }
            } finally {
                purchasingProductID = null
            }
        }
    }

    /** iOS: Restore Purchases (`AppStore.sync()`). */
    fun restore() {
        if (!Purchases.isConfigured) return
        isRestoringPurchases = true
        scope.launch {
            try {
                apply(Purchases.sharedInstance.awaitRestore())
            } catch (_: PurchasesException) {
            }
            isRestoringPurchases = false
            message = if (source == StashyPlusSource.Subscription || source == StashyPlusSource.Lifetime) "Purchases restored." else "No previous purchase found."
        }
    }

    /** iOS: manage-subscriptions sheet → Play subscription center. */
    fun manageSubscriptions(context: Context) {
        val pid = activeProductID?.takeIf { it in StashyPlusProduct.subscriptionIDs }
        val url = if (pid != null) "https://play.google.com/store/account/subscriptions?sku=$pid&package=${context.packageName}"
        else "https://play.google.com/store/account/subscriptions"
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Debug toggle (Settings → stashy+ in debug builds), iOS `debugForceLockedKey`. */
    fun setDebugForceLocked(locked: Boolean) {
        Prefs.setBool(DEBUG_FORCE_LOCKED_KEY, locked)
        recompute()
    }

    /** Price line for a product (subscriptions: the base plan's recurring price). */
    fun price(product: StashyStoreProduct): String = product.price
}
