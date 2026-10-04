package de.letzgo.stashy.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusRestorer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.UniversalSearchRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** iOS: `TVSearchView` state — debounced (420 ms, ≥ 2 characters) search over five kinds. */
class TvSearchModel {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val focus = TvFocusMemory()
    var query by mutableStateOf("")
        private set
    var hasSearched by mutableStateOf(false); private set
    var isBusy by mutableStateOf(false); private set
    var didAutoFocus = false
    val scenes = mutableStateListOf<Scene>()
    val performers = mutableStateListOf<Performer>()
    val studios = mutableStateListOf<Studio>()
    val tags = mutableStateListOf<Tag>()
    val groups = mutableStateListOf<StashGroup>()
    private var job: Job? = null

    val hasAnyResults: Boolean get() = scenes.isNotEmpty() || performers.isNotEmpty() || studios.isNotEmpty() || tags.isNotEmpty() || groups.isNotEmpty()

    fun update(text: String) {
        query = text
        job?.cancel()
        val trimmed = text.trim()
        if (trimmed.length < 2) { clear(); return }
        job = scope.launch { delay(420); run(trimmed) }
    }

    fun commit() {
        job?.cancel()
        val trimmed = query.trim()
        if (trimmed.length < 2) { clear(); return }
        job = scope.launch { run(trimmed) }
    }

    fun reset() { job?.cancel(); query = ""; clear() }

    private fun clear() {
        hasSearched = false
        scenes.clear(); performers.clear(); studios.clear(); tags.clear(); groups.clear()
    }

    private suspend fun run(q: String) {
        hasSearched = true
        isBusy = true
        val s = scope.async { runCatching { UniversalSearchRepository.scenes(q, 20) }.getOrDefault(emptyList()) }
        val p = scope.async { runCatching { UniversalSearchRepository.performers(q, 50) }.getOrDefault(emptyList()) }
        val st = scope.async { runCatching { UniversalSearchRepository.studios(q, 50) }.getOrDefault(emptyList()) }
        val t = scope.async { runCatching { UniversalSearchRepository.tags(q, 50) }.getOrDefault(emptyList()) }
        val g = scope.async { runCatching { UniversalSearchRepository.groups(q, 20) }.getOrDefault(emptyList()) }
        scenes.apply { clear(); addAll(s.await()) }
        performers.apply { clear(); addAll(p.await()) }
        studios.apply { clear(); addAll(st.await()) }
        tags.apply { clear(); addAll(t.await()) }
        groups.apply { clear(); addAll(g.await()) }
        isBusy = false
    }

    fun dispose() = scope.cancel()
}

/** iOS: `TVSearchView` — own search field, then result rows per kind. */
@Composable
fun TvSearch(model: TvSearchModel) {
    val fieldFocus = remember { FocusRequester() }
    Box(Modifier.fillMaxSize().background(TvColors.background)) {
        if (ServerConfigManager.activeConfig?.hasValidConfig != true) {
            TvConnectionError(subtitle = "Add a server in Settings.") {}
            return@Box
        }
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = pt(40), end = pt(40), top = pt(48), bottom = pt(140)),
            verticalArrangement = Arrangement.spacedBy(pt(44)),
        ) {
            item(key = "bar") {
                Row(
                    Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(28)),
                ) {
                    Icon(TvIcons.magnifier, null, Modifier.size(pt(44)), tint = TvColors.secondary)
                    TvTextField(
                        "Scenes, Performers …", model.query, { model.update(it) },
                        Modifier.weight(1f).focusRequester(fieldFocus).tvFocusMemory(model.focus, "field"),
                        imeAction = ImeAction.Search, onSubmit = { model.commit() },
                    )
                    if (model.query.isNotBlank()) {
                        TvButton({ model.reset(); runCatching { fieldFocus.requestFocus() } }) { Icon(TvIcons.clear, "Clear input", Modifier.size(pt(36))) }
                    }
                }
            }
            when {
                model.isBusy && !model.hasAnyResults -> item(key = "busy") { TvLoading("Searching …") }
                model.hasSearched && !model.hasAnyResults -> item(key = "none") {
                    Column(Modifier.fillMaxWidth().padding(top = pt(40)), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(20))) {
                        Icon(TvIcons.magnifier, null, Modifier.size(pt(56)), tint = TvColors.secondary)
                        Text("No results for \"${model.query}\"", style = TvType.title3, color = TvColors.secondary)
                        TvButton({ runCatching { fieldFocus.requestFocus() } }) { Text("Refine Search", style = TvType.headline) }
                    }
                }
                model.hasSearched -> results(model)
                else -> item(key = "placeholder") {
                    Column(Modifier.fillMaxWidth().padding(top = pt(60)), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(16))) {
                        Icon(TvIcons.magnifier, null, Modifier.size(pt(56)), tint = TvColors.secondary)
                        Text("Search your Stash library", style = TvType.title3, color = TvColors.secondary)
                        Text("Type at least two characters. Remote or voice input supported.", style = TvType.callout, color = TvColors.secondary, textAlign = TextAlign.Center)
                    }
                }
            }
        }
    }
    val inputMode = androidx.compose.ui.platform.LocalInputModeManager.current
    // Only on the first visit: returning from a result keeps focus on that result.
    LaunchedEffect(Unit) {
        if (model.didAutoFocus) return@LaunchedEffect
        delay(200)
        inputMode.requestKeyboardMode()
        runCatching { fieldFocus.requestFocus() }
        TvFocusLog.log("initial", "search.field")
        model.didAutoFocus = true
    }
}

private fun LazyListScope.results(model: TvSearchModel) {
    if (model.scenes.isNotEmpty()) item(key = "scenes") {
        ResultSection(TvIcons.film, "Scenes", model.scenes.size) {
            items(model.scenes, key = { it.id }) { s -> TvSceneTile(s, { TvNav.push(TvSceneDetailRoute(s.id, s)) }, Modifier.tvFocusMemory(model.focus, "s.${s.id}"), pt(400), pt(225)) }
        }
    }
    if (model.performers.isNotEmpty()) item(key = "performers") {
        ResultSection(TvIcons.person2, "Performers", model.performers.size) {
            items(model.performers, key = { it.id }) { p -> TvPerformerCard(p, { TvNav.push(TvPerformerDetailRoute(p.id, p.name)) }, Modifier.tvFocusMemory(model.focus, "p.${p.id}")) }
        }
    }
    if (model.studios.isNotEmpty()) item(key = "studios") {
        ResultSection(TvIcons.building, "Studios", model.studios.size) {
            items(model.studios, key = { it.id }) { s -> TvStudioCard(s, { TvNav.push(TvStudioDetailRoute(s.id, s.name)) }, Modifier.tvFocusMemory(model.focus, "st.${s.id}")) }
        }
    }
    if (model.tags.isNotEmpty()) item(key = "tags") {
        ResultSection(TvIcons.tag, "Tags", model.tags.size) {
            items(model.tags, key = { it.id }) { t -> TvTagCard(t, { TvNav.push(TvTagDetailRoute(t.id, t.name)) }, Modifier.tvFocusMemory(model.focus, "t.${t.id}")) }
        }
    }
    if (model.groups.isNotEmpty()) item(key = "groups") {
        ResultSection(TvIcons.stack, "Groups", model.groups.size) {
            items(model.groups, key = { it.id }) { g -> TvGroupCard(g, { TvNav.push(TvGroupDetailRoute(g.id, g.name)) }, Modifier.tvFocusMemory(model.focus, "g.${g.id}")) }
        }
    }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun ResultSection(icon: ImageVector, title: String, count: Int, content: LazyListScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(pt(18))) {
        Row(Modifier.padding(horizontal = pt(50)), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(12))) {
            Icon(icon, null, Modifier.size(pt(34)), tint = TvColors.tint)
            Text(title, style = TvType.title2, color = Color.White)
            Text("$count", style = TvType.callout, color = TvColors.secondary)
        }
        LazyRow(Modifier.focusRestorer(), horizontalArrangement = Arrangement.spacedBy(pt(30)), contentPadding = PaddingValues(horizontal = pt(50), vertical = pt(20)), content = content)
    }
}
