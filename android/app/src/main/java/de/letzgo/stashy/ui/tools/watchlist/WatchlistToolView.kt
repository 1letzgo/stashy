package de.letzgo.stashy.ui.tools.watchlist

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.WatchlistStore
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.bottomBarContentPadding
import de.letzgo.stashy.ui.player.MiniPlayerStore
import de.letzgo.stashy.ui.player.WatchlistDragState
import de.letzgo.stashy.ui.player.WatchlistIcons
import de.letzgo.stashy.ui.player.watchlistRows
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import de.letzgo.stashy.ui.tools.ToolsTokens
import de.letzgo.stashy.ui.tools.toolsTopPadding

/**
 * iOS: `WatchlistToolsView` (Tools › Library › Watchlist) — "Play all" + "Reset", then the same
 * plain, reorderable watchlist as Now Playing. A row opens that scene's page with autoplay;
 * leaving it hands the video to the mini player as usual.
 */
@Composable
fun WatchlistToolView() {
    val p = Theme.palette
    val scenes = WatchlistStore.all
    val drag = remember { WatchlistDragState() }
    var confirmReset by remember { mutableStateOf(false) }
    if (confirmReset) AlertDialog(
        onDismissRequest = { confirmReset = false },
        title = { Text("Reset watchlist?") },
        text = { Text("All scenes are removed from the watchlist.") },
        confirmButton = { TextButton({ confirmReset = false; WatchlistStore.clear() }) { Text("Reset", color = StashyColors.systemRed) } },
        dismissButton = { TextButton({ confirmReset = false }) { Text("Cancel") } },
        containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.secondaryText,
    )

    if (scenes.isEmpty()) {
        Column(
            Modifier.fillMaxSize().padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        ) {
            Icon(WatchlistIcons.add, null, tint = p.secondaryText, modifier = Modifier.size(48.dp))
            Text("Watchlist is empty", style = IosTypography.headline, color = p.text)
            Text(
                "Add scenes with \"Add to watchlist\" on a scene. They play one after another in the mini player.",
                style = IosTypography.subheadline, color = p.secondaryText, textAlign = TextAlign.Center,
            )
        }
        return
    }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = toolsTopPadding(), bottom = bottomBarContentPadding()),
    ) {
        item(key = "actions") {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = ToolsTokens.contentPadding)
                    .padding(top = ToolsTokens.menuTopPadding, bottom = ToolsTokens.menuBottomPadding),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Row(
                    Modifier.weight(1f).height(40.dp).clip(RoundedCornerShape(50)).background(Appearance.tint)
                        .clickable { scenes.firstOrNull()?.let { open(it) } },
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(SF.playFill, null, tint = Color.White, modifier = Modifier.size(18.dp))
                    Text("  Play all", style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
                }
                Box(
                    Modifier.height(40.dp).clip(RoundedCornerShape(50)).background(p.secondaryBackground)
                        .clickable { confirmReset = true }.padding(horizontal = 18.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("Reset", style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = StashyColors.systemRed)
                }
            }
        }
        watchlistRows(scenes.toList(), MiniPlayerStore.session?.scene?.id, drag, ToolsTokens.contentPadding) { open(it) }
    }
}

private fun open(scene: de.letzgo.stashy.data.Scene) {
    Nav.push(SceneDetailScreen(scene.id, scene, autoPlay = true))
}
