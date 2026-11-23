package de.letzgo.stashy.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import de.letzgo.stashy.R
import de.letzgo.stashy.data.DeepLink
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.GraphQLError
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.ScenesRepository
import de.letzgo.stashy.data.SecurityManager
import de.letzgo.stashy.data.ServerConfig
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.arr
import de.letzgo.stashy.data.obj
import de.letzgo.stashy.data.stringOrNull
import de.letzgo.stashy.data.vars
import de.letzgo.stashy.tr
import de.letzgo.stashy.ui.player.MiniPlayerStore
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import de.letzgo.stashy.ui.settings.ActiveServerStatus
import de.letzgo.stashy.ui.settings.connectServer
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.first

/**
 * iOS: `StashyDeepLinkRouter` — runs `stashy://` links (parsing: `data/DeepLink.kt`). The
 * activity hands every VIEW intent to [handle]; [Effect] inside `AppShell` runs the waiting link
 * once the app is unlocked, switches server through the normal path ([connectServer]) when the
 * link names another one, fetches the scene / marker and pushes its page on Home, the same way
 * Feeds' title link hands a start position to the page (`resumeTime` + `autoPlay`).
 * One link waits at a time; a newer one replaces it. Phone only (TV forwards no data).
 */
object DeepLinkRouter {
    private data class Pending(val link: DeepLink, val token: Long = System.nanoTime())

    private var pending by mutableStateOf<Pending?>(null)

    /** Returns false when [uri] is no `stashy:` link. */
    fun handle(uri: String?): Boolean = when (val result = DeepLink.parse(uri)) {
        is DeepLink.Result.Failed -> {
            log("rejected $uri")
            if (result.error != DeepLink.Error.WrongScheme) showError(tr(R.string.error_link_invalid))
            result.error != DeepLink.Error.WrongScheme
        }
        is DeepLink.Result.Ok -> { log("queued $uri"); pending = Pending(result.link); true }
    }

    /**
     * Runs the waiting link: after the unlock and once the activity is resumed (a cold start
     * composes the shell before that). The link stays queued when this run is cancelled (the
     * shell left composition, a newer link); it is dropped only once it ran, opened or failed.
     */
    @Composable
    fun Effect() {
        val current = pending ?: return
        val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
        LaunchedEffect(current.token) {
            // Never past the lock: wait for the passcode / biometrics.
            snapshotFlow { SecurityManager.isAppLocked }.first { !it }
            lifecycle.currentStateFlow.first { it.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED) }
            log("running")
            var finished = false
            try {
                open(current.link)
                finished = true
            } catch (e: CancellationException) {
                log("cancelled, stays queued")
                throw e
            } catch (e: Exception) {
                android.util.Log.w("StashyDeepLink", "open failed", e)
                showError(tr(R.string.error_link_open_failed))
                finished = true
            } finally {
                if (finished && pending?.token == current.token) pending = null
            }
        }
    }

    private fun log(message: String) {
        if (de.letzgo.stashy.BuildConfig.DEBUG) android.util.Log.d("StashyDeepLink", message)
    }

    private suspend fun open(link: DeepLink) {
        val active = ServerConfigManager.activeConfig ?: return showError(tr(R.string.error_link_no_server))
        link.server?.let { wanted ->
            // The active server wins a tie (two servers with the same name).
            val candidates = listOf(active) + ServerConfigManager.savedServers.filter { it.id != active.id }
            val match = candidates.firstOrNull { matches(wanted, it) }
                ?: return showError(tr(R.string.error_link_unknown_server_arg, wanted))
            if (match.id != active.id) {
                // The normal switch: activate, reset status and every stack.
                log("switching server")
                connectServer(match)
            }
        }
        // A real answer from the server (connected or not), not a fixed delay: on a cold start or
        // right after a switch the connection is still being made. Already known: returns at once.
        val connected = withTimeoutOrNull(15_000) {
            ActiveServerStatus.test()
            ActiveServerStatus.isConnected
        }
        log("server connected=$connected")

        val scene: Scene
        val start: Double?
        when (val target = link.target) {
            is DeepLink.Target.Scene -> {
                scene = ScenesRepository.scene(target.id) ?: return showError(tr(R.string.error_link_scene_not_found))
                start = link.time?.let { DeepLink.clamp(it, scene.sceneDuration) }
            }
            is DeepLink.Target.Marker -> {
                val marker = fetchMarker(target.id) ?: return showError(tr(R.string.error_link_marker_not_found))
                scene = ScenesRepository.scene(marker.second) ?: return showError(tr(R.string.error_link_marker_not_found))
                start = DeepLink.clamp(link.time ?: marker.first, scene.sceneDuration)
            }
        }

        // Now Playing would cover either result.
        MiniPlayerStore.showsNowPlaying = false
        val front = Nav.top as? SceneDetailScreen
        when (val route = DeepLink.route(scene.id, start, front?.sceneId)) {
            // The scene's page is on top: it stays (Back unchanged); a time seeks there.
            is DeepLink.Route.InPlace -> route.start?.let { front?.applyLinkStart(it) }
            is DeepLink.Route.Open -> {
                // One fresh page on the Home root, with its own screen key (a page of this scene
                // may still be leaving the stack). The start also goes in explicitly: the page may
                // take over a running player of this scene from the mini player.
                Nav.tab = MainTab.Home
                Nav.popToRoot(MainTab.Home)
                val shown = route.startAt?.let { scene.copy(resumeTime = it) } ?: scene
                Nav.push(SceneDetailScreen(scene.id, shown, autoPlay = route.autoPlay, fromLink = true, startAt = route.startAt))
            }
        }
    }

    private fun matches(value: String, config: ServerConfig): Boolean =
        DeepLink.serverMatches(value, config.name, listOfNotNull(config.externalBaseURL, config.localURL?.takeIf { it.isNotBlank() }))

    /** Marker id → (seconds, scene id). */
    private suspend fun fetchMarker(id: String): Pair<Double, String>? {
        val data = try {
            GraphQL.data(
                "query FindSceneMarkerById(\$ids: [ID!]) { findSceneMarkers(ids: \$ids) { scene_markers { id seconds scene { id } } } }",
                vars("ids" to listOf(id)),
            )
        } catch (e: GraphQLError.Query) {
            // Stash answers an unknown id in `ids` with an error (no rows), not an empty list. A
            // server that does not know `ids` here says "Unknown argument": that stays a failure.
            if (e.serverMessages.any { "Unknown argument" in it || "Cannot query field" in it }) throw e
            return null
        }
        val marker = data["findSceneMarkers"].obj?.get("scene_markers").arr
            ?.mapNotNull { it.obj }?.firstOrNull { it["id"].stringOrNull == id } ?: return null
        val seconds = marker["seconds"].stringOrNull?.toDoubleOrNull() ?: return null
        val sceneId = marker["scene"].obj?.get("id").stringOrNull ?: return null
        return seconds to sceneId
    }

    private fun showError(message: String) = de.letzgo.stashy.ui.tools.showToast(message, long = true)
}
