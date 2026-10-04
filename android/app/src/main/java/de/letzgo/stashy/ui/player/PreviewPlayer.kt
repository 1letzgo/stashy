package de.letzgo.stashy.ui.player

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.input.pointer.pointerInput
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.background
import de.letzgo.stashy.data.Prefs
import java.lang.ref.WeakReference

/**
 * iOS: `AetherPreviewPool` — caps how many preview players decode at once (2). A new preview
 * evicts the least recently started one outright: previews are decoration.
 */
object PreviewPlayerPool {
    const val MAX_CONCURRENT = 2
    private val owners = mutableListOf<WeakReference<PreviewPlayer>>()

    internal fun acquire(owner: PreviewPlayer): StashPlayer {
        owners.removeAll { it.get() == null || it.get() === owner }
        while (owners.size >= MAX_CONCURRENT) {
            owners.removeAt(0).get()?.stop(release = true)
            owners.removeAll { it.get() == null }
        }
        owners += WeakReference(owner)
        return StashPlayer(Prefs.appContext, StashPlayer.Role.Preview).apply { loops = true; isMuted = true }
    }

    internal fun release(owner: PreviewPlayer) {
        owners.removeAll { it.get() == null || it.get() === owner }
    }
}

/**
 * iOS: `AetherPreviewPlayer` — a muted, looping preview. [start] is idempotent for the same URL,
 * [stop] pauses or (`release = true`) gives the player and its pool slot back. Use from cards
 * (long-press preview) and from Feeds for muted autoplay; draw it with [PreviewSurface].
 */
class PreviewPlayer {
    var player by mutableStateOf<StashPlayer?>(null); private set
    private var currentURL: String? = null

    val hasFirstFrame: Boolean get() = player?.hasFirstFrame == true

    fun start(url: String) {
        player?.let { if (currentURL == url) { it.play(); return } }
        val p = player ?: PreviewPlayerPool.acquire(this).also { player = it }
        currentURL = url
        p.load(url, autoplay = true)
    }

    fun stop(release: Boolean) {
        val p = player
        if (p == null) { if (release) PreviewPlayerPool.release(this); return }
        if (release) {
            player = null
            currentURL = null
            p.release()
            PreviewPlayerPool.release(this)
        } else p.pause()
    }
}

/** iOS: `AetherPreviewSurface` — black until the preview has a player, then its picture. */
@Composable
fun PreviewSurface(preview: PreviewPlayer, modifier: Modifier = Modifier, fill: Boolean = true, topAligned: Boolean = false) {
    Box(modifier.background(Color.Black), contentAlignment = Alignment.Center) {
        preview.player?.let { VideoSurface(it, Modifier.matchParentSize(), fill = fill, topAligned = topAligned) }
    }
}

/** A [PreviewPlayer] tied to the composition: released when it leaves (iOS `onDisappear { stop(release: true) }`). */
@Composable
fun rememberPreviewPlayer(): PreviewPlayer {
    val preview = remember { PreviewPlayer() }
    DisposableEffect(preview) { onDispose { preview.stop(release = true) } }
    return preview
}

/**
 * Card long-press preview (iOS `SceneCardView.onLongPressGesture(minimumDuration: 0.15)`):
 * fills its parent; after holding 0.15 s plays [previewURL] muted + looping via the shared pool,
 * stops on release, scroll or when the card leaves. Observes the pointer without consuming it,
 * so the card's own tap / the list's scroll keep working.
 */
@Composable
fun BoxScope.ScenePreviewOnHold(previewURL: String?) {
    val preview = rememberPreviewPlayer()
    var previewing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    Box(
        Modifier.matchParentSize().pointerInput(previewURL) {
            if (previewURL == null) return@pointerInput
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                val arm = scope.launch {
                    delay(150)
                    preview.start(previewURL)
                    previewing = true
                }
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                    if (!change.pressed || change.isConsumed) break
                }
                arm.cancel()
                if (previewing) { previewing = false; preview.stop(release = true) }
            }
        },
    )
    if (previewing) PreviewSurface(preview, Modifier.matchParentSize())
}
