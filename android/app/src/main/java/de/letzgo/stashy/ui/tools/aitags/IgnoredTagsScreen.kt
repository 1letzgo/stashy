package de.letzgo.stashy.ui.tools.aitags

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.outlined.ThumbDown
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.tools.AITagSuggestions
import de.letzgo.stashy.ui.EmptyState
import de.letzgo.stashy.ui.NativeConfirmDialog
import de.letzgo.stashy.ui.NativeSearchField
import de.letzgo.stashy.ui.NativeTopBar
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.nativeTopBarPadding
import de.letzgo.stashy.ui.tools.GroupedCard
import de.letzgo.stashy.ui.tools.RowDivider
import de.letzgo.stashy.ui.tools.SectionSpacer
import de.letzgo.stashy.ui.tools.SettingsList
import de.letzgo.stashy.ui.tools.SettingsRow
import de.letzgo.stashy.ui.tools.SettingsSectionFooter
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

/**
 * iOS: `IgnoredTagsView` (Settings › Recommendations › Ignored Tags) — every tag waved away with
 * "Ignore Tag", each removable on its own, plus Reset All behind a confirmation. Names come from
 * the statistics; a tag they never saw is asked for on the server, one deleted there shows as
 * "Unknown Tag" with its id and can still be removed.
 */
class IgnoredTagsScreen : Screen {
    override val key: String = "ignored-tags"

    @Composable
    override fun Content() = IgnoredTagsView()
}

/** The search field appears once the list is long enough to need it (iOS `searchThreshold`). */
private const val SEARCH_THRESHOLD = 8

private data class IgnoredTagEntry(val id: String, val name: String?)

@Composable
private fun IgnoredTagsView() {
    val p = Theme.palette
    val manager = AITagSuggestions
    val fetchedNames = remember { mutableStateMapOf<String, String>() }
    val missingIds = remember { mutableStateMapOf<String, Boolean>() }
    var search by remember { mutableStateOf("") }
    var confirmsResetAll by remember { mutableStateOf(false) }

    val ids = manager.ignoredTagIds
    LaunchedEffect(Unit) {
        manager.loadIfNeeded()
        // Ids the statistics don't know: ask the server, a few at a time.
        val unresolved = manager.ignoredTagIds.filter { manager.knownTagName(it) == null }.take(50)
        coroutineScope {
            unresolved.map { id ->
                async {
                    val result = runCatching { DetailRepository.tag(id) }
                    result.getOrNull()?.let { fetchedNames[id] = it.name }
                    if (result.isSuccess && result.getOrNull() == null) missingIds[id] = true
                }
            }.awaitAll()
        }
    }

    val all = ids.map { IgnoredTagEntry(it, manager.knownTagName(it) ?: fetchedNames[it]) }
        .sortedWith(compareBy<IgnoredTagEntry> { it.name == null }.thenBy { it.name?.lowercase() ?: it.id })
    val term = search.trim()
    val shown = if (term.isEmpty()) all else all.filter { (it.name ?: it.id).contains(term, ignoreCase = true) || it.id == term }

    val topBar = nativeTopBarPadding()
    Box(Modifier.fillMaxSize().background(p.background)) {
        SettingsList(topPadding = topBar) {
            if (all.isEmpty()) {
                item {
                    Box(Modifier.fillMaxWidth().padding(top = 48.dp), contentAlignment = Alignment.Center) {
                        EmptyState(Icons.Outlined.ThumbDown, tr(R.string.empty_no_ignored_tags), tr(R.string.hint_ignored_tags))
                    }
                }
            } else {
                if (all.size >= SEARCH_THRESHOLD) {
                    item {
                        Box(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                            NativeSearchField(search, { search = it })
                        }
                        SectionSpacer()
                    }
                }
                item {
                    GroupedCard {
                        if (shown.isEmpty()) SettingsRow(tr(R.string.nothing_found), titleColor = p.secondaryText)
                        shown.forEachIndexed { i, entry ->
                            if (i > 0) RowDivider(16.dp)
                            val isMissing = missingIds[entry.id] == true
                            SettingsRow(
                                entry.name ?: if (isMissing) tr(R.string.unknown_tag) else entry.id,
                                SF.tag,
                                titleColor = if (entry.name == null) p.secondaryText else p.text,
                                subtitle = if (entry.name == null && isMissing) "ID ${entry.id}" else null,
                            ) {
                                IconButton({ manager.undismiss(entry.id) }) {
                                    Icon(SF.trash, tr(R.string.action_remove), tint = p.secondaryText, modifier = Modifier.size(20.dp))
                                }
                            }
                        }
                    }
                    SettingsSectionFooter(tr(R.string.hint_ignored_tags))
                    SectionSpacer()
                }
                item {
                    GroupedCard {
                        SettingsRow(
                            tr(R.string.action_reset_all), Icons.AutoMirrored.Filled.Undo,
                            iconTint = StashyColors.systemRed, titleColor = StashyColors.systemRed,
                            onClick = { confirmsResetAll = true },
                        )
                    }
                }
            }
        }
        NativeTopBar(tr(R.string.ignored_tags))
    }
    if (confirmsResetAll) {
        NativeConfirmDialog(
            tr(R.string.confirm_reset_ignored_tags), null,
            onDismiss = { confirmsResetAll = false }, confirmLabel = tr(R.string.action_reset_all), destructive = true,
            onConfirm = { manager.resetDismissals(); confirmsResetAll = false },
        )
    }
}
