package de.letzgo.stashy.data

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.consumePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
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
    None("none"), Subscription("subscription"), Lifetime("lifetime"), LocalDevelopment("localDevelopment");

    val statusTitle: String get() = when (this) {
        None -> "Not unlocked"
        LocalDevelopment -> "stashy+ (Local Build)"
        Subscription -> "stashy+ active"
        Lifetime -> "stashy+ Lifetime"
    }

    val statusDetail: String get() = when (this) {
        None -> "Subscribe or buy Lifetime to unlock premium features."
        LocalDevelopment -> "Unlocked automatically because this is a debug build. Not active in any distributed build."
        Subscription -> "Thanks for supporting stashy."
        Lifetime -> "Unlocked forever on this Google account."
    }

    companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: None }
}

/**
 * iOS: `StashyPlusManager` + `StoreManager` — the single gate for stashy+ features and the
 * Google Play Billing store (subscriptions monthly/yearly, lifetime in-app product, tips).
 * Play is the source of truth; prefs (`stashy_plus_*`, same keys as iOS) only make the app
 * start in the right state before Play answers.
 */
object StashyPlus : PurchasesUpdatedListener {
    private const val LIFETIME_KEY = "stashy_plus_lifetime"
    private const val SOURCE_KEY = "stashy_plus_source"
    private const val ACTIVE_PRODUCT_KEY = "stashy_plus_active_product_id"
    private const val TIPS_COUNT_KEY = "totalTipsCount"
    /** Debug helper like iOS: keep the paywall locked even in debug builds. */
    const val DEBUG_FORCE_LOCKED_KEY = "stashy_plus_debug_force_locked"

    private val localUnlockActive: Boolean get() = BuildConfig.DEBUG && !Prefs.bool(DEBUG_FORCE_LOCKED_KEY)

    var source by mutableStateOf(initialSource()); private set
    var isUnlocked by mutableStateOf(source != StashyPlusSource.None); private set
    var activeProductID by mutableStateOf(Prefs.string(ACTIVE_PRODUCT_KEY)); private set

    var products by mutableStateOf<List<ProductDetails>>(emptyList()); private set
    var tipProducts by mutableStateOf<List<ProductDetails>>(emptyList()); private set
    var isLoadingProducts by mutableStateOf(false); private set
    var lastProductError by mutableStateOf<String?>(null); private set
    var purchasingProductID by mutableStateOf<String?>(null); private set
    var isRestoringPurchases by mutableStateOf(false); private set
    /** One-shot message for a toast after purchase/restore. */
    var message by mutableStateOf<String?>(null)

    val hasLifetime: Boolean get() = source == StashyPlusSource.Lifetime
    /** iOS: `shouldOfferPurchases` — subscribers can still buy Lifetime. */
    val shouldOfferPurchases: Boolean get() =
        Prefs.bool(DEBUG_FORCE_LOCKED_KEY) || source == StashyPlusSource.LocalDevelopment || !isUnlocked || source == StashyPlusSource.Subscription
    val tipsCount: Int get() = Prefs.int(TIPS_COUNT_KEY)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var client: BillingClient? = null

    private fun initialSource(): StashyPlusSource {
        if (BuildConfig.DEBUG && !Prefs.bool(DEBUG_FORCE_LOCKED_KEY)) return StashyPlusSource.LocalDevelopment
        if (Prefs.bool(DEBUG_FORCE_LOCKED_KEY)) return StashyPlusSource.None
        return StashyPlusSource.from(Prefs.string(SOURCE_KEY))
    }

    /** Connects to Play and syncs entitlements. Call at app start (Application.onCreate). */
    fun start(context: Context) {
        if (client != null) return
        client = BillingClient.newBuilder(context.applicationContext)
            .setListener(this)
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .build()
        connect()
    }

    private fun connect(then: (suspend () -> Unit)? = null) {
        val c = client ?: return
        if (c.isReady) { then?.let { scope.launch { it() } }; return }
        c.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) scope.launch {
                    syncUnlockFromStore()
                    fetchProducts()
                    then?.invoke()
                } else {
                    lastProductError = "Google Play Billing unavailable (${result.debugMessage.ifBlank { result.responseCode.toString() }})"
                }
            }
            override fun onBillingServiceDisconnected() {}
        })
    }

    /** Re-check on foreground (iOS: `willEnterForeground` → `syncUnlockFromStore`). */
    fun refresh() = connect { syncUnlockFromStore() }

    suspend fun fetchProducts() {
        val c = client?.takeIf { it.isReady } ?: return
        isLoadingProducts = true
        lastProductError = null
        try {
            val subs = c.queryProductDetails(QueryProductDetailsParams.newBuilder().setProductList(
                StashyPlusProduct.subscriptionIDs.map { product(it, BillingClient.ProductType.SUBS) }).build()).productDetailsList.orEmpty()
            val inapp = c.queryProductDetails(QueryProductDetailsParams.newBuilder().setProductList(
                (listOf(StashyPlusProduct.LIFETIME) + StashyPlusProduct.tipIDs).map { product(it, BillingClient.ProductType.INAPP) }).build()).productDetailsList.orEmpty()
            val all = subs + inapp
            products = all.filter { it.productId in StashyPlusProduct.allIDs }.sortedBy { StashyPlusProduct.sortOrder[it.productId] ?: 99 }
            tipProducts = all.filter { it.productId in StashyPlusProduct.tipIDs }.sortedBy { StashyPlusProduct.sortOrder[it.productId] ?: 99 }
            val missing = StashyPlusProduct.allIDs - products.map { it.productId }.toSet()
            lastProductError = when {
                products.isEmpty() -> "No stashy+ products returned. Install from the Play Store (internal testing) to load products."
                missing.isNotEmpty() -> "Missing from Play Console: ${missing.sorted().joinToString(", ")}"
                else -> null
            }
        } catch (e: Exception) {
            lastProductError = e.message
        } finally {
            isLoadingProducts = false
        }
    }

    private fun product(id: String, type: String) =
        QueryProductDetailsParams.Product.newBuilder().setProductId(id).setProductType(type).build()

    /** Reads owned purchases and applies them (iOS: `applyStoreEntitlements`). */
    suspend fun syncUnlockFromStore() {
        val c = client?.takeIf { it.isReady } ?: return
        val subs = c.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build()).purchasesList
        val inapp = c.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()).purchasesList
        (subs + inapp).filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }.forEach { handle(it, announce = false) }
        val owned = (subs + inapp).filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }.flatMap { it.products }.toSet()
        val newSource = when {
            StashyPlusProduct.LIFETIME in owned -> StashyPlusSource.Lifetime
            owned.any { it in StashyPlusProduct.subscriptionIDs } -> StashyPlusSource.Subscription
            else -> StashyPlusSource.None
        }
        apply(newSource, owned.firstOrNull { it in StashyPlusProduct.allIDs })
    }

    private fun apply(storeSource: StashyPlusSource, productID: String?) {
        Prefs.setString(SOURCE_KEY, storeSource.raw)
        Prefs.setBool(LIFETIME_KEY, storeSource == StashyPlusSource.Lifetime)
        Prefs.setString(ACTIVE_PRODUCT_KEY, productID)
        activeProductID = productID
        source = when {
            Prefs.bool(DEBUG_FORCE_LOCKED_KEY) -> StashyPlusSource.None
            storeSource == StashyPlusSource.None && localUnlockActive -> StashyPlusSource.LocalDevelopment
            else -> storeSource
        }
        isUnlocked = source != StashyPlusSource.None
    }

    /** Starts the Play purchase sheet (iOS: `StoreManager.purchase`). */
    fun purchase(activity: Activity, details: ProductDetails) {
        val c = client?.takeIf { it.isReady } ?: run { message = "Google Play is not available."; return }
        val params = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(details).apply {
            details.subscriptionOfferDetails?.firstOrNull()?.offerToken?.let { setOfferToken(it) }
        }.build()
        purchasingProductID = details.productId
        val result = c.launchBillingFlow(activity, BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(params)).build())
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            purchasingProductID = null
            message = "Purchase failed: ${result.debugMessage}"
        }
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        scope.launch {
            when (result.responseCode) {
                BillingClient.BillingResponseCode.OK -> {
                    purchases.orEmpty().forEach { handle(it, announce = true) }
                    syncUnlockFromStore()
                }
                BillingClient.BillingResponseCode.USER_CANCELED -> {}
                BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> { syncUnlockFromStore(); message = "You already own this." }
                else -> message = "Purchase failed: ${result.debugMessage}"
            }
            purchasingProductID = null
        }
    }

    private suspend fun handle(purchase: Purchase, announce: Boolean) {
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) {
            if (announce && purchase.purchaseState == Purchase.PurchaseState.PENDING) message = "Purchase pending — it unlocks once payment completes."
            return
        }
        val c = client ?: return
        val isTip = purchase.products.any { it in StashyPlusProduct.tipIDs }
        if (isTip) {
            // Tips are consumables: consume so they can be bought again.
            val consumed = c.consumePurchase(ConsumeParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build())
            if (consumed.billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                Prefs.setInt(TIPS_COUNT_KEY, tipsCount + 1)
                if (announce) message = "Thank you for your support! ❤️"
            }
            return
        }
        if (!purchase.isAcknowledged) {
            c.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build())
        }
        if (announce) message = "stashy+ unlocked. Thank you!"
    }

    /** iOS: Restore Purchases (`AppStore.sync()`). */
    fun restore() {
        isRestoringPurchases = true
        connect {
            syncUnlockFromStore()
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
        apply(StashyPlusSource.from(Prefs.string(SOURCE_KEY)), activeProductID)
    }

    /** Price line for a product: subscriptions show the first pricing phase of the first offer. */
    fun price(details: ProductDetails): String =
        details.oneTimePurchaseOfferDetails?.formattedPrice
            ?: details.subscriptionOfferDetails?.firstOrNull()?.pricingPhases?.pricingPhaseList?.lastOrNull()?.formattedPrice
            ?: ""
}
