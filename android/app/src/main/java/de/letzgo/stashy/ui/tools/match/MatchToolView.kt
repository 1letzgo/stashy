package de.letzgo.stashy.ui.tools.match

import de.letzgo.stashy.ui.tabBarHeight
import de.letzgo.stashy.ui.bottomBarContentPadding
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.PersonOff
import androidx.compose.material.icons.outlined.StopCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.AsyncImage
import de.letzgo.stashy.ui.components.SelectChip
import coil3.compose.AsyncImagePainter
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.tools.MatchDuelMode
import de.letzgo.stashy.data.tools.MatchElo
import de.letzgo.stashy.data.tools.MatchRepository
import de.letzgo.stashy.data.tools.MatchVoteSide
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.detail.PerformerDetailScreen
import de.letzgo.stashy.ui.tools.NoServerPlaceholder
import de.letzgo.stashy.ui.tools.ToolsTokens
import de.letzgo.stashy.ui.tools.toolsTopPadding

// iOS: `HotOrNotToolsView` and its private views (`stashy/HotOrNotToolsView.swift`).

/** iOS: `StashyExpandingDock.activeHeight` / `itemSpacing`. */
internal val MatchPillSpacing: Dp = 10.dp

/** iOS `HapticManager` counterpart on a [View]. */
internal fun View.performMatchHaptic(kind: MatchHaptic) {
    val constant = when (kind) {
        MatchHaptic.Light -> HapticFeedbackConstants.CONTEXT_CLICK
        MatchHaptic.Selection -> HapticFeedbackConstants.CLOCK_TICK
        MatchHaptic.Success -> if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.CONTEXT_CLICK
    }
    performHapticFeedback(constant)
}

private val numberStyle = TextStyle(fontFeatureSettings = "tnum")

/**
 * iOS: `HotOrNotToolsView` — Match: duel modes 1 vs. 1 / Rise / Legend, Charts leaderboard and
 * pool settings. Root composable hosted full screen by the Tools tab.
 */
@Composable
fun MatchToolView() {
    val config = ServerConfigManager.activeConfig
    if (config == null) {
        NoServerPlaceholder(SF.flame, "Select a server first to use Match.")
        return
    }
    val model: MatchViewModel = viewModel(key = "match-${config.id}")
    val view = LocalView.current
    DisposableEffect(model, view) {
        model.haptic = { view.performMatchHaptic(it) }
        onDispose { model.haptic = null }
    }
    LaunchedEffect(model) { model.onAppear() }

    val density = LocalDensity.current
    var bottomChromePx by remember { mutableIntStateOf(0) }
    val bottomChrome = with(density) { bottomChromePx.toDp() }
    val isRegular = LocalConfiguration.current.screenWidthDp >= 600
    val hPad = if (isRegular) Tokens.Spacing.xl else ToolsTokens.contentPadding

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(top = toolsTopPadding())) {
            model.errorMessage?.let { err ->
                Text(
                    err, style = IosTypography.footnote, color = StashyColors.systemRed, textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = ToolsTokens.contentPadding),
                )
            }
            MatchPillMenuRow(
                items = MatchViewModel.Section.entries.map { it.title },
                selectedIndex = model.section.ordinal,
                onSelect = { idx ->
                    view.performMatchHaptic(MatchHaptic.Selection)
                    model.selectSection(MatchViewModel.Section.entries[idx])
                },
            )
            val bottom = bottomBarContentPadding() + if (model.section == MatchViewModel.Section.Battle) bottomChrome else 0.dp
            when (model.section) {
                MatchViewModel.Section.Battle -> BattleContent(model, hPad, isRegular, bottom)
                MatchViewModel.Section.Leaderboard -> LeaderboardContent(model, hPad, isRegular, bottom)
                MatchViewModel.Section.Settings -> PoolSettings(model, hPad, bottom)
            }
        }

        // iOS: `.safeAreaInset(edge: .bottom)` — duel actions + mode pills above the tab bar.
        if (model.section == MatchViewModel.Section.Battle) {
            Column(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(bottom = tabBarHeight())
                    .onSizeChanged { bottomChromePx = it.height },
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (model.showsDuelActions) DuelActionsRow(model, hPad)
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = Tokens.Spacing.md).padding(bottom = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(MatchPillSpacing),
                ) {
                    MatchDuelMode.entries.forEach { mode ->
                        MatchPill(
                            title = mode.label,
                            selected = model.duelMode == mode,
                            enabled = !model.isSubmitting,
                            modifier = Modifier.weight(1f),
                        ) { model.selectDuelMode(mode) }
                    }
                }
            }
        }
    }
}

// MARK: - Chrome

/** iOS: `ToolsPillMenuRow` — equal-width capsules, selected = tint with glow. */
@Composable
internal fun MatchPillMenuRow(items: List<String>, selectedIndex: Int, onSelect: (Int) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = ToolsTokens.contentPadding)
            .padding(top = ToolsTokens.menuTopPadding, bottom = ToolsTokens.menuBottomPadding),
        horizontalArrangement = Arrangement.spacedBy(MatchPillSpacing),
    ) {
        items.forEachIndexed { i, title ->
            MatchPill(title, selected = i == selectedIndex, modifier = Modifier.weight(1f)) {
                if (i != selectedIndex) onSelect(i)
            }
        }
    }
}

/** Pill of `ToolsPillMenuRow` / `hotOrNotDuelModeChip` — Material `FilterChip`, label centred for equal-width rows. */
@Composable
internal fun MatchPill(title: String, selected: Boolean, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    SelectChip(title, selected, onClick, modifier, enabled = enabled, centered = true)
}

/** iOS `.buttonStyle(.bordered)` / `.borderedProminent` with a `Label` — Material filled / tonal button. */
@Composable
private fun MatchActionButton(
    title: String,
    icon: ImageVector,
    prominent: Boolean,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    accessibilityLabel: String? = null,
    onClick: () -> Unit,
) {
    val tint = Appearance.tint
    val padding = PaddingValues(horizontal = 10.dp)
    @Suppress("NAME_SHADOWING")
    val modifier = if (accessibilityLabel != null) modifier.semantics { contentDescription = accessibilityLabel } else modifier
    val label: @Composable RowScope.() -> Unit = {
        Icon(icon, null, modifier = Modifier.size(ButtonDefaults.IconSize))
        Spacer(Modifier.width(ButtonDefaults.IconSpacing))
        Text(title, style = MaterialTheme.typography.labelLarge, maxLines = 1)
    }
    if (prominent) {
        Button(
            onClick, modifier, enabled = enabled, contentPadding = padding,
            colors = ButtonDefaults.buttonColors(containerColor = tint, contentColor = Color.White),
            content = label,
        )
    } else {
        FilledTonalButton(
            onClick, modifier, enabled = enabled, contentPadding = padding,
            colors = ButtonDefaults.filledTonalButtonColors(containerColor = tint.copy(alpha = 0.15f), contentColor = tint),
            content = label,
        )
    }
}

/** iOS: `hotOrNotDuelActionsRow` — Draw / Stop, New pair, Stop. */
@Composable
private fun DuelActionsRow(model: MatchViewModel, hPad: Dp) {
    val view = LocalView.current
    Row(Modifier.fillMaxWidth().padding(horizontal = hPad), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (model.duelMode == MatchDuelMode.Champion) {
            MatchActionButton("Stop", Icons.Outlined.StopCircle, prominent = false, enabled = !model.isSubmitting, modifier = Modifier.weight(1f), accessibilityLabel = "End Legend run") {
                view.performMatchHaptic(MatchHaptic.Light)
                model.startNewClimbRun()
            }
        } else {
            MatchActionButton("Draw", Icons.Filled.DragHandle, prominent = false, enabled = !model.isSubmitting, modifier = Modifier.weight(1f)) {
                model.skipDrawAsync()
            }
        }
        if (model.duelMode == MatchDuelMode.Placement) {
            MatchActionButton("New pair", Icons.Filled.Autorenew, prominent = false, enabled = false, modifier = Modifier.weight(1f), accessibilityLabel = "New pair, not available in Rise") {}
            MatchActionButton("Stop", Icons.Outlined.StopCircle, prominent = true, enabled = !model.isSubmitting, modifier = Modifier.weight(1f), accessibilityLabel = "End Rise run") {
                view.performMatchHaptic(MatchHaptic.Light)
                model.startNewClimbRun()
            }
        } else {
            MatchActionButton(
                "New pair", Icons.Filled.Autorenew, prominent = true,
                enabled = !model.isSubmitting && !model.isLoadingPair, modifier = Modifier.weight(1f),
            ) { model.newPair() }
        }
    }
}

// MARK: - Shared bits

/** iOS: `StandardLoadingView(message:)`. */
@Composable
internal fun MatchLoadingView(message: String, modifier: Modifier = Modifier) {
    val p = Theme.palette
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically)) {
        CircularProgressIndicator(color = p.secondaryText)
        Text(message, style = IosTypography.subheadline, color = p.secondaryText)
    }
}

/** iOS: `ContentUnavailableView(title, systemImage:, description:)`. */
@Composable
internal fun MatchUnavailableView(title: String, icon: ImageVector, description: String?, modifier: Modifier = Modifier) {
    val p = Theme.palette
    Column(
        modifier.padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
    ) {
        Icon(icon, null, tint = p.secondaryText, modifier = Modifier.size(44.dp))
        Text(title, style = IosTypography.title3.copy(fontWeight = FontWeight.Bold), color = p.text, textAlign = TextAlign.Center)
        if (!description.isNullOrEmpty()) {
            Text(description, style = IosTypography.subheadline, color = p.secondaryText, textAlign = TextAlign.Center)
        }
    }
}

/** Card chrome used across Match: secondary fill, 0.5 pt primary stroke at 10 %, card shadow. */
@Composable
private fun Modifier.matchCard(shape: RoundedCornerShape = RoundedCornerShape(Tokens.Radius.card)): Modifier {
    val p = Theme.palette
    return this
        .cardShadow(shape)
        .clip(shape)
        .background(p.secondaryBackground, shape)
        .border(0.5.dp, p.text.copy(alpha = 0.1f), shape)
}

/** Performer photo with spinner while loading and the `person.fill` placeholder (iOS `photoOverlay`). */
@Composable
private fun PerformerPhoto(performer: Performer, modifier: Modifier = Modifier, placeholderSize: Dp = 34.dp) {
    val url = remember(performer.id, performer.imagePath) { MatchRepository.thumbnailURL(performer) }
    var state by remember(url) { mutableStateOf<AsyncImagePainter.State?>(null) }
    Box(modifier.background(Color.Gray.copy(alpha = 0.1f)), contentAlignment = Alignment.Center) {
        if (url != null) {
            AsyncImage(
                model = url, contentDescription = performer.name, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(), onState = { state = it },
            )
        }
        when {
            url == null || state is AsyncImagePainter.State.Error ->
                Icon(Icons.Filled.Person, null, tint = StashyColors.appAccent.copy(alpha = 0.45f), modifier = Modifier.size(placeholderSize))
            state == null || state is AsyncImagePainter.State.Loading ->
                CircularProgressIndicator(Modifier.size(22.dp), color = Theme.palette.secondaryText, strokeWidth = 2.dp)
        }
    }
}

// MARK: - Battle

@Composable
private fun BattleContent(model: MatchViewModel, hPad: Dp, isRegular: Boolean, bottom: Dp) {
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = hPad)
            .padding(bottom = bottom),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        val l = model.left
        val r = model.right
        val victor = model.climbVictory
        when {
            victor != null -> VictoryCard(model, victor)
            model.needsPlacementStarterSelection -> PlacementStarterInline(model)
            model.isLoadingPair && l == null -> MatchLoadingView("Loading pair...", Modifier.fillMaxWidth().heightIn(min = 320.dp))
            l != null && r != null -> Row(
                Modifier.fillMaxWidth().let { if (isRegular) it.widthIn(max = 920.dp) else it },
                horizontalArrangement = Arrangement.spacedBy(if (isRegular) 20.dp else 10.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    BattleColumn(model, l, model.rankLeft, model.duelFeedback?.left) { model.chooseAsync(leftWins = true) }
                    ProfileLinkCard(l)
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    BattleColumn(model, r, model.rankRight, model.duelFeedback?.right) { model.chooseAsync(leftWins = false) }
                    ProfileLinkCard(r)
                }
            }
        }
        Spacer(Modifier.height(ToolsTokens.menuBottomPadding))
    }
}

/** iOS: Legend / Rise finished — "Legend!" card with New run. */
@Composable
private fun VictoryCard(model: MatchViewModel, victor: Performer) {
    val p = Theme.palette
    val tint = Appearance.tint
    Column(
        Modifier.fillMaxWidth().matchCard().padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Legend!", style = IosTypography.title2.copy(fontWeight = FontWeight.Bold), color = p.text)
        Text(victor.name, style = IosTypography.headline, color = p.text, textAlign = TextAlign.Center)
        Text("${model.climbWins} wins · cleared the ladder", style = IosTypography.caption, color = p.secondaryText, textAlign = TextAlign.Center)
        Box(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(50)).background(tint)
                .clickable { model.startNewClimbRun() }.padding(vertical = 6.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text("New run", style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
        }
    }
}

/** iOS: `HotOrNotBattleColumn` — photo, name, fixed 3×2 info grid; tap = vote; feedback overlay. */
@Composable
private fun BattleColumn(
    model: MatchViewModel,
    performer: Performer,
    rank: Int?,
    voteFeedback: MatchVoteSide?,
    choose: () -> Unit,
) {
    val p = Theme.palette
    val shape = RoundedCornerShape(Tokens.Radius.card)
    val rows = remember(performer) { MatchElo.battleInfoRows(performer) }
    // Keep the last feedback for the fade-out.
    var shown by remember { mutableStateOf(voteFeedback) }
    LaunchedEffect(voteFeedback) { if (voteFeedback != null) shown = voteFeedback }
    val display = voteFeedback ?: shown

    Box(
        Modifier
            .fillMaxWidth()
            .matchCard(shape)
            .semantics { contentDescription = "Choose ${performer.name}" }
            .clickable(
                enabled = !model.isSubmitting,
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = choose,
            ),
    ) {
        Column(Modifier.fillMaxWidth()) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .aspectRatio(3f / 4f)
                    .clip(RoundedCornerShape(topStart = Tokens.Radius.card, topEnd = Tokens.Radius.card)),
            ) {
                PerformerPhoto(performer, Modifier.fillMaxSize())
                if (rank != null) {
                    Text(
                        "#$rank",
                        style = IosTypography.caption2.copy(fontWeight = FontWeight.Bold),
                        color = p.text,
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(8.dp)
                            .background(p.secondaryBackground.copy(alpha = 0.75f), CircleShape)
                            .padding(6.dp),
                    )
                }
            }
            Column(Modifier.fillMaxWidth().padding(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    performer.name, style = IosTypography.subheadline.copy(fontWeight = FontWeight.Bold), color = p.text,
                    maxLines = 3, overflow = TextOverflow.Ellipsis,
                )
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    rows.chunked(2).forEach { pair ->
                        Row(Modifier.fillMaxWidth()) {
                            pair.forEach { (label, value) ->
                                Column(Modifier.weight(1f)) {
                                    Text(label.uppercase(), fontSize = 8.sp, lineHeight = 10.sp, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(
                                        value, fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.Medium, color = p.text,
                                        maxLines = 2, overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        AnimatedVisibility(
            visible = voteFeedback != null,
            modifier = Modifier.matchParentSize(),
            enter = fadeIn(tween(180)),
            exit = fadeOut(tween(150)),
        ) {
            val vote = display
            if (vote != null) {
                val fill = when {
                    vote.delta100 > 0 -> StashyColors.systemGreen.copy(alpha = 0.42f)
                    vote.delta100 < 0 -> StashyColors.systemRed.copy(alpha = 0.42f)
                    else -> StashyColors.defaultTint.copy(alpha = 0.35f)
                }
                val shadow = Shadow(Color.Black.copy(alpha = 0.35f), Offset(0f, 2f), 4f)
                Box(Modifier.fillMaxSize().background(fill, shape), contentAlignment = Alignment.Center) {
                    Column(
                        Modifier.padding(horizontal = 8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            if (vote.delta100 > 0) "+${vote.delta100}" else "${vote.delta100}",
                            style = numberStyle.copy(fontSize = 30.sp, fontWeight = FontWeight.ExtraBold, shadow = shadow),
                            color = Color.White,
                        )
                        Text("SCORE", fontSize = 9.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.92f))
                        Text(
                            "${vote.rating100After}",
                            style = IosTypography.title2.merge(numberStyle).copy(fontWeight = FontWeight.Bold, shadow = shadow),
                            color = Color.White,
                        )
                    }
                }
            }
        }
    }
}

/** iOS: `HotOrNotProfileLinkCard` — row under each duel column, pushes the performer detail. */
@Composable
private fun ProfileLinkCard(performer: Performer) {
    val p = Theme.palette
    Row(
        Modifier
            .fillMaxWidth()
            .matchCard()
            .semantics { contentDescription = "Profile, ${performer.name}" }
            .clickable { Nav.push(PerformerDetailScreen(performer.id, performer)) }
            .padding(12.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Outlined.Groups, null, tint = p.text, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(6.dp))
        Text("Profile", style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = p.text)
    }
}

/** iOS: `placementStarterInline` — 3-column grid of up to six Rise starters. */
@Composable
private fun PlacementStarterInline(model: MatchViewModel) {
    when {
        model.isLoadingPlacementStarters && model.placementStarters.isEmpty() ->
            MatchLoadingView("Loading starters...", Modifier.fillMaxWidth().heightIn(min = 220.dp))
        model.placementStarters.isEmpty() ->
            MatchUnavailableView("No starters", Icons.Outlined.PersonOff, model.errorMessage ?: "", Modifier.fillMaxWidth())
        else -> Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            model.placementStarters.take(6).chunked(3).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { performer ->
                        StarterPickCard(model, performer, Modifier.weight(1f)) { model.pickPlacementStarter(performer) }
                    }
                    repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

/** iOS: `HotOrNotGauntletStarterPickCard` — photo, name (2 lines reserved), rating only. */
@Composable
private fun StarterPickCard(model: MatchViewModel, performer: Performer, modifier: Modifier, onPick: () -> Unit) {
    val p = Theme.palette
    Column(
        modifier
            .matchCard()
            .semantics { contentDescription = "Pick ${performer.name} as Rise starter" }
            .clickable(enabled = !model.isSubmitting, onClick = onPick),
    ) {
        PerformerPhoto(
            performer,
            Modifier
                .fillMaxWidth()
                .aspectRatio(3f / 4f)
                .clip(RoundedCornerShape(topStart = Tokens.Radius.card, topEnd = Tokens.Radius.card)),
            placeholderSize = 28.dp,
        )
        Column(Modifier.fillMaxWidth().padding(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                performer.name, style = IosTypography.subheadline.copy(fontWeight = FontWeight.Bold), color = p.text,
                maxLines = 2, minLines = 2, overflow = TextOverflow.Ellipsis,
            )
            Column {
                Text("RATING", fontSize = 8.sp, lineHeight = 10.sp, color = p.secondaryText)
                Text(
                    "${performer.rating100 ?: MatchElo.DEFAULT_RATING}",
                    style = numberStyle.copy(fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.Medium), color = p.text,
                )
            }
        }
    }
}

// MARK: - Charts

@Composable
private fun LeaderboardContent(model: MatchViewModel, hPad: Dp, isRegular: Boolean, bottom: Dp) {
    if (model.isLoadingBoard && model.leaderboard.isEmpty()) {
        MatchLoadingView("Loading charts...", Modifier.fillMaxSize())
        return
    }
    LazyVerticalGrid(
        columns = GridCells.Fixed(if (isRegular) 2 else 1),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = hPad, end = hPad, bottom = bottom + ToolsTokens.menuBottomPadding),
        verticalArrangement = Arrangement.spacedBy(ToolsTokens.rankedGridSpacing),
        horizontalArrangement = Arrangement.spacedBy(ToolsTokens.rankedGridSpacing),
    ) {
        itemsIndexed(model.leaderboard, key = { _, p -> p.id }) { index, performer ->
            LeaderboardCard(performer, index + 1) { Nav.push(PerformerDetailScreen(performer.id, performer)) }
        }
        if (model.leaderboardHasMore) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                // iOS: `PaginationLoadingFooter().onAppear { loadMoreLeaderboard() }`.
                LaunchedEffect(model.leaderboard.size) { model.loadMoreLeaderboardAsync() }
                Box(Modifier.fillMaxWidth().padding(16.dp), Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(22.dp), color = Theme.palette.secondaryText, strokeWidth = 2.dp)
                }
            }
        }
    }
}

/** iOS: `HotOrNotLeaderboardCard` — thumbnail strip with place badge, name, stats, streaks. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LeaderboardCard(performer: Performer, place: Int, onClick: () -> Unit) {
    val p = Theme.palette
    val s = remember(performer) { MatchElo.stats(performer) }
    val thumbWidth = 68.dp
    val shape = RoundedCornerShape(Tokens.Radius.card)
    Box(Modifier.fillMaxWidth().matchCard(shape).clickable(onClick = onClick)) {
        // Thumbnail as background so the text column alone decides the height (min 90 pt).
        Box(Modifier.matchParentSize()) {
            Box(
                Modifier
                    .fillMaxHeight()
                    .width(thumbWidth)
                    .clip(RoundedCornerShape(topStart = Tokens.Radius.card, bottomStart = Tokens.Radius.card)),
            ) {
                PerformerPhoto(performer, Modifier.fillMaxSize(), placeholderSize = 24.dp)
                Text(
                    "#$place",
                    fontSize = 9.sp, fontWeight = FontWeight.Bold, color = p.text,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(4.dp)
                        .background(p.secondaryBackground.copy(alpha = 0.75f), CircleShape)
                        .padding(horizontal = 6.dp, vertical = 3.dp),
                )
            }
        }
        Row(Modifier.fillMaxWidth().heightIn(min = 90.dp)) {
            Spacer(Modifier.width(thumbWidth + 12.dp))
            Column(
                Modifier.weight(1f).padding(top = 10.dp, bottom = 10.dp, end = 10.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    performer.name, style = IosTypography.subheadline.copy(fontWeight = FontWeight.Bold), color = p.text,
                    maxLines = 2, overflow = TextOverflow.Ellipsis,
                )
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    // 5 columns; at large font scales they wrap into rows of 3 instead of clipping the numbers.
                    FlowRow(
                        Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp),
                        maxItemsInEachRow = if (LocalDensity.current.fontScale > 1.3f) 3 else 5,
                    ) {
                        StatColumn("Rating", "${performer.rating100 ?: MatchElo.DEFAULT_RATING}", Modifier.weight(1f))
                        StatColumn("Duels", "${s.totalMatches}", Modifier.weight(1f))
                        StatColumn("W", "${s.wins}", Modifier.weight(1f))
                        StatColumn("L", "${s.losses}", Modifier.weight(1f))
                        StatColumn("D", "${s.draws}", Modifier.weight(1f))
                    }
                    MatchElo.streakSummaryLine(s)?.let {
                        Text(it, style = IosTypography.caption2, color = p.tertiaryText, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

@Composable
private fun StatColumn(title: String, value: String, modifier: Modifier) {
    val p = Theme.palette
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(title.uppercase(), fontSize = 8.sp, lineHeight = 10.sp, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(
            value,
            style = IosTypography.title2.merge(numberStyle).copy(fontWeight = FontWeight.Bold),
            color = p.text, maxLines = 1, softWrap = false, overflow = TextOverflow.Clip, textAlign = TextAlign.Center,
        )
    }
}

// MARK: - Settings

/** iOS: `HotOrNotPoolSettingsView` — "Genders in pool" toggles. */
@Composable
private fun PoolSettings(model: MatchViewModel, hPad: Dp, bottom: Dp) {
    val p = Theme.palette
    val tint = Appearance.tint
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(bottom = bottom),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            "Genders in pool",
            style = IosTypography.title3.copy(fontWeight = FontWeight.SemiBold), color = p.text,
            modifier = Modifier.padding(horizontal = 12.dp).padding(top = 8.dp),
        )
        Column(
            Modifier
                .padding(horizontal = hPad)
                .padding(bottom = ToolsTokens.menuBottomPadding)
                .fillMaxWidth()
                .matchCard(),
        ) {
            MatchRepository.genderRows.forEachIndexed { index, (code, label) ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable { model.toggleGender(code) }
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(label, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = p.text, modifier = Modifier.weight(1f))
                    Switch(
                        checked = code in model.selectedGenders,
                        onCheckedChange = { model.toggleGender(code) },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Color.White,
                            checkedTrackColor = tint,
                            checkedBorderColor = tint,
                            uncheckedThumbColor = Color.White,
                            uncheckedTrackColor = p.separator,
                            uncheckedBorderColor = p.separator,
                        ),
                    )
                }
                if (index < MatchRepository.genderRows.size - 1) {
                    Box(Modifier.fillMaxWidth().padding(start = 12.dp).height(0.5.dp).background(p.separator))
                }
            }
        }
    }
}
