package de.letzgo.stashy.ui.player

import android.content.Context
import android.content.Intent
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * Background audio + media notification (iOS: `UIBackgroundModes audio` with the
 * `MPNowPlayingInfoCenter` of the scene player). The scene's [StashPlayer] owns its
 * `MediaSession`; this service only hosts it, so Media3 posts the playback notification and keeps
 * the process in the foreground while the scene plays with the app in the background.
 * Started by [StashPlayer] when the main player first plays (the app is in the foreground then).
 */
class PlaybackService : MediaSessionService() {
    override fun onCreate() {
        super.onCreate()
        instance = this
        pending?.let { runCatching { addSession(it) } }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = pending

    override fun onTaskRemoved(rootIntent: Intent?) {
        // App swiped away: stop playback and the service, like iOS ending the scene.
        pending?.player?.pause()
        stopSelf()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        private var instance: PlaybackService? = null
        private var pending: MediaSession? = null

        fun attach(session: MediaSession) {
            pending?.let { old -> instance?.let { runCatching { it.removeSession(old) } } }
            pending = session
            instance?.let { runCatching { it.addSession(session) } }
        }

        fun detach(session: MediaSession) {
            instance?.let { runCatching { it.removeSession(session) } }
            if (pending === session) {
                pending = null
                instance?.stopSelf()
            }
        }

        fun ensureStarted(context: Context) {
            if (instance != null || pending == null) return
            runCatching { context.startService(Intent(context, PlaybackService::class.java)) }
        }
    }
}
