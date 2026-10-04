package de.letzgo.stashy.ui.tools.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow

// Shared chrome of the three insight tools (Overview, O-Count, Timeline).

/** iOS `.monospacedDigit()`. */
internal fun TextStyle.monoDigits(): TextStyle = copy(fontFeatureSettings = "tnum")

/**
 * iOS card chrome used by the stats cards: secondary background, card radius, 0.5 pt
 * `primary.opacity(0.1)` stroke and `cardShadow()`.
 */
@Composable
internal fun Modifier.insightsCard(shape: Shape = RoundedCornerShape(Tokens.Radius.card), fill: Color? = null): Modifier {
    val p = Theme.palette
    return this
        .cardShadow(shape)
        .clip(shape)
        .background(fill ?: p.secondaryBackground, shape)
        .border(0.5.dp, p.text.copy(alpha = 0.1f), shape)
}

/** iOS: `StashySectionHeading` — footnote, secondary, uppercase. */
@Composable
internal fun InsightsSectionHeading(title: String, modifier: Modifier = Modifier) {
    Text(title.uppercase(), style = IosTypography.footnote, color = Theme.palette.secondaryText, modifier = modifier.fillMaxWidth())
}

/** iOS: `StandardLoadingView(message:)` — `ProgressView(message)`. */
@Composable
internal fun InsightsLoading(message: String, modifier: Modifier = Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically)) {
        CircularProgressIndicator(Modifier.size(24.dp), color = Theme.palette.secondaryText, strokeWidth = 2.5.dp)
        Text(message, style = IosTypography.subheadline, color = Theme.palette.secondaryText)
    }
}

/** iOS: `ConnectionErrorView` (`StatusPlaceholderView` with server icon and retry button). */
@Composable
internal fun InsightsConnectionError(onRetry: () -> Unit, title: String = "Server not reachable") {
    val p = Theme.palette
    Column(
        Modifier.fillMaxSize().padding(horizontal = 24.dp),
        verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.lg, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(SF.server, null, tint = Appearance.tint, modifier = Modifier.size(64.dp))
        Text(title, style = IosTypography.title3.copy(fontWeight = FontWeight.Bold), color = p.text, textAlign = TextAlign.Center)
        Button(onClick = onRetry, colors = ButtonDefaults.buttonColors(containerColor = Appearance.tint, contentColor = Color.White)) {
            Text("Retry Connection", fontWeight = FontWeight.SemiBold)
        }
    }
}

/** iOS `.refreshable` — Material pull-to-refresh with the indicator below the floating chrome. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun InsightsRefreshBox(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    indicatorTop: Dp,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    val state = rememberPullToRefreshState()
    PullToRefreshBox(
        isRefreshing = isRefreshing,
        onRefresh = onRefresh,
        modifier = modifier.fillMaxSize(),
        state = state,
        indicator = {
            PullToRefreshDefaults.Indicator(
                state = state,
                isRefreshing = isRefreshing,
                modifier = Modifier.align(Alignment.TopCenter).padding(top = indicatorTop),
                containerColor = Theme.palette.secondaryBackground,
                color = Appearance.tint,
            )
        },
        content = content,
    )
}

/** Thin spacer helper. */
@Composable
internal fun VSpace(height: Dp) = Spacer(Modifier.height(height))

/** Placeholder box behind thumbnails (iOS `Color.gray.opacity(placeholder)`). */
@Composable
internal fun ThumbPlaceholder(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit = {}) {
    Box(modifier.background(Color.Gray.copy(alpha = 0.1f)), contentAlignment = Alignment.Center, content = content)
}
