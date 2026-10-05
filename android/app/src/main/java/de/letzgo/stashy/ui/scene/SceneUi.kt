package de.letzgo.stashy.ui.scene

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.noRippleClickable
import de.letzgo.stashy.ui.player.PlayerIcons
import kotlinx.coroutines.delay

/** iOS: `ToastManager` (style colours: success green, error red, info blue). */
object SceneToast {
    enum class Style { Success, Error, Info }
    data class Message(val text: String, val icon: ImageVector?, val style: Style, val id: Long = System.nanoTime())

    var current by mutableStateOf<Message?>(null)
        private set

    fun show(text: String, icon: ImageVector? = null, style: Style = Style.Info) { current = Message(text, icon, style) }
    internal fun clear(id: Long) { if (current?.id == id) current = null }
}

/** Renders [SceneToast] at the top (iOS toasts slide in under the status bar). */
@Composable
fun SceneToastHost(modifier: Modifier = Modifier) {
    val message = SceneToast.current
    LaunchedEffect(message?.id) { message?.let { delay(2500); SceneToast.clear(it.id) } }
    AnimatedVisibility(message != null, modifier, enter = slideInVertically { -it } + fadeIn(), exit = slideOutVertically { -it } + fadeOut()) {
        val m = message ?: return@AnimatedVisibility
        val color = when (m.style) { SceneToast.Style.Success -> StashyColors.systemGreen; SceneToast.Style.Error -> StashyColors.systemRed; SceneToast.Style.Info -> StashyColors.systemBlue }
        Row(
            Modifier.statusBarsPadding().padding(16.dp).shadow(8.dp, RoundedCornerShape(50)).clip(RoundedCornerShape(50))
                .background(Color(0xFF1C2433).copy(alpha = 0.95f)).border(0.5.dp, color.copy(alpha = 0.5f), RoundedCornerShape(50))
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            m.icon?.let { Icon(it, null, tint = color, modifier = Modifier.size(18.dp)) }
            Text(m.text, style = IosTypography.subheadline.copy(fontWeight = FontWeight.Medium), color = Color.White, maxLines = 3)
        }
    }
}

/** Card background used by every scene detail card (secondary background, card radius, card shadow). */
@Composable
fun SceneCardContainer(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(Tokens.Radius.card)
    Column(modifier.cardShadow(shape).clip(shape).background(Theme.palette.secondaryBackground), content = content)
}

/** Card title (`.title3` semibold) with the edit pencil when edit mode is on. */
@Composable
fun SceneCardHeader(title: String, onEdit: (() -> Unit)?, trailing: (@Composable () -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = IosTypography.title3, color = Theme.palette.text)
        Spacer(Modifier.weight(1f))
        trailing?.invoke()
        if (onEdit != null && Appearance.isEditModeEnabled) EditCircleButton(onEdit)
    }
}

/** iOS `pencil.circle.fill` in the tint colour, 20 pt. */
@Composable
fun EditCircleButton(onClick: () -> Unit) {
    Box(Modifier.size(22.dp).clip(CircleShape).background(Appearance.tint).noRippleClickable(onClick), contentAlignment = Alignment.Center) {
        Icon(PlayerIcons.edit, "Edit", tint = Color.White, modifier = Modifier.size(12.dp))
    }
}

/** Empty-card line ("No performers assigned"). */
@Composable
fun SceneCardEmpty(text: String) {
    Text(text, Modifier.padding(start = 12.dp, end = 12.dp, bottom = 12.dp), style = IosTypography.subheadline, color = Theme.palette.secondaryText)
}

/** Name capsule hanging off the bottom of performer/studio/group tiles. */
@Composable
fun NamePill(text: String, modifier: Modifier = Modifier) {
    val p = Theme.palette
    val tint = Appearance.tint
    Text(
        text,
        modifier.shadow(2.dp, RoundedCornerShape(50)).clip(RoundedCornerShape(50)).background(p.secondaryBackground).background(tint.copy(alpha = 0.1f))
            .border(0.5.dp, tint.copy(alpha = 0.4f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 4.dp),
        style = IosTypography.caption2.copy(fontWeight = FontWeight.Bold), color = p.pillAccent, maxLines = 1, overflow = TextOverflow.Ellipsis,
    )
}

/**
 * iOS: `stashyModalSheetChrome(title, onBack:) { StashyChromeTrailingTextButton }` inside a
 * `NavigationView` + `Form` — a large modal sheet with a close button, title and trailing action.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SceneModalSheet(
    title: String,
    onDismiss: () -> Unit,
    actionTitle: String? = null,
    actionEnabled: Boolean = true,
    actionBusy: Boolean = false,
    onAction: () -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    val p = Theme.palette
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = p.background,
        dragHandle = null,
    ) {
        // Material sheet header: close ✕ · title · text action (like the other tool sheets).
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.material3.IconButton(onClick = onDismiss) { Icon(PlayerIcons.close, "Close", tint = p.text) }
            Text(title, Modifier.weight(1f).padding(start = 4.dp), style = de.letzgo.stashy.ui.NativeType.titleLarge, color = p.text, maxLines = 1)
            if (actionTitle != null) {
                if (actionBusy) CircularProgressIndicator(Modifier.padding(horizontal = 16.dp).size(20.dp), color = Appearance.tint, strokeWidth = 2.dp)
                else de.letzgo.stashy.ui.NativeTextButton(actionTitle, enabled = actionEnabled, onClick = onAction)
            }
        }
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), content = content)
        Spacer(Modifier.height(24.dp))
    }
}

/** Grouped form section (iOS `Form` `Section(header:)`). */
@Composable
fun FormSection(header: String?, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    val p = Theme.palette
    // Material settings section: titleSmall accent header, 16 dp group, bodySmall footer.
    Column(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
        header?.let { de.letzgo.stashy.ui.NativeSectionHeader(it) }
        de.letzgo.stashy.ui.NativeGroup(content = content)
        footer?.let { de.letzgo.stashy.ui.NativeSectionFooter(it) }
    }
}

internal val pillTextStyle = IosTypography.caption2.copy(fontSize = 10.sp, fontWeight = FontWeight.Bold)

