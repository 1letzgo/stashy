package de.letzgo.stashy.ui.tools

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.TabBarClearance
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.catalog.catalogTopPadding

// Shared building blocks for the Tools tab, its tools and the stashy+ paywall. They mirror the
// iOS settings-list chrome in `SharedUtilities.swift` (`stashySettingsList`,
// `stashyScrollingSectionHeader`, `stashyGroupedBlockRow`, `StashyBetaBadge`) and
// `DesignTokens.Tools`.

/** iOS: `DesignTokens.Tools`. */
object ToolsTokens {
    val contentPadding: Dp = Tokens.Spacing.md
    /** Space above a tool's first row (plus `Chrome.contentTopGap`). */
    val menuTopPadding: Dp = Tokens.Spacing.xs
    val menuBottomPadding: Dp = Tokens.Spacing.sm
    val rankedGridSpacing: Dp = 12.dp
}

/** Top padding for tool content under the floating Tools chip strip. */
@Composable
fun toolsTopPadding(): Dp = catalogTopPadding()

/** Bottom padding for every scrolling tool root (floating tab bar). */
val ToolsBottomPadding: Dp = TabBarClearance + 16.dp

/**
 * iOS: `List { … }.stashySettingsList()` — plain list, 20 pt horizontal margins, 20 pt top,
 * 24 pt between sections. Use [SettingsSectionHeader] / [GroupedCard] / [SettingsSectionFooter]
 * inside; separate sections with `item { SectionSpacer() }`.
 */
@Composable
fun SettingsList(
    modifier: Modifier = Modifier,
    topPadding: Dp = toolsTopPadding(),
    state: LazyListState = rememberLazyListState(),
    content: LazyListScope.() -> Unit,
) {
    LazyColumn(
        modifier.fillMaxSize(),
        state = state,
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = topPadding + 12.dp, bottom = TabBarClearance + 28.dp),
        content = content,
    )
}

/** Gap between sections — 20 dp like the Settings list. */
@Composable
fun SectionSpacer() = Spacer(Modifier.height(20.dp))

/** iOS: `stashyScrollingSectionHeader(_:isBeta:)` — Material section header (titleSmall, accent). */
@Composable
fun SettingsSectionHeader(title: String, isBeta: Boolean = false, modifier: Modifier = Modifier) =
    de.letzgo.stashy.ui.NativeSectionHeader(title, modifier, badge = if (isBeta) ({ BetaBadge() }) else null)

/** iOS: `stashyScrollingSectionFooter(_:)` — Material supporting text. */
@Composable
fun SettingsSectionFooter(text: String, modifier: Modifier = Modifier) = de.letzgo.stashy.ui.NativeSectionFooter(text, modifier)

/** iOS: `StashyBetaBadge`. */
@Composable
fun BetaBadge() {
    val tint = Appearance.tint
    Text(
        "Beta",
        fontSize = 10.sp, fontWeight = FontWeight.Bold, color = tint,
        modifier = Modifier.background(tint.copy(alpha = 0.16f), RoundedCornerShape(50)).padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

/**
 * iOS: rows with `stashyGroupedBlockRow(index:count:)` — one rounded Material group (16 dp) in the
 * secondary background. Put rows inside and separate them with [RowDivider].
 */
@Composable
fun GroupedCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) =
    de.letzgo.stashy.ui.NativeGroup(modifier, content)

/** Divider between grouped rows — 16 dp inset like the Settings rows. */
@Composable
fun RowDivider(startInset: Dp = 16.dp) = de.letzgo.stashy.ui.NativeDivider(startInset)

/**
 * iOS: `Label(title, systemImage:)` row in a grouped list — identical to [de.letzgo.stashy.ui.NativeListItem]
 * (56 dp / 72 dp with subtitle, 24 dp leading icon, bodyLarge / bodyMedium, trailing content).
 */
@Composable
fun SettingsRow(
    title: String,
    icon: ImageVector? = null,
    modifier: Modifier = Modifier,
    iconTint: Color = Appearance.tint,
    titleColor: Color = Theme.palette.text,
    subtitle: String? = null,
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null,
    trailing: @Composable RowScope.() -> Unit = {},
) = de.letzgo.stashy.ui.NativeListItem(
    title, modifier, supporting = subtitle, icon = icon, iconTint = iconTint, headlineColor = titleColor,
    enabled = enabled, onClick = onClick, trailing = trailing,
)

/** Small spinner like iOS `ProgressView()` in a row. */
@Composable
fun SmallSpinner(color: Color = Theme.palette.secondaryText) =
    CircularProgressIndicator(Modifier.size(18.dp), color = color, strokeWidth = 2.dp)

/** iOS: the "No active server" placeholder of the Tools views. */
@Composable
fun NoServerPlaceholder(icon: ImageVector, message: String) {
    val p = Theme.palette
    Column(
        Modifier.fillMaxSize().padding(horizontal = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(icon, null, tint = Appearance.tint, modifier = Modifier.size(64.dp))
        Text("No active server", style = IosTypography.title3.copy(fontWeight = FontWeight.Bold), color = p.text)
        Text(message, style = IosTypography.body, color = p.secondaryText, textAlign = TextAlign.Center)
    }
}

/** iOS `.alert` with OK/Cancel or a destructive confirm button — Material 3 AlertDialog. */
@Composable
fun StashyAlert(
    title: String,
    message: String?,
    onDismiss: () -> Unit,
    confirmLabel: String = "OK",
    destructive: Boolean = false,
    dismissLabel: String? = null,
    onConfirm: () -> Unit = onDismiss,
) = de.letzgo.stashy.ui.NativeConfirmDialog(
    title, message, onDismiss, confirmLabel = confirmLabel, destructive = destructive, dismissLabel = dismissLabel, onConfirm = onConfirm,
)

/** iOS: `ToastManager.shared.show(...)` — Android shows a system toast. */
fun showToast(message: String, long: Boolean = false) {
    runCatching {
        Toast.makeText(Prefs.appContext, message, if (long) Toast.LENGTH_LONG else Toast.LENGTH_SHORT).show()
    }
}
