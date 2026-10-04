package de.letzgo.stashy.ui.tools

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.android.billingclient.api.ProductDetails
import kotlinx.coroutines.launch
import de.letzgo.stashy.MainActivity
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.data.StashyPlusProduct
import de.letzgo.stashy.data.StashyPlusSource
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.BackPill
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Chevron
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.statusBars

/** iOS: `StashyLegalLinks` — Play equivalents of the EULA link. */
private object StashyLegalLinks {
    const val TERMS_OF_USE = "https://play.google.com/about/play-terms/"
    const val PRIVACY_POLICY = "https://github.com/1letzgo/stashy#privacy"
}

/**
 * Opens the stashy+ paywall on top of the current tab (used by every gated feature, e.g. the
 * download button or a locked tool). While locked the Tools tab itself is the paywall.
 */
fun openStashyPlusPaywall() {
    if (Nav.top is StashyPlusPaywallScreen) return
    Nav.push(StashyPlusPaywallScreen())
}

/** The paywall as a pushed screen (back pill top-left). */
class StashyPlusPaywallScreen : Screen {
    override val key = "stashy-plus-paywall"
    @Composable override fun Content() {
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 60.dp
            StashyPlusSettingsContent(topPadding = top)
            BackPill({ Nav.pop() }, Modifier.statusBarsPadding().padding(16.dp))
        }
    }
}

/**
 * iOS: the locked stashy+ tab — `SettingsView(stashyPlusOnly: true)`. With a single section iOS
 * hides the chrome switcher, so the list starts right under the status bar.
 */
@Composable
fun StashyPlusPaywallContent() {
    val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 8.dp
    StashyPlusSettingsContent(topPadding = top)
}

/**
 * iOS: `SettingsView.stashyPlusSettings` — the whole stashy+ section as a list. Locked: the
 * "Included with stashy+" feature list and the purchase menu (the paywall). Unlocked: custom app
 * icons, Tag Suggestions & Similar Scenes, and the subscription status / Lifetime upgrade.
 * The Settings tab can show this for its "stashy+" section.
 */
@Composable
fun StashyPlusSettingsContent(topPadding: Dp = toolsTopPadding()) {
    PlusMessageToasts()
    LaunchedEffect(Unit) {
        StashyPlus.syncUnlockFromStore()
        if (StashyPlus.products.isEmpty()) StashyPlus.fetchProducts()
    }
    SettingsList(topPadding = topPadding) {
        stashyPlusItems()
    }
}

/** Shows [StashyPlus.message] once as a toast (iOS: `ToastManager` after purchase/restore). */
@Composable
fun PlusMessageToasts() {
    val message = StashyPlus.message
    LaunchedEffect(message) {
        if (message != null) {
            showToast(message, long = message.length > 40)
            StashyPlus.message = null
        }
    }
}

private fun LazyListScope.stashyPlusItems() {
    if (StashyPlus.isUnlocked) {
        item {
            SettingsSectionHeader("Custom App Icons")
            GroupedCard { Box(Modifier.padding(horizontal = 16.dp)) { AppIconPicker() } }
            SectionSpacer()
        }
        item {
            SettingsSectionHeader("Tag Suggestions & Similar Scenes", isBeta = true)
            GroupedCard {
                SettingsRow("Tag Suggestions & Similar Scenes", SF.sparkles, onClick = {
                    Nav.push(de.letzgo.stashy.ui.tools.aitags.AITagsSettingsScreen())
                }) { Icon(Icons.Chevron, null, tint = Theme.palette.tertiaryText) }
            }
            SectionSpacer()
        }
    } else {
        item {
            SettingsSectionHeader("Included with stashy+")
            val features = listOf(
                "Custom App Icons", "Download Scenes",
                ToolsItem.Statistics.plusFeatureTitle, ToolsItem.OCount.plusFeatureTitle,
                ToolsItem.Timeline.plusFeatureTitle, ToolsItem.TopLists.plusFeatureTitle,
                ToolsItem.Filters.plusFeatureTitle, ToolsItem.HotOrNot.plusFeatureTitle,
                ToolsItem.RateMe.title,
            )
            GroupedCard {
                features.forEachIndexed { i, title ->
                    SettingsRow(title, SF.lockFill, iconTint = Theme.palette.secondaryText, titleColor = Theme.palette.secondaryText)
                    if (i < features.lastIndex) RowDivider()
                }
            }
            SectionSpacer()
        }
    }
    item { PurchaseSection() }
}

/** iOS: `stashyPlusPurchaseSection`. */
@Composable
private fun PurchaseSection() {
    val p = Theme.palette
    val context = LocalContext.current
    val unlocked = StashyPlus.isUnlocked
    SettingsSectionHeader(if (unlocked) "stashy+" else "Unlock stashy+")

    if (unlocked) {
        GroupedCard {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(SF.checkmarkSealFill, null, tint = StashyColors.systemGreen, modifier = Modifier.size(22.dp))
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(StashyPlus.source.statusTitle, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = p.text)
                    Text(statusDetailText(), style = IosTypography.caption, color = p.secondaryText)
                }
            }
        }
        Spacer(Modifier.size(8.dp))
    }

    if (StashyPlus.shouldOfferPurchases) {
        if (StashyPlus.products.isEmpty()) {
            GroupedCard {
                if (StashyPlus.isLoadingProducts) {
                    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        SmallSpinner()
                        Text("Loading stashy+ options…", style = IosTypography.body, color = p.secondaryText)
                    }
                } else {
                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(StashyPlus.lastProductError ?: "stashy+ products unavailable.", style = IosTypography.caption, color = p.secondaryText)
                        Text("Retry", style = IosTypography.body, color = Appearance.tint, modifier = Modifier.clickable { retryProducts() })
                    }
                }
            }
        } else {
            GroupedCard(Modifier.padding(vertical = 4.dp)) {
                val products = StashyPlus.products
                products.forEachIndexed { i, product ->
                    PurchaseButton(product)
                    if (i < products.lastIndex) RowDivider(16.dp)
                }
                if (!unlocked) {
                    RowDivider(16.dp)
                    Spacer(Modifier.size(8.dp))
                    RestoreButton()
                }
            }
            StashyPlus.lastProductError?.takeIf { it.startsWith("Missing from Play Console") }?.let {
                Text(it, style = IosTypography.caption2, color = p.secondaryText, modifier = Modifier.padding(top = 6.dp))
            }
        }
        Spacer(Modifier.size(8.dp))
    }

    if (!unlocked && (StashyPlus.products.isEmpty() || !StashyPlus.shouldOfferPurchases)) {
        GroupedCard(Modifier.padding(top = 12.dp, bottom = 4.dp)) { RestoreButton() }
    }

    if (StashyPlus.source == StashyPlusSource.Subscription) {
        GroupedCard(Modifier.padding(vertical = 4.dp)) {
            SecondaryButton("Manage Subscription", SF.creditcard, showsProgress = false) { StashyPlus.manageSubscriptions(context) }
        }
    }

    if (!unlocked) {
        SettingsSectionFooter("Monthly, Yearly, or Lifetime. Bought stashy+ before with this Google account, or reinstalled? Tap Restore Purchases.")
    }

    if (StashyPlus.shouldOfferPurchases) {
        Column(Modifier.fillMaxWidth().padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                "Subscriptions renew automatically unless canceled before the end of the current period. Manage or cancel in your Google Play account settings.",
                style = IosTypography.caption2, color = p.secondaryText,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                LinkText("Terms of Use") { openUrl(context, StashyLegalLinks.TERMS_OF_USE) }
                LinkText("Privacy Policy") { openUrl(context, StashyLegalLinks.PRIVACY_POLICY) }
            }
        }
    }
}

@Composable
private fun LinkText(title: String, onClick: () -> Unit) =
    Text(title, style = IosTypography.caption, color = Appearance.tint, modifier = Modifier.clickable(onClick = onClick))

private fun openUrl(context: android.content.Context, url: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

/** iOS: "Retry" → `storeManager.fetchProducts()`; reconnects to Play first if needed. */
private fun retryProducts() {
    StashyPlus.refresh()
    kotlinx.coroutines.MainScope().launch { StashyPlus.fetchProducts() }
}

/** iOS: `statusDetailText` (Play does not hand the client an expiry date). */
private fun statusDetailText(): String {
    val id = StashyPlus.activeProductID
    if (StashyPlus.source == StashyPlusSource.Subscription && id != null) {
        StashyPlusProduct.displayNames[id]?.let { return "$it plan" }
    }
    return StashyPlus.source.statusDetail
}

/** iOS: `iconFor(productID:)`. */
private fun iconFor(productID: String): ImageVector = when (productID) {
    StashyPlusProduct.MONTHLY -> SF.calendar
    StashyPlusProduct.YEARLY -> SF.calendarBadgeClock
    StashyPlusProduct.LIFETIME -> SF.infinity
    StashyPlusProduct.TIP_SMALL -> SF.heart
    StashyPlusProduct.TIP_MEDIUM -> SF.heartFill
    StashyPlusProduct.TIP_LARGE -> SF.boltHeartFill
    else -> SF.sparkles
}

/** iOS: `stashyPlusRowLabel(_:systemImage:)`. */
@Composable
private fun PlusRowLabel(title: String, icon: ImageVector, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.width(22.dp), contentAlignment = Alignment.Center) { Icon(icon, null, tint = Appearance.tint, modifier = Modifier.size(20.dp)) }
        Text(title, style = IosTypography.body, color = Theme.palette.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** iOS: `stashyPlusPurchaseButton(for:)`. */
@Composable
private fun PurchaseButton(product: ProductDetails) {
    val purchasing = StashyPlus.purchasingProductID
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp)
            .clickable(enabled = purchasing == null) { purchase(product) }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        PlusRowLabel(StashyPlusProduct.displayNames[product.productId] ?: product.name, iconFor(product.productId), Modifier.weight(1f))
        if (purchasing == product.productId) SmallSpinner()
        else Text(StashyPlus.price(product), style = IosTypography.subheadline, color = Theme.palette.secondaryText, maxLines = 1)
    }
}

private fun purchase(product: ProductDetails) {
    val activity = MainActivity.current ?: run { showToast("Google Play is not available."); return }
    StashyPlus.purchase(activity, product)
}

@Composable
private fun RestoreButton() {
    SecondaryButton(
        "Restore Purchases", SF.arrowClockwise,
        showsProgress = StashyPlus.isRestoringPurchases,
        enabled = StashyPlus.purchasingProductID == null && !StashyPlus.isRestoringPurchases,
    ) { StashyPlus.restore() }
}

/** iOS: `stashyPlusSecondaryButton(title:systemImage:showsProgress:action:)`. */
@Composable
private fun SecondaryButton(title: String, icon: ImageVector, showsProgress: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(enabled = enabled, onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        PlusRowLabel(title, icon, Modifier.weight(1f))
        if (showsProgress) SmallSpinner()
    }
}

/**
 * iOS: `SettingsView.tipSection` — consumable tips (never unlock stashy+). Used by the Settings
 * tab's about section; a plain column so it can sit in any list item.
 */
@Composable
fun StashyTipsSection(modifier: Modifier = Modifier) {
    val p = Theme.palette
    PlusMessageToasts()
    LaunchedEffect(Unit) { if (StashyPlus.tipProducts.isEmpty()) StashyPlus.fetchProducts() }
    Column(modifier.fillMaxWidth()) {
        SettingsSectionHeader("Tips")
        val tips = StashyPlus.tipProducts
        GroupedCard {
            if (tips.isEmpty()) {
                if (StashyPlus.isLoadingProducts) {
                    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        SmallSpinner()
                        Text("Loading tips…", style = IosTypography.body, color = p.secondaryText)
                    }
                } else {
                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Tips unavailable.", style = IosTypography.caption, color = p.secondaryText)
                        Text("Retry", style = IosTypography.body, color = Appearance.tint, modifier = Modifier.clickable { retryProducts() })
                    }
                }
            } else {
                tips.forEachIndexed { i, product ->
                    val purchasing = StashyPlus.purchasingProductID
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 44.dp)
                            .clickable(enabled = purchasing == null) { purchase(product) }
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        PlusRowLabel(StashyPlusProduct.displayNames[product.productId] ?: product.name, iconFor(product.productId), Modifier.weight(1f))
                        if (purchasing == product.productId) SmallSpinner()
                        else Text(StashyPlus.price(product), style = IosTypography.body, color = p.secondaryText)
                    }
                    if (i < tips.lastIndex) RowDivider()
                }
            }
        }
        SettingsSectionFooter("Support stashy. Tips do not unlock stashy+.")
    }
}
